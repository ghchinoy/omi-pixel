package com.ghchinoy.omi_pixel

import android.app.KeyguardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_STATE_CHANNEL = "com.ghchinoy.omi_pixel/device_state"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_STATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDeviceLocked" -> {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                        result.success(km?.isKeyguardLocked == true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
