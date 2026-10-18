// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "camera_plugin.h"

#include <flutter/flutter_view.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <mfapi.h>
#include <mfidl.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>

#include <cassert>
#include <iostream>
#include <chrono>
#include <memory>
#include <optional>
#include <utility>

#include "capture_device_info.h"
#include "com_heap_ptr.h"
#include "messages.g.h"
#include "string_utils.h"

namespace camera_windows {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

const std::string kPictureCaptureExtension = "jpeg";
const std::string kVideoCaptureExtension = "mp4";

// Builds CaptureDeviceInfo object from given device holding device name and id.
std::unique_ptr<CaptureDeviceInfo> GetDeviceInfo(IMFActivate* device) {
  assert(device);
  auto device_info = std::make_unique<CaptureDeviceInfo>();
  ComHeapPtr<wchar_t> name;
  UINT32 name_size;

  HRESULT hr = device->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
                                          &name, &name_size);
  if (FAILED(hr)) {
    return device_info;
  }

  ComHeapPtr<wchar_t> id;
  UINT32 id_size;
  hr = device->GetAllocatedString(
      MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &id, &id_size);

  if (FAILED(hr)) {
    return device_info;
  }

  device_info->SetDisplayName(Utf8FromUtf16(std::wstring(name, name_size)));
  device_info->SetDeviceID(Utf8FromUtf16(std::wstring(id, id_size)));
  return device_info;
}

// Builds datetime string from current time.
// Used as part of the filenames for captured pictures and videos.
std::string GetCurrentTimeString() {
  std::chrono::system_clock::duration now =
      std::chrono::system_clock::now().time_since_epoch();

  auto s = std::chrono::duration_cast<std::chrono::seconds>(now).count();
  auto ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(now).count() % 1000;

  struct tm newtime;
  localtime_s(&newtime, &s);

  std::string time_start = "";
  time_start.resize(80);
  size_t len =
      strftime(&time_start[0], time_start.size(), "%Y_%m%d_%H%M%S_", &newtime);
  if (len > 0) {
    time_start.resize(len);
  }

  // Add milliseconds to make sure the filename is unique
  return time_start + std::to_string(ms);
}

// Builds file path for picture capture.
std::optional<std::string> GetFilePathForPicture() {
  ComHeapPtr<wchar_t> known_folder_path;
  HRESULT hr = SHGetKnownFolderPath(FOLDERID_Pictures, KF_FLAG_CREATE, nullptr,
                                    &known_folder_path);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  std::string path = Utf8FromUtf16(std::wstring(known_folder_path));

  return path + "\\" + "PhotoCapture_" + GetCurrentTimeString() + "." +
         kPictureCaptureExtension;
}

// Builds file path for video capture.
std::optional<std::string> GetFilePathForVideo() {
  ComHeapPtr<wchar_t> known_folder_path;
  HRESULT hr = SHGetKnownFolderPath(FOLDERID_Videos, KF_FLAG_CREATE, nullptr,
                                    &known_folder_path);
  if (FAILED(hr)) {
    return std::nullopt;
  }

  std::string path = Utf8FromUtf16(std::wstring(known_folder_path));

  return path + "\\" + "VideoCapture_" + GetCurrentTimeString() + "." +
         kVideoCaptureExtension;
}
}  // namespace

// static
void CameraPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  std::unique_ptr<CameraPlugin> plugin = std::make_unique<CameraPlugin>(
      registrar->texture_registrar(), registrar->messenger());
  plugin->RegisterPlatformThreadDispatcher(registrar);

  CameraApi::SetUp(registrar->messenger(), plugin.get());

  registrar->AddPlugin(std::move(plugin));
}

namespace {
// Identifies this plugin's posts to the platform thread. It sits in the range
// Windows reserves for an application's own messages.
constexpr UINT kPlatformTaskMessage = WM_APP + 0x4A;
}  // namespace

CameraPlugin::CameraPlugin(flutter::TextureRegistrar* texture_registrar,
                           flutter::BinaryMessenger* messenger)
    : CameraPlugin(texture_registrar,
                   messenger,
                   std::make_unique<CameraFactoryImpl>()) {}

CameraPlugin::CameraPlugin(flutter::TextureRegistrar* texture_registrar,
                           flutter::BinaryMessenger* messenger,
                           std::unique_ptr<CameraFactory> camera_factory)
    : texture_registrar_(texture_registrar),
      messenger_(messenger),
      camera_factory_(std::move(camera_factory)) {
  image_stream_handler_ = std::make_unique<ImageStreamHandler>(
      messenger_, [this](std::function<void()> task) {
        PostToPlatformThread(std::move(task));
      });
  image_stream_handler_->SetStateChangeCallback(
      [this](int64_t camera_id, bool running) {
        OnImageStreamStateChange(camera_id, running);
      });
}

