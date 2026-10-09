// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.focuspoint;

import android.annotation.SuppressLint;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.MeteringRectangle;
import android.util.Log;
import android.util.Size;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.embedding.engine.systemchannels.PlatformChannel;
import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.CameraRegionUtils;
import io.flutter.plugins.camera.features.CameraFeature;
import io.flutter.plugins.camera.features.Point;
import io.flutter.plugins.camera.features.sensororientation.SensorOrientationFeature;

/** Focus point controls where in the frame focus will come from. */
public class FocusPointFeature extends CameraFeature<Point> {

  private static final String TAG = "FocusPointFeature";

  private Size cameraBoundaries;
  @Nullable private Point focusPoint;
  private MeteringRectangle focusRectangle;
  @NonNull private final SensorOrientationFeature sensorOrientationFeature;

  /**
   * Creates a new instance of the {@link FocusPointFeature}.
   *
   * @param cameraProperties Collection of the characteristics for the current camera device.
   */
  public FocusPointFeature(
      @NonNull CameraProperties cameraProperties,
      @NonNull SensorOrientationFeature sensorOrientationFeature) {
    super(cameraProperties);
    this.sensorOrientationFeature = sensorOrientationFeature;
  }

  /**
   * Sets the camera boundaries that are required for the focus point feature to function.
   *
   * @param cameraBoundaries - The camera boundaries to set.
   */
  public void setCameraBoundaries(@NonNull Size cameraBoundaries) {
    this.cameraBoundaries = cameraBoundaries;
    this.buildFocusRectangle();
  }

  @NonNull
  @Override
  public String getDebugName() {
    return "FocusPointFeature";
  }

  @SuppressLint("KotlinPropertyAccess")
  @Nullable
  @Override
  public Point getValue() {
    return focusPoint;
  }

  @Override
  public void setValue(@Nullable Point value) {
    this.focusPoint = value == null || value.x == null || value.y == null ? null : value;
    this.buildFocusRectangle();
  }

  // Whether or not this camera can set the focus point.
  @Override
  public boolean checkIsSupported() {
    Integer supportedRegions = cameraProperties.getControlMaxRegionsAutoFocus();
    return supportedRegions != null && supportedRegions > 0;
  }

  @Override
  public void updateBuilder(@NonNull CaptureRequest.Builder requestBuilder) {
    if (!checkIsSupported()) {
      return;
    }
    requestBuilder.set(
        CaptureRequest.CONTROL_AF_REGIONS,
        focusRectangle == null ? null : new MeteringRectangle[] {focusRectangle});
  }

  private void buildFocusRectangle() {
    if (this.cameraBoundaries == null) {
      // No boundaries yet, so a point cannot be turned into a rectangle. This used
      // to throw, which took the whole app down: the boundaries are set while a
      // capture session is created (Camera.createCaptureSession), so a tap that
      // arrives before the first session is configured - on a preview that is
      // already showing frames, or a point restored at startup - hit it. The point
      // is kept, and setCameraBoundaries() builds the rectangle as soon as the
      // boundaries exist. A dropped focus tap beats a crash.
      Log.w(TAG, "Focus point ignored: camera boundaries are not known yet.");
      this.focusRectangle = null;
      return;
    }
    if (this.focusPoint == null) {
      this.focusRectangle = null;
    } else {
      PlatformChannel.DeviceOrientation orientation =
          this.sensorOrientationFeature.getLockedCaptureOrientation();
      if (orientation == null) {
        orientation =
            this.sensorOrientationFeature.getDeviceOrientationManager().getLastUIOrientation();
      }
      this.focusRectangle =
          CameraRegionUtils.convertPointToMeteringRectangle(
              this.cameraBoundaries, this.focusPoint.x, this.focusPoint.y, orientation);
    }
  }
}
