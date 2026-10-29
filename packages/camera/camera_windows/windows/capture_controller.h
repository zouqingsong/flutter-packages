// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_CAPTURE_CONTROLLER_H_
#define PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_CAPTURE_CONTROLLER_H_

#include <d3d11.h>
#include <flutter/texture_registrar.h>
#include <mfapi.h>
#include <mfcaptureengine.h>
#include <mferror.h>
#include <mfidl.h>
#include <windows.h>
#include <wrl/client.h>

#include <atomic>
#include <memory>
#include <optional>
#include <string>

#include "capture_controller_listener.h"
#include "capture_engine_listener.h"
#include "image_stream_handler.h"
#include "messages.g.h"
#include "photo_handler.h"
#include "preview_handler.h"
#include "record_handler.h"
#include "texture_handler.h"

namespace camera_windows {
using flutter::TextureRegistrar;
using Microsoft::WRL::ComPtr;

// Camera capture engine state.
//
// On creation, |CaptureControllers| start in state |kNotInitialized|.
// On initialization, the capture controller transitions to the |kInitializing|
// and then |kInitialized| state.
enum class CaptureEngineState { kNotInitialized, kInitializing, kInitialized };

// Interface for a class that enumerates video capture device sources.
class VideoCaptureDeviceEnumerator {
 private:
  virtual bool EnumerateVideoCaptureDeviceSources(IMFActivate*** devices,
                                                  UINT32* count) = 0;
};

// Interface implemented by capture controllers.
//
// Capture controllers are used to capture video streams or still photos from
// their associated |Camera|.
class CaptureController {
 public:
  CaptureController() {}
  virtual ~CaptureController() = default;

  // Disallow copy and move.
  CaptureController(const CaptureController&) = delete;
  CaptureController& operator=(const CaptureController&) = delete;

  // Initializes the capture controller with the specified device id.
  //
  // Returns false if the capture controller could not be initialized
  // or is already initialized.
  //
  // texture_registrar: Pointer to Flutter TextureRegistrar instance. Used to
  //                    register texture for capture preview.
  // device_id:         A string that holds information of camera device id to
  //                    be captured.
  // media_settings:    Settings controlling capture behavior.
  virtual bool InitCaptureDevice(
      TextureRegistrar* texture_registrar, const std::string& device_id,
      const PlatformMediaSettings& media_settings) = 0;

  // Returns preview frame width
  virtual uint32_t GetPreviewWidth() const = 0;

  // Returns preview frame height
  virtual uint32_t GetPreviewHeight() const = 0;

  // Starts the preview.
  virtual void StartPreview() = 0;

  // Pauses the preview.
  virtual void PausePreview() = 0;

  // Resumes the preview.
  virtual void ResumePreview() = 0;

  // Starts recording video.
  virtual void StartRecord(const std::string& file_path) = 0;

  // Stops the current video recording.
  virtual void StopRecord() = 0;

  // Captures a still photo.
  virtual void TakePicture(const std::string& file_path) = 0;

  // Sets the sink that receives preview frames for image streaming, or null to
  // stop streaming. Called on the platform thread; frames are delivered on the
  // capture engine's sample thread.
  virtual void SetImageStreamSink(ImageStreamSink* sink) = 0;

  // Whether a sink is currently attached, for the plugin's status reporting.
  virtual bool HasImageStreamSink() const = 0;

  // A short description of the capture state ("initialized, preview running"),
  // for the plugin's status reporting: frames only flow once the preview is
  // running, and "no frames" says nothing about which of those is missing.
  virtual std::string DescribeState() const = 0;

  // The picture sizes the device can deliver, largest first.
  virtual std::vector<std::pair<uint32_t, uint32_t>> GetSupportedPreviewSizes()
      const = 0;

  // The picture formats the device can deliver, largest first, one entry per
  // size and rate.
  virtual std::vector<PlatformVideoFormat> GetSupportedVideoFormats() const = 0;

  // Pins the format the next preview should use, or clears it with zeros.
  //
  // A device media type cannot be swapped under a running capture engine, so the
  // caller re-creates the camera to change it and this records what to use.
  virtual void SetPreferredFormat(uint32_t width, uint32_t height,
                                  uint32_t frame_rate) = 0;
};

// Concrete implementation of the |CaptureController| interface.
//
// Handles the video preview stream via a |PreviewHandler| instance, video
// capture via a |RecordHandler| instance, and still photo capture via a
// |PhotoHandler| instance.
class CaptureControllerImpl : public CaptureController,
                              public CaptureEngineObserver {
 public:
  static bool EnumerateVideoCaptureDeviceSources(IMFActivate*** devices,
                                                 UINT32* count);

  explicit CaptureControllerImpl(CaptureControllerListener* listener);
  virtual ~CaptureControllerImpl();

  // Disallow copy and move.
  CaptureControllerImpl(const CaptureControllerImpl&) = delete;
  CaptureControllerImpl& operator=(const CaptureControllerImpl&) = delete;

  // CaptureController
  bool InitCaptureDevice(TextureRegistrar* texture_registrar,
                         const std::string& device_id,
                         const PlatformMediaSettings& media_settings) override;
  uint32_t GetPreviewWidth() const override { return preview_frame_width_; }
  uint32_t GetPreviewHeight() const override { return preview_frame_height_; }
  std::vector<std::pair<uint32_t, uint32_t>> GetSupportedPreviewSizes()
      const override;
  std::vector<PlatformVideoFormat> GetSupportedVideoFormats() const override;
  void SetPreferredFormat(uint32_t width, uint32_t height,
                          uint32_t frame_rate) override;
  void StartPreview() override;
  void PausePreview() override;
  void ResumePreview() override;
  void StartRecord(const std::string& file_path) override;
  void StopRecord() override;
  void TakePicture(const std::string& file_path) override;
  void SetImageStreamSink(ImageStreamSink* sink) override;
  bool HasImageStreamSink() const override {
    return image_stream_sink_.load() != nullptr;
  }
  std::string DescribeState() const override;

  // CaptureEngineObserver
  void OnEvent(IMFMediaEvent* event) override;
  bool IsReadyForSample() const override {
    return capture_engine_state_ == CaptureEngineState::kInitialized &&
           preview_handler_ && preview_handler_->IsRunning();
  }
  bool IsServingImageStream() const override { return HasImageStreamSink(); }
  bool UpdateBuffer(uint8_t* data, uint32_t data_length) override;
  void UpdateCaptureTime(uint64_t capture_time) override;

  // Sets capture engine, for testing purposes.
  void SetCaptureEngine(IMFCaptureEngine* capture_engine) {
    capture_engine_ = capture_engine;
  }

  // Sets video source, for testing purposes.
  void SetVideoSource(IMFMediaSource* video_source) {
    video_source_ = video_source;
  }

  // Sets audio source, for testing purposes.
  void SetAudioSource(IMFMediaSource* audio_source) {
    audio_source_ = audio_source;
  }

 private:
  // Helper function to return initialized state as boolean;
  bool IsInitialized() const {
    return capture_engine_state_ == CaptureEngineState::kInitialized;
  }

  // Resets capture controller state.
  // This is called if capture engine creation fails or is disposed.
  void ResetCaptureController();

  // Returns max preview height calculated from resolution present.
  uint32_t GetMaxPreviewHeight() const;

  // Uses first audio source to capture audio.
  // Note: Enumerating audio sources via platform interface is not supported.
  HRESULT CreateDefaultAudioCaptureSource();

  // Initializes video capture source from camera device.
  HRESULT CreateVideoCaptureSourceForDevice(const std::string& video_device_id);

  // Creates DX11 Device and D3D Manager.
  HRESULT CreateD3DManagerWithDX11Device();

  // Initializes capture engine object.
  HRESULT CreateCaptureEngine();

  // Enumerates video_sources media types and finds out best resolution
  // for preview and video capture.
  HRESULT FindBaseMediaTypes();

  // Enumerates video_sources media types and finds out best resolution
  // for a given source.
  HRESULT FindBaseMediaTypesForSource(IMFCaptureSource* source);

  // Finds the media type the caller pinned, if any.
  bool FindPreferredMediaType(DWORD source_stream_index, IMFCaptureSource* source,
                              IMFMediaType** target_media_type);

  // The format the caller pinned, or zeros when none was.
  uint32_t preferred_width_ = 0;
  uint32_t preferred_height_ = 0;
  uint32_t preferred_frame_rate_ = 0;

  // Stops preview. Called internally on camera reset and dispose.
  HRESULT StopPreview();

  // Handles capture engine initalization event.
  void OnCaptureEngineInitialized(CameraResult result,
                                  const std::string& error);

  // Handles capture engine errors.
  void OnCaptureEngineError(CameraResult result, const std::string& error);

  // Handles picture events.
  void OnPicture(CameraResult result, const std::string& error);

  // Handles preview started events.
  void OnPreviewStarted(CameraResult result, const std::string& error);

  // Handles preview stopped events.
  void OnPreviewStopped(CameraResult result, const std::string& error);

  // Handles record started events.
  void OnRecordStarted(CameraResult result, const std::string& error);

  // Handles record stopped events.
  void OnRecordStopped(CameraResult result, const std::string& error);

  bool media_foundation_started_ = false;

  // The sink is set on the platform thread and read on the sample thread, so it
  // is read through an atomic pointer rather than copied into the frame path.
  std::atomic<ImageStreamSink*> image_stream_sink_{nullptr};

  // Every sample the capture engine delivers, counted before anything decides
  // what to do with it: a stream with no frames is either "the camera sent
  // nothing" or "we dropped it", and only a count tells them apart.
  std::atomic<uint64_t> samples_seen_{0};
  std::atomic<uint64_t> samples_forwarded_{0};
  std::atomic<int> last_sample_length_{0};

  uint32_t preview_frame_width_ = 0;
  uint32_t preview_frame_height_ = 0;
  UINT dx_device_reset_token_ = 0;
  std::unique_ptr<RecordHandler> record_handler_;
  std::unique_ptr<PreviewHandler> preview_handler_;
  std::unique_ptr<PhotoHandler> photo_handler_;
  std::unique_ptr<TextureHandler> texture_handler_;
  CaptureControllerListener* capture_controller_listener_;

  std::string video_device_id_;
  CaptureEngineState capture_engine_state_ =
      CaptureEngineState::kNotInitialized;
  PlatformMediaSettings media_settings_;
  ComPtr<IMFCaptureEngine> capture_engine_;
  ComPtr<CaptureEngineListener> capture_engine_callback_handler_;
  ComPtr<IMFDXGIDeviceManager> dxgi_device_manager_;
  ComPtr<ID3D11Device> dx11_device_;
  ComPtr<IMFMediaType> base_capture_media_type_;
  // The media type a recording is configured with: the capture type above
  // narrowed to the resolution preset, because a clip is written frame after
  // frame at whatever size it was set up for.
  ComPtr<IMFMediaType> base_record_media_type_;
  ComPtr<IMFMediaType> base_preview_media_type_;
  ComPtr<IMFMediaSource> video_source_;
  ComPtr<IMFMediaSource> audio_source_;

  TextureRegistrar* texture_registrar_ = nullptr;
};

// Inferface for factory classes that create |CaptureController| instances.
class CaptureControllerFactory {
 public:
  CaptureControllerFactory() {}
  virtual ~CaptureControllerFactory() = default;

  // Disallow copy and move.
  CaptureControllerFactory(const CaptureControllerFactory&) = delete;
  CaptureControllerFactory& operator=(const CaptureControllerFactory&) = delete;

  // Create and return a |CaptureController| that makes callbacks on the
  // specified |CaptureControllerListener|, which must not be null.
  virtual std::unique_ptr<CaptureController> CreateCaptureController(
      CaptureControllerListener* listener) = 0;
};

// Concreate implementation of |CaptureControllerFactory|.
class CaptureControllerFactoryImpl : public CaptureControllerFactory {
 public:
  CaptureControllerFactoryImpl() {}
  virtual ~CaptureControllerFactoryImpl() = default;

  // Disallow copy and move.
  CaptureControllerFactoryImpl(const CaptureControllerFactoryImpl&) = delete;
  CaptureControllerFactoryImpl& operator=(const CaptureControllerFactoryImpl&) =
      delete;

  std::unique_ptr<CaptureController> CreateCaptureController(
      CaptureControllerListener* listener) override {
    return std::make_unique<CaptureControllerImpl>(listener);
  }
};

}  // namespace camera_windows

#endif  // PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_CAPTURE_CONTROLLER_H_
