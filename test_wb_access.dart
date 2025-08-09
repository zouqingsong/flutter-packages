import 'package:camera/camera.dart' as camera;

void main() {
  // Test accessing all camera modes with prefix
  print('FlashMode.auto: ${camera.FlashMode.auto}');
  print('FocusMode.auto: ${camera.FocusMode.auto}');
  print('ExposureMode.auto: ${camera.ExposureMode.auto}');
  print('WhiteBalanceMode.auto: ${camera.WhiteBalanceMode.auto}');
  
  // Test enum values
  print('FlashMode values: ${camera.FlashMode.values}');
  print('WhiteBalanceMode values: ${camera.WhiteBalanceMode.values}');
}