CameraPlugin::~CameraPlugin() {
  // Order matters: the handler must be gone before the tasks that would use it
  // can run, and the delegate must be gone before the window can dispatch to
  // them.
  image_stream_handler_ = nullptr;
  if (registrar_ != nullptr && window_proc_delegate_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(
        window_proc_delegate_id_);
    window_proc_delegate_id_ = -1;
  }
  {
    const std::lock_guard<std::mutex> lock(platform_tasks_mutex_);
    platform_tasks_.clear();
  }
}

void CameraPlugin::RegisterPlatformThreadDispatcher(
    flutter::PluginRegistrarWindows* registrar) {
  registrar_ = registrar;
  flutter::FlutterView* view = registrar->GetView();
  window_ = view == nullptr ? nullptr : view->GetNativeWindow();
  if (window_ == nullptr) {
    return;
  }
  window_proc_delegate_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam,
             LPARAM lparam) -> std::optional<LRESULT> {
        if (message != kPlatformTaskMessage) {
          return std::nullopt;
        }
        std::vector<std::function<void()>> tasks;
        {
          const std::lock_guard<std::mutex> lock(platform_tasks_mutex_);
          tasks.swap(platform_tasks_);
        }
        for (auto& task : tasks) {
          task();
        }
        // The message is this plugin's own, so it is not swallowed: other
        // delegates are welcome to ignore it too.
        return std::nullopt;
      });
}

void CameraPlugin::PostToPlatformThread(std::function<void()> task) {
  if (window_ == nullptr) {
    task();
    return;
  }
  {
    const std::lock_guard<std::mutex> lock(platform_tasks_mutex_);
    platform_tasks_.push_back(std::move(task));
  }
  ::PostMessage(window_, kPlatformTaskMessage, 0, 0);
}

void CameraPlugin::OnImageStreamStateChange(int64_t camera_id, bool running) {
  Camera* target = nullptr;
  for (auto& camera : cameras_) {
    if (camera->HasCameraId(camera_id)) {
      target = camera.get();
      break;
    }
  }
  // An id that matches nothing used to leave every sink detached and the caller
  // waiting for frames that could never arrive. Falling back to the only camera
  // turns a mismatch into a stream, and there is nothing ambiguous to pick.
  if (running && target == nullptr && cameras_.size() == 1) {
    target = cameras_.front().get();
    std::cerr << "camera_windows: image stream for camera " << camera_id
              << " not found; streaming the only camera instead" << std::endl;
  }

  for (auto& camera : cameras_) {
    CaptureController* controller = camera->GetCaptureController();
    if (controller == nullptr) {
      continue;
    }
    // One stream at a time: starting one clears every other sink, so a camera
    // that is disposed or replaced cannot leave a sink pointing at frames that
    // belong to a different device.
    if (running && camera.get() == target) {
      controller->SetImageStreamSink(image_stream_handler_.get());
    } else {
      controller->SetImageStreamSink(nullptr);
    }
  }
}

Camera* CameraPlugin::GetCameraByDeviceId(std::string& device_id) {
  for (auto it = begin(cameras_); it != end(cameras_); ++it) {
    if ((*it)->HasDeviceId(device_id)) {
      return it->get();
    }
  }
  return nullptr;
}

Camera* CameraPlugin::GetCameraByCameraId(int64_t camera_id) {
  for (auto it = begin(cameras_); it != end(cameras_); ++it) {
    if ((*it)->HasCameraId(camera_id)) {
      return it->get();
    }
  }
  return nullptr;
}

void CameraPlugin::DisposeCameraByCameraId(int64_t camera_id) {
  for (auto it = begin(cameras_); it != end(cameras_); ++it) {
    if ((*it)->HasCameraId(camera_id)) {
      cameras_.erase(it);
      return;
    }
  }
}

ErrorOr<flutter::EncodableList> CameraPlugin::GetAvailableCameras() {
  // Enumerate devices.
  ComHeapPtr<IMFActivate*> devices;
  UINT32 count = 0;
  if (!this->EnumerateVideoCaptureDeviceSources(&devices, &count)) {
    // No need to free devices here, since allocation failed.
    return FlutterError("System error", "Failed to get available cameras");
  }

  // Format found devices to the response.
  EncodableList devices_list;
  for (UINT32 i = 0; i < count; ++i) {
    auto device_info = GetDeviceInfo(devices[i]);
    auto deviceName = device_info->GetUniqueDeviceName();

    devices_list.push_back(EncodableValue(deviceName));
  }

  return devices_list;
}

bool CameraPlugin::EnumerateVideoCaptureDeviceSources(IMFActivate*** devices,
                                                      UINT32* count) {
  return CaptureControllerImpl::EnumerateVideoCaptureDeviceSources(devices,
                                                                   count);
}

