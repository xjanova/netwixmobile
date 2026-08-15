import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform hooks for leaving the app without destroying it.
class AppNavigation {
  static const MethodChannel _channel = MethodChannel('com.netwix.app/navigation');

  /// Send the app to the background, the way the Home button does.
  ///
  /// Flutter's default when back is pressed on the root route is `SystemNavigator.pop()`, which
  /// finishes the Activity — Android drops the task, so the next launch is a COLD start back at the
  /// intro screen instead of where the viewer was. `moveTaskToBack` keeps the task in Recents with
  /// its state, so re-opening resumes in place.
  ///
  /// Android-only; on any other platform this is a no-op and the caller should leave the default
  /// behaviour alone (iOS has no back button and apps are not expected to close themselves).
  static Future<bool> moveTaskToBack() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('moveTaskToBack') ?? false;
    } on PlatformException {
      return false; // older build without the channel — fall back to the default pop
    } on MissingPluginException {
      return false;
    }
  }
}
