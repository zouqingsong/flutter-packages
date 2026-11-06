#include "source_reader_capture.h"

#include <mfapi.h>
#include <mferror.h>
#include <wincodec.h>

#include <algorithm>
#include <cmath>
#include <iostream>

#include "string_utils.h"

namespace camera_windows {
using Microsoft::WRL::ComPtr;
constexpr DWORD kVideoStream =
    static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);

class ReaderCallback final : public IMFSourceReaderCallback {
 public:
  explicit ReaderCallback(SourceReaderCapture* owner) : owner_(owner) {}
  STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
    if (!object) return E_POINTER;
    if (iid == IID_IUnknown || iid == __uuidof(IMFSourceReaderCallback)) {
      *object = static_cast<IMFSourceReaderCallback*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
  STDMETHODIMP_(ULONG) Release() override {
    const ULONG remaining = --references_;
    if (!remaining) delete this;
    return remaining;
  }
  STDMETHODIMP OnReadSample(HRESULT status, DWORD, DWORD flags,
                            LONGLONG timestamp, IMFSample* sample) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (owner_) owner_->OnSample(status, flags, timestamp, sample);
    return S_OK;
  }
  STDMETHODIMP OnEvent(DWORD, IMFMediaEvent*) override { return S_OK; }
  STDMETHODIMP OnFlush(DWORD) override { return S_OK; }
  void Detach() {
    std::lock_guard<std::mutex> lock(mutex_);
    owner_ = nullptr;
  }
 private:
  std::atomic<ULONG> references_{1};
  std::mutex mutex_;
  SourceReaderCapture* owner_;
};

SourceReaderCapture::~SourceReaderCapture() { Stop(); }

HRESULT SourceReaderCapture::Initialize(IMFMediaSource* source,
                                        uint32_t max_height, uint32_t width,
                                        uint32_t height, uint32_t fps) {
  source_ = source;
  ComPtr<IMFAttributes> options;
  HRESULT hr = MFCreateAttributes(&options, 1);
  if (FAILED(hr)) return hr;
  options->SetUINT32(MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);
  callback_.Attach(new ReaderCallback(this));
  options->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, callback_.Get());
  hr = MFCreateSourceReaderFromMediaSource(source, options.Get(), &reader_);
  if (FAILED(hr)) return hr;
  ComPtr<IMFMediaType> best;
  uint64_t best_area = 0;
  bool best_fits = false;
  double best_rate_distance = 1e9;
  for (DWORD i = 0;; ++i) {
    ComPtr<IMFMediaType> type;
    if (FAILED(reader_->GetNativeMediaType(kVideoStream,
                                           i, &type))) break;
    UINT32 w = 0, h = 0, n = 0, d = 0;
    if (FAILED(MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &w, &h)) ||
        FAILED(MFGetAttributeRatio(type.Get(), MF_MT_FRAME_RATE, &n, &d)) ||
        !w || !h || !d) continue;
    if (width && (w != width || h != height)) continue;
    const uint64_t area = static_cast<uint64_t>(w) * h;
    const bool fits = h <= max_height;
    const double distance = std::abs(static_cast<double>(n) / d -
                                     (fps ? fps : 30));
    if (!best || (fits && !best_fits) ||
        (fits == best_fits &&
         ((fits ? area > best_area : area < best_area) ||
          (area == best_area && distance < best_rate_distance)))) {
      best = type;
      best_area = area;
      best_fits = fits;
      best_rate_distance = distance;
    }
  }
  if (!best) return MF_E_INVALIDMEDIATYPE;
  UINT32 selected_w = 0, selected_h = 0, selected_n = 0, selected_d = 0;
  GUID selected_subtype = GUID_NULL;
  MFGetAttributeSize(best.Get(), MF_MT_FRAME_SIZE, &selected_w, &selected_h);
  MFGetAttributeRatio(best.Get(), MF_MT_FRAME_RATE, &selected_n, &selected_d);
  best->GetGUID(MF_MT_SUBTYPE, &selected_subtype);
  std::cerr << "camera_windows: SourceReader native " << selected_w << "x"
            << selected_h << " rate=" << selected_n << "/" << selected_d
            << " subtype=0x" << std::hex << selected_subtype.Data1 << std::dec
            << std::endl;
  hr = reader_->SetCurrentMediaType(kVideoStream,
                                     nullptr, best.Get());
  if (FAILED(hr)) {
    std::cerr << "camera_windows: native type rejected 0x" << std::hex
              << static_cast<uint32_t>(hr) << std::dec << std::endl;
    return hr;
  }
  hr = MFCreateMediaType(&output_);
  if (FAILED(hr)) return hr;
  output_->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output_->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  hr = reader_->SetCurrentMediaType(kVideoStream,
                                     nullptr, output_.Get());
  if (FAILED(hr)) return hr;
  hr = reader_->GetCurrentMediaType(kVideoStream,
                                     output_.ReleaseAndGetAddressOf());
  if (FAILED(hr)) return hr;
  MFGetAttributeRatio(output_.Get(), MF_MT_FRAME_RATE, &rate_num_, &rate_den_);
  return MFGetAttributeSize(output_.Get(), MF_MT_FRAME_SIZE, &width_, &height_);
}

