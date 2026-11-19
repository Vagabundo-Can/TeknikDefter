package com.vagabundo.teknik_defter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Dışarıdan gelen PDF/görselleri ("Birlikte aç", "Paylaş") önbelleğe kopyalayıp Dart'a yol olarak verir. */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: List<String> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "teknik_defter/intent")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialFiles" -> {
                    result.success(pending)
                    pending = emptyList()
                }
                "addCalendarEvent" -> {
                    val i = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.Events.TITLE, call.argument<String>("title"))
                        .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
                        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, call.argument<Number>("begin")!!.toLong())
                        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, call.argument<Number>("end")!!.toLong())
                    try {
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("calendar", e.message, null)
                    }
                }
                "setCallNotes" -> {
                    val on = call.argument<Boolean>("enabled") == true
                    getSharedPreferences("teknik_defter", Context.MODE_PRIVATE).edit().putBoolean("call_notes", on).apply()
                    if (on) {
                        val perms = mutableListOf(Manifest.permission.READ_PHONE_STATE)
                        if (Build.VERSION.SDK_INT >= 33) perms.add(Manifest.permission.POST_NOTIFICATIONS)
                        val missing = perms.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 42)
                    }
                    result.success(true)
                }
                "getCallNotes" -> result.success(getSharedPreferences("teknik_defter", Context.MODE_PRIVATE).getBoolean("call_notes", false))
                "refreshWidget" -> {
                    QuickWidget.refresh(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        pending = filesFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val files = filesFrom(intent)
        if (files.isNotEmpty()) channel?.invokeMethod("filesReceived", files)
    }

    private fun filesFrom(intent: Intent?): List<String> {
        if (intent == null) return emptyList()
        // uygulama içi bağlantılar ve kısayollar
        intent.data?.let { d ->
            if (d.scheme == "teknikdefter") {
                return when (d.host) {
                    "page" -> listOf("page:" + (d.lastPathSegment ?: ""))
                    "new" -> listOf("action:new")
                    "call" -> listOf("action:call")
                    else -> emptyList()
                }
            }
        }
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            Intent.ACTION_SEND -> {
                val u: Uri? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
                u?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                list?.let { uris.addAll(it) }
            }
        }
        val out = mutableListOf<String>()
        for (uri in uris) {
            try {
                val name = displayName(uri) ?: "dosya_${System.currentTimeMillis()}"
                val dir = File(cacheDir, "gelen").apply { mkdirs() }
                val f = File(dir, name)
                contentResolver.openInputStream(uri)?.use { input -> f.outputStream().use { input.copyTo(it) } }
                out.add(f.absolutePath)
            } catch (e: Exception) {
                android.util.Log.e("TeknikDefter", "Dosya alınamadı: $uri", e)
            }
        }
        return out
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (i >= 0) return c.getString(i)
            }
        }
        val type = contentResolver.getType(uri) ?: ""
        val ext = when {
            type.contains("pdf") -> ".pdf"
            type.contains("png") -> ".png"
            else -> ".jpg"
        }
        return "dosya_${System.currentTimeMillis()}$ext"
    }
}
