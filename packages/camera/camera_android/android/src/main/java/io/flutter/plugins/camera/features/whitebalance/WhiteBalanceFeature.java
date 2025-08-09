// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.whitebalance;

import android.annotation.SuppressLint;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CaptureRequest;
import androidx.annotation.NonNull;
import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.features.CameraFeature;

/** Controls the white balance mode for the camera. */
public class WhiteBalanceFeature extends CameraFeature<WhiteBalanceMode> {
  @NonNull private WhiteBalanceMode currentSetting = WhiteBalanceMode.auto;

  /**
   * Creates a new instance of the {@see WhiteBalanceFeature}.
   *
   * @param cameraProperties Collection of the characteristics for the current camera device.
   */
  public WhiteBalanceFeature(@NonNull CameraProperties cameraProperties) {
    super(cameraProperties);
  }

  @NonNull
  @Override
  public String getDebugName() {
    return "WhiteBalanceFeature";
  }

  @SuppressLint("KotlinPropertyAccess")
  @NonNull
  @Override
  public WhiteBalanceMode getValue() {
    return currentSetting;
  }

  @Override
  public void setValue(@NonNull WhiteBalanceMode value) {
    this.currentSetting = value;
  }

  @Override
  public boolean checkIsSupported() {
    // White balance is supported on most devices
    return true;
  }

  @Override
  public void updateBuilder(@NonNull CaptureRequest.Builder requestBuilder) {
    if (!checkIsSupported()) {
      return;
    }

    switch (currentSetting) {
      case auto:
        requestBuilder.set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO);
        requestBuilder.set(CaptureRequest.CONTROL_AWB_LOCK, false);
        break;
      case locked:
        requestBuilder.set(CaptureRequest.CONTROL_AWB_LOCK, true);
        break;
    }
  }
}
