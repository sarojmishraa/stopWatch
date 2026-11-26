import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Publish the supplied artist's actual attribution on the app's licence page.
/// An absent asset has no invented credit. Installation supplies CREDITS.md.
void registerGoldenEagleCredits() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const path = 'assets/3d/CREDITS.md';
    if (!manifest.listAssets().contains(path)) return;
    yield LicenseEntryWithLineBreaks(const [
      'Golden eagle 3D model',
    ], await rootBundle.loadString(path));
  });
}
