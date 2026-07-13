package com.naveen.expense_manager.expense_manager

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.naveen.expense_manager/updater"
    private val notificationChannel = "com.naveen.expense_manager/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestInstalls" -> result.success(canRequestInstalls())
                    "openInstallPermission" -> {
                        openInstallPermission()
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("missing_path", "APK path is required", null)
                        } else {
                            try {
                                installApk(path)
                                result.success(null)
                            } catch (error: Exception) {
                                result.error("install_failed", error.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessEnabled" -> result.success(
                        FinancialNotificationListenerService.isAccessEnabled(this),
                    )
                    "openAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "setCaptureEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        FinancialNotificationListenerService.setCaptureEnabled(this, enabled)
                        result.success(null)
                    }
                    "getPending" -> result.success(
                        FinancialNotificationListenerService.getPending(this),
                    )
                    "acknowledge" -> {
                        val ids = call.argument<List<String>>("ids").orEmpty()
                        FinancialNotificationListenerService.acknowledge(this, ids)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canRequestInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
        }
    }

    private fun installApk(path: String) {
        val apk = File(path)
        require(apk.exists()) { "Downloaded APK does not exist" }
        val uri = FileProvider.getUriForFile(this, "$packageName.updater", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }
}
