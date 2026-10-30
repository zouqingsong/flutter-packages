// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "texture_handler.h"

#include <d3dcompiler.h>

#include <cassert>
#include <cstdlib>
#include <iostream>

namespace camera_windows {

namespace {

// Read when the app has not said anything, which is how a headless run — a test
// rig with no settings page to flip the switch on — turns the GPU path on.
constexpr char kGpuTextureEnvironment[] = "CAMERA_WINDOWS_GPU_TEXTURE";

// A fullscreen triangle, so the flip needs no vertex buffer.
constexpr char kMirrorShaderSource[] = R"(
Texture2D frame : register(t0);
SamplerState frame_sampler : register(s0);

struct VertexOut {
  float4 position : SV_Position;
  float2 uv : TEXCOORD0;
};

VertexOut MirrorVertex(uint id : SV_VertexID) {
  VertexOut output;
  float2 uv = float2((id << 1) & 2, id & 2);
  output.uv = float2(1.0 - uv.x, uv.y);
  output.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
  return output;
}

float4 MirrorPixel(VertexOut input) : SV_Target {
  return frame.Sample(frame_sampler, input.uv);
}
)";

}  // namespace

std::atomic<int> TextureHandler::gpu_texture_setting_{-1};

void TextureHandler::SetGpuTextureEnabled(bool enabled) {
  gpu_texture_setting_.store(enabled ? 1 : 0);
}

bool TextureHandler::GpuTextureEnabled() {
  const int setting = gpu_texture_setting_.load();
  if (setting >= 0) {
    return setting == 1;
  }

  char value[8] = {};
  size_t length = 0;
  if (getenv_s(&length, value, sizeof(value), kGpuTextureEnvironment) != 0 ||
      length == 0) {
    return false;
  }
  return value[0] == '1';
}

TextureHandler::TextureHandler(flutter::TextureRegistrar* texture_registrar,
                               ComPtr<ID3D11Device> d3d_device)
    : texture_registrar_(texture_registrar), d3d_device_(std::move(d3d_device)) {
  if (!GpuTextureEnabled() || !d3d_device_) {
    return;
  }

  // A video processor needs a device created for video, and every conversion
  // below runs on the context the capture engine already renders with.
  if (FAILED(d3d_device_.As(&video_device_))) {
    std::cerr << "camera_windows: device cannot convert video, preview stays on "
                 "the CPU path"
              << std::endl;
    return;
  }
  d3d_device_->GetImmediateContext(d3d_context_.GetAddressOf());
  if (!d3d_context_ || FAILED(d3d_context_.As(&video_context_))) {
    std::cerr << "camera_windows: no immediate context for preview conversion"
              << std::endl;
    return;
  }
  use_gpu_ = true;
}

TextureHandler::~TextureHandler() {
  // Texture might still be processed while destructor is called.
  // Lock mutex for safe destruction
  const std::lock_guard<std::mutex> lock(buffer_mutex_);
  if (texture_registrar_ && texture_id_ > 0) {
    texture_registrar_->UnregisterTexture(texture_id_);
  }
  texture_id_ = -1;
  texture_ = nullptr;
  texture_registrar_ = nullptr;
}

int64_t TextureHandler::RegisterTexture() {
  if (!texture_registrar_) {
    return -1;
  }

  if (use_gpu_) {
    texture_ = std::make_unique<flutter::TextureVariant>(
        flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [this](size_t width, size_t height) {
              return this->ObtainDescriptor(width, height);
            }));
  } else {
    // Create flutter desktop pixelbuffer texture;
    texture_ =
        std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
            [this](size_t width,
                   size_t height) -> const FlutterDesktopPixelBuffer* {
              return this->ConvertPixelBufferForFlutter(width, height);
            }));
  }

  texture_id_ = texture_registrar_->RegisterTexture(texture_.get());
  return texture_id_;
}