void SourceReaderCapture::Start(Frame frame, Error error) {
  stopping_ = false;
  frame_ = std::move(frame);
  error_ = std::move(error);
  const HRESULT hr = reader_->ReadSample(kVideoStream, 0, nullptr, nullptr,
                                         nullptr, nullptr);
  if (FAILED(hr)) error_(hr);
}

void SourceReaderCapture::OnSample(HRESULT hr, DWORD flags,
                                    LONGLONG timestamp, IMFSample* sample) {
  if (stopping_) return;
  if (FAILED(hr) || (flags & (MF_SOURCE_READERF_ERROR |
                              MF_SOURCE_READERF_ENDOFSTREAM))) {
    error_(FAILED(hr) ? hr : E_FAIL);
    return;
  }
  if (sample) {
    ComPtr<IMFMediaBuffer> buffer;
    hr = sample->ConvertToContiguousBuffer(&buffer);
    if (FAILED(hr)) {
      error_(hr);
      return;
    }
    BYTE* data = nullptr;
    DWORD length = 0;
    hr = buffer->Lock(&data, nullptr, &length);
    if (FAILED(hr)) {
      error_(hr);
      return;
    }
    if (length == width_ * height_ * 4) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        latest_.assign(data, data + length);
        if (writer_ && SUCCEEDED(recording_error_)) {
          if (first_timestamp_ < 0) first_timestamp_ = timestamp;
          sample->SetSampleTime(timestamp - first_timestamp_);
          sample->SetSampleDuration(10000000LL * rate_den_ / rate_num_);
          recording_error_ = writer_->WriteSample(writer_stream_, sample);
        }
      }
      frame_(data, length);
      if (++frames_ == 1) {
        std::cerr << "camera_windows: SourceReader decoded frame "
                  << width_ << "x" << height_ << ", bytes=" << length
                  << std::endl;
      }
    }
    buffer->Unlock();
  }
  if (!stopping_) {
    hr = reader_->ReadSample(kVideoStream, 0, nullptr, nullptr, nullptr, nullptr);
    if (FAILED(hr)) error_(hr);
  }
}

void SourceReaderCapture::Stop() {
  stopping_ = true;
  // Detach before releasing the reader: late asynchronous callbacks must not
  // retain a raw controller pointer or race texture destruction.
  if (callback_) static_cast<ReaderCallback*>(callback_.Get())->Detach();
  if (reader_) reader_->Flush(kVideoStream);
  if (source_) source_->Shutdown();
  StopRecord();
  reader_.Reset();
  source_.Reset();
  callback_.Reset();
}

