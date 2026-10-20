// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_CAMERA_PLUGIN_H_
#define PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_CAMERA_PLUGIN_H_

#include <flutter/flutter_view.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <functional>
#include <mutex>
#include <vector>

#include "camera.h"
#include "capture_controller.h"
#include "capture_controller_listener.h"
#include "image_stream_handler.h"
#include "messages.g.h"

namespace camera_windows {
using flutter::MethodResult;

namespace test {
namespace {
// Forward declaration of test class.
class MockCameraPlugin;
}  // namespace
}  // namespace test

class CameraPlugin : public flutter::Plugin,
                     public CameraApi,
                     public VideoCaptureDeviceEnumerator {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  CameraPlugin(flutter::TextureRegistrar* texture_registrar,
               flutter::BinaryMessenger* messenger);

  // Creates a plugin instance with the given CameraFactory instance.
  // Exists for unit testing with mock implementations.
  CameraPlugin(flutter::TextureRegistrar* texture_registrar,
               flutter::BinaryMessenger* messenger,
               std::unique_ptr<CameraFactory> camera_factory);

  virtual ~CameraPlugin();

  // Disallow copy and move.
  CameraPlugin(const CameraPlugin&) = delete;
  CameraPlugin& operator=(const CameraPlugin&) = delete;

  // CameraApi:
  ErrorOr<flutter::EncodableList> GetAvailableCameras() override;
  void Create(const std::string& camera_name,
              const PlatformMediaSettings& settings,
              std::function<void(ErrorOr<int64_t> reply)> result) override;
  void Initialize(
      int64_t camera_id,
      std::function<void(ErrorOr<PlatformSize> reply)> result) override;
  void PausePreview(
      int64_t camera_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ResumePreview(
      int64_t camera_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void StartVideoRecording(
      int64_t camera_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void StopVideoRecording(
      int64_t camera_id,
      std::function<void(ErrorOr<std::string> reply)> result) override;
  void TakePicture(
      int64_t camera_id,
      std::function<void(ErrorOr<std::string> reply)> result) override;
  std::optional<FlutterError> Dispose(int64_t camera_id) override;

 private:
  // Loops through cameras and returns camera
  // with matching device_id or nullptr.
  Camera* GetCameraByDeviceId(std::string& device_id);

  // Loops through cameras and returns camera
  // with matching camera_id or nullptr.
  Camera* GetCameraByCameraId(int64_t camera_id);

  // Points the image stream at the camera Dart asked for, or clears it.
  // Called on the platform thread from the image stream channel.
  void OnImageStreamStateChange(int64_t camera_id, bool running);

  // What the plugin knows about the image stream, for a `status` request: how
  // many cameras it holds and how many of them have a sink attached.
  flutter::EncodableMap BuildImageStreamStatus();

  // Sets up the window message used to reach the platform thread.
  //
  // Called once from RegisterWithRegistrar. The Windows embedder exposes no
  // task runner, so a plugin that has work on a media thread posts a private
  // window message instead and runs the work in the window proc delegate —
  // which is the only callback the embedder makes on the platform thread.
  void RegisterPlatformThreadDispatcher(
      flutter::PluginRegistrarWindows* registrar);

  // Runs |task| on the platform thread, returning false when it could not be
  // queued. Runs it inline when no dispatcher has been registered, which is
  // what tests do: a single-threaded test has no other thread to hop to.
  bool PostToPlatformThread(std::function<void()> task);

  // Disposes camera by camera id.
  void DisposeCameraByCameraId(int64_t camera_id);

  // Enumerates video capture devices.
  bool EnumerateVideoCaptureDeviceSources(IMFActivate*** devices,
                                          UINT32* count) override;

  std::unique_ptr<CameraFactory> camera_factory_;
  flutter::TextureRegistrar* texture_registrar_;
  flutter::BinaryMessenger* messenger_;
  std::unique_ptr<ImageStreamHandler> image_stream_handler_;
  std::vector<std::unique_ptr<Camera>> cameras_;

  // The dispatcher behind PostToPlatformThread.
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  int window_proc_delegate_id_ = -1;

  // The window a platform task may be posted to, resolved from the view's
  // ancestor at the moment it is needed. See RegisterPlatformThreadDispatcher.
  HWND TopLevelWindow() const;
  std::mutex platform_tasks_mutex_;
  std::vector<std::function<void()>> platform_tasks_;

  friend class camera_windows::test::MockCameraPlugin;
};

}  // namespace camera_windows

#endif  // PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_CAMERA_PLUGIN_H_
