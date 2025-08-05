// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.manualsettings;

import android.annotation.SuppressLint;
import android.hardware.camera2.CaptureRequest;
import android.util.Range;
import androidx.annotation.NonNull;
import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.features.CameraFeature;

/** Controls the manual ISO sensitivity for the camera. */
public class ManualIsoFeature extends CameraFeature<Integer> {
  private int currentSetting = 100; // Default ISO value

  /**
   * Creates a new instance of the {@link ManualIsoFeature}.
   *
   * @param cameraProperties Collection of the characteristics for the current camera device.
   */
  public ManualIsoFeature(@NonNull CameraProperties cameraProperties) {
    super(cameraProperties);
  }

  @NonNull
  @Override
  public String getDebugName() {
    return "ManualIsoFeature";
  }

  @SuppressLint("KotlinPropertyAccess")
  @NonNull
  @Override
  public Integer getValue() {
    return currentSetting;
  }

  @Override
  public void setValue(@NonNull Integer value) {
    this.currentSetting = value;
  }

  @Override
  public boolean checkIsSupported() {
    Range<Integer> isoRange = cameraProperties.getSensorInfoSensitivityRange();
    return isoRange != null;
  }

  @Override
  public void updateBuilder(@NonNull CaptureRequest.Builder requestBuilder) {
    // The control modes (CONTROL_MODE, CONTROL_AE_MODE) are handled by Camera.java  
    // This feature only provides the ISO value when needed
    // Camera.java will check if currentSetting > 0 and coordinate all manual controls
    if (!checkIsSupported()) {
      return;
    }
    
    // The actual setting is handled by Camera.java in updateBuilderSettings
    // This method is kept for compatibility but doesn't apply settings directly
  }

  /**
   * Returns the minimum supported ISO sensitivity.
   *
   * @return int Minimum ISO sensitivity.
   */
  public int getMinIso() {
    Range<Integer> isoRange = cameraProperties.getSensorInfoSensitivityRange();
    if (isoRange == null) {
      return 100; // Default minimum
    }
    return isoRange.getLower();
  }

  /**
   * Returns the maximum supported ISO sensitivity.
   *
   * @return int Maximum ISO sensitivity.
   */
  public int getMaxIso() {
    Range<Integer> isoRange = cameraProperties.getSensorInfoSensitivityRange();
    if (isoRange == null) {
      return 3200; // Default maximum
    }
    return isoRange.getUpper();
  }
}