bool TextureHandler::UpdateBuffer(uint8_t* data, uint32_t data_length) {
  {
    const std::lock_guard<std::mutex> lock(buffer_mutex_);
    if (!TextureRegistered()) {
      return false;
    }

    const uint32_t pixels = preview_frame_width_ * preview_frame_height_;
    const uint32_t expected = pixels * bytes_per_pixel_;
    // Converting here rather than in the texture callback keeps the raster thread
    // out of the work: at 4K the per-pixel pass measured 31 ms on this machine,
    // which is a whole frame interval the picture sat still for.
    frame_ready_ = pixels > 0 && data_length == expected;
    if (frame_ready_) {
      if (dest_buffer_.size() != data_length) {
        dest_buffer_.resize(data_length);
      }
      ConvertFrame(data, dest_buffer_.data(), preview_frame_width_,
                   preview_frame_height_, mirror_preview_);
      if (use_gpu_) {
        // A frame that arrives without a GPU surface still has to be drawn, or
        // the registered texture would show nothing at all.
        UploadToOutput(dest_buffer_.data(), preview_frame_width_,
                       preview_frame_height_);
      }
    }
  }
  OnBufferUpdated();
  return true;
};

void TextureHandler::ConvertFrame(const uint8_t* source, uint8_t* dest,
                                  uint32_t width, uint32_t height, bool mirror) {
  const uint32_t count = width * height;
  const uint32_t* src = reinterpret_cast<const uint32_t*>(source);
  uint32_t* dst = reinterpret_cast<uint32_t*>(dest);
  if (!mirror) {
    // RGB32 arrives B,G,R,A and Flutter reads R,G,B,A: one 32-bit operation per
    // pixel swaps the two ends and forces the alpha.
    for (uint32_t i = 0; i < count; i++) {
      const uint32_t pixel = src[i];
      dst[i] = 0xFF000000u | ((pixel & 0x00FF0000u) >> 16) |
               (pixel & 0x0000FF00u) | ((pixel & 0x000000FFu) << 16);
    }
    return;
  }
  for (uint32_t y = 0; y < height; y++) {
    const uint32_t row = y * width;
    for (uint32_t x = 0; x < width; x++) {
      const uint32_t pixel = src[row + x];
      dst[row + (width - 1 - x)] = 0xFF000000u |
                                   ((pixel & 0x00FF0000u) >> 16) |
                                   (pixel & 0x0000FF00u) |
                                   ((pixel & 0x000000FFu) << 16);
    }
  }
}

// Marks texture frame available after buffer is updated.
void TextureHandler::OnBufferUpdated() {
  if (TextureRegistered()) {
    texture_registrar_->MarkTextureFrameAvailable(texture_id_);
  }
}

const FlutterDesktopPixelBuffer* TextureHandler::ConvertPixelBufferForFlutter(
    size_t target_width, size_t target_height) {
  // Lock buffer mutex to protect texture processing
  std::unique_lock<std::mutex> buffer_lock(buffer_mutex_);
  if (!TextureRegistered() || !frame_ready_ || dest_buffer_.empty()) {
    return nullptr;
  }

  if (!flutter_desktop_pixel_buffer_) {
    flutter_desktop_pixel_buffer_ = std::make_unique<FlutterDesktopPixelBuffer>();

    // Unlocks mutex after texture is processed.
    flutter_desktop_pixel_buffer_->release_callback = [](void* release_context) {
      auto mutex = reinterpret_cast<std::mutex*>(release_context);
      mutex->unlock();
    };
  }

  flutter_desktop_pixel_buffer_->buffer = dest_buffer_.data();
  flutter_desktop_pixel_buffer_->width = preview_frame_width_;
  flutter_desktop_pixel_buffer_->height = preview_frame_height_;

  // Releases unique_lock and set mutex pointer for release context.
  flutter_desktop_pixel_buffer_->release_context = buffer_lock.release();

  return flutter_desktop_pixel_buffer_.get();
}

