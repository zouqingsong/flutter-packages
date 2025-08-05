// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.manualsettings;

import android.annotation.SuppressLint;
import android.hardware.camera2.CaptureRequest;
import android.util.Range;
import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.features.CameraFeature;

/** Controls the manual exposure time for the camera. */
public class ManualExposureTimeFeature extends CameraFeature<Integer> {
  private Integer currentSetting = 0;

  /**
   * Creates a new instance of the {@link ManualExposureTimeFeature}.
   *
   * @param cameraProperties Collection of the characteristics for the current camera device.
   */
  public ManualExposureTimeFeature(CameraProperties cameraProperties) {
    super(cameraProperties);
  }

  public String getDebugName() {
    return "ManualExposureTimeFeature";
  }

  @SuppressLint("KotlinPropertyAccess")
  public Integer getValue() {
    return currentSetting;
  }

  /**
   * Sets the manual exposure time value.
   *
   * @param value The exposure time in microseconds.
   */
  public void setValue(Integer value) {
    if (value == null) {
      currentSetting = 0;
    } else {
      currentSetting = value;
    }
  }

  @Override
  public void updateBuilder(CaptureRequest.Builder requestBuilder) {
    // The control modes (CONTROL_MODE, CONTROL_AE_MODE) are handled by Camera.java
    // This feature only applies the exposure time value when needed
    // Camera.java will check if currentSetting > 0 and coordinate all manual controls
    if (!checkIsSupported()) {
      return;
    }
    
    // The actual setting is handled by Camera.java in updateBuilderSettings
    // This method is kept for compatibility but doesn't apply settings directly
  }

  /**
   * Returns the minimum supported exposure time in microseconds.
   *
   * @return int Minimum exposure time in microseconds.
   */
  public int getMinExposureTime() {
    Range<Long> range = cameraProperties.getSensorInfoExposureTimeRange();
    if (range == null) {
      return 0;
    }
    // Convert nanoseconds to microseconds
    return (int) (range.getLower() / 1000L);
  }

  /**
   * Returns the maximum supported exposure time in microseconds.
   *
   * @return int Maximum exposure time in microseconds.
   */
  public int getMaxExposureTime() {
    Range<Long> range = cameraProperties.getSensorInfoExposureTimeRange();
    if (range == null) {
      return 0;
    }
    // Convert nanoseconds to microseconds and limit to reasonable maximum
    long maxNs = range.getUpper();
    long maxMicros = maxNs / 1000L;
    
    // Limit to 30 seconds (30,000,000 microseconds) to prevent unreasonably long exposures
    return (int) Math.min(maxMicros, 30_000_000L);
  }

  @Override
  public boolean checkIsSupported() {
    Range<Long> range = cameraProperties.getSensorInfoExposureTimeRange();
    return range != null && range.getLower() != null && range.getUpper() != null;
  }
}