HRESULT SourceReaderCapture::TakePicture(const std::string& path) {
  std::vector<uint8_t> pixels;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    pixels = latest_;
  }
  if (pixels.empty()) return MF_E_NOTACCEPTING;
  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (FAILED(hr)) return hr;
  ComPtr<IWICStream> stream;
  hr = factory->CreateStream(&stream);
  if (FAILED(hr)) return hr;
  hr = stream->InitializeFromFilename(Utf16FromUtf8(path).c_str(), GENERIC_WRITE);
  if (FAILED(hr)) return hr;
  ComPtr<IWICBitmapEncoder> encoder;
  hr = factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, &encoder);
  if (FAILED(hr)) return hr;
  hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  if (FAILED(hr)) return hr;
  ComPtr<IWICBitmapFrameEncode> frame;
  hr = encoder->CreateNewFrame(&frame, nullptr);
  if (FAILED(hr)) return hr;
  hr = frame->Initialize(nullptr);
  if (FAILED(hr)) return hr;
  frame->SetSize(width_, height_);
  WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
  hr = frame->SetPixelFormat(&format);
  if (FAILED(hr)) return hr;
  std::vector<uint8_t> bgr(static_cast<size_t>(width_) * height_ * 3);
  for (size_t i = 0, j = 0; i < pixels.size(); i += 4, j += 3) {
    std::copy_n(pixels.data() + i, 3, bgr.data() + j);
  }
  hr = frame->WritePixels(height_, width_ * 3,
                           static_cast<UINT>(bgr.size()), bgr.data());
  if (FAILED(hr)) return hr;
  hr = frame->Commit();
  return FAILED(hr) ? hr : encoder->Commit();
}

HRESULT SourceReaderCapture::StartRecord(const std::string& path) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (writer_) return MF_E_INVALIDREQUEST;
  ComPtr<IMFSinkWriter> writer;
  auto configure = [&](uint32_t width, uint32_t height) -> HRESULT {
    writer.Reset();
    HRESULT hr = MFCreateSinkWriterFromURL(Utf16FromUtf8(path).c_str(), nullptr,
                                            nullptr, &writer);
    if (FAILED(hr)) return hr;
    ComPtr<IMFMediaType> encoded;
    hr = MFCreateMediaType(&encoded);
    if (FAILED(hr)) return hr;
    encoded->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    encoded->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    encoded->SetUINT32(MF_MT_AVG_BITRATE, static_cast<UINT32>(
        std::min<uint64_t>(40000000, static_cast<uint64_t>(width) * height * 4)));
    encoded->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    MFSetAttributeSize(encoded.Get(), MF_MT_FRAME_SIZE, width, height);
    MFSetAttributeRatio(encoded.Get(), MF_MT_FRAME_RATE, rate_num_, rate_den_);
    MFSetAttributeRatio(encoded.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    hr = writer->AddStream(encoded.Get(), &writer_stream_);
    if (FAILED(hr)) return hr;
    hr = writer->SetInputMediaType(writer_stream_, output_.Get(), nullptr);
    if (FAILED(hr)) return hr;
    return writer->BeginWriting();
  };
  HRESULT hr = configure(width_, height_);
  if (FAILED(hr) && (width_ > 4096 || height_ > 2304)) {
    // The Windows H.264 encoder cannot accept a 12 MP sensor frame. Negotiate
    // an aspect-preserving video size; preview and JPEG stay at sensor size.
    const double scale = std::min<double>(4096.0 / width_, 2304.0 / height_);
    const uint32_t width = static_cast<uint32_t>(width_ * scale) & ~1u;
    const uint32_t height = static_cast<uint32_t>(height_ * scale) & ~1u;
    hr = configure(width, height);
    if (SUCCEEDED(hr)) {
      std::cerr << "camera_windows: H264 recording " << width << "x" << height
                << " from " << width_ << "x" << height_ << std::endl;
    }
  }
  if (FAILED(hr)) return hr;
  first_timestamp_ = -1;
  recording_error_ = S_OK;
  writer_ = writer;
  return S_OK;
}

HRESULT SourceReaderCapture::StopRecord() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!writer_) return S_OK;
  const HRESULT finalized = writer_->Finalize();
  writer_.Reset();
  return FAILED(recording_error_) ? recording_error_ : finalized;
}
}  // namespace camera_windows
