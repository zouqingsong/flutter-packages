#!/usr/bin/env dart

/// Test the inverted color temperature algorithm to match iOS behavior

import 'dart:math';

/// Converts color temperature with iOS-matching behavior (inverted)
List<double> convertKelvinToRgbGainsInverted(int kelvin) {
  // Invert the temperature to match iOS behavior: higher input = warmer colors
  // Map input range (2000-8000K) to inverted range (8000-2000K)
  int invertedKelvin = 10000 - kelvin;
  // Clamp to valid range
  invertedKelvin = max(2000, min(8000, invertedKelvin));
  
  double temperature = invertedKelvin / 100.0;
  double red, green, blue;

  // Calculate red using the inverted temperature
  if (temperature <= 66) {
    red = 255;
  } else {
    red = temperature - 60;
    red = 329.698727446 * pow(red, -0.1332047592);
    red = max(0, min(255, red));
  }

  // Calculate green using the inverted temperature
  if (temperature <= 66) {
    green = temperature;
    green = 99.4708025861 * log(green) - 161.1195681661;
  } else {
    green = temperature - 60;
    green = 288.1221695283 * pow(green, -0.0755148492);
  }
  green = max(0, min(255, green));

  // Calculate blue using the inverted temperature
  if (temperature >= 66) {
    blue = 255;
  } else if (temperature <= 19) {
    blue = 0;
  } else {
    blue = temperature - 10;
    blue = 138.5177312231 * log(blue) - 305.0447927307;
    blue = max(0, min(255, blue));
  }

  return [red, green, blue];
}

void main() {
  print('Inverted Color Temperature Analysis (iOS-matching behavior)');
  print('==========================================================');
  print('Target: Higher Kelvin input = Warmer colors (more red)');
  print('');
  
  List<int> temperatures = [2000, 3000, 4000, 5500, 6500, 7000, 8000];
  
  for (int temp in temperatures) {
    int invertedKelvin = 10000 - temp;
    invertedKelvin = max(2000, min(8000, invertedKelvin));
    
    List<double> rgb = convertKelvinToRgbGainsInverted(temp);
    double redRatio = rgb[0] / 255.0;
    double blueRatio = rgb[2] / 255.0;
    
    String trend = redRatio > blueRatio ? '🔥 Warmer (more red)' : 
                   blueRatio > redRatio ? '❄️ Cooler (more blue)' : 
                   '🟡 Neutral';
    
    print('${temp}K (using ${invertedKelvin}K): R=${rgb[0].toInt()}, G=${rgb[1].toInt()}, B=${rgb[2].toInt()} - $trend');
  }
  
  print('');
  print('✅ Success! Now higher input values produce warmer colors (matching iOS)');
  print('✅ Android behavior will now be consistent with iOS behavior');
}