void CameraPlugin::Create(const std::string& camera_name,
                          const PlatformMediaSettings& settings,
                          std::function<void(ErrorOr<int64_t> reply)> result) {
  auto device_info = std::make_unique<CaptureDeviceInfo>();
  if (!device_info->ParseDeviceInfoFromCameraName(camera_name)) {
    return result(FlutterError("camera_error",
                               "Cannot parse device info from " + camera_name));
  }

  auto device_id = device_info->GetDeviceId();
  if (GetCameraByDeviceId(device_id)) {
    return result(
        FlutterError("camera_error",
                     "Camera with given device id already exists. Existing "
                     "camera must be disposed before creating it again."));
  }

  std::unique_ptr<camera_windows::Camera> camera =
      camera_factory_->CreateCamera(device_id);

  if (camera->HasPendingResultByType(PendingResultType::kCreateCamera)) {
    return result(
        FlutterError("camera_error", "Pending camera creation request exists"));
  }

  if (camera->AddPendingIntResult(PendingResultType::kCreateCamera,
                                  std::move(result))) {
    bool initialized =
        camera->InitCamera(texture_registrar_, messenger_, settings);
    if (initialized) {
      cameras_.push_back(std::move(camera));
    }
  }
}

void CameraPlugin::Initialize(
    int64_t camera_id,
    std::function<void(ErrorOr<PlatformSize> reply)> result) {
  auto camera = GetCameraByCameraId(camera_id);
  if (!camera) {
    return result(FlutterError("camera_error", "Camera not created"));
  }

  if (camera->HasPendingResultByType(PendingResultType::kInitialize)) {
    return result(
        FlutterError("camera_error", "Pending initialization request exists"));
  }

  if (camera->AddPendingSizeResult(PendingResultType::kInitialize,
                                   std::move(result))) {
    auto cc = camera->GetCaptureController();
    assert(cc);
    cc->StartPreview();
  }
}

void CameraPlugin::PausePreview(
    int64_t camera_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto camera = GetCameraByCameraId(camera_id);
  if (!camera) {
    return result(FlutterError("camera_error", "Camera not created"));
  }

  if (camera->HasPendingResultByType(PendingResultType::kPausePreview)) {
    return result(
        FlutterError("camera_error", "Pending pause preview request exists"));
  }

  if (camera->AddPendingVoidResult(PendingResultType::kPausePreview,
                                   std::move(result))) {
    auto cc = camera->GetCaptureController();
    assert(cc);
    cc->PausePreview();
  }
}

void CameraPlugin::ResumePreview(
    int64_t camera_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto camera = GetCameraByCameraId(camera_id);
  if (!camera) {
    return result(FlutterError("camera_error", "Camera not created"));
  }

  if (camera->HasPendingResultByType(PendingResultType::kResumePreview)) {
    return result(
        FlutterError("camera_error", "Pending resume preview request exists"));
  }

  if (camera->AddPendingVoidResult(PendingResultType::kResumePreview,
                                   std::move(result))) {
    auto cc = camera->GetCaptureController();
    assert(cc);
    cc->ResumePreview();
  }
}

void CameraPlugin::StartVideoRecording(
    int64_t camera_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  auto camera = GetCameraByCameraId(camera_id);
  if (!camera) {
    return result(FlutterError("camera_error", "Camera not created"));
  }

  if (camera->HasPendingResultByType(PendingResultType::kStartRecord)) {
    return result(
        FlutterError("camera_error", "Pending start recording request exists"));
  }

  std::optional<std::string> path = GetFilePathForVideo();
  if (path) {
    if (camera->AddPendingVoidResult(PendingResultType::kStartRecord,
                                     std::move(result))) {
      auto cc = camera->GetCaptureController();
      assert(cc);
      cc->StartRecord(*path);
    }
  } else {
    return result(
        FlutterError("system_error", "Failed to get path for video capture"));
  }
}

void CameraPlugin::StopVideoRecording(
    int64_t camera_id, std::function<void(ErrorOr<std::string> reply)> result) {
  auto camera = GetCameraByCameraId(camera_id);
  if (!camera) {
    return result(FlutterError("camera_error", "Camera not created"));
  }

  if (camera->HasPendingResultByType(PendingResultType::kStopRecord)) {
    return result(
        FlutterError("camera_error", "Pending stop recording request exists"));
  }

  if (camera->AddPendingStringResult(PendingResultType::kStopRecord,
                                     std::move(result))) {
    auto cc = camera->GetCaptureController();
    assert(cc);
    cc->StopRecord();
  }
}

void CameraPlugin::TakePicture(
    int64_t camera_id, std::function<void(ErrorOr<std::string> reply)> result) {
  auto camera = GetCameraByCameraId(camera_id);
  if (!camera) {
    return result(FlutterError("camera_error", "Camera not created"));
  }

  if (camera->HasPendingResultByType(PendingResultType::kTakePicture)) {
    return result(
        FlutterError("camera_error", "Pending take picture request exists"));
  }

  std::optional<std::string> path = GetFilePathForPicture();
  if (path) {
    if (camera->AddPendingStringResult(PendingResultType::kTakePicture,
                                       std::move(result))) {
      auto cc = camera->GetCaptureController();
      assert(cc);
      cc->TakePicture(*path);
    }
  } else {
    return result(
        FlutterError("system_error", "Failed to get capture path for picture"));
  }
}

std::optional<FlutterError> CameraPlugin::Dispose(int64_t camera_id) {
  DisposeCameraByCameraId(camera_id);
  return std::nullopt;
}

}  // namespace camera_windows