bool TextureHandler::UpdateGpuSample(IMFSample* sample) {
  if (!use_gpu_ || sample == nullptr) {
    return false;
  }

  ComPtr<IMFMediaBuffer> buffer;
  if (FAILED(sample->GetBufferByIndex(0, buffer.GetAddressOf()))) {
    return false;
  }
  ComPtr<IMFDXGIBuffer> dxgi_buffer;
  if (FAILED(buffer.As(&dxgi_buffer))) {
    // This driver copied the frame back to system memory before handing it
    // over; UpdateBuffer already knows how to deal with that.
    return false;
  }
  ComPtr<ID3D11Texture2D> input;
  if (FAILED(dxgi_buffer->GetResource(IID_PPV_ARGS(input.GetAddressOf()))) ||
      !input) {
    return false;
  }
  UINT subresource = 0;
  dxgi_buffer->GetSubresourceIndex(&subresource);

  D3D11_TEXTURE2D_DESC input_description{};
  input->GetDesc(&input_description);

  bool converted = false;
  {
    const std::lock_guard<std::mutex> lock(buffer_mutex_);
    if (!TextureRegistered()) {
      return false;
    }

    if (EnsureVideoProcessor(input_description.Width, input_description.Height,
                             input_description.Format) &&
        EnsureSharedOutput(input_description.Width, input_description.Height)) {
      if (mirror_preview_ && mirror_shader_ready_) {
        converted = ConvertOnGpu(input.Get(), subresource,
                                 converted_texture_.Get()) &&
                    MirrorIntoOutput();
      } else {
        converted = ConvertOnGpu(input.Get(), subresource,
                                 output_texture_.Get());
      }
      if (converted) {
        preview_frame_width_ = input_description.Width;
        preview_frame_height_ = input_description.Height;
        frame_ready_ = true;
      }
    }

    // Said once per session: a frame that never reaches the shared texture
    // otherwise shows up as a preview that stays black with no explanation.
    static bool reported = false;
    if (!converted && !reported) {
      reported = true;
      std::cerr << "camera_windows: could not convert a "
                << input_description.Width << "x" << input_description.Height
                << " preview frame (format "
                << static_cast<int>(input_description.Format)
                << ") on the GPU; unset CAMERA_WINDOWS_GPU_TEXTURE to use the "
                   "CPU path"
                << std::endl;
    }
  }

  if (converted) {
    OnBufferUpdated();
  }
  return converted;
}

const FlutterDesktopGpuSurfaceDescriptor* TextureHandler::ObtainDescriptor(
    size_t width, size_t height) {
  const std::lock_guard<std::mutex> lock(buffer_mutex_);
  if (!frame_ready_ || output_shared_handle_ == nullptr) {
    return nullptr;
  }

  // Flutter asks for the size it means to draw; the frame itself is always the
  // texture's own size.
  descriptor_.visible_width =
      width > 0 && width < gpu_width_ ? width : gpu_width_;
  descriptor_.visible_height =
      height > 0 && height < gpu_height_ ? height : gpu_height_;
  return &descriptor_;
}

bool TextureHandler::EnsureSharedOutput(uint32_t width, uint32_t height) {
  if (width == 0 || height == 0) {
    return false;
  }
  if (output_texture_ && width == gpu_width_ && height == gpu_height_ &&
      output_shared_handle_ != nullptr) {
    return true;
  }

  output_view_.Reset();
  output_texture_.Reset();
  output_shared_handle_ = nullptr;

  D3D11_TEXTURE2D_DESC description{};
  description.Width = width;
  description.Height = height;
  description.MipLevels = 1;
  description.ArraySize = 1;
  description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  description.SampleDesc.Count = 1;
  description.Usage = D3D11_USAGE_DEFAULT;
  description.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  // Flutter opens the frame by handle, which is the only way a texture can
  // cross from this device to the engine's.
  description.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  if (FAILED(d3d_device_->CreateTexture2D(&description, nullptr,
                                          output_texture_.GetAddressOf()))) {
    return false;
  }
  if (FAILED(d3d_device_->CreateRenderTargetView(
          output_texture_.Get(), nullptr, output_view_.GetAddressOf()))) {
    return false;
  }
  ComPtr<IDXGIResource> resource;
  if (FAILED(output_texture_.As(&resource)) ||
      FAILED(resource->GetSharedHandle(&output_shared_handle_))) {
    output_view_.Reset();
    output_texture_.Reset();
    return false;
  }

  descriptor_ = {};
  descriptor_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  descriptor_.handle = output_shared_handle_;
  descriptor_.width = width;
  descriptor_.height = height;
  descriptor_.visible_width = width;
  descriptor_.visible_height = height;
  descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
  descriptor_.release_callback = nullptr;
  descriptor_.release_context = nullptr;

  gpu_width_ = width;
  gpu_height_ = height;
  return true;
}

