// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import CoreMotion
import Flutter

/// A class that manages camera's state and performs camera operations.
protocol Camera: FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate,
  AVCaptureAudioDataOutputSampleBufferDelegate
{
  /// The API instance used to communicate with the Dart side of the plugin.
  /// Once initially set, this should only ever be accessed on the main thread.
  var dartAPI: CameraEventApi? { get set }

  var onFrameAvailable: (() -> Void)? { get set }

  /// Format used for video and image streaming.
  var videoFormat: FourCharCode { get set }

  var isPreviewPaused: Bool { get }
  var isStreamingImages: Bool { get }

  var deviceOrientation: UIDeviceOrientation { get set }

  var minimumAvailableZoomFactor: CGFloat { get }
  var maximumAvailableZoomFactor: CGFloat { get }
  var minimumExposureOffset: CGFloat { get }
  var maximumExposureOffset: CGFloat { get }

  func setUpCaptureSessionForAudioIfNeeded()

  /// Informs the Dart side of the plugin of the current camera state and capabilities.
  func reportInitializationState()

  /// Acknowledges the receipt of one image stream frame.
  ///
  /// This should be called each time a frame is received. Failing to call it may
  /// cause later frames to be dropped instead of streamed.
  func receivedImageStreamData()

  func start()
  func stop()

  /// Starts recording a video with an optional streaming messenger.
  /// If the messenger is non-nil then it will be called for each
  /// captured frame, allowing streaming concurrently with recording.
  ///
  /// @param messenger Nullable messenger for capturing each frame.
  func startVideoRecording(
    completion: @escaping (Result<Void, any Error>) -> Void,
    messengerForStreaming: FlutterBinaryMessenger?
  )
  func pauseVideoRecording()
  func resumeVideoRecording()
  func stopVideoRecording(completion: @escaping (Result<String, any Error>) -> Void)

  func captureToFile(completion: @escaping (Result<String, any Error>) -> Void)

  func lockCaptureOrientation(_ orientation: PlatformDeviceOrientation)
  func unlockCaptureOrientation()

  func setImageFileFormat(_ fileFormat: PlatformImageFileFormat)

  func setExposureMode(_ mode: PlatformExposureMode)
  func setExposureOffset(_ offset: Double)

  /// Sets the exposure point, in a (0,1) coordinate system.
  ///
  /// If @c point is nil, the exposure point will reset to the center.
  func setExposurePoint(
    _ point: PlatformPoint?,
    withCompletion: @escaping (Result<Void, any Error>) -> Void
  )

  /// Sets FocusMode on the current AVCaptureDevice.
  ///
  /// If the @c focusMode is set to FocusModeAuto the AVCaptureDevice is configured to use
  /// AVCaptureFocusModeContinuousModeAutoFocus when supported, otherwise it is set to
  /// AVCaptureFocusModeAutoFocus. If neither AVCaptureFocusModeContinuousModeAutoFocus nor
  /// AVCaptureFocusModeAutoFocus are supported focus mode will not be set.
  /// If @c focusMode is set to FocusModeLocked the AVCaptureDevice is configured to use
  /// AVCaptureFocusModeAutoFocus. If AVCaptureFocusModeAutoFocus is not supported focus mode will not
  /// be set.
  ///
  /// @param mode The focus mode that should be applied.
  func setFocusMode(_ mode: PlatformFocusMode)

  /// Sets the focus point, in a (0,1) coordinate system.
  ///
  /// If @c point is nil, the focus point will reset to the center.
  func setFocusPoint(
    _ point: PlatformPoint?,
    completion: @escaping (Result<Void, any Error>) -> Void
  )

  /// Sets manual focus distance.
  /// @param distance Focus distance value where 0.0 is closest and 1.0 is farthest.
  func setManualFocusDistance(_ distance: Double)

  /// Sets manual exposure time.
  /// @param exposureTime Exposure time in microseconds.
  func setManualExposureTime(_ exposureTime: Int)

  /// Sets manual ISO sensitivity.
  /// @param iso ISO sensitivity value.
  func setManualIso(_ iso: Int)

  /// Gets the minimum supported focus distance.
  func getMinFocusDistance() -> Double

  /// Gets the maximum supported focus distance.
  func getMaxFocusDistance() -> Double

  /// Gets the minimum supported exposure time in microseconds.
  func getMinExposureTime() -> Int

  /// Gets the maximum supported exposure time in microseconds.
  func getMaxExposureTime() -> Int

  /// Gets the minimum supported ISO value.
  func getMinIso() -> Int

  /// Gets the maximum supported ISO value.
  func getMaxIso() -> Int

  /// Sets the white balance mode.
  /// @param mode The white balance mode to apply.
  func setWhiteBalanceMode(_ mode: PlatformWhiteBalanceMode,
    withCompletion: @escaping (Result<Void, any Error>) -> Void)

  /// Sets manual color temperature.
  /// @param colorTemperature Color temperature in Kelvin.
  func setManualColorTemperature(_ colorTemperature: Int)

  /// Gets the minimum supported color temperature in Kelvin.
  func getMinColorTemperature() -> Int

  /// Gets the maximum supported color temperature in Kelvin.
  func getMaxColorTemperature() -> Int

  // MARK: - Torch Level Control
  /// Sets the torch level (0.0 to 1.0).
  /// @param level Torch level where 0.0 is off and 1.0 is maximum brightness.
  func setTorchLevel(_ level: Double,
    withCompletion: @escaping (Result<Void, any Error>) -> Void)

  /// Gets the current torch level (0.0 to 1.0).
  func getTorchLevel() -> Double

  /// Returns whether torch level control is supported.
  func isTorchLevelSupported() -> Bool

  /// Gets the maximum supported torch level.
  func getMaxTorchLevel() -> Double

  // MARK: - Extended Camera Controls
  func setFrameRateRange(
    minFrameRate: Int,
    maxFrameRate: Int,
    withCompletion completion: @escaping (Result<Void, any Error>) -> Void
  )
  func getSupportedFrameRateRanges() -> [(Int64, Int64)]
  func setVideoStabilization(
    _ enabled: Bool,
    withCompletion completion: @escaping (Result<Void, any Error>) -> Void
  )
  func isVideoStabilizationSupported() -> Bool
  func getLensAperture() -> Double
  func getFocalLength() -> Double
  func setColorEffect(
    _ effect: PlatformColorEffect,
    withCompletion completion: @escaping (Result<Void, any Error>) -> Void
  )
  func getSupportedColorEffects() -> [PlatformColorEffect]

  func setZoomLevel(_ zoom: CGFloat, withCompletion: @escaping (Result<Void, any Error>) -> Void)

  func setVideoStabilizationMode(
    _ mode: PlatformVideoStabilizationMode,
    withCompletion: @escaping (Result<Void, any Error>) -> Void)

  func isVideoStabilizationModeSupported(_ mode: PlatformVideoStabilizationMode) -> Bool

  func setFlashMode(
    _ mode: PlatformFlashMode,
    withCompletion: @escaping (Result<Void, any Error>) -> Void
  )

  func pausePreview()
  func resumePreview()

  func setDescriptionWhileRecording(
    _ cameraName: String,
    withCompletion: @escaping (Result<Void, any Error>) -> Void
  )

  func startImageStream(
    with: FlutterBinaryMessenger, completion: @escaping (Result<Void, any Error>) -> Void)
  func stopImageStream()

  // Override to make `AVCaptureVideoDataOutputSampleBufferDelegate`/
  // `AVCaptureAudioDataOutputSampleBufferDelegate` method non optional
  override func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  )

  func close()
}
