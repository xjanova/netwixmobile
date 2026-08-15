package com.netwix.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Lets Dart background the app instead of closing it.
     *
     * Flutter's default for a back press on the root route is SystemNavigator.pop(), which FINISHES
     * this Activity. Android then tears the task down, so the next launch is a cold start at the
     * intro screen and whatever the viewer was browsing is gone (owner, 2026-08-16: backing out of
     * the app should leave it where it was, not restart it from the beginning).
     *
     * moveTaskToBack() is what the Home button does: the task stays in Recents with its state
     * intact, so re-opening resumes exactly where the viewer left off.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.netwix.app/navigation")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }
}