bool TextureHandler::EnsureVideoProcessor(uint32_t width, uint32_t height,
                                          DXGI_FORMAT input_format) {
  if (video_processor_ready_ && input_format == input_format_ &&
      width == gpu_width_ && height == gpu_height_ &&
      mirror_preview_ == processor_mirror_) {
    return true;
  }

  video_processor_ready_ = false;
  video_processor_.Reset();
  video_enumerator_.Reset();
  converted_view_.Reset();
  converted_texture_.Reset();
  input_format_ = DXGI_FORMAT_UNKNOWN;

  if (!video_device_ || !video_context_ || width == 0 || height == 0) {
    return false;
  }

  D3D11_VIDEO_PROCESSOR_CONTENT_DESC content{};
  content.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
  content.InputWidth = width;
  content.InputHeight = height;
  content.OutputWidth = width;
  content.OutputHeight = height;
  content.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;

  if (FAILED(video_device_->CreateVideoProcessorEnumerator(
          &content, video_enumerator_.GetAddressOf()))) {
    return false;
  }

  UINT input_flags = 0;
  if (FAILED(video_enumerator_->CheckVideoProcessorFormat(input_format,
                                                          &input_flags)) ||
      (input_flags & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT) == 0) {
    return false;
  }
  UINT output_flags = 0;
  if (FAILED(video_enumerator_->CheckVideoProcessorFormat(
          DXGI_FORMAT_B8G8R8A8_UNORM, &output_flags)) ||
      (output_flags & D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_OUTPUT) == 0) {
    return false;
  }

  if (FAILED(video_device_->CreateVideoProcessor(
          video_enumerator_.Get(), 0, video_processor_.GetAddressOf()))) {
    return false;
  }

  // The camera sends studio-range YUV; Flutter expects full-range BGRA.
  D3D11_VIDEO_PROCESSOR_COLOR_SPACE input_colour{};
  input_colour.Usage = 0;         // playback
  input_colour.RGB_Range = 0;     // full range
  input_colour.YCbCr_Matrix = 1;  // BT.709
  input_colour.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
  video_context_->VideoProcessorSetStreamColorSpace(video_processor_.Get(), 0,
                                                    &input_colour);

  D3D11_VIDEO_PROCESSOR_COLOR_SPACE output_colour{};
  output_colour.Usage = 0;
  output_colour.RGB_Range = 0;  // full range
  output_colour.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_0_255;
  video_context_->VideoProcessorSetOutputColorSpace(video_processor_.Get(),
                                                    &output_colour);

  video_context_->VideoProcessorSetStreamFrameFormat(
      video_processor_.Get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);

  // Mirroring needs a second pass because a video processor can rotate a frame
  // but has no way to reflect it.
  if (mirror_preview_ && EnsureMirrorShader()) {
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1;
    description.ArraySize = 1;
    description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags =
        D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(d3d_device_->CreateTexture2D(
            &description, nullptr, converted_texture_.GetAddressOf())) ||
        FAILED(d3d_device_->CreateShaderResourceView(
            converted_texture_.Get(), nullptr,
            converted_view_.GetAddressOf()))) {
      converted_view_.Reset();
      converted_texture_.Reset();
      mirror_shader_ready_ = false;
    }
  }

  input_format_ = input_format;
  processor_mirror_ = mirror_preview_;
  video_processor_ready_ = true;
  return true;
}

