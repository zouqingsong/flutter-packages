// Example of how to use torch level control features in your Flutter app

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class TorchLevelControlExample extends StatefulWidget {
  final CameraController controller;

  const TorchLevelControlExample({Key? key, required this.controller}) : super(key: key);

  @override
  _TorchLevelControlExampleState createState() => _TorchLevelControlExampleState();
}

class _TorchLevelControlExampleState extends State<TorchLevelControlExample> {
  double _currentTorchLevel = 0.0;
  double _maxTorchLevel = 1.0;
  bool _isTorchLevelSupported = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeTorchControl();
  }

  Future<void> _initializeTorchControl() async {
    try {
      // Check if torch level control is supported
      _isTorchLevelSupported = await widget.controller.isTorchLevelSupported();
      
      // Get the maximum torch level
      _maxTorchLevel = await widget.controller.getMaxTorchLevel();
      
      // Get the current torch level
      _currentTorchLevel = await widget.controller.getTorchLevel();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error initializing torch control: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _setTorchLevel(double level) async {
    try {
      await widget.controller.setTorchLevel(level);
      
      // Update current level
      final newLevel = await widget.controller.getTorchLevel();
      setState(() {
        _currentTorchLevel = newLevel;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error setting torch level: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Torch Level Control',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // Support status
            Row(
              children: [
                Icon(
                  _isTorchLevelSupported ? Icons.check_circle : Icons.error,
                  color: _isTorchLevelSupported ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  _isTorchLevelSupported 
                    ? 'Variable torch levels supported'
                    : 'Only on/off torch control supported',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Current level display
            Text('Current Level: ${_currentTorchLevel.toStringAsFixed(2)}'),
            Text('Max Level: ${_maxTorchLevel.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            
            // Torch level slider
            Text('Torch Level'),
            Slider(
              value: _currentTorchLevel,
              min: 0.0,
              max: _maxTorchLevel,
              divisions: _maxTorchLevel > 1.0 ? (_maxTorchLevel * 10).round() : 10,
              label: _currentTorchLevel.toStringAsFixed(2),
              onChanged: (value) => _setTorchLevel(value),
            ),
            
            // Quick action buttons
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _setTorchLevel(0.0),
                  child: const Text('Off'),
                ),
                ElevatedButton(
                  onPressed: () => _setTorchLevel(_maxTorchLevel * 0.25),
                  child: const Text('25%'),
                ),
                ElevatedButton(
                  onPressed: () => _setTorchLevel(_maxTorchLevel * 0.5),
                  child: const Text('50%'),
                ),
                ElevatedButton(
                  onPressed: () => _setTorchLevel(_maxTorchLevel * 0.75),
                  child: const Text('75%'),
                ),
                ElevatedButton(
                  onPressed: () => _setTorchLevel(_maxTorchLevel),
                  child: const Text('Max'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Platform-specific info
            Text(
              'Platform Info:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '• iOS: Supports variable torch levels (0.0 to 1.0)\n'
              '• Android: Simplified on/off control mapped to 0.0/1.0',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// Usage example in your main app:
class CameraExampleApp extends StatefulWidget {
  @override
  _CameraExampleAppState createState() => _CameraExampleAppState();
}

class _CameraExampleAppState extends State<CameraExampleApp> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _controller = CameraController(_cameras[0], ResolutionPreset.medium);
        await _controller!.initialize();
        setState(() {});
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Camera with Torch Control')),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            flex: 2,
            child: CameraPreview(_controller!),
          ),
          
          // Torch level control
          Expanded(
            flex: 1,
            child: TorchLevelControlExample(controller: _controller!),
          ),
        ],
      ),
    );
  }
}
