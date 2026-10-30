package com.wealthsync.wealthsync

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class IncomingSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "android.provider.Telephony.SMS_RECEIVED") return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val first = messages.firstOrNull() ?: return
        MainActivity.emitIncomingSms(
            address = first.originatingAddress.orEmpty(),
            body = messages.joinToString(separator = "") { it.messageBody.orEmpty() },
            dateMs = first.timestampMillis,
        )
    }
}
