package com.example.new_notif

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONObject
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            
            for (sms in messages) {
                val sender = sms.displayOriginatingAddress
                val body = sms.messageBody
                val timestamp = System.currentTimeMillis()
                
                // Save message to SharedPreferences
                saveMessage(context, sender, body, timestamp)
                
                // Update notification
                updateServiceNotification(context, sender, body)
                
                // Launch the app
                launchApp(context)
            }
        }
    }
    
    private fun saveMessage(context: Context, sender: String, body: String, timestamp: Long) {
        val prefs = context.getSharedPreferences("sms_messages_prefs", Context.MODE_PRIVATE)
        val messagesJson = prefs.getString("sms_messages", "[]")
        
        try {
            val messagesArray = JSONArray(messagesJson)
            
            // Create new message JSON object
            val messageObj = JSONObject()
            messageObj.put("sender", sender)
            messageObj.put("body", body)
            messageObj.put("timeReceived", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).format(Date(timestamp)))
            
            // Add to array
            messagesArray.put(messageObj)
            
            // Save back to SharedPreferences
            val editor = prefs.edit()
            editor.putString("sms_messages", messagesArray.toString())
            editor.apply()
            
        } catch (e: Exception) {
            Log.e("SmsReceiver", "Error saving message: ${e.message}")
        }
    }
    
    private fun updateServiceNotification(context: Context, sender: String, body: String) {
        val serviceIntent = Intent(context, SmsReaderService::class.java)
        serviceIntent.action = "UPDATE_NOTIFICATION"
        serviceIntent.putExtra("sender", sender)
        serviceIntent.putExtra("message", body)
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
    
    private fun launchApp(context: Context) {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launchIntent)
    }
}