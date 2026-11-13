package com.vitra.vitra_radio

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pendingFolder: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.vitra.radio/device-music").setMethodCallHandler { call, result ->
            when (call.method) {
                "chooseFolder" -> {
                    if (pendingFolder != null) { result.error("busy", "A folder chooser is already open", null) }
                    else {
                        pendingFolder = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION), 4701)
                        } catch (e: Exception) { pendingFolder = null; result.error("folder", "No folder picker available", null) }
                    }
                }
                "scanFolder" -> {
                    val uri = call.argument<String>("uri")
                    worker.execute {
                        try {
                            require(uri != null && Uri.parse(uri).scheme == "content")
                            val tracks = scan(Uri.parse(uri))
                            runOnUiThread { result.success(tracks) }
                        } catch (e: Exception) { runOnUiThread { result.error("folder", "Folder unavailable; select it again", null) } }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    @Deprecated("Used for compatibility with Android 7 and above")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4701) return
        val result = pendingFolder ?: return
        pendingFolder = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            var name = "Music"
            contentResolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor -> if (cursor.moveToFirst()) name = cursor.getString(0) }
            result.success(mapOf("uri" to uri.toString(), "name" to name))
        } catch (e: Exception) { result.error("folder", "Could not keep access to this folder", null) }
    }
    private fun scan(tree: Uri): List<Map<String, String>> {
        val found = ArrayList<Map<String, String>>()
        val queue = java.util.ArrayDeque<String>()
        val seen = HashSet<String>()
        queue.add(DocumentsContract.getTreeDocumentId(tree))
        var inspected = 0
        while (queue.isNotEmpty() && found.size < 5000 && inspected < 20000) {
            val parent = queue.removeFirst()
            if (!seen.add(parent)) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
            contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
                while (cursor.moveToNext() && found.size < 5000 && inspected++ < 20000) {
                    val id = cursor.getString(0); val name = cursor.getString(1) ?: "Music"; val mime = cursor.getString(2) ?: ""
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) queue.add(id)
                    else if (mime.startsWith("audio/") || name.substringAfterLast('.').lowercase() in listOf("mp3", "m4a", "aac", "ogg", "opus", "flac", "wav", "aiff", "wma")) {
                        found.add(mapOf("uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(), "title" to name.substringBeforeLast('.')))
                    }
                }
            }
        }
        return found.sortedBy { it["title"]?.lowercase() }
    }
}