bool TextureHandler::EnsureMirrorShader() {
  if (mirror_shader_checked_) {
    return mirror_shader_ready_;
  }
  mirror_shader_checked_ = true;

  ComPtr<ID3DBlob> vertex_blob;
  ComPtr<ID3DBlob> pixel_blob;
  ComPtr<ID3DBlob> error_blob;
  const UINT compile_flags = D3DCOMPILE_OPTIMIZATION_LEVEL3;
  if (FAILED(D3DCompile(kMirrorShaderSource, sizeof(kMirrorShaderSource) - 1,
                        "camera_windows_mirror", nullptr, nullptr,
                        "MirrorVertex", "vs_4_0", compile_flags, 0,
                        vertex_blob.GetAddressOf(), error_blob.GetAddressOf())) ||
      FAILED(D3DCompile(kMirrorShaderSource, sizeof(kMirrorShaderSource) - 1,
                        "camera_windows_mirror", nullptr, nullptr,
                        "MirrorPixel", "ps_4_0", compile_flags, 0,
                        pixel_blob.GetAddressOf(),
                        error_blob.GetAddressOf()))) {
    std::cerr << "camera_windows: mirror pass unavailable, the preview will not "
                 "be mirrored"
              << std::endl;
    return false;
  }

  if (FAILED(d3d_device_->CreateVertexShader(
          vertex_blob->GetBufferPointer(), vertex_blob->GetBufferSize(), nullptr,
          mirror_vertex_shader_.GetAddressOf())) ||
      FAILED(d3d_device_->CreatePixelShader(pixel_blob->GetBufferPointer(),
                                            pixel_blob->GetBufferSize(), nullptr,
                                            mirror_pixel_shader_
                                                .GetAddressOf()))) {
    return false;
  }

  D3D11_SAMPLER_DESC sampler{};
  sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
  sampler.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler.ComparisonFunc = D3D11_COMPARISON_NEVER;
  sampler.MaxLOD = D3D11_FLOAT32_MAX;
  if (FAILED(d3d_device_->CreateSamplerState(
          &sampler, mirror_sampler_.GetAddressOf()))) {
    return false;
  }

  mirror_shader_ready_ = true;
  return true;
}

bool TextureHandler::ConvertOnGpu(ID3D11Texture2D* input, UINT subresource,
                                  ID3D11Texture2D* target) {
  if (!video_processor_ || input == nullptr || target == nullptr) {
    return false;
  }

  D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC input_description{};
  input_description.FourCC = 0;
  input_description.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
  input_description.Texture2D.MipSlice = 0;
  input_description.Texture2D.ArraySlice = subresource;

  ComPtr<ID3D11VideoProcessorInputView> input_view;
  if (FAILED(video_device_->CreateVideoProcessorInputView(
          input, video_enumerator_.Get(), &input_description,
          input_view.GetAddressOf()))) {
    return false;
  }

  D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC output_description{};
  output_description.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
  output_description.Texture2D.MipSlice = 0;

  ComPtr<ID3D11VideoProcessorOutputView> output_view;
  if (FAILED(video_device_->CreateVideoProcessorOutputView(
          target, video_enumerator_.Get(), &output_description,
          output_view.GetAddressOf()))) {
    return false;
  }

  D3D11_VIDEO_PROCESSOR_STREAM stream{};
  stream.Enable = TRUE;
  stream.OutputIndex = 0;
  stream.InputFrameOrField = 0;
  stream.pInputSurface = input_view.Get();

  return SUCCEEDED(video_context_->VideoProcessorBlt(
      video_processor_.Get(), output_view.Get(), 0, 1, &stream));
}

bool TextureHandler::MirrorIntoOutput() {
  if (!mirror_shader_ready_ || !converted_view_ || !output_view_) {
    return false;
  }

  ID3D11ShaderResourceView* views[] = {converted_view_.Get()};
  d3d_context_->PSSetShaderResources(0, 1, views);
  ID3D11SamplerState* samplers[] = {mirror_sampler_.Get()};
  d3d_context_->PSSetSamplers(0, 1, samplers);
  d3d_context_->VSSetShader(mirror_vertex_shader_.Get(), nullptr, 0);
  d3d_context_->PSSetShader(mirror_pixel_shader_.Get(), nullptr, 0);
  d3d_context_->IASetInputLayout(nullptr);
  d3d_context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  d3d_context_->OMSetRenderTargets(1, output_view_.GetAddressOf(), nullptr);
  d3d_context_->Draw(3, 0);

  // Flutter samples the texture from its own device, so the bindings are
  // dropped and the context flushed before the frame is announced.
  ID3D11ShaderResourceView* no_views[] = {nullptr};
  d3d_context_->PSSetShaderResources(0, 1, no_views);
  ID3D11RenderTargetView* no_targets[] = {nullptr};
  d3d_context_->OMSetRenderTargets(1, no_targets, nullptr);
  d3d_context_->Flush();
  return true;
}

void TextureHandler::UploadToOutput(const uint8_t* bgra, uint32_t width,
                                    uint32_t height) {
  if (bgra == nullptr || !EnsureSharedOutput(width, height)) {
    return;
  }
  d3d_context_->UpdateSubresource(output_texture_.Get(), 0, nullptr, bgra,
                                  width * 4, 0);
  d3d_context_->Flush();
}

}  // namespace camera_windows
