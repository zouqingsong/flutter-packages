// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut: 'darwin/camera_avfoundation/Sources/camera_avfoundation/Messages.swift',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// Pigeon version of CameraLensDirection.
enum PlatformCameraLensDirection {
  /// Front facing camera (a user looking at the screen is seen by the camera).
  front,

  /// Back facing camera (a user looking at the screen is not seen by the camera).
  back,

  /// External camera which may not be mounted to the device.
  external,
}

// Pigeon version of CameraLensDirection.
enum PlatformCameraLensType {
  /// A built-in wide-angle camera device type.
  wide,

  /// A built-in camera device type with a longer focal length than a wide-angle camera.
  telephoto,

  /// A built-in camera device type with a shorter focal length than a wide-angle camera.
  ultraWide,

  /// Unknown camera device type.
  unknown,
}

// Pigeon version of DeviceOrientation.
enum PlatformDeviceOrientation { portraitUp, landscapeLeft, portraitDown, landscapeRight }

// Pigeon version of ExposureMode.
enum PlatformExposureMode { auto, locked }

// Pigeon version of FlashMode.
enum PlatformFlashMode { off, auto, always, torch }

// Pigeon version of FocusMode.
enum PlatformFocusMode { auto, locked }

// Pigeon version of WhiteBalanceMode.
enum PlatformWhiteBalanceMode {
  auto,
  locked,
}

// Pigeon version of ColorEffect.
enum PlatformColorEffect {
  none,
  mono,
  negative,
  sepia,
  posterize,
  aqua,
}

/// Pigeon version of ImageFileFormat.
enum PlatformImageFileFormat { jpeg, heif }

// Pigeon version of the subset of ImageFormatGroup supported on iOS.
enum PlatformImageFormatGroup { bgra8888, yuv420 }

// Pigeon version of ResolutionPreset.
enum PlatformResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }

enum PlatformVideoStabilizationMode { off, standard, cinematic, cinematicExtended }

// Pigeon version of CameraDescription.
class PlatformCameraDescription {
  PlatformCameraDescription({
    required this.name,
    required this.lensDirection,
    required this.lensType,
  });

  /// The name of the camera device.
  final String name;

  /// The direction the camera is facing.
  final PlatformCameraLensDirection lensDirection;

  /// The type of the camera lens.
  final PlatformCameraLensType lensType;
}

// Pigeon version of the data needed for a CameraInitializedEvent.
class PlatformCameraState {
  PlatformCameraState({
    required this.previewSize,
    required this.exposureMode,
    required this.focusMode,
    required this.whiteBalanceMode,
    required this.exposurePointSupported,
    required this.focusPointSupported,
  });

  /// The size of the preview, in pixels.
  final PlatformSize previewSize;

  /// The default exposure mode
  final PlatformExposureMode exposureMode;

  /// The default focus mode
  final PlatformFocusMode focusMode;

  /// The default white balance mode
  final PlatformWhiteBalanceMode whiteBalanceMode;

  /// Whether setting exposure points is supported.
  final bool exposurePointSupported;

  /// Whether setting focus points is supported.
  final bool focusPointSupported;
}

// Pigeon version of the data needed for a CameraImageData.
class PlatformCameraImageData {
  PlatformCameraImageData({
    required this.formatCode,
    required this.width,
    required this.height,
    required this.planes,
    required this.lensAperture,
    required this.sensorExposureTimeNanoseconds,
    required this.sensorSensitivity,
  });

  /// The FourCharCode of the image format.
  final int formatCode;

  final int width;
  final int height;
  final List<PlatformCameraImagePlane> planes;
  final double lensAperture;
  final int sensorExposureTimeNanoseconds;
  final double sensorSensitivity;
}

