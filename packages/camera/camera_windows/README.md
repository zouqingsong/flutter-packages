# Camera Windows Plugin

The Windows implementation of [`camera`][camera].

*Note*: This plugin is under development.
See [missing implementations and limitations](#missing-features-on-the-windows-platform).

## Usage

### Depend on the package

This package is not an [endorsed][endorsed-federated-plugin]
implementation of the [`camera`][camera] plugin, so in addition to depending
on [`camera`][camera] you'll need to
[add `camera_windows` to your pubspec.yaml explicitly][install].
Once you do, you can use the [`camera`][camera] APIs as you normally would.

### FlexionCam capture-only UVC devices

This local fork uses an asynchronous Media Foundation Source Reader for
`VID_4255&PID_0134`. Its capture-only compressed stream can fail Capture Engine
decoder negotiation on some Windows hosts; Source Reader negotiates RGB32
through advanced video processing instead. Other cameras retain Capture Engine.
There is no global frame-rate cap, codec exclusion, or hardware-transform override.

The route supports preview, image streaming, JPEG and H.264 MP4 capture, and
preview pause/resume. Audio recording is explicitly unsupported on this route;
applications should create its controller with `enableAudio: false`.
If the installed H.264 encoder rejects a sensor size larger than 4096×2304,
recording retries an aspect-preserving size within those encoder bounds.
For example, 4000×3000 preview/JPEG remain full size while MP4 is 3072×2304.

Native tests include actual stream-index resolution and asynchronous preview
failure propagation. The `SourceReaderCapture` hardware test is skipped unless
`CAMERA_HARDWARE_SMOKE_DIR` names an output directory. With explicit opt-in it
opens FlexionCam twice, verifies decoded frames at the smallest/fallback and
maximum presets, writes JPEG/MP4 samples, and checks bounded source shutdown.
It sends no vendor USB control commands.

On Windows window destruction, the plugin stops camera sources and unregisters
its image-stream channel before the Flutter engine starts messenger teardown.
This avoids reentering the messenger callback lock from a plugin destructor.
Shutdown is idempotent and rejects new platform-thread work once closing starts.

## Missing features on the Windows platform

### Device orientation

Device orientation detection
is not yet implemented: [issue #97540][device-orientation-issue].

### Pause and Resume video recording

Pausing and resuming the video recording
is not supported due to Windows API limitations.

### Exposure mode, point and offset

Support for explosure mode and offset
is not yet implemented: [issue #97537][camera-control-issue].

Exposure points are not supported due to
limitations of the Windows API.

### Focus mode and point

Support for explosure mode and offset
is not yet implemented: [issue #97537][camera-control-issue].

### Flash mode

Support for flash mode is not yet implemented: [issue #97537][camera-control-issue].

Focus points are not supported due to
current limitations of the Windows API.

### Streaming of frames

Support for image streaming is not yet implemented: [issue #97542][image-streams-issue].

## Error handling

Camera errors can be listened using the platform's `onCameraError` method.

Listening to errors is important, and in certain situations,
disposing of the camera is the only way to reset the situation.

<!-- Links -->

[camera]: https://pub.dev/packages/camera
[endorsed-federated-plugin]: https://flutter.dev/to/endorsed-federated-plugin
[install]: https://pub.dev/packages/camera_windows/install
[camera-control-issue]: https://github.com/flutter/flutter/issues/97537
[device-orientation-issue]: https://github.com/flutter/flutter/issues/97540
[image-streams-issue]: https://github.com/flutter/flutter/issues/97542
