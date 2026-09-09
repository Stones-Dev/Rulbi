package com.stonesdev.iptv.iptv_app

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.stonesdev.iptv/form_factor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isLeanbackDevice" -> {
                    val isTv = isTelevisionDevice()
                    result.success(isTv)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.stonesdev.iptv/pip").setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE))
                    } else {
                        result.success(false)
                    }
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            val entered = enterPictureInPictureMode(params)
                            result.success(entered)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isTelevisionDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager != null && uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        val pm = packageManager
        return pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
               pm.hasSystemFeature("android.hardware.type.television")
    }
}