// Pigeon version of the data needed for a CameraImagePlane.
class PlatformCameraImagePlane {
  const PlatformCameraImagePlane({
    required this.bytes,
    required this.bytesPerRow,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int width;
  final int height;
}

// Pigeon version of to MediaSettings.
class PlatformMediaSettings {
  PlatformMediaSettings({
    required this.resolutionPreset,
    required this.framesPerSecond,
    required this.videoBitrate,
    required this.audioBitrate,
    required this.enableAudio,
  });

  final PlatformResolutionPreset resolutionPreset;
  final int? framesPerSecond;
  final int? videoBitrate;
  final int? audioBitrate;
  final bool enableAudio;
}

// Pigeon equivalent of CGPoint.
class PlatformPoint {
  PlatformPoint({required this.x, required this.y});

  final double x;
  final double y;
}

// Pigeon equivalent of CGSize.
class PlatformSize {
  PlatformSize({required this.width, required this.height});

  final double width;
  final double height;
}

// Pigeon version of FrameRateRange.
class PlatformFrameRateRange {
  PlatformFrameRateRange({required this.minFrameRate, required this.maxFrameRate});

  final int minFrameRate;
  final int maxFrameRate;
}

@HostApi()
abstract class CameraApi {
  /// Returns the list of available cameras.
  @async
  @ObjCSelector('availableCamerasWithCompletion')
  List<PlatformCameraDescription> getAvailableCameras();

  /// Create a new camera with the given settings, and returns its ID.
  @async
  @ObjCSelector('createCameraWithName:settings:')
  int create(String cameraName, PlatformMediaSettings settings);

  /// Initializes the camera with the given ID.
  @async
  @ObjCSelector('initializeCamera:withImageFormat:')
  void initialize(int cameraId, PlatformImageFormatGroup imageFormat);

  /// Begins streaming frames from the camera.
  @async
  void startImageStream();

  /// Stops streaming frames from the camera.
  @async
  void stopImageStream();

  /// Called by the Dart side of the plugin when it has received the last image
  /// frame sent.
  ///
  /// This is used to throttle sending frames across the channel.
  @async
  void receivedImageStreamData();

  /// Indicates that the given camera is no longer being used on the Dart side,
  /// and any associated resources can be cleaned up.
  @async
  @ObjCSelector('disposeCamera:')
  void dispose(int cameraId);

  /// Locks the camera capture to the current device orientation.
  @async
  @ObjCSelector('lockCaptureOrientation:')
  void lockCaptureOrientation(PlatformDeviceOrientation orientation);

  /// Unlocks camera capture orientation, allowing it to automatically adapt to
  /// device orientation.
  @async
  void unlockCaptureOrientation();

  /// Takes a picture with the current settings, and returns the path to the
  /// resulting file.
  @async
  String takePicture();

  /// Does any preprocessing necessary before beginning to record video.
  @async
  void prepareForVideoRecording();

  /// Begins recording video, optionally enabling streaming to Dart at the same
  /// time.
  @async
  @ObjCSelector('startVideoRecordingWithStreaming:')
  void startVideoRecording(bool enableStream);

  /// Stops recording video, and results the path to the resulting file.
  @async
  String stopVideoRecording();

  /// Pauses video recording.
  @async
  void pauseVideoRecording();

  /// Resumes a previously paused video recording.
  @async
  void resumeVideoRecording();

  /// Switches the camera to the given flash mode.
  @async
  @ObjCSelector('setFlashMode:')
  void setFlashMode(PlatformFlashMode mode);

  /// Switches the camera to the given exposure mode.
  @async
  @ObjCSelector('setExposureMode:')
  void setExposureMode(PlatformExposureMode mode);

  /// Anchors auto-exposure to the given point in (0,1) coordinate space.
  ///
  /// A null value resets to the default exposure point.
  @async
  @ObjCSelector('setExposurePoint:')
  void setExposurePoint(PlatformPoint? point);

  /// Returns the minimum exposure offset supported by the camera.
  @async
  @ObjCSelector('getMinimumExposureOffset')
  double getMinExposureOffset();

  /// Returns the maximum exposure offset supported by the camera.
  @async
  @ObjCSelector('getMaximumExposureOffset')
  double getMaxExposureOffset();

  /// Sets the exposure offset manually to the given value.
  @async
  @ObjCSelector('setExposureOffset:')
  void setExposureOffset(double offset);

  /// Switches the camera to the given focus mode.
  @async
  @ObjCSelector('setFocusMode:')
  void setFocusMode(PlatformFocusMode mode);

  /// Anchors auto-focus to the given point in (0,1) coordinate space.
  ///
  /// A null value resets to the default focus point.
  @async
  @ObjCSelector('setFocusPoint:')
  void setFocusPoint(PlatformPoint? point);

  /// Sets the manual focus distance.
  ///
  /// The distance should be between 0.0 and 1.0, where 0.0 represents
  /// the nearest focus distance and 1.0 represents the farthest (infinity).
  @async
  @ObjCSelector('setManualFocusDistance:')
  void setManualFocusDistance(double distance);

  /// Returns the minimum supported manual focus distance.
  @async
  @ObjCSelector('getMinFocusDistance')
  double getMinFocusDistance();

  /// Returns the maximum supported manual focus distance.
  @async
  @ObjCSelector('getMaxFocusDistance')
  double getMaxFocusDistance();

  /// Sets the manual exposure time (shutter speed) in microseconds.
  @async
  @ObjCSelector('setManualExposureTime:')
  void setManualExposureTime(int exposureTime);

  /// Returns the minimum supported exposure time in microseconds.
  @async
  @ObjCSelector('getMinExposureTime')
  int getMinExposureTime();

  /// Returns the maximum supported exposure time in microseconds.
  @async
  @ObjCSelector('getMaxExposureTime')
  int getMaxExposureTime();

  /// Sets the manual ISO sensitivity.
  @async
  @ObjCSelector('setManualIso:')
  void setManualIso(int iso);

  /// Returns the minimum supported ISO sensitivity.
  @async
  @ObjCSelector('getMinIso')
  int getMinIso();

  /// Returns the maximum supported ISO sensitivity.
  @async
  @ObjCSelector('getMaxIso')
  int getMaxIso();

  /// Switches the camera to the given white balance mode.
  @async
  @ObjCSelector('setWhiteBalanceMode:')
  void setWhiteBalanceMode(PlatformWhiteBalanceMode mode);

  /// Sets the manual color temperature in Kelvin.
  ///
  /// This should only be used when white balance mode is locked.
  /// Color temperature typically ranges from 2000K to 8000K.
  @async
  @ObjCSelector('setManualColorTemperature:')
  void setManualColorTemperature(int colorTemperature);

  /// Returns the minimum supported color temperature in Kelvin.
  @async
  @ObjCSelector('getMinColorTemperature')
  int getMinColorTemperature();

  /// Returns the maximum supported color temperature in Kelvin.
  @async
  @ObjCSelector('getMaxColorTemperature')
  int getMaxColorTemperature();

  /// Returns the minimum zoom level supported by the camera.
  @async
  @ObjCSelector('getMinimumZoomLevel')
  double getMinZoomLevel();

  /// Returns the maximum zoom level supported by the camera.
  @async
  @ObjCSelector('getMaximumZoomLevel')
  double getMaxZoomLevel();

  /// Sets the zoom factor.
  @async
  @ObjCSelector('setZoomLevel:')
  void setZoomLevel(double zoom);

  /// Sets the video stabilization mode.
  @async
  @ObjCSelector('setVideoStabilizationMode:')
  void setVideoStabilizationMode(PlatformVideoStabilizationMode mode);

  /// Gets if the given video stabilization mode is supported.
  @async
  @ObjCSelector('isVideoStabilizationModeSupported:')
  bool isVideoStabilizationModeSupported(PlatformVideoStabilizationMode mode);

  /// Pauses streaming of preview frames.
  @async
  void pausePreview();

  /// Resumes a previously paused preview stream.
  @async
  void resumePreview();

  /// Changes the camera used while recording video.
  ///
  /// This should only be called while video recording is active.
  @async
  void updateDescriptionWhileRecording(String cameraName);

  /// Sets the file format used for taking pictures.
  @async
  @ObjCSelector('setImageFileFormat:')
  void setImageFileFormat(PlatformImageFileFormat format);

  /// Sets the JPEG compression quality for still image capture.
  @async
  @ObjCSelector('setJpegImageQuality:')
  void setJpegImageQuality(int quality);

  // MARK: - Frame Rate Control
  /// Sets the frame rate range for video capture.
  @async
  @ObjCSelector('setFrameRateRange:maxFrameRate:')
  void setFrameRateRange(int minFrameRate, int maxFrameRate);

  /// Returns the supported frame rate ranges.
  @async
  @ObjCSelector('getSupportedFrameRateRanges')
  List<PlatformFrameRateRange> getSupportedFrameRateRanges();

  // MARK: - Image Stabilization
  /// Sets video stabilization mode.
  @async
  @ObjCSelector('setVideoStabilization:')
  void setVideoStabilization(bool enabled);

  /// Returns whether video stabilization is supported.
  @async
  @ObjCSelector('isVideoStabilizationSupported')
  bool isVideoStabilizationSupported();

  // MARK: - Lens Properties
  /// Returns the lens aperture value.
  @async
  @ObjCSelector('getLensAperture')
  double getLensAperture();

  /// Returns the focal length in millimeters.
  @async
  @ObjCSelector('getFocalLength')
  double getFocalLength();

  // MARK: - Torch Level Control
  /// Sets the torch level (0.0 to 1.0).
  @async
  @ObjCSelector('setTorchLevel:')
  void setTorchLevel(double level);

  /// Gets the current torch level (0.0 to 1.0).
  @ObjCSelector('getTorchLevel')
  double getTorchLevel();

  /// Returns whether torch level control is supported.
  @ObjCSelector('isTorchLevelSupported')
  bool isTorchLevelSupported();

  /// Returns the maximum supported torch level.
  @async
  @ObjCSelector('getMaxTorchLevel')
  double getMaxTorchLevel();

  // MARK: - Color Effects
  /// Sets a color effect filter.
  @async
  @ObjCSelector('setColorEffect:')
  void setColorEffect(PlatformColorEffect effect);

  /// Returns the supported color effects.
  @async
  @ObjCSelector('getSupportedColorEffects')
  List<PlatformColorEffect> getSupportedColorEffects();
}

@EventChannelApi()
abstract class CameraImageStreamEventApi {
  PlatformCameraImageData imageDataStream();
}

/// Handler for native callbacks that are not tied to a specific camera ID.
@FlutterApi()
abstract class CameraGlobalEventApi {
  /// Called when the device's physical orientation changes.
  void deviceOrientationChanged(PlatformDeviceOrientation orientation);
}

/// Handler for native callbacks that are tied to a specific camera ID.
///
/// This is intended to be initialized with the camera ID as a suffix.
@FlutterApi()
abstract class CameraEventApi {
  /// Called when the camera is inialitized for use.
  @ObjCSelector('initializedWithState:')
  void initialized(PlatformCameraState initialState);

  /// Called when an error occurs in the camera.
  ///
  /// This should be used for errors that occur outside of the context of
  /// handling a specific HostApi call, such as during streaming.
  @ObjCSelector('reportError:')
  void error(String message);
}
