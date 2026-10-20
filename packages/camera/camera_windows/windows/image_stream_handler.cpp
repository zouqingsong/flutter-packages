// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "image_stream_handler.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <utility>

namespace camera_windows {

using flutter::EncodableMap;
using flutter::EncodableValue;

ImageStreamHandler::ImageStreamHandler(flutter::BinaryMessenger* messenger,
                                       PostCallback post)
    : post_(std::move(post)) {
  channel_ =
      std::make_unique<flutter::BasicMessageChannel<EncodableValue>>(
          messenger, kChannelName, &flutter::StandardMessageCodec::GetInstance());
  channel_->SetMessageHandler(
      [this](const EncodableValue& message,
             const flutter::MessageReply<EncodableValue>& reply) {
        const EncodableValue reply_value = OnControlMessage(message);
        if (reply) {
          // Answered rather than ignored: a message that never reaches this
          // handler and one that arrives look identical to the sender otherwise,
          // which makes a stream with no frames impossible to diagnose from
          // Dart.
          reply(reply_value);
        }
      });
}

ImageStreamHandler::~ImageStreamHandler() {
  // Stops frames from being posted any further. A task already queued on the
  // platform thread is still run, which is why the plugin destroys this handler
  // only after it has stopped dispatching.
  running_ = false;
  channel_->SetMessageHandler(nullptr);
}

void ImageStreamHandler::SetStateChangeCallback(
    StateChangeCallback callback) {
  state_change_callback_ = std::move(callback);
}

void ImageStreamHandler::SetStatusCallback(StatusCallback callback) {
  status_callback_ = std::move(callback);
}

EncodableValue ImageStreamHandler::OnControlMessage(
    const EncodableValue& message) {
  if (!std::holds_alternative<EncodableMap>(message)) {
    return EncodableValue(false);
  }
  const EncodableMap& map = std::get<EncodableMap>(message);

  auto command_it = map.find(EncodableValue("command"));
  if (command_it == map.end() ||
      !std::holds_alternative<std::string>(command_it->second)) {
    return EncodableValue(false);
  }
  const std::string& command = std::get<std::string>(command_it->second);

  if (command == "status") {
    EncodableMap status = status_callback_ ? status_callback_() : EncodableMap();
    status[EncodableValue("running")] = EncodableValue(IsRunning());
    status[EncodableValue("received")] =
        EncodableValue(static_cast<int32_t>(frames_received_.load()));
    status[EncodableValue("sent")] =
        EncodableValue(static_cast<int32_t>(frames_sent_.load()));
    status[EncodableValue("posted")] =
        EncodableValue(static_cast<int32_t>(tasks_posted_.load()));
    status[EncodableValue("drained")] =
        EncodableValue(static_cast<int32_t>(tasks_drained_.load()));
    return EncodableValue(std::move(status));
  }

  // A frame that needs no camera: it travels the same path a real one does
  // (media thread, platform thread, channel) and arrives in Dart marked 64x64,
  // so a stream with no frames can be told apart from a broken transport
  // without a camera that has to cooperate.
  if (command == "test-frame") {
    constexpr uint32_t size = 64;
    running_ = true;
    std::vector<uint8_t> bytes(size * size * 4, 0x40);
    const bool queued = post_([this, bytes = std::move(bytes), size]() mutable {
      SendFrame(std::move(bytes), size, size);
    });
    if (queued) tasks_posted_++;
    EncodableMap reply;
    reply[EncodableValue("queued")] = EncodableValue(queued);
    return EncodableValue(std::move(reply));
  }

  // Dart sends an int as int32 when it fits and int64 when it does not, so both
  // have to be read: accepting only int64 silently left the id at -1, no camera
  // matched, no sink was attached and the stream stalled until it timed out.
  auto id_it = map.find(EncodableValue("cameraId"));
  if (id_it != map.end()) {
    const EncodableValue& id = id_it->second;
    if (std::holds_alternative<int32_t>(id)) {
      camera_id_ = std::get<int32_t>(id);
    } else if (std::holds_alternative<int64_t>(id)) {
      camera_id_ = std::get<int64_t>(id);
    }
  }

  if (command == "start") {
    last_frame_at_ = std::chrono::steady_clock::time_point();
    running_ = true;
    if (state_change_callback_) {
      state_change_callback_(camera_id_, true);
    }
  } else if (command == "stop") {
    running_ = false;
    if (state_change_callback_) {
      state_change_callback_(camera_id_, false);
    }
  }
  return EncodableValue(true);
}

void ImageStreamHandler::OnImageFrame(const uint8_t* bgra, uint32_t width,
                                      uint32_t height) {
  if (!IsRunning() || bgra == nullptr || width == 0 || height == 0) {
    return;
  }

  // Decimated rather than sampled: a frame that is not wanted is dropped before
  // it is copied, which is what makes a 30 fps camera as cheap as a 15 fps one.
  const auto interval = std::chrono::microseconds(1000000 / kMaxFramesPerSecond);
  const auto now = std::chrono::steady_clock::now();
  if (now - last_frame_at_ < interval) {
    return;
  }
  if (frame_in_flight_.exchange(true)) {
    return;
  }
  last_frame_at_ = now;
  frames_received_++;

  const size_t row_bytes = static_cast<size_t>(width) * 4;
  std::vector<uint8_t> bytes(row_bytes * height);
  std::copy(bgra, bgra + bytes.size(), bytes.data());

  // The channel may only be used from the platform thread, and the capture
  // engine calls this on a media thread.
  const bool queued =
      post_([this, bytes = std::move(bytes), width, height]() mutable {
        SendFrame(std::move(bytes), width, height);
      });
  if (queued) {
    tasks_posted_++;
  } else {
    // Nothing will send this frame, so the next one must not be dropped in its
    // favour: a flag left set here stops the stream for good.
    frame_in_flight_ = false;
  }
}

void ImageStreamHandler::SendFrame(std::vector<uint8_t> bytes, uint32_t width,
                                   uint32_t height) {
  tasks_drained_++;
  if (!IsRunning()) {
    frame_in_flight_ = false;
    return;
  }

  frames_sent_++;

  EncodableMap map;
  map[EncodableValue("bytes")] = EncodableValue(std::move(bytes));
  map[EncodableValue("width")] =
      EncodableValue(static_cast<int32_t>(width));
  map[EncodableValue("height")] =
      EncodableValue(static_cast<int32_t>(height));
  map[EncodableValue("bytesPerRow")] =
      EncodableValue(static_cast<int32_t>(width * 4));
  map[EncodableValue("bytesPerPixel")] = EncodableValue(4);
  // Named for what the bytes are, not for the Media Foundation format they
  // came from: MFVideoFormat_RGB32 is B,G,R,X in memory.
  map[EncodableValue("format")] = EncodableValue("bgra8888");
  map[EncodableValue("cameraId")] = EncodableValue(camera_id_);

  channel_->Send(EncodableValue(std::move(map)));
  frame_in_flight_ = false;
}

}  // namespace camera_windows
