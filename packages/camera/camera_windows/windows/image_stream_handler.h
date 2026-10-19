// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_IMAGE_STREAM_HANDLER_H_
#define PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_IMAGE_STREAM_HANDLER_H_

#include <flutter/basic_message_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/standard_message_codec.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

namespace camera_windows {

// Receives preview frames for image streaming.
//
// Implemented by |ImageStreamHandler|; an interface only so the capture
// controller can be handed a sink without knowing about channels or threads.
class ImageStreamSink {
 public:
  virtual ~ImageStreamSink() = default;

  // Called from the capture engine's sample thread with one preview frame, as
  // B,G,R,X pixels in top-down row order. The pointer is only valid for the
  // duration of the call, so an implementation that needs to keep the pixels
  // has to copy them.
  virtual void OnImageFrame(const uint8_t* bgra, uint32_t width,
                            uint32_t height) = 0;
};

// Streams preview frames to Dart.
//
// Frames travel over a |BasicMessageChannel| rather than an event channel
// because this channel carries the start and stop requests as well: one
// channel per camera stream, in both directions, means the Dart side does not
// need a second API (and no generated Pigeon surface) just to say "begin".
//
// The channel is only a transport. Throttling, the drop-when-behind policy and
// the thread hop all live here, because the capture engine calls on a media
// thread and the Flutter platform channel may only be used from the platform
// thread.
class ImageStreamHandler : public ImageStreamSink {
 public:
  // The channel frames are sent on, and control messages received on.
  static constexpr char kChannelName[] =
      "plugins.flutter.io/camera_windows/imageStream";

  // Frames are decimated to this rate before they are copied.
  //
  // A 720p BGRA frame is about 3.7 MB, so a camera running at 30 fps would put
  // 110 MB/s through the channel: more than the stream needs — a viewer sees
  // 15 fps as smooth for a live camera — and enough to make the UI thread the
  // bottleneck. The copy is skipped entirely for a dropped frame, so a camera
  // that runs faster than this costs nothing.
  static constexpr int kMaxFramesPerSecond = 15;

  // Called on the platform thread when Dart asks for the stream to start or
  // stop, so the plugin can point this sink at the right camera. The camera id
  // is whatever Dart sent with the request.
  using StateChangeCallback = std::function<void(int64_t camera_id, bool running)>;

  // Reports what the plugin knows about the stream, for a `status` request.
  using StatusCallback = std::function<flutter::EncodableMap()>;

  // Moves a task to the platform thread, returning false when that was not
  // possible. Supplied by the plugin, which uses a window message because the
  // Windows embedder exposes no task runner.
  using PostCallback = std::function<bool(std::function<void()>)>;

  // |post| hops from the capture engine's sample thread to the platform thread.
  // A callback that runs its task inline is only for tests: the channel may not
  // be used from a media thread in a real app.
  ImageStreamHandler(flutter::BinaryMessenger* messenger, PostCallback post);
  virtual ~ImageStreamHandler();

  // Disallow copy and move.
  ImageStreamHandler(const ImageStreamHandler&) = delete;
  ImageStreamHandler& operator=(const ImageStreamHandler&) = delete;

  void SetStateChangeCallback(StateChangeCallback callback);
  void SetStatusCallback(StatusCallback callback);

  /// Frames handed to Dart since this handler was created.
  int FramesSent() const { return frames_sent_; }

  /// Frames offered by the camera and copied, whether or not they were sent.
  int FramesReceived() const { return frames_received_; }

  // Whether a stream is wanted. Frames arriving while this is false are
  // dropped without being copied.
  bool IsRunning() const { return running_.load(); }

  // ImageStreamSink
  void OnImageFrame(const uint8_t* bgra, uint32_t width,
                    uint32_t height) override;

 private:
  // Handles a control message from Dart, returning what to reply. Runs on the
  // platform thread.
  flutter::EncodableValue OnControlMessage(
      const flutter::EncodableValue& message);

  // Encodes and sends one frame. Runs on the platform thread.
  void SendFrame(std::vector<uint8_t> bytes, uint32_t width, uint32_t height);

  std::unique_ptr<flutter::BasicMessageChannel<flutter::EncodableValue>>
      channel_;
  PostCallback post_;
  StateChangeCallback state_change_callback_;
  StatusCallback status_callback_;
  std::atomic<int> frames_sent_{0};
  std::atomic<int> frames_received_{0};

  std::atomic<bool> running_{false};
  // Set while a frame is on its way to Dart, so a frame that the platform
  // thread has not consumed yet is dropped rather than queued: a live stream
  // that grows a backlog is worse than one that loses a frame.
  std::atomic<bool> frame_in_flight_{false};
  // Only touched from the capture engine's sample thread.
  std::chrono::steady_clock::time_point last_frame_at_;
  int64_t camera_id_ = -1;
};

}  // namespace camera_windows

#endif  // PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_IMAGE_STREAM_HANDLER_H_
