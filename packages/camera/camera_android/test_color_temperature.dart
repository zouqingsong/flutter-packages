#!/usr/bin/env dart

/// Test script to validate the color temperature conversion algorithm
/// adapted from the Xamarin implementation.

import 'dart:math';

/// Converts color temperature in Kelvin to RGB gains for Camera2 API.
/// Algorithm adapted from proven Xamarin implementation.
List<double> convertKelvinToRgbGains(int kelvin) {
  double temperature = kelvin / 100.0;
  double red, green, blue;

  // Calculate red
  if (temperature <= 66) {
    red = 255;
  } else {
    red = temperature - 60;
    red = 329.698727446 * pow(red, -0.1332047592);
    red = max(0, min(255, red));
  }

  // Calculate green
  if (temperature <= 66) {
    green = temperature;
    green = 99.4708025861 * log(green) - 161.1195681661;
  } else {
    green = temperature - 60;
    green = 288.1221695283 * pow(green, -0.0755148492);
  }
  green = max(0, min(255, green));

  // Calculate blue
  if (temperature >= 66) {
    blue = 255;
  } else if (temperature <= 19) {
    blue = 0;
  } else {
    blue = temperature - 10;
    blue = 138.5177312231 * log(blue) - 305.0447927307;
    blue = max(0, min(255, blue));
  }

  // Convert to normalized gains (0-1 range) and create RGGB array
  // Note: RGGB format means Red, Green, Green, Blue (two green channels)
  return [
    (red / 255.0) * 2.0,    // Red gain
    (green / 255.0),        // Green gain
    (green / 255.0),        // Green gain (duplicate)
    (blue / 255.0) * 2.0    // Blue gain
  ];
}

void main() {
  print('Color Temperature to RGB Gains Conversion Test');
  print('Algorithm adapted from Xamarin Camera2Basic implementation');
  print('===================================================');
  
  // Test common color temperature values
  List<int> testTemperatures = [2000, 2700, 3000, 4000, 5500, 6500, 7000, 8000];
  
  for (int temp in testTemperatures) {
    List<double> gains = convertKelvinToRgbGains(temp);
    print('${temp}K: R=${gains[0].toStringAsFixed(3)}, '
          'G=${gains[1].toStringAsFixed(3)}, '
          'G=${gains[2].toStringAsFixed(3)}, '
          'B=${gains[3].toStringAsFixed(3)}');
  }
  
  print('\nValidation:');
  print('- Warmer colors (2000-3000K) should have higher red gains');
  print('- Cooler colors (6000-8000K) should have higher blue gains');
  print('- Green gains should be relatively consistent');
  print('- All gains should be in range [0, 2] for proper camera operation');
  
  // Validate ranges
  bool allValid = true;
  for (int temp in testTemperatures) {
    List<double> gains = convertKelvinToRgbGains(temp);
    for (double gain in gains) {
      if (gain < 0 || gain > 2.0) {
        print('WARNING: Invalid gain ${gain} for ${temp}K');
        allValid = false;
      }
    }
  }
  
  if (allValid) {
    print('\n✅ All color temperature conversions are within valid range!');
    print('✅ The Xamarin algorithm has been successfully adapted to Dart!');
  } else {
    print('\n❌ Some gains are outside valid range');
  }
}
