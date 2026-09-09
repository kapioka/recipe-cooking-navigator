package com.kapioka.recipe_cooking_navigator

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.concurrent.Executors

class RecipeInboxChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingSelection: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(::handleCall)
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selectFolder" -> selectFolder(result)
            "scan" -> scan(call.argument<String>("treeUri"), result)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun selectFolder(result: MethodChannel.Result) {
        if (pendingSelection != null) {
            result.error("busy", "A folder selection is already running.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        pendingSelection = result
        try {
            activity.startActivityForResult(intent, SELECT_FOLDER_REQUEST)
        } catch (error: Exception) {
            pendingSelection = null
            result.error("selection_failed", "Could not open the folder picker.", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SELECT_FOLDER_REQUEST) {
            return false
        }
        val result = pendingSelection ?: return true
        pendingSelection = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val treeUri = requireNotNull(data.data)
        try {
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            result.success(
                mapOf(
                    "treeUri" to treeUri.toString(),
                    "displayName" to readFolderName(treeUri),
                ),
            )
        } catch (error: Exception) {
            result.error("selection_failed", "Could not retain access to the folder.", null)
        }
        return true
    }

    private fun scan(treeUriValue: String?, result: MethodChannel.Result) {
        if (treeUriValue.isNullOrBlank()) {
            result.error("not_configured", "No Inbox folder is configured.", null)
            return
        }
        executor.execute {
            try {
                val files = readInboxFiles(Uri.parse(treeUriValue))
                activity.runOnUiThread { result.success(files) }
            } catch (error: SecurityException) {
                activity.runOnUiThread {
                    result.error("permission_lost", "Inbox permission is unavailable.", null)
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("folder_unavailable", "Inbox folder is unavailable.", null)
                }
            }
        }
    }

    private fun readFolderName(treeUri: Uri): String {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        activity.contentResolver.query(
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val name = cursor.getString(0)
                if (!name.isNullOrBlank()) {
                    return name
                }
            }
        }
        return treeUri.lastPathSegment ?: "Inbox"
    }

    private fun readInboxFiles(treeUri: Uri): List<Map<String, Any?>> {
        val hasReadPermission = activity.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
        if (!hasReadPermission) {
            throw SecurityException("Persisted read permission is unavailable.")
        }

        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val files = mutableListOf<Map<String, Any?>>()
        val cursor = activity.contentResolver.query(
            childrenUri,
            projection,
            null,
            null,
            null,
        ) ?: throw IllegalStateException("The folder provider returned no cursor.")

        cursor.use {
            val idColumn = it.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = it.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeColumn = it.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            while (it.moveToNext()) {
                val documentId = it.getString(idColumn) ?: continue
                val name = it.getString(nameColumn) ?: documentId
                val mimeType = it.getString(mimeColumn)
                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR ||
                    !name.endsWith(".json", ignoreCase = true)
                ) {
                    continue
                }

                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    documentId,
                )
                try {
                    val bytes = activity.contentResolver.openInputStream(documentUri)?.use {
                        input -> input.readBytes()
                    } ?: throw IllegalStateException("The file stream is unavailable.")
                    val source = Charsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(ByteBuffer.wrap(bytes))
                        .toString()
                    files.add(
                        mapOf(
                            "documentId" to documentId,
                            "name" to name,
                            "source" to source,
                            "sha256" to sha256(bytes),
                        ),
                    )
                } catch (error: Exception) {
                    files.add(
                        mapOf(
                            "documentId" to documentId,
                            "name" to name,
                            "readError" to "ファイルを読み込めませんでした。",
                        ),
                    )
                }
            }
        }
        return files
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest
        .getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingSelection = null
        executor.shutdownNow()
    }

    companion object {
        private const val CHANNEL_NAME = "recipe/inbox"
        private const val SELECT_FOLDER_REQUEST = 52
    }
}
