
// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "capture_engine_listener.h"

#include <d3d11.h>
#include <mfcaptureengine.h>
#include <wrl/client.h>

#include <iostream>

namespace camera_windows {

using Microsoft::WRL::ComPtr;

// IUnknown
STDMETHODIMP_(ULONG) CaptureEngineListener::AddRef() {
  return InterlockedIncrement(&ref_);
}

// IUnknown
STDMETHODIMP_(ULONG)
CaptureEngineListener::Release() {
  LONG ref = InterlockedDecrement(&ref_);
  if (ref == 0) {
    delete this;
  }
  return ref;
}

// IUnknown
STDMETHODIMP_(HRESULT)
CaptureEngineListener::QueryInterface(const IID& riid, void** ppv) {
  *ppv = nullptr;

  if (riid == IID_IMFCaptureEngineOnEventCallback) {
    *ppv = static_cast<IMFCaptureEngineOnEventCallback*>(this);
    ((IUnknown*)*ppv)->AddRef();
    return S_OK;
  } else if (riid == IID_IMFCaptureEngineOnSampleCallback) {
    *ppv = static_cast<IMFCaptureEngineOnSampleCallback*>(this);
    ((IUnknown*)*ppv)->AddRef();
    return S_OK;
  }

  return E_NOINTERFACE;
}

STDMETHODIMP CaptureEngineListener::OnEvent(IMFMediaEvent* event) {
  if (observer_) {
    observer_->OnEvent(event);
  }
  return S_OK;
}

// IMFCaptureEngineOnSampleCallback
HRESULT CaptureEngineListener::OnSample(IMFSample* sample) {
  HRESULT hr = S_OK;

  if (this->observer_ && sample) {
    LONGLONG raw_time_stamp = 0;
    // Receives the presentation time, in 100-nanosecond units.
    sample->GetSampleTime(&raw_time_stamp);

    // Report time in microseconds.
    this->observer_->UpdateCaptureTime(
        static_cast<uint64_t>(raw_time_stamp / 10));

    if (!this->observer_->IsReadyForSample() &&
        !this->observer_->IsServingImageStream()) {
      // Nothing to draw on and nothing subscribed: the sample is of no use to
      // anyone. Previewing off is not enough of a reason on its own, because an
      // image stream can be served with no preview at all.
      return hr;
    }

    // The GPU path keeps the frame where the engine put it. An image stream is
    // a CPU consumer, so it keeps the sample on the old route.
    if (this->observer_->UsesGpuTexture() &&
        !this->observer_->IsServingImageStream() &&
        this->observer_->UpdateGpuSample(sample)) {
      return hr;
    }

    ComPtr<IMFMediaBuffer> buffer;
    hr = sample->ConvertToContiguousBuffer(&buffer);

    // Said once per session: whether the frame is still on the GPU decides
    // whether a zero-copy texture is possible here at all, and a camera whose
    // driver hands back system memory cannot be told apart from one that does
    // without this line.
    static bool surface_reported = false;
    if (!surface_reported) {
      surface_reported = true;
      ComPtr<IMFMediaBuffer> first_buffer;
      ComPtr<IMFDXGIBuffer> dxgi_buffer;
      if (SUCCEEDED(sample->GetBufferByIndex(0, first_buffer.GetAddressOf())) &&
          SUCCEEDED(first_buffer.As(&dxgi_buffer))) {
        ComPtr<ID3D11Texture2D> texture;
        HRESULT texture_hr =
            dxgi_buffer->GetResource(IID_PPV_ARGS(texture.GetAddressOf()));
        D3D11_TEXTURE2D_DESC description{};
        if (SUCCEEDED(texture_hr) && texture) {
          texture->GetDesc(&description);
        }
        std::cerr << "camera_windows: preview samples are DXGI-backed; texture "
                  << (texture ? "ok" : "unavailable") << ", "
                  << description.Width << "x" << description.Height
                  << ", format " << static_cast<int>(description.Format)
                  << std::endl;
      } else {
        std::cerr << "camera_windows: preview samples are system memory (no "
                     "IMFDXGIBuffer)"
                  << std::endl;
      }
    }

    // Draw the frame.
    if (SUCCEEDED(hr) && buffer) {
      DWORD max_length = 0;
      DWORD current_length = 0;
      uint8_t* data;
      if (SUCCEEDED(buffer->Lock(&data, &max_length, &current_length))) {
        this->observer_->UpdateBuffer(data, current_length);
      }
      hr = buffer->Unlock();
    }
  }
  return hr;
}

}  // namespace camera_windows
