#ifndef PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_SOURCE_READER_CAPTURE_H_
#define PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_SOURCE_READER_CAPTURE_H_

#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace camera_windows {

// Capture Engine does not insert a decoder for some compressed-only UVC
// capture streams. Source Reader's advanced processing negotiates that chain.
class SourceReaderCapture {
 public:
  using Frame = std::function<void(uint8_t*, uint32_t)>;
  using Error = std::function<void(HRESULT)>;
  ~SourceReaderCapture();
  HRESULT Initialize(IMFMediaSource* source, uint32_t max_height,
                     uint32_t width, uint32_t height, uint32_t fps);
  void Start(Frame frame, Error error);
  void Stop();
  HRESULT TakePicture(const std::string& path);
  HRESULT StartRecord(const std::string& path);
  HRESULT StopRecord();
  uint32_t width() const { return width_; }
  uint32_t height() const { return height_; }

 private:
  friend class ReaderCallback;
  void OnSample(HRESULT status, DWORD flags, LONGLONG timestamp,
                 IMFSample* sample);
  Microsoft::WRL::ComPtr<IMFMediaSource> source_;
  Microsoft::WRL::ComPtr<IMFSourceReader> reader_;
  Microsoft::WRL::ComPtr<IMFMediaType> output_;
  Microsoft::WRL::ComPtr<IMFSinkWriter> writer_;
  Microsoft::WRL::ComPtr<IMFSourceReaderCallback> callback_;
  Frame frame_;
  Error error_;
  uint64_t frames_ = 0;
  std::atomic<bool> stopping_{false};
  std::mutex mutex_;
  std::vector<uint8_t> latest_;
  uint32_t width_ = 0, height_ = 0;
  uint32_t rate_num_ = 30, rate_den_ = 1;
  DWORD writer_stream_ = 0;
  LONGLONG first_timestamp_ = -1;
  HRESULT recording_error_ = S_OK;
};
}  // namespace camera_windows
#endif
