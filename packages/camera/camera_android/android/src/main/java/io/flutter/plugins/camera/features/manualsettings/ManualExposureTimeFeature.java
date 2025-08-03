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

/** Controls the manual exposure time (shutter speed) for the camera. */
public class ManualExposureTimeFeature extends CameraFeature<Integer> {
  private int currentSetting = 0; // Exposure time in microseconds

  /**
   * Creates a new instance of the {@link ManualExposureTimeFeature}.
   *
   * @param cameraProperties Collection of the characteristics for the current camera device.
   */
  public ManualExposureTimeFeature(@NonNull CameraProperties cameraProperties) {
    super(cameraProperties);
  }

  @NonNull
  @Override
  public String getDebugName() {
    return "ManualExposureTimeFeature";
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
    Range<Long> exposureTimeRange = cameraProperties.getSensorInfoExposureTimeRange();
    return exposureTimeRange != null;
  }

  @Override
  public void updateBuilder(@NonNull CaptureRequest.Builder requestBuilder) {
    if (!checkIsSupported()) {
      return;
    }

    // Convert microseconds to nanoseconds (Camera2 API uses nanoseconds)
    long exposureTimeNs = currentSetting * 1000L;
    requestBuilder.set(CaptureRequest.SENSOR_EXPOSURE_TIME, exposureTimeNs);
  }

  /**
   * Returns the minimum supported exposure time in microseconds.
   *
   * @return int Minimum exposure time in microseconds.
   */
  public int getMinExposureTime() {
    Range<Long> exposureTimeRange = cameraProperties.getSensorInfoExposureTimeRange();
    if (exposureTimeRange == null) {
      return 0;
    }
    // Convert nanoseconds to microseconds
    return (int) (exposureTimeRange.getLower() / 1000L);
  }

  /**
   * Returns the maximum supported exposure time in microseconds.
   *
   * @return int Maximum exposure time in microseconds.
   */
  public int getMaxExposureTime() {
    Range<Long> exposureTimeRange = cameraProperties.getSensorInfoExposureTimeRange();
    if (exposureTimeRange == null) {
      return 0;
    }
    // Convert nanoseconds to microseconds, cap at reasonable max
    long maxTimeNs = exposureTimeRange.getUpper();
    long maxTimeMicros = maxTimeNs / 1000L;
    // Cap at 30 seconds (30,000,000 microseconds) for practical use
    return (int) Math.min(maxTimeMicros, 30_000_000L);
  }
}
