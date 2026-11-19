package com.vagabundo.teknik_defter

import android.content.Intent
import android.net.Uri
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
