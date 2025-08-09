// Research Camera2 API for white balance and color temperature characteristics
// According to Android Camera2 API documentation:

/*
Camera2 API White Balance Related Characteristics:

1. CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES
   - Available white balance modes (auto, off, incandescent, etc.)

2. CameraCharacteristics.CONTROL_MAX_REGIONS_AWB  
   - Maximum number of auto-white-balance regions

3. CameraCharacteristics.COLOR_CORRECTION_AVAILABLE_ABERRATION_MODES
   - Available color correction aberration modes

4. However, there is NO direct Camera2 API characteristic for:
   - Color temperature ranges (min/max Kelvin values)
   - Color correction gains ranges
   
The reason is that Camera2 API typically uses predefined white balance modes:
- AUTO, INCANDESCENT, FLUORESCENT, WARM_FLUORESCENT, DAYLIGHT, CLOUDY_DAYLIGHT, TWILIGHT, SHADE, OFF

Manual color temperature control via ColorCorrectionGains is not standardized
across devices, so manufacturers don't expose min/max temperature ranges.

Common real-world device ranges vary:
- Budget phones: ~2700K - 6500K  
- Flagship phones: ~2000K - 8000K
- Professional cameras: ~2000K - 10000K+

The hardcoded 2000K-8000K range is actually a reasonable conservative estimate
that should work on most Android devices without causing invalid gain values.
*/
