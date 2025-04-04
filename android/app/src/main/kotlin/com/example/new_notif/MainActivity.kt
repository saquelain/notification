package com.example.new_notif

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.app.ActivityManager

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.new_notif/sms_reader"
    private val SMS_RECEIVER_CHANNEL = "com.example.new_notif/sms_receiver"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "startService" -> {
                    startSmsReaderService()
                    result.success(true)
                }
                "stopService" -> {
                    stopSmsReaderService()
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(isServiceRunning(SmsReaderService::class.java))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun startSmsReaderService() {
        val serviceIntent = Intent(this, SmsReaderService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }
    
    private fun stopSmsReaderService() {
        val serviceIntent = Intent(this, SmsReaderService::class.java)
        stopService(serviceIntent)
    }
    
    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (service in manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.name == service.service.className) {
                return true
            }
        }
        return false
    }
}