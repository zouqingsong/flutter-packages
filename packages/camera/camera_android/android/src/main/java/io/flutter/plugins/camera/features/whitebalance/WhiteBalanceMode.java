// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.whitebalance;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

// Mirrors white_balance_mode.dart
public enum WhiteBalanceMode {
  auto("auto"),
  locked("locked");

  private final String strValue;

  WhiteBalanceMode(String strValue) {
    this.strValue = strValue;
  }

  /**
   * Tries to convert the supplied string into a {@see WhiteBalanceMode} enum value.
   *
   * <p>When the supplied string doesn't match a valid {@see WhiteBalanceMode} enum value, null is
   * returned.
   *
   * @param modeStr String value to convert into an {@see WhiteBalanceMode} enum value.
   * @return Matching {@see WhiteBalanceMode} enum value, or null if no match is found.
   */
  @Nullable
  public static WhiteBalanceMode getValueForString(@NonNull String modeStr) {
    for (WhiteBalanceMode value : values()) {
      if (value.strValue.equals(modeStr)) return value;
    }
    return null;
  }

  @Override
  public String toString() {
    return strValue;
  }
}
