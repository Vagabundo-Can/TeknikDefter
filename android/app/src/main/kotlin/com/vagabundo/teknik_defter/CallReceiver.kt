package com.vagabundo.teknik_defter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telephony.TelephonyManager

/** Görüşme bitince "Arama notu al" bildirimi (Ayarlar'dan açılırsa). */
class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("teknik_defter", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("call_notes", false)) return
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        when (state) {
            TelephonyManager.EXTRA_STATE_OFFHOOK -> prefs.edit().putBoolean("in_call", true).apply()
            TelephonyManager.EXTRA_STATE_IDLE -> if (prefs.getBoolean("in_call", false)) {
                prefs.edit().putBoolean("in_call", false).apply()
                notify(context)
            }
        }
    }

    private fun notify(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel("call_notes", "Arama notları", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = Intent(Intent.ACTION_VIEW, Uri.parse("teknikdefter://call"), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(context, 7, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(context, "call_notes") else @Suppress("DEPRECATION") android.app.Notification.Builder(context)
        b.setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("Görüşme bitti")
            .setContentText("Dokun: arama notu al")
            .setAutoCancel(true)
            .setContentIntent(pi)
        try {
            nm.notify(1001, b.build())
        } catch (_: SecurityException) {
        }
    }
}
