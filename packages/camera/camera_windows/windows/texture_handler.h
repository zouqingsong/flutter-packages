// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_TEXTURE_HANDLER_H_
#define PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_TEXTURE_HANDLER_H_

#include <d3d11.h>
#include <flutter/texture_registrar.h>
#include <mfobjects.h>
#include <wrl/client.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace camera_windows {

using Microsoft::WRL::ComPtr;

// Describes flutter desktop pixelbuffers pixel data order.
struct FlutterDesktopPixel {
  uint8_t r = 0;
  uint8_t g = 0;
  uint8_t b = 0;
  uint8_t a = 0;
};

// Describes MFVideoFormat_RGB32 data order.
struct MFVideoFormatRGB32Pixel {
  uint8_t b = 0;
  uint8_t g = 0;
  uint8_t r = 0;
  uint8_t x = 0;
};

// Handles the registration of Flutter textures, pixel buffers, and the
// conversion of texture formats.
class TextureHandler {
 public:
  TextureHandler(flutter::TextureRegistrar* texture_registrar,
                 ComPtr<ID3D11Device> d3d_device);
  virtual ~TextureHandler();

  // Prevent copying.
  TextureHandler(TextureHandler const&) = delete;
  TextureHandler& operator=(TextureHandler const&) = delete;

  // True when the preview is drawn from a D3D11 texture shared with the
  // engine, so samples are converted on the GPU instead of on the CPU.
  bool UsesGpuTexture() const { return use_gpu_; }

  // Switches the GPU preview on or off for cameras opened afterwards.
  //
  // This is a developer option, off unless it is turned on: the CPU path is the
  // one that has been everywhere, and a conversion that fails on a particular
  // driver shows up as a preview that stays black. A camera that is already
  // running keeps the path it was built with.
  static void SetGpuTextureEnabled(bool enabled);

  // Whether the GPU preview is switched on, from the developer option or, when
  // that was never set, from the environment.
  static bool GpuTextureEnabled();

  // Updates source data buffer with given data.
  bool UpdateBuffer(uint8_t* data, uint32_t data_length);

  // Converts a capture engine sample on the GPU and publishes the result.
  // Returns false when the sample cannot be used that way, in which case the
  // caller falls back to UpdateBuffer.
  bool UpdateGpuSample(IMFSample* sample);

  // Registers texture and updates given texture_id pointer value.
  int64_t RegisterTexture();

  // Updates current preview texture size.
  void UpdateTextureSize(uint32_t width, uint32_t height) {
    preview_frame_width_ = width;
    preview_frame_height_ = height;
  }

  // Sets software mirror state.
  void SetMirrorPreviewState(bool mirror) { mirror_preview_ = mirror; }

 private:
  // Informs flutter texture registrar of updated texture.
  void OnBufferUpdated();

  // Converts local pixel buffer to flutter pixel buffer.
  const FlutterDesktopPixelBuffer* ConvertPixelBufferForFlutter(size_t width,
                                                                size_t height);

  // Writes RGBA out of the sink's RGB32 frame. Called on the sample thread, so
  // the engine's texture callback only has to hand the result over.
  static void ConvertFrame(const uint8_t* source, uint8_t* dest, uint32_t width,
                           uint32_t height, bool mirror);

  // Checks if texture registrar, texture id and texture are available.
  bool TextureRegistered() {
    return texture_registrar_ && texture_ && texture_id_ > -1;
  }

  // Gives Flutter the texture the engine wrote into. Called on the raster
  // thread each time the texture is sampled.
  const FlutterDesktopGpuSurfaceDescriptor* ObtainDescriptor(size_t width,
                                                             size_t height);

  // Creates the BGRA texture Flutter samples, along with the shared handle
  // Flutter opens it with. Cheap to call again for an unchanged size.
  bool EnsureSharedOutput(uint32_t width, uint32_t height);

  // Sets up (or reuses) the video processor that turns a YUY2/NV12 frame into
  // BGRA without touching system memory.
  bool EnsureVideoProcessor(uint32_t width, uint32_t height,
                            DXGI_FORMAT input_format);

  // Compiles the pass that mirrors the converted frame when preview mirroring
  // is on. A video processor can rotate but cannot reflect, so the flip needs
  // a draw.
  bool EnsureMirrorShader();

  // Runs the video processor over one frame of the engine's texture.
  bool ConvertOnGpu(ID3D11Texture2D* input, UINT subresource,
                    ID3D11Texture2D* target);

  // Draws |converted_texture_| into the output texture left-to-right reversed.
  bool MirrorIntoOutput();

  // Copies a CPU frame into the shared output texture. Used when a sample
  // arrives without a GPU surface even though the GPU texture is registered.
  void UploadToOutput(const uint8_t* bgra, uint32_t width, uint32_t height);

  bool mirror_preview_ = true;
  int64_t texture_id_ = -1;
  uint32_t bytes_per_pixel_ = 4;
  uint32_t preview_frame_width_ = 0;
  uint32_t preview_frame_height_ = 0;
  std::vector<uint8_t> dest_buffer_;

  // Whether dest_buffer_ holds a complete, usable frame.
  bool frame_ready_ = false;
  std::unique_ptr<flutter::TextureVariant> texture_;
  std::unique_ptr<FlutterDesktopPixelBuffer> flutter_desktop_pixel_buffer_ =
      nullptr;
  flutter::TextureRegistrar* texture_registrar_ = nullptr;

  // The engine's device, and what is drawn from it. All of it is created and
  // used on the sample thread; the descriptor callback only reads the handle.
  bool use_gpu_ = false;

  // The developer option, as -1 (never set), 0 or 1. Static because it is a
  // decision about the machine, not about one camera.
  static std::atomic<int> gpu_texture_setting_;
  ComPtr<ID3D11Device> d3d_device_;
  ComPtr<ID3D11DeviceContext> d3d_context_;
  ComPtr<ID3D11VideoDevice> video_device_;
  ComPtr<ID3D11VideoContext> video_context_;
  ComPtr<ID3D11VideoProcessorEnumerator> video_enumerator_;
  ComPtr<ID3D11VideoProcessor> video_processor_;
  ComPtr<ID3D11Texture2D> converted_texture_;
  ComPtr<ID3D11ShaderResourceView> converted_view_;
  ComPtr<ID3D11Texture2D> output_texture_;
  ComPtr<ID3D11RenderTargetView> output_view_;
  ComPtr<ID3D11VertexShader> mirror_vertex_shader_;
  ComPtr<ID3D11PixelShader> mirror_pixel_shader_;
  ComPtr<ID3D11SamplerState> mirror_sampler_;
  HANDLE output_shared_handle_ = nullptr;
  FlutterDesktopGpuSurfaceDescriptor descriptor_{};
  uint32_t gpu_width_ = 0;
  uint32_t gpu_height_ = 0;
  DXGI_FORMAT input_format_ = DXGI_FORMAT_UNKNOWN;
  bool video_processor_ready_ = false;
  // The mirror state the processor and its textures were built for: flipping
  // preview mirroring means the second pass has to be set up or torn down.
  bool processor_mirror_ = false;
  bool mirror_shader_checked_ = false;
  bool mirror_shader_ready_ = false;

  std::mutex buffer_mutex_;
};

}  // namespace camera_windows

#endif  // PACKAGES_CAMERA_CAMERA_WINDOWS_WINDOWS_TEXTURE_HANDLER_H_
