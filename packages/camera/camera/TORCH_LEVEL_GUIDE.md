# Torch Level Control

The camera plugin now supports advanced torch (flashlight) level control on both iOS and Android platforms.

## Features

### iOS (Full Support)
- ✅ Variable torch brightness levels (0.0 to 1.0)
- ✅ Real-time torch level reading
- ✅ Maximum torch level detection
- ✅ Support status checking

### Android (On/Off with Interface Mapping)
- ✅ Reliable on/off torch control
- ✅ Consistent API interface (0.0 = off, >0.0 = on)
- ✅ Graceful handling of device limitations

## API Methods

### `setTorchLevel(double level)`
Sets the torch brightness level.
- **level**: 0.0 (off) to getMaxTorchLevel() (maximum brightness)
- Throws `ArgumentError` if level < 0.0
- Throws `CameraException` on platform errors

```dart
// Turn torch off
await controller.setTorchLevel(0.0);

// Set to 50% brightness (iOS) or on (Android)
await controller.setTorchLevel(0.5);

// Set to maximum brightness
final maxLevel = await controller.getMaxTorchLevel();
await controller.setTorchLevel(maxLevel);
```

### `getTorchLevel()`
Returns the current torch level.
- **Returns**: `Future<double>` - Current torch level
- iOS: Actual brightness level (0.0 to 1.0)
- Android: 0.0 (off) or max level (on)

```dart
final currentLevel = await controller.getTorchLevel();
print('Current torch level: $currentLevel');
```

### `isTorchLevelSupported()`
Checks if variable torch levels are supported.
- **Returns**: `Future<bool>` - True if variable levels supported
- iOS: Usually true (device dependent)
- Android: True (but only on/off control)

```dart
final isSupported = await controller.isTorchLevelSupported();
if (isSupported) {
  print('Variable torch levels supported');
} else {
  print('Only on/off torch control available');
}
```

### `getMaxTorchLevel()`
Gets the maximum supported torch level.
- **Returns**: `Future<double>` - Maximum torch level
- iOS: 1.0 (standard range)
- Android: 1.0 (mapped for consistency)

```dart
final maxLevel = await controller.getMaxTorchLevel();
print('Maximum torch level: $maxLevel');
```

## Usage Example

```dart
import 'package:camera/camera.dart';

class TorchControlWidget extends StatefulWidget {
  final CameraController controller;
  
  @override
  _TorchControlWidgetState createState() => _TorchControlWidgetState();
}

class _TorchControlWidgetState extends State<TorchControlWidget> {
  double _torchLevel = 0.0;
  double _maxTorchLevel = 1.0;
  
  @override
  void initState() {
    super.initState();
    _initializeTorchControl();
  }
  
  Future<void> _initializeTorchControl() async {
    try {
      _maxTorchLevel = await widget.controller.getMaxTorchLevel();
      _torchLevel = await widget.controller.getTorchLevel();
      setState(() {});
    } catch (e) {
      print('Error initializing torch control: $e');
    }
  }
  
  Future<void> _updateTorchLevel(double level) async {
    try {
      await widget.controller.setTorchLevel(level);
      _torchLevel = await widget.controller.getTorchLevel();
      setState(() {});
    } catch (e) {
      print('Error setting torch level: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Torch Level: ${_torchLevel.toStringAsFixed(2)}'),
        Slider(
          value: _torchLevel,
          min: 0.0,
          max: _maxTorchLevel,
          onChanged: _updateTorchLevel,
        ),
        Row(
          children: [
            ElevatedButton(
              onPressed: () => _updateTorchLevel(0.0),
              child: Text('Off'),
            ),
            ElevatedButton(
              onPressed: () => _updateTorchLevel(_maxTorchLevel),
              child: Text('Max'),
            ),
          ],
        ),
      ],
    );
  }
}
```

## Platform Differences

### iOS Behavior
- Uses AVFoundation's `setTorchModeOn(level:)` method
- Supports smooth variable brightness control
- Returns actual hardware torch level values
- Automatically handles device capabilities

### Android Behavior  
- Uses Camera2 API's `FLASH_MODE_TORCH` on/off control
- Maps torch levels to binary on/off state:
  - `level == 0.0` → Torch off
  - `level > 0.0` → Torch on
- Returns 0.0 when off, max level when on
- Provides consistent API while working within Android limitations

## Error Handling

All methods can throw `CameraException` with these common error codes:

- **`TORCH_NOT_AVAILABLE`**: Device doesn't have a torch
- **`TORCH_ERROR`**: Platform-specific torch control error  
- **`CAMERA_ERROR`**: Camera not available or not initialized

```dart
try {
  await controller.setTorchLevel(0.5);
} on CameraException catch (e) {
  switch (e.code) {
    case 'TORCH_NOT_AVAILABLE':
      print('This device does not have a torch');
      break;
    case 'TORCH_ERROR':
      print('Torch control error: ${e.description}');
      break;
    default:
      print('Camera error: ${e.description}');
  }
} catch (e) {
  print('Unexpected error: $e');
}
```

## Migration from Basic Flash Control

If you were using basic flash modes, you can enhance your app with variable torch control:

```dart
// Old: Basic flash mode
await controller.setFlashMode(FlashMode.torch);

// New: Variable torch level control
await controller.setTorchLevel(0.8); // 80% brightness

// Check support before offering variable control
final supportsVariableLevels = await controller.isTorchLevelSupported();
if (supportsVariableLevels) {
  // Show slider for variable control
} else {
  // Show simple on/off buttons
}
```

## Best Practices

1. **Always check support**: Use `isTorchLevelSupported()` to determine UI behavior
2. **Handle errors gracefully**: Wrap torch calls in try-catch blocks
3. **Respect device limitations**: Android devices provide on/off control mapped to the variable interface
4. **Update UI reactively**: Use `getTorchLevel()` to sync UI with actual torch state
5. **Consider battery impact**: Higher torch levels consume more battery

## Complete Working Example

See `example/lib/torch_level_example.dart` for a complete working implementation with UI controls and error handling.
