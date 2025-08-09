// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:camera_android/camera_android.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';

/// A simple example demonstrating white balance controls for the camera.
class WhiteBalanceExample extends StatefulWidget {
  /// Default Constructor
  const WhiteBalanceExample({super.key});

  @override
  State<WhiteBalanceExample> createState() => _WhiteBalanceExampleState();
}

class _WhiteBalanceExampleState extends State<WhiteBalanceExample> {
  CameraController? controller;
  String? error;
  WhiteBalanceMode currentWhiteBalanceMode = WhiteBalanceMode.auto;
  int currentColorTemperature = 5500; // Default daylight temperature
  int minColorTemperature = 2000;
  int maxColorTemperature = 8000;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          error = 'No cameras available';
        });
        return;
      }

      // Prefer back camera for more white balance options
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller!.initialize();

      // Get white balance temperature range
      try {
        minColorTemperature = await controller!.getMinColorTemperature();
        maxColorTemperature = await controller!.getMaxColorTemperature();
        
        // Set current color temperature to middle of range
        currentColorTemperature = (minColorTemperature + maxColorTemperature) ~/ 2;
      } catch (e) {
        print('Error getting color temperature range: $e');
        // Use defaults if not supported
      }

      setState(() {});
    } catch (e) {
      setState(() {
        error = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _setWhiteBalanceMode(WhiteBalanceMode mode) async {
    if (controller == null) return;

    try {
      await controller!.setWhiteBalanceMode(mode);
      setState(() {
        currentWhiteBalanceMode = mode;
      });
    } catch (e) {
      setState(() {
        error = 'Failed to set white balance mode: $e';
      });
    }
  }

  Future<void> _setColorTemperature(int temperature) async {
    if (controller == null) return;

    try {
      await controller!.setManualColorTemperature(temperature);
      setState(() {
        currentColorTemperature = temperature;
      });
    } catch (e) {
      setState(() {
        error = 'Failed to set color temperature: $e';
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('White Balance Example')),
        body: Center(
          child: Text(
            error!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('White Balance Example')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('White Balance Controls'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Camera Preview
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CameraPreview(controller!),
              ),
            ),
          ),
          
          // Controls
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // White Balance Mode
                  const Text(
                    'White Balance Mode:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _setWhiteBalanceMode(WhiteBalanceMode.auto),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentWhiteBalanceMode == WhiteBalanceMode.auto
                                ? Colors.blue
                                : Colors.grey[300],
                            foregroundColor: currentWhiteBalanceMode == WhiteBalanceMode.auto
                                ? Colors.white
                                : Colors.black,
                          ),
                          child: const Text('Auto'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _setWhiteBalanceMode(WhiteBalanceMode.locked),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentWhiteBalanceMode == WhiteBalanceMode.locked
                                ? Colors.blue
                                : Colors.grey[300],
                            foregroundColor: currentWhiteBalanceMode == WhiteBalanceMode.locked
                                ? Colors.white
                                : Colors.black,
                          ),
                          child: const Text('Manual'),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Manual Color Temperature (only when in locked mode)
                  if (currentWhiteBalanceMode == WhiteBalanceMode.locked) ...[
                    Text(
                      'Color Temperature: ${currentColorTemperature}K',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Cool\n(${2000}K)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: currentColorTemperature.toDouble(),
                            min: minColorTemperature.toDouble(),
                            max: maxColorTemperature.toDouble(),
                            divisions: ((maxColorTemperature - minColorTemperature) / 100).round(),
                            onChanged: (value) {
                              setState(() {
                                currentColorTemperature = value.round();
                              });
                            },
                            onChangeEnd: (value) {
                              _setColorTemperature(value.round());
                            },
                          ),
                        ),
                        const Text('Warm\n(${8000}K)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    
                    // Preset Temperature Buttons
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        _TemperaturePresetButton(
                          label: 'Tungsten\n(3000K)',
                          temperature: 3000,
                          onPressed: () => _setColorTemperature(3000),
                        ),
                        _TemperaturePresetButton(
                          label: 'Fluorescent\n(4000K)',
                          temperature: 4000,
                          onPressed: () => _setColorTemperature(4000),
                        ),
                        _TemperaturePresetButton(
                          label: 'Daylight\n(5500K)',
                          temperature: 5500,
                          onPressed: () => _setColorTemperature(5500),
                        ),
                        _TemperaturePresetButton(
                          label: 'Shade\n(7000K)',
                          temperature: 7000,
                          onPressed: () => _setColorTemperature(7000),
                        ),
                      ],
                    ),
                  ],
                  
                  // Current Status
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Current: ${currentWhiteBalanceMode == WhiteBalanceMode.auto ? "Auto White Balance" : "Manual ($currentColorTemperature K)"}',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemperaturePresetButton extends StatelessWidget {
  const _TemperaturePresetButton({
    required this.label,
    required this.temperature,
    required this.onPressed,
  });

  final String label;
  final int temperature;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue[800],
          side: BorderSide(color: Colors.blue[300]!),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
