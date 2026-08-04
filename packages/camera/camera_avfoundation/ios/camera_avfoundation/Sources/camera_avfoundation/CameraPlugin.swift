// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import Flutter

public final class CameraPlugin: NSObject, FlutterPlugin {
  private let registry: FlutterTextureRegistry
  private let messenger: FlutterBinaryMessenger
  private let globalEventAPI: CameraGlobalEventApiProtocol
  private let deviceDiscoverer: CameraDeviceDiscoverer
  private let permissionManager: CameraPermissionManager
  private let captureDeviceFactory: VideoCaptureDeviceFactory
  private let captureSessionFactory: CaptureSessionFactory
  private let captureDeviceInputFactory: CaptureDeviceInputFactory

  /// All FLTCam's state access and capture session related operations should be on run on this queue.
  private let captureSessionQueue: DispatchQueue

  /// An internal camera object that manages camera's state and performs camera operations.
  var camera: Camera?

  public static func register(with registrar: FlutterPluginRegistrar) {
    NSLog("🔥🔥🔥 CameraPlugin.register called - registering method channel")
    
    let instance = CameraPlugin(
      registry: registrar.textures(),
      messenger: registrar.messenger(),
      globalAPI: CameraGlobalEventApi(binaryMessenger: registrar.messenger()),
      deviceDiscoverer: DefaultCameraDeviceDiscoverer(),
      permissionManager: CameraPermissionManager(
        permissionService: DefaultPermissionService()),
      deviceFactory: { name in
        // TODO(RobertOdrowaz) Implement better error handling and remove non-null assertion
        AVCaptureDevice(uniqueID: name)!
      },
      captureSessionFactory: { AVCaptureSession() },
      captureDeviceInputFactory: DefaultCaptureDeviceInputFactory(),
      captureSessionQueue: DispatchQueue(label: "io.flutter.camera.captureSessionQueue")
    )

    CameraApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
  }

  init(
    registry: FlutterTextureRegistry,
    messenger: FlutterBinaryMessenger,
    globalAPI: CameraGlobalEventApiProtocol,
    deviceDiscoverer: CameraDeviceDiscoverer,
    permissionManager: CameraPermissionManager,
    deviceFactory: @escaping VideoCaptureDeviceFactory,
    captureSessionFactory: @escaping CaptureSessionFactory,
    captureDeviceInputFactory: CaptureDeviceInputFactory,
    captureSessionQueue: DispatchQueue
  ) {
    self.registry = registry
    self.messenger = messenger
    self.globalEventAPI = globalAPI
    self.deviceDiscoverer = deviceDiscoverer
    self.permissionManager = permissionManager
    self.captureDeviceFactory = deviceFactory
    self.captureSessionFactory = captureSessionFactory
    self.captureDeviceInputFactory = captureDeviceInputFactory
    self.captureSessionQueue = captureSessionQueue

    super.init()

    captureSessionQueue.setSpecific(
      key: captureSessionQueueSpecificKey, value: captureSessionQueueSpecificValue)

    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification,
      object: UIDevice.current,
      queue: .main
    ) { [weak self] notification in
      self?.orientationChanged(notification)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
  }

  private static func pigeonErrorFromNSError(_ error: NSError) -> PigeonError {
    return PigeonError(
      code: "Error \(error.code)",
      message: error.localizedDescription,
      details: error.domain)
  }

  func orientationChanged(_ notification: Notification) {
    guard let device = notification.object as? UIDevice else { return }
    let orientation = device.orientation

    if orientation == .faceUp || orientation == .faceDown {
      // Do not change when oriented flat.
      return
    }

    self.captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else { return }
      // `Camera.deviceOrientation` must be set on capture session queue.
      strongSelf.camera?.deviceOrientation = orientation
      // `CameraPlugin.sendDeviceOrientation` can be called on any queue.
      strongSelf.sendDeviceOrientation(orientation)
    }
  }

  func sendDeviceOrientation(_ orientation: UIDeviceOrientation) {
    DispatchQueue.main.async { [weak self] in
      self?.globalEventAPI.deviceOrientationChanged(
        orientation: getPigeonDeviceOrientation(for: orientation)
      ) { _ in
        // Ignore errors; this is essentially a broadcast stream, and
        // it's fine if the other end doesn't receive the message
        // (e.g., if it doesn't currently have a listener set up).
      }
    }
  }
}

extension CameraPlugin: CameraApi {

  func getAvailableCameras(
    completion: @escaping (Result<[PlatformCameraDescription], any Error>) -> Void
  ) {
    NSLog("🔥🔥🔥 NATIVE: CameraPlugin.availableCameras called")
    captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else { return }

      let discoveryDevices: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .builtInTelephotoCamera,
        .builtInUltraWideCamera,
      ]

