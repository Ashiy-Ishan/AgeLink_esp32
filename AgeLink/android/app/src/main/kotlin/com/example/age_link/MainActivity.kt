package com.example.age_link

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "agelink/local_reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "begin" -> {
                        LocalReminders.begin(this, requireNotNull(call.argument<String>("uid")))
                        result.success(null)
                    }
                    "replace" -> {
                        LocalReminders.replace(
                            this, requireNotNull(call.argument<String>("uid")),
                            requireNotNull(call.argument<String>("doses"))
                        )
                        result.success(null)
                    }
                    "clear" -> {
                        LocalReminders.clear(this)
                        result.success(null)
                    }
                    "refresh" -> {
                        LocalReminders.refresh(this, keepPending = true)
                        result.success(null)
                    }
                    "status" -> result.success(LocalReminders.status(this))
                    "exactSettings" -> {
                        if (Build.VERSION.SDK_INT >= 31) {
                            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
