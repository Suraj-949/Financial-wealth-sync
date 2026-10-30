package com.wealthsync.wealthsync

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, INCOMING_SMS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    companion object {
        private const val INCOMING_SMS_CHANNEL = "wealthsync/sms_incoming"
        @Volatile private var eventSink: EventChannel.EventSink? = null

        fun emitIncomingSms(address: String, body: String, dateMs: Long) {
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(
                    mapOf("address" to address, "body" to body, "dateMs" to dateMs),
                )
            }
        }
    }
}
