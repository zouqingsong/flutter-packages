// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "record_handler.h"

#include <mfapi.h>
#include <mfcaptureengine.h>

#include <cassert>

#include "string_utils.h"

namespace camera_windows {

using Microsoft::WRL::ComPtr;

// Ceiling, floor and fallback for a bitrate the caller did not choose. 6 Mbps is
// the 1080p30 figure from the heuristic below, for a camera whose frame size the
// plugin could not read.
constexpr UINT32 kMinimumVideoBitrate = 2000000;
constexpr UINT32 kMaximumVideoBitrate = 40000000;
constexpr UINT32 kDefaultVideoBitrate = 6000000;

// Initializes media type for video capture.
HRESULT BuildMediaTypeForVideoCapture(IMFMediaType* src_media_type,
                                      IMFMediaType** video_record_media_type,
                                      GUID capture_format) {
  assert(src_media_type);
  ComPtr<IMFMediaType> new_media_type;

  HRESULT hr = MFCreateMediaType(&new_media_type);
  if (FAILED(hr)) {
    return hr;
  }

  // Clones everything from original media type.
  hr = src_media_type->CopyAllItems(new_media_type.Get());
  if (FAILED(hr)) {
    return hr;
  }

  hr = new_media_type->SetGUID(MF_MT_SUBTYPE, capture_format);
  if (FAILED(hr)) {
    return hr;
  }

  new_media_type.CopyTo(video_record_media_type);
  return S_OK;
}

// Queries interface object from collection.
template <class Q>
HRESULT GetCollectionObject(IMFCollection* pCollection, DWORD index,
                            Q** ppObj) {
  ComPtr<IUnknown> pUnk;
  HRESULT hr = pCollection->GetElement(index, pUnk.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }
  return pUnk->QueryInterface(IID_PPV_ARGS(ppObj));
}

// Initializes media type for audo capture.
HRESULT BuildMediaTypeForAudioCapture(IMFMediaType** audio_record_media_type) {
  ComPtr<IMFAttributes> audio_output_attributes;
  ComPtr<IMFMediaType> src_media_type;
  ComPtr<IMFMediaType> new_media_type;
  ComPtr<IMFCollection> available_output_types;
  DWORD mt_count = 0;

  HRESULT hr = MFCreateAttributes(&audio_output_attributes, 1);
  if (FAILED(hr)) {
    return hr;
  }

  // Enumerates only low latency audio outputs.
  hr = audio_output_attributes->SetUINT32(MF_LOW_LATENCY, TRUE);
  if (FAILED(hr)) {
    return hr;
  }

  DWORD mft_flags = (MFT_ENUM_FLAG_ALL & (~MFT_ENUM_FLAG_FIELDOFUSE)) |
                    MFT_ENUM_FLAG_SORTANDFILTER;

  hr = MFTranscodeGetAudioOutputAvailableTypes(
      MFAudioFormat_AAC, mft_flags, audio_output_attributes.Get(),
      available_output_types.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }

  hr = GetCollectionObject(available_output_types.Get(), 0,
                           src_media_type.GetAddressOf());
  if (FAILED(hr)) {
    return hr;
  }

  hr = available_output_types->GetElementCount(&mt_count);
  if (FAILED(hr)) {
    return hr;
  }

  if (mt_count == 0) {
    // No sources found, mark process as failure.
    return E_FAIL;
  }

  // Create new media type to copy original media type to.
  hr = MFCreateMediaType(&new_media_type);
  if (FAILED(hr)) {
    return hr;
  }

  hr = src_media_type->CopyAllItems(new_media_type.Get());
  if (FAILED(hr)) {
    return hr;
  }

  new_media_type.CopyTo(audio_record_media_type);
  return hr;
}

// Helper function to set the frame rate on a video media type.
inline HRESULT SetFrameRate(IMFMediaType* pType, UINT32 numerator,
                            UINT32 denominator) {
  return MFSetAttributeRatio(pType, MF_MT_FRAME_RATE, numerator, denominator);
}

// Helper function to set the video bitrate on a video media type.
inline HRESULT SetVideoBitrate(IMFMediaType* pType, UINT32 bitrate) {
  return pType->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
}

// Helper function to set the audio bitrate on an audio media type.
inline HRESULT SetAudioBitrate(IMFMediaType* pType, UINT32 bitrate) {
  return pType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, bitrate);
}

// A bitrate for an encoder the caller asked nothing of: about 0.1 bits per pixel
// per frame, which is 6 Mbps at 1080p30, held between 2 and 40 Mbps so that a
// small picture is not starved and a 4K one is not asked for more than the
// encoder will write.
inline UINT32 DefaultVideoBitrate(IMFMediaType* pType) {
  UINT32 width = 0;
  UINT32 height = 0;
  UINT32 numerator = 0;
  UINT32 denominator = 0;
  MFGetAttributeSize(pType, MF_MT_FRAME_SIZE, &width, &height);
  MFGetAttributeRatio(pType, MF_MT_FRAME_RATE, &numerator, &denominator);
  const double frames_per_second =
      denominator ? static_cast<double>(numerator) / denominator : 30.0;
  if (width == 0 || height == 0) {
    return kDefaultVideoBitrate;
  }
  const double bitrate =
      static_cast<double>(width) * height * frames_per_second * 0.1;
  if (bitrate < kMinimumVideoBitrate) {
    return kMinimumVideoBitrate;
  }
  if (bitrate > kMaximumVideoBitrate) {
    return kMaximumVideoBitrate;
  }
  return static_cast<UINT32>(bitrate);
}

// Adds what the H.264 encoder requires of its output type and the camera's own
// type does not carry.
//
// Copied from the camera, a raw video type brings the picture with it: frame
// size, frame rate and interlace mode. It cannot bring the encoder's own
// settings, and the encoder refuses a type that is missing any required
// attribute — which the capture engine reports as MF_E_INVALIDMEDIATYPE the
// moment recording starts, reaching the app as "the data specified for the media
// type is invalid, inconsistent, or not supported by this object", a message
// that names neither the attribute nor the encoder.
void CompleteEncoderMediaType(IMFMediaType* pType,
                              const PlatformMediaSettings& media_settings) {
  if (media_settings.video_bitrate()) {
    assert(*media_settings.video_bitrate() > 0);
    SetVideoBitrate(pType, static_cast<UINT32>(*media_settings.video_bitrate()));
  } else {
    SetVideoBitrate(pType, DefaultVideoBitrate(pType));
  }

  UINT32 aspect_numerator = 0;
  UINT32 aspect_denominator = 0;
  if (FAILED(MFGetAttributeRatio(pType, MF_MT_PIXEL_ASPECT_RATIO,
                                 &aspect_numerator, &aspect_denominator)) ||
      !aspect_denominator) {
    // Square pixels, which is what a camera that does not say otherwise has.
    MFSetAttributeRatio(pType, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  }

  UINT32 interlace_mode = 0;
  if (FAILED(pType->GetUINT32(MF_MT_INTERLACE_MODE, &interlace_mode))) {
    pType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  }
}

HRESULT RecordHandler::InitRecordSink(IMFCaptureEngine* capture_engine,
                                      IMFMediaType* base_media_type) {
  assert(!file_path_.empty());
  assert(capture_engine);
  assert(base_media_type);

  HRESULT hr = S_OK;
  if (record_sink_) {
    // If record sink already exists, only update output filename.
    hr = record_sink_->SetOutputFileName(Utf16FromUtf8(file_path_).c_str());

    if (FAILED(hr)) {
      record_sink_ = nullptr;
    }
    return hr;
  }

  ComPtr<IMFMediaType> video_record_media_type;
  ComPtr<IMFCaptureSink> capture_sink;

  // Gets sink from capture engine with record type.

  hr = capture_engine->GetSink(MF_CAPTURE_ENGINE_SINK_TYPE_RECORD,
                               &capture_sink);
  if (FAILED(hr)) {
    return hr;
  }

  hr = capture_sink.As(&record_sink_);
  if (FAILED(hr)) {
    return hr;
  }

  // Removes existing streams if available.
  hr = record_sink_->RemoveAllStreams();
  if (FAILED(hr)) {
    return hr;
  }

  hr = BuildMediaTypeForVideoCapture(base_media_type,
                                     video_record_media_type.GetAddressOf(),
                                     MFVideoFormat_H264);
  if (FAILED(hr)) {
    return hr;
  }

  if (media_settings_.frames_per_second()) {
    assert(*media_settings_.frames_per_second() > 0);
    SetFrameRate(video_record_media_type.Get(),
                 static_cast<UINT32>(*media_settings_.frames_per_second()), 1);
  }

  CompleteEncoderMediaType(video_record_media_type.Get(), media_settings_);

  DWORD video_record_sink_stream_index;
  hr = record_sink_->AddStream(
      (DWORD)MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_VIDEO_RECORD,
      video_record_media_type.Get(), nullptr, &video_record_sink_stream_index);
  if (FAILED(hr)) {
    return hr;
  }

  if (media_settings_.enable_audio()) {
    ComPtr<IMFMediaType> audio_record_media_type;
    HRESULT audio_capture_hr = S_OK;
    audio_capture_hr =
        BuildMediaTypeForAudioCapture(audio_record_media_type.GetAddressOf());

    if (SUCCEEDED(audio_capture_hr)) {
      if (media_settings_.audio_bitrate()) {
        assert(*media_settings_.audio_bitrate() > 0);
        SetAudioBitrate(audio_record_media_type.Get(),
                        static_cast<UINT32>(*media_settings_.audio_bitrate()));
      }

      DWORD audio_record_sink_stream_index;
      hr = record_sink_->AddStream(
          (DWORD)MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_AUDIO,
          audio_record_media_type.Get(), nullptr,
          &audio_record_sink_stream_index);
    }

    if (FAILED(hr)) {
      return hr;
    }
  }

  hr = record_sink_->SetOutputFileName(Utf16FromUtf8(file_path_).c_str());

  return hr;
}

HRESULT RecordHandler::StartRecord(const std::string& file_path,
                                   IMFCaptureEngine* capture_engine,
                                   IMFMediaType* base_media_type) {
  assert(!file_path.empty());
  assert(capture_engine);
  assert(base_media_type);

  file_path_ = file_path;
  recording_start_timestamp_us_ = -1;
  recording_duration_us_ = 0;

  HRESULT hr = InitRecordSink(capture_engine, base_media_type);
  if (FAILED(hr)) {
    return hr;
  }

  recording_state_ = RecordState::kStarting;
  return capture_engine->StartRecord();
}

HRESULT RecordHandler::StopRecord(IMFCaptureEngine* capture_engine) {
  if (recording_state_ == RecordState::kRunning) {
    recording_state_ = RecordState::kStopping;
    return capture_engine->StopRecord(true, false);
  }
  return E_FAIL;
}

void RecordHandler::OnRecordStarted() {
  if (recording_state_ == RecordState::kStarting) {
    recording_state_ = RecordState::kRunning;
  }
}

void RecordHandler::OnRecordStopped() {
  if (recording_state_ == RecordState::kStopping) {
    file_path_ = "";
    recording_start_timestamp_us_ = -1;
    recording_duration_us_ = 0;
    recording_state_ = RecordState::kNotStarted;
  }
}

void RecordHandler::UpdateRecordingTime(uint64_t timestamp) {
  if (recording_start_timestamp_us_ < 0) {
    recording_start_timestamp_us_ = timestamp;
  }

  recording_duration_us_ = (timestamp - recording_start_timestamp_us_);
}

}  // namespace camera_windows
