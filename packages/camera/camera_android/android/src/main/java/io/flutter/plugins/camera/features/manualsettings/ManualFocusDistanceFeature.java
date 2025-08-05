// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.manualsettings;

import android.annotation.SuppressLint;
import android.hardware.camera2.CaptureRequest;
import androidx.annotation.NonNull;
import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.features.CameraFeature;

/** Controls the manual focus distance for the camera. */
public class ManualFocusDistanceFeature extends CameraFeature<Double> {
  private double currentSetting = 0.0;

  /**
   * Creates a new instance of the {@link ManualFocusDistanceFeature}.
   *
   * @param cameraProperties Collection of the characteristics for the current camera device.
   */
  public ManualFocusDistanceFeature(@NonNull CameraProperties cameraProperties) {
    super(cameraProperties);
  }

  @NonNull
  @Override
  public String getDebugName() {
    return "ManualFocusDistanceFeature";
  }

  @SuppressLint("KotlinPropertyAccess")
  @NonNull
  @Override
  public Double getValue() {
    return currentSetting;
  }

  @Override
  public void setValue(@NonNull Double value) {
    this.currentSetting = value;
  }

  @Override
  public boolean checkIsSupported() {
    Float minFocus = cameraProperties.getLensInfoMinimumFocusDistance();
    // Manual focus is supported if the camera has adjustable focus
    return minFocus != null && minFocus > 0;
  }

  @Override
  public void updateBuilder(@NonNull CaptureRequest.Builder requestBuilder) {
    // Manual focus distance is handled by Camera.java in updateBuilderSettings
    // This method is kept for compatibility but doesn't apply settings directly
    if (!checkIsSupported()) {
      return;
    }
    
    // The actual setting is handled by Camera.java in updateBuilderSettings
    // Camera.java will check if currentSetting > 0.0 and apply the focus distance
  }

  /**
   * Returns the minimum focus distance supported by the camera.
   *
   * @return double Minimum focus distance (normalized 0.0-1.0).
   */
  public double getMinFocusDistance() {
    return 0.0; // Always 0.0 for closest focus
  }

  /**
   * Returns the maximum focus distance supported by the camera.
   *
   * @return double Maximum focus distance (normalized 0.0-1.0).
   */
  public double getMaxFocusDistance() {
    return 1.0; // Always 1.0 for infinity focus
  }
}
