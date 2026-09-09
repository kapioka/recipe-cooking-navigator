package com.kapioka.recipe_cooking_navigator

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.OperationCanceledException
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class RecipeInboxChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val timeoutExecutor = Executors.newSingleThreadScheduledExecutor()
    private var pendingSelection: MethodChannel.Result? = null
    private var pendingScan: MethodChannel.Result? = null
    @Volatile private var activeScan: Future<*>? = null
    @Volatile private var activeScanTimeout: ScheduledFuture<*>? = null
    @Volatile private var activeCancellationSignal: CancellationSignal? = null
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler(::handleCall)
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("cancelled", "Inbox operation was cancelled.", null)
            return
        }
        when (call.method) {
            "selectFolder" -> selectFolder(result)
            "scan" -> scan(call.argument<String>("treeUri"), result)
            "releaseFolder" -> releaseFolder(call.argument<String>("treeUri"), result)
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
            validateGoogleDriveTree(treeUri)
            val folderName = readFolderName(treeUri)
            if (folderName != REQUIRED_FOLDER_NAME) {
                result.error(
                    "wrong_folder",
                    "Select the Google Drive Inbox folder.",
                    null,
                )
                return true
            }
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            result.success(
                mapOf(
                    "treeUri" to treeUri.toString(),
                    "displayName" to folderName,
                ),
            )
        } catch (error: InboxAccessException) {
            result.error(error.code, error.message, null)
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
        if (pendingScan != null) {
            result.error("busy", "An Inbox scan is already running.", null)
            return
        }

        val treeUri = Uri.parse(treeUriValue)
        val cancellationSignal = CancellationSignal()
        pendingScan = result
        activeCancellationSignal = cancellationSignal
        val task = executor.submit {
            try {
                val files = readInboxFiles(treeUri, cancellationSignal)
                completeScan(result) { result.success(files) }
            } catch (error: InboxAccessException) {
                completeScan(result) { result.error(error.code, error.message, null) }
            } catch (error: SecurityException) {
                completeScan(result) {
                    result.error("permission_lost", "Inbox permission is unavailable.", null)
                }
            } catch (error: OperationCanceledException) {
                completeScan(result) {
                    result.error("timeout", "Inbox scan was cancelled or timed out.", null)
                }
            } catch (error: Exception) {
                completeScan(result) {
                    result.error("folder_unavailable", "Inbox folder is unavailable.", null)
                }
            }
        }
        activeScan = task
        activeScanTimeout = timeoutExecutor.schedule(
            {
                cancellationSignal.cancel()
                task.cancel(true)
                completeScan(result) {
                    result.error("timeout", "Inbox scan timed out.", null)
                }
            },
            SCAN_TIMEOUT_SECONDS,
            TimeUnit.SECONDS,
        )
    }

    private fun releaseFolder(treeUriValue: String?, result: MethodChannel.Result) {
        if (treeUriValue.isNullOrBlank()) {
            result.error("invalid_request", "No Inbox folder was provided.", null)
            return
        }
        try {
            val treeUri = Uri.parse(treeUriValue)
            val hasReadPermission = activity.contentResolver.persistedUriPermissions.any {
                it.uri == treeUri && it.isReadPermission
            }
            if (hasReadPermission) {
                activity.contentResolver.releasePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("release_failed", "Could not release the previous folder.", null)
        }
    }

    private fun completeScan(
        result: MethodChannel.Result,
        completion: () -> Unit,
    ) {
        mainHandler.post {
            if (disposed || pendingScan !== result) {
                return@post
            }
            pendingScan = null
            activeScanTimeout?.cancel(false)
            activeScanTimeout = null
            activeScan = null
            activeCancellationSignal = null
            completion()
        }
    }

    private fun validateGoogleDriveTree(treeUri: Uri) {
        if (!DocumentsContract.isTreeUri(treeUri)) {
            throw InboxAccessException(
                "unsupported_provider",
                "The selected location is not a document tree.",
            )
        }
        val authority = treeUri.authority
        val providerPackage = authority?.let {
            activity.packageManager.resolveContentProvider(it, 0)?.packageName
        }
        if (providerPackage != GOOGLE_DRIVE_PACKAGE) {
            throw InboxAccessException(
                "unsupported_provider",
                "Select the Inbox folder from Google Drive.",
            )
        }
    }

    private fun readFolderName(
        treeUri: Uri,
        cancellationSignal: CancellationSignal? = null,
    ): String {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        val cursor = if (cancellationSignal == null) {
            activity.contentResolver.query(documentUri, projection, null, null, null)
        } else {
            activity.contentResolver.query(
                documentUri,
                projection,
                null,
                null,
                null,
                cancellationSignal,
            )
        }
        cursor?.use { current ->
            if (current.moveToFirst()) {
                val name = current.getString(0)
                if (!name.isNullOrBlank()) {
                    return name
                }
            }
        }
        return treeUri.lastPathSegment ?: "Inbox"
    }

    private fun readInboxFiles(
        treeUri: Uri,
        cancellationSignal: CancellationSignal,
    ): List<Map<String, Any?>> {
        validateGoogleDriveTree(treeUri)
        val hasReadPermission = activity.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
        if (!hasReadPermission) {
            throw SecurityException("Persisted read permission is unavailable.")
        }
        if (readFolderName(treeUri, cancellationSignal) != REQUIRED_FOLDER_NAME) {
            throw InboxAccessException(
                "wrong_folder",
                "The configured folder is no longer named Inbox.",
            )
        }

        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        val files = mutableListOf<Map<String, Any?>>()
        val cursor = activity.contentResolver.query(
            childrenUri,
            projection,
            null,
            null,
            null,
            cancellationSignal,
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
            val sizeColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            var candidateCount = 0
            var totalBytes = 0L
            while (it.moveToNext()) {
                if (cancellationSignal.isCanceled || Thread.currentThread().isInterrupted) {
                    throw OperationCanceledException()
                }
                val documentId = it.getString(idColumn) ?: continue
                val name = it.getString(nameColumn) ?: documentId
                val mimeType = it.getString(mimeColumn)
                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR ||
                    !name.endsWith(".json", ignoreCase = true)
                ) {
                    continue
                }
                candidateCount += 1
                if (candidateCount > MAX_FILE_COUNT) {
                    files.add(
                        mapOf(
                            "documentId" to "__file_limit__",
                            "name" to "その他のJSONファイル",
                            "readError" to "一度に確認できるJSONファイルは${MAX_FILE_COUNT}件までです。",
                        ),
                    )
                    break
                }

                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    documentId,
                )
                try {
                    val reportedSize = if (sizeColumn >= 0 && !it.isNull(sizeColumn)) {
                        it.getLong(sizeColumn)
                    } else {
                        null
                    }
                    val remainingTotal = MAX_TOTAL_BYTES - totalBytes
                    val bytes = readBoundedBytes(
                        documentUri,
                        reportedSize,
                        remainingTotal,
                        cancellationSignal,
                    )
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
                    totalBytes += bytes.size
                } catch (error: InboxFileReadException) {
                    files.add(
                        mapOf(
                            "documentId" to documentId,
                            "name" to name,
                            "readError" to error.message,
                        ),
                    )
                } catch (error: OperationCanceledException) {
                    throw error
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

    private fun readBoundedBytes(
        documentUri: Uri,
        reportedSize: Long?,
        remainingTotal: Long,
        cancellationSignal: CancellationSignal,
    ): ByteArray {
        if (remainingTotal <= 0L) {
            throw InboxFileReadException("一度に確認できる合計サイズを超えています。")
        }
        val allowedBytes = minOf(MAX_FILE_BYTES, remainingTotal)
        if (reportedSize != null && reportedSize > allowedBytes) {
            throw InboxFileReadException(
                if (reportedSize > MAX_FILE_BYTES) {
                    "JSONファイルが大きすぎます（上限1 MB）。"
                } else {
                    "一度に確認できる合計サイズを超えています。"
                },
            )
        }

        val input = activity.contentResolver.openInputStream(documentUri)
            ?: throw IllegalStateException("The file stream is unavailable.")
        return input.use {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(READ_BUFFER_BYTES)
            while (true) {
                if (cancellationSignal.isCanceled || Thread.currentThread().isInterrupted) {
                    throw OperationCanceledException()
                }
                val count = it.read(buffer)
                if (count < 0) {
                    break
                }
                if (output.size().toLong() + count > allowedBytes) {
                    throw InboxFileReadException(
                        if (allowedBytes == MAX_FILE_BYTES) {
                            "JSONファイルが大きすぎます（上限1 MB）。"
                        } else {
                            "一度に確認できる合計サイズを超えています。"
                        },
                    )
                }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest
        .getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    fun dispose() {
        disposed = true
        pendingSelection?.error("cancelled", "Folder selection was cancelled.", null)
        pendingSelection = null
        pendingScan?.error("cancelled", "Inbox scan was cancelled.", null)
        pendingScan = null
        activeCancellationSignal?.cancel()
        activeCancellationSignal = null
        activeScan?.cancel(true)
        activeScan = null
        activeScanTimeout?.cancel(true)
        activeScanTimeout = null
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        timeoutExecutor.shutdownNow()
    }

    companion object {
        private const val CHANNEL_NAME = "recipe/inbox"
        private const val SELECT_FOLDER_REQUEST = 52
        private const val GOOGLE_DRIVE_PACKAGE = "com.google.android.apps.docs"
        private const val REQUIRED_FOLDER_NAME = "Inbox"
        private const val MAX_FILE_COUNT = 100
        private const val MAX_FILE_BYTES = 1_000_000L
        private const val MAX_TOTAL_BYTES = 5_000_000L
        private const val READ_BUFFER_BYTES = 8_192
        private const val SCAN_TIMEOUT_SECONDS = 30L
    }
}

private class InboxAccessException(
    val code: String,
    message: String,
) : Exception(message)

private class InboxFileReadException(message: String) : Exception(message)
