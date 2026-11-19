package com.vagabundo.teknik_defter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/** Ana ekran widget'ı: Yeni not · Arama notu · Son sayfa */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private fun link(context: Context, uri: String, code: Int): PendingIntent {
            val i = Intent(Intent.ACTION_VIEW, Uri.parse(uri), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        fun views(context: Context): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.widget_quick)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val lastId = prefs.getString("flutter.lastPageId", null)
            val lastTitle = prefs.getString("flutter.lastPageTitle", null)
            v.setOnClickPendingIntent(R.id.w_new, link(context, "teknikdefter://new", 1))
            v.setOnClickPendingIntent(R.id.w_call, link(context, "teknikdefter://call", 2))
            v.setOnClickPendingIntent(R.id.w_logo, link(context, "teknikdefter://home", 4))
            if (lastId != null) {
                v.setTextViewText(R.id.w_last, lastTitle ?: "Son sayfa")
                v.setOnClickPendingIntent(R.id.w_last, link(context, "teknikdefter://page/$lastId", 3))
            }
            return v
        }

        fun refresh(context: Context) {
            val m = AppWidgetManager.getInstance(context)
            val ids = m.getAppWidgetIds(ComponentName(context, QuickWidget::class.java))
            for (id in ids) m.updateAppWidget(id, views(context))
        }
    }
}