      let devices = strongSelf.deviceDiscoverer.discoverySession(
        withDeviceTypes: discoveryDevices,
        mediaType: .video,
        position: .unspecified)

      var reply: [PlatformCameraDescription] = []

      for device in devices {
        let lensFacing = strongSelf.platformLensDirection(for: device)
        let lensType = strongSelf.platformLensType(for: device)
        let cameraDescription = PlatformCameraDescription(
          name: device.uniqueID,
          lensDirection: lensFacing,
          lensType: lensType
        )
        reply.append(cameraDescription)
      }

      completion(.success(reply))
    }
  }

  private func platformLensDirection(for device: CaptureDevice) -> PlatformCameraLensDirection {
    switch device.position {
    case .back:
      return .back
    case .front:
      return .front
    case .unspecified:
      return .external
    @unknown default:
      return .external
    }
  }

  private func platformLensType(for device: CaptureDevice) -> PlatformCameraLensType {
    switch device.deviceType {
    case .builtInWideAngleCamera:
      return .wide
    case .builtInTelephotoCamera:
      return .telephoto
    case .builtInUltraWideCamera:
      return .ultraWide
    case .builtInDualWideCamera:
      return .wide
    default:
      return .unknown
    }
  }

  func create(
    cameraName: String, settings: PlatformMediaSettings,
    completion: @escaping (Result<Int64, any Error>) -> Void
  ) {
    // Create FLTCam only if granted camera access (and audio access if audio is enabled)
    captureSessionQueue.async { [weak self] in
      self?.permissionManager.requestCameraPermission { error in
        guard let strongSelf = self else { return }

        if let error = error {
          completion(.failure(error))
          return
        }

        // Request audio permission on `create` call with `enableAudio` argument instead of the
        // `prepareForVideoRecording` call. This is because `prepareForVideoRecording` call is
        // optional, and used as a workaround to fix a missing frame issue on iOS.
        if settings.enableAudio {
          // Setup audio capture session only if granted audio access.
          strongSelf.permissionManager.requestAudioPermission { [weak self] audioError in
            // cannot use the outter `strongSelf`
            guard let strongSelf = self else { return }

            if let audioError = audioError {
              completion(.failure(audioError))
              return
            }

            strongSelf.createCameraOnSessionQueue(
              withName: cameraName,
              settings: settings,
              completion: completion)
          }
        } else {
          strongSelf.createCameraOnSessionQueue(
            withName: cameraName,
            settings: settings,
            completion: completion)
        }
      }
    }
  }

  func createCameraOnSessionQueue(
    withName: String,
    settings: PlatformMediaSettings,
    completion: @escaping (Result<Int64, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.sessionQueueCreateCamera(name: withName, settings: settings, completion: completion)
    }
  }

  // This must be called on captureSessionQueue. It is extracted from createCameraOnSessionQueue
  // to make it easier to reason about strong/weak self pointers.
  private func sessionQueueCreateCamera(
    name: String,
    settings: PlatformMediaSettings,
    completion: @escaping (Result<Int64, any Error>) -> Void
  ) {
    let mediaSettingsAVWrapper = FLTCamMediaSettingsAVWrapper()

    let camConfiguration = CameraConfiguration(
      mediaSettings: settings,
      mediaSettingsWrapper: mediaSettingsAVWrapper,
      captureDeviceFactory: captureDeviceFactory,
      audioCaptureDeviceFactory: { AVCaptureDevice.default(for: .audio)! },
      captureSessionFactory: captureSessionFactory,
      captureSessionQueue: captureSessionQueue,
      captureDeviceInputFactory: captureDeviceInputFactory,
      initialCameraName: name
    )

    do {
      let newCamera = try DefaultCamera(configuration: camConfiguration)

      camera?.close()
      camera = newCamera

      ensureToRunOnMainQueue { [weak self] in
        guard let strongSelf = self else { return }
        completion(.success(strongSelf.registry.register(newCamera)))
      }
    } catch let error as NSError {
      completion(.failure(CameraPlugin.pigeonErrorFromNSError(error)))
    }
  }

  func initialize(
    cameraId: Int64, imageFormat: PlatformImageFormatGroup,
    completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.sessionQueueInitializeCamera(
        cameraId,
        withImageFormat: imageFormat,
        completion: completion)
    }
  }

  // This must be called on captureSessionQueue. It is extracted from initializeCamera to make it
  // easier to reason about strong/weak self pointers.
  private func sessionQueueInitializeCamera(
    _ cameraId: Int64,
    withImageFormat imageFormat: PlatformImageFormatGroup,
    completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    guard let camera = camera else { return }

    camera.videoFormat = getPixelFormat(for: imageFormat)

    camera.onFrameAvailable = { [weak self] in
      guard let camera = self?.camera else { return }
      if !camera.isPreviewPaused {
        ensureToRunOnMainQueue {
          self?.registry.textureFrameAvailable(Int64(cameraId))
        }
      }
    }

    camera.dartAPI = CameraEventApi(
      binaryMessenger: messenger,
      messageChannelSuffix: "\(cameraId)"
    )

    camera.reportInitializationState()
    sendDeviceOrientation(UIDevice.current.orientation)
    camera.start()
    completion(.success(()))
  }

  func startImageStream(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else {
        completion(.success(()))
        return
      }
      strongSelf.camera?.startImageStream(with: strongSelf.messenger, completion: completion)
    }
  }

  func stopImageStream(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.stopImageStream()
      completion(.success(()))
    }
  }

  func receivedImageStreamData(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.receivedImageStreamData()
      completion(.success(()))
    }
  }

  func dispose(cameraId: Int64, completion: @escaping (Result<Void, any Error>) -> Void) {
    registry.unregisterTexture(Int64(cameraId))
    captureSessionQueue.async { [weak self] in
      if let strongSelf = self {
        strongSelf.camera?.close()
        strongSelf.camera = nil
      }
      completion(.success(()))
    }
  }

  func lockCaptureOrientation(
    orientation: PlatformDeviceOrientation, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.lockCaptureOrientation(orientation)
      completion(.success(()))
    }
  }

  func unlockCaptureOrientation(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.unlockCaptureOrientation()
      completion(.success(()))
    }
  }

  func takePicture(completion: @escaping (Result<String, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.captureToFile(completion: completion)
    }
  }

  func prepareForVideoRecording(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setUpCaptureSessionForAudioIfNeeded()
      completion(.success(()))
    }
  }

  func startVideoRecording(
    enableStream: Bool, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else { return }
      strongSelf.camera?.startVideoRecording(
        completion: completion,
        messengerForStreaming: enableStream ? strongSelf.messenger : nil)
    }
  }

  func stopVideoRecording(completion: @escaping (Result<String, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.stopVideoRecording(completion: completion)
    }
  }

  func pauseVideoRecording(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.pauseVideoRecording()
      completion(.success(()))
    }
  }

  func resumeVideoRecording(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.resumeVideoRecording()
      completion(.success(()))
    }
  }

  func setFlashMode(
    mode: PlatformFlashMode, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setFlashMode(mode, withCompletion: completion)
    }
  }

  func setExposureMode(
    mode: PlatformExposureMode, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    NSLog("🔥🔥🔥 NATIVE: CameraPlugin.setExposureMode called with \(mode == .auto ? "auto" : "locked")")
    captureSessionQueue.async { [weak self] in
      self?.camera?.setExposureMode(mode)
      completion(.success(()))
    }
  }

  func setExposurePoint(
    point: PlatformPoint?, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setExposurePoint(point, withCompletion: completion)
    }
  }

  func getMinExposureOffset(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let minOffset = self?.camera?.minimumExposureOffset {
        completion(.success(minOffset))
      } else {
        completion(.success(0))
      }
    }
  }

  func getMaxExposureOffset(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let maxOffset = self?.camera?.maximumExposureOffset {
        completion(.success(maxOffset))
      } else {
        completion(.success(0))
      }
    }
  }

  func setExposureOffset(offset: Double, completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setExposureOffset(offset)
      completion(.success(()))
    }
  }

  func setFocusMode(
    mode: PlatformFocusMode, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setFocusMode(mode)
      completion(.success(()))
    }
  }

  func setFocusPoint(point: PlatformPoint?, completion: @escaping (Result<Void, any Error>) -> Void)
  {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setFocusPoint(point, completion: completion)
    }
  }

  func getMinZoomLevel(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let minZoom = self?.camera?.minimumAvailableZoomFactor {
        completion(.success(minZoom))
      } else {
        completion(.success(0))
      }
    }
  }

  func getMaxZoomLevel(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let maxZoom = self?.camera?.maximumAvailableZoomFactor {
        completion(.success(maxZoom))
      } else {
        completion(.success(0))
      }
    }
  }

  func setZoomLevel(zoom: Double, completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setZoomLevel(zoom, withCompletion: completion)
    }
  }

  func setVideoStabilizationMode(
    mode: PlatformVideoStabilizationMode, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setVideoStabilizationMode(mode, withCompletion: completion)
    }
  }

  func isVideoStabilizationModeSupported(
    mode: PlatformVideoStabilizationMode,
    completion: @escaping (Result<Bool, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      if let camera = self?.camera {
        let isSupported = camera.isVideoStabilizationModeSupported(mode)
        completion(.success(isSupported))
      } else {
        completion(.success(false))
      }
    }
  }

  func pausePreview(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.pausePreview()
      completion(.success(()))
    }
  }

  func resumePreview(completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.resumePreview()
      completion(.success(()))
    }
  }

  func updateDescriptionWhileRecording(
    cameraName: String, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setDescriptionWhileRecording(cameraName, withCompletion: completion)
    }
  }

  func setImageFileFormat(
    format: PlatformImageFileFormat, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setImageFileFormat(format)
      completion(.success(()))
    }
  }

  func setManualFocusDistance(
    distance: Double, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setManualFocusDistance(distance)
      completion(.success(()))
    }
  }

  func getMinFocusDistance(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(camera.getMinFocusDistance()))
    }
  }

  func getMaxFocusDistance(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(camera.getMaxFocusDistance()))
    }
  }

  func setManualExposureTime(
    exposureTime: Int64, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setManualExposureTime(Int(exposureTime))
      completion(.success(()))
    }
  }

  func getMinExposureTime(completion: @escaping (Result<Int64, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(Int64(camera.getMinExposureTime())))
    }
  }

  func getMaxExposureTime(completion: @escaping (Result<Int64, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(Int64(camera.getMaxExposureTime())))
    }
  }

  func setManualIso(iso: Int64, completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setManualIso(Int(iso))
      completion(.success(()))
    }
  }

  func getMinIso(completion: @escaping (Result<Int64, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(Int64(camera.getMinIso())))
    }
  }

  func getMaxIso(completion: @escaping (Result<Int64, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(Int64(camera.getMaxIso())))
    }
  }

  func setWhiteBalanceMode(
    mode: PlatformWhiteBalanceMode, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setWhiteBalanceMode(mode, withCompletion: completion)
    }
  }

  func setManualColorTemperature(
    colorTemperature: Int64, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setManualColorTemperature(Int(colorTemperature))
      completion(.success(()))
    }
  }

  func getMinColorTemperature(completion: @escaping (Result<Int64, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(Int64(camera.getMinColorTemperature())))
    }
  }

  func getMaxColorTemperature(completion: @escaping (Result<Int64, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(Int64(camera.getMaxColorTemperature())))
    }
  }

  func setFrameRateRange(
    minFrameRate: Int64,
    maxFrameRate: Int64,
    completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setFrameRateRange(
        minFrameRate: Int(minFrameRate),
        maxFrameRate: Int(maxFrameRate),
        withCompletion: completion
      )
    }
  }

  func getSupportedFrameRateRanges(
    completion: @escaping (Result<[PlatformFrameRateRange], any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      let ranges = self?.camera?.getSupportedFrameRateRanges() ?? []
      completion(
        .success(
          ranges.map {
            PlatformFrameRateRange(minFrameRate: $0.0, maxFrameRate: $0.1)
          }
        )
      )
    }
  }

  func setVideoStabilization(
    enabled: Bool, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setVideoStabilization(enabled, withCompletion: completion)
    }
  }

  func isVideoStabilizationSupported(completion: @escaping (Result<Bool, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      completion(.success(self?.camera?.isVideoStabilizationSupported() ?? false))
    }
  }

  func getLensAperture(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(camera.getLensAperture()))
    }
  }

  func getFocalLength(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(camera.getFocalLength()))
    }
  }

  func setTorchLevel(level: Double, completion: @escaping (Result<Void, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let plugin = self else {
        completion(.success(()))
        return
      }
      plugin.camera?.setTorchLevel(level, withCompletion: completion)
    }
  }

  func getTorchLevel() throws -> Double {
    guard let camera = self.camera else {
      throw PigeonError(code: "camera_error", message: "Camera not available", details: nil)
    }
    return camera.getTorchLevel()
  }

  func isTorchLevelSupported() throws -> Bool {
    guard let camera = self.camera else {
      throw PigeonError(code: "camera_error", message: "Camera not available", details: nil)
    }
    return camera.isTorchLevelSupported()
  }

  func getMaxTorchLevel(completion: @escaping (Result<Double, any Error>) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let camera = self?.camera else {
        completion(
          .failure(PigeonError(code: "camera_error", message: "Camera not available", details: nil))
        )
        return
      }
      completion(.success(camera.getMaxTorchLevel()))
    }
  }

  func setColorEffect(
    effect: PlatformColorEffect, completion: @escaping (Result<Void, any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setColorEffect(effect, withCompletion: completion)
    }
  }

  func getSupportedColorEffects(
    completion: @escaping (Result<[PlatformColorEffect], any Error>) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      completion(.success(self?.camera?.getSupportedColorEffects() ?? [.none]))
    }
  }
}
