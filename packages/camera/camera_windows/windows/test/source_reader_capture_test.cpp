#include "source_reader_capture.h"

#include <mfapi.h>
#include <gtest/gtest.h>
#include <wrl/client.h>

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <filesystem>
#include <mutex>
#include <thread>

namespace camera_windows {
using Microsoft::WRL::ComPtr;

TEST(SourceReaderCapture, ExplicitHardwareFramesPhotoRecordAndReopen) {
  char* directory = nullptr;
  size_t size = 0;
  _dupenv_s(&directory, &size, "CAMERA_HARDWARE_SMOKE_DIR");
  if (!directory) GTEST_SKIP() << "Set CAMERA_HARDWARE_SMOKE_DIR to opt in";
  const std::string output(directory);
  free(directory);
  std::filesystem::create_directories(output);
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  ASSERT_TRUE(SUCCEEDED(com));
  ASSERT_EQ(MFStartup(MF_VERSION), S_OK);
  for (int session = 0; session < 2; ++session) {
    ComPtr<IMFAttributes> attributes;
    ASSERT_EQ(MFCreateAttributes(&attributes, 1), S_OK);
    attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                        MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    IMFActivate** devices = nullptr;
    UINT32 count = 0;
    ASSERT_EQ(MFEnumDeviceSources(attributes.Get(), &devices, &count), S_OK);
    ComPtr<IMFMediaSource> source;
    for (UINT32 i = 0; i < count; ++i) {
      WCHAR* name = nullptr;
      UINT32 length = 0;
      devices[i]->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
                                      &name, &length);
      if (name && wcsstr(name, L"Flexion")) {
        devices[i]->ActivateObject(IID_PPV_ARGS(&source));
      }
      CoTaskMemFree(name);
      devices[i]->Release();
    }
    CoTaskMemFree(devices);
    ASSERT_NE(source.Get(), nullptr);
    SourceReaderCapture capture;
    // Cover both the fallback below the camera's smallest mode and the app's
    // initial desktop preset (maximum sensor resolution).
    ASSERT_EQ(capture.Initialize(source.Get(), session ? UINT32_MAX : 720,
                                 0, 0, 0), S_OK);
    std::mutex mutex;
    std::condition_variable changed;
    int frames = 0;
    HRESULT error = S_OK;
    capture.Start(
        [&](uint8_t*, uint32_t length) {
          std::lock_guard<std::mutex> lock(mutex);
          EXPECT_EQ(length, capture.width() * capture.height() * 4);
          ++frames;
          changed.notify_all();
        },
        [&](HRESULT hr) {
          std::lock_guard<std::mutex> lock(mutex);
          error = hr;
          changed.notify_all();
        });
    {
      std::unique_lock<std::mutex> lock(mutex);
      EXPECT_TRUE(changed.wait_for(lock, std::chrono::seconds(20),
                                    [&] { return frames >= 4 || FAILED(error); }));
      EXPECT_EQ(error, S_OK);
      EXPECT_GE(frames, 4);
    }
    const std::string photo = output + "/reader-" + std::to_string(session) + ".jpg";
    const std::string video = output + "/reader-" + std::to_string(session) + ".mp4";
    EXPECT_EQ(capture.TakePicture(photo), S_OK);
    EXPECT_EQ(capture.StartRecord(video), S_OK);
    std::this_thread::sleep_for(std::chrono::seconds(3));
    EXPECT_EQ(capture.StopRecord(), S_OK);
    const auto start = std::chrono::steady_clock::now();
    capture.Stop();
    EXPECT_LT(std::chrono::steady_clock::now() - start, std::chrono::seconds(5));
    EXPECT_GT(std::filesystem::file_size(photo), 1000u);
    EXPECT_GT(std::filesystem::file_size(video), 1000u);
  }
  MFShutdown();
  CoUninitialize();
}
}  // namespace camera_windows
