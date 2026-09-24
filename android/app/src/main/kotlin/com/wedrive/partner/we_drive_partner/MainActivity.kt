package com.wedrive.partner.we_drive_partner

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "wedrive_booking_high",
                "WeDrive247 Booking Requests",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Urgent incoming chauffeur booking requests"
                enableVibration(true)
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
    companion object {
        private const val CHANNEL = "we_drive/maps"
        private const val GOOGLE_MAPS_PACKAGE = "com.google.android.apps.maps"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "openGoogleMaps") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val destination = call.argument<String>("destination")?.trim().orEmpty()
                if (destination.isEmpty()) {
                    result.success(false)
                    return@setMethodCallHandler
                }

                val navigationUri = Uri.parse(
                    "google.navigation:q=${Uri.encode(destination)}&mode=d"
                )
                val mapIntent = Intent(Intent.ACTION_VIEW, navigationUri).apply {
                    setPackage(GOOGLE_MAPS_PACKAGE)
                }

                if (mapIntent.resolveActivity(packageManager) == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }

                try {
                    startActivity(mapIntent)
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
    }
}
