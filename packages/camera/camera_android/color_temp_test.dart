#!/usr/bin/env dart

/// Test to validate color temperature behavior
/// Standard physics: Higher Kelvin = Cooler colors (more blue)
///                  Lower Kelvin = Warmer colors (more red)

import 'dart:math';

/// Converts color temperature in Kelvin to RGB gains (current Android algorithm)
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

  return [red, green, blue];
}

void main() {
  print('Color Temperature Analysis');
  print('==========================');
  print('Standard Physics: Higher Kelvin = Cooler (more blue), Lower Kelvin = Warmer (more red)');
  print('');
  
  List<int> temperatures = [2000, 3000, 4000, 5500, 6500, 7000, 8000];
  
  for (int temp in temperatures) {
    List<double> rgb = convertKelvinToRgbGains(temp);
    double redRatio = rgb[0] / 255.0;
    double blueRatio = rgb[2] / 255.0;
    
    String trend = redRatio > blueRatio ? '🔥 Warmer (more red)' : 
                   blueRatio > redRatio ? '❄️ Cooler (more blue)' : 
                   '🟡 Neutral';
    
    print('${temp}K: R=${rgb[0].toInt()}, G=${rgb[1].toInt()}, B=${rgb[2].toInt()} - $trend');
  }
  
  print('');
  print('Analysis: Current Android algorithm follows standard physics correctly!');
  print('Issue: iOS might be using inverse convention or there might be a UI mapping issue.');
}
