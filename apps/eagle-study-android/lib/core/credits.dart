import 'package:flutter/foundation.dart';

/// Adds third-party asset credits to Flutter's licence page
/// (showLicensePage). CC BY 4.0 requires visible attribution.
void registerAssetCredits() {
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['Bald Eagle 3D model'],
        '"Bald Eagle" by ucdavisterc\n'
        'https://sketchfab.com/3d-models/none-8874cfcf83a54575ba8068376f8a63a8\n\n'
        'Licensed under Creative Commons Attribution 4.0 International '
        '(CC BY 4.0): https://creativecommons.org/licenses/by/4.0/\n\n'
        'Changes: converted to a single .glb file and textures downscaled '
        'for mobile devices. Animated in-app by EAGLE STUDY.',
      ),
    ),
  );
}
