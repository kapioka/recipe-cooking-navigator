package com.kapioka.recipe_cooking_navigator

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Add-only archive, separate from the read-only Recipe Inbox permission. */
class FeedbackArchiveChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "recipe/feedback_archive")
    private val preferences = activity.getSharedPreferences("feedback_archive", 0)
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var selection: MethodChannel.Result? = null
    @Volatile private var closed = false
    private val accessFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "selectRoot" -> {
                    if (selection != null) result.error("busy", "Folder selection is already active.", null)
                    else {
                        selection = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(accessFlags or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                            }, 53)
                        } catch (error: Exception) {
                            selection = null
                            result.error("selection_failed", "Could not select the archive folder.", null)
                        }
                    }
                }
                "loadRoot" -> result.success(preferences.getString("root", null))
                "readEvidence" -> work(result) {
                    val rootValue = call.argument<String>("root") ?: error("Missing root")
                    if (rootValue != preferences.getString("root", null)) error("Archive connection has changed.")
                    val root = Uri.parse(rootValue)
                    validateRoot(root)
                    val directory = child(root, document(root), "Feedback")
                    val resultItems = ArrayList<Map<String, String>>()
                    if (directory != null) {
                        require(directory.mime == DocumentsContract.Document.MIME_TYPE_DIR)
                        val years = children(root, directory.uri).filter {
                            it.name.matches(Regex("[0-9]{4}"))
                        }.sortedBy { it.name }
                        require(years.map { it.name }.distinct().size == years.size) { "Duplicate archive years." }
                        require(years.size <= 20) { "Archive contains too many years." }
                        var bytes = 0
                        for (year in years) {
                            require(year.mime == DocumentsContract.Document.MIME_TYPE_DIR)
                            for (file in children(root, year.uri).filter { it.name.endsWith(".json", true) }.sortedBy { it.name }) {
                                require(resultItems.size < 100) { "Archive contains more than 100 Feedback files." }
                                val name = "${year.name}/${file.name}"
                                val source = try {
                                    require(file.mime != DocumentsContract.Document.MIME_TYPE_DIR)
                                    read(file.uri)
                                } catch (error: SecurityException) { throw error }
                                catch (error: Exception) { null }
                                if (source == null) resultItems.add(mapOf("name" to name, "error" to "評価ファイルを読み込めませんでした。"))
                                else {
                                    bytes += source.toByteArray(Charsets.UTF_8).size
                                    require(bytes <= 5 * MAX_BYTES) { "Feedback archive exceeds the total read limit." }
                                    resultItems.add(mapOf("name" to name, "source" to source))
                                }
                            }
                        }
                    }
                    resultItems
                }
                "readProfile" -> work(result) {
                    val rootValue = call.argument<String>("root") ?: error("Missing root")
                    if (rootValue != preferences.getString("root", null)) error("Archive connection has changed.")
                    val root = Uri.parse(rootValue)
                    validateRoot(root)
                    val directory = child(root, document(root), "Profile")
                    if (directory == null) null
                    else {
                        require(directory.mime == DocumentsContract.Document.MIME_TYPE_DIR)
                        val profile = child(root, directory.uri, "cooking-profile.json")
                        if (profile == null) null
                        else {
                            require(profile.mime != DocumentsContract.Document.MIME_TYPE_DIR)
                            read(profile.uri)
                        }
                    }
                }
                "readHistory" -> work(result) {
                    val rootValue = call.argument<String>("root") ?: error("Missing root")
                    if (rootValue != preferences.getString("root", null)) error("Archive connection has changed.")
                    val root = Uri.parse(rootValue)
                    validateRoot(root)
                    val profile = child(root, document(root), "Profile")
                    val resultItems = ArrayList<Map<String, String>>()
                    if (profile != null) {
                        require(profile.mime == DocumentsContract.Document.MIME_TYPE_DIR)
                        val history = child(root, profile.uri, "History")
                        if (history != null) {
                            require(history.mime == DocumentsContract.Document.MIME_TYPE_DIR)
                            val profiles = children(root, history.uri).sortedBy { it.name }
                            require(profiles.size <= 20 && profiles.map { it.name }.distinct().size == profiles.size) {
                                "Profile history directory is ambiguous or too large."
                            }
                            var bytes = 0
                            for (directory in profiles) {
                                require(directory.mime == DocumentsContract.Document.MIME_TYPE_DIR)
                                val files = children(root, directory.uri).filter { it.name.endsWith(".json", true) }.sortedBy { it.name }
                                require(files.map { it.name }.distinct().size == files.size) { "Duplicate Profile history names." }
                                for (file in files) {
                                    require(resultItems.size < 100 && file.mime != DocumentsContract.Document.MIME_TYPE_DIR)
                                    val source = read(file.uri) // One unreadable record invalidates the observed graph.
                                    bytes += source.toByteArray(Charsets.UTF_8).size
                                    require(bytes <= 5 * MAX_BYTES) { "Profile history exceeds read limit." }
                                    resultItems.add(mapOf("name" to "${directory.name}/${file.name}", "source" to source))
                                }
                            }
                        }
                    }
                    resultItems
                }
                "append" -> work(result) {
                    val rootValue = call.argument<String>("root") ?: error("Missing root")
                    if (rootValue != preferences.getString("root", null)) error("Archive connection has changed.")
                    val root = Uri.parse(rootValue)
                    validateRoot(root)
                    val source = call.argument<String>("source") ?: error("Missing source")
                    val id = call.argument<String>("feedbackId") ?: error("Missing identifier")
                    val year = call.argument<String>("year") ?: error("Missing year")
                    require(year.matches(Regex("[0-9]{4}")))
                    require(source.toByteArray(Charsets.UTF_8).size <= MAX_BYTES)
                    val json = JSONObject(source)
                    require(json.getString("type") == "feedback_evidence" && json.getString("evidence_schema_version") == "1.0.0")
                    require(json.getString("feedback_id") == id && id.isNotBlank())
                    require(json.getJSONObject("feedback").getString("type") == "recipe_feedback")
                    val feedback = folder(root, document(root), "Feedback")
                    val annual = folder(root, feedback, year)
                    val digest = MessageDigest.getInstance("SHA-256").digest(id.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
                    val name = "feedback-$digest.json"
                    val existing = child(root, annual, name)
                    if (existing != null) {
                        if (existing.mime == DocumentsContract.Document.MIME_TYPE_DIR || read(existing.uri) != source) error("Existing Feedback has different content. It was not overwritten.")
                        "already_exists"
                    } else {
                        val created = DocumentsContract.createDocument(activity.contentResolver, annual, "application/json", name)
                            ?: error("Provider did not create the Feedback file.")
                        activity.contentResolver.query(created, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                            require(it.moveToFirst() && it.getString(0) == name) { "Provider changed the Feedback filename." }
                        } ?: error("Could not verify created Feedback metadata.")
                        activity.contentResolver.openOutputStream(created, "w")?.use { it.write(source.toByteArray(Charsets.UTF_8)); it.flush() }
                            ?: error("Provider did not open the Feedback file.")
                        // A provider write completion is not cloud synchronization evidence.
                        if (read(created) != source) error("Feedback verification failed. The incomplete file was retained.")
                        "created"
                    }
                }
                "appendHistory" -> work(result) {
                    val rootValue = call.argument<String>("root") ?: error("Missing root")
                    require(rootValue == preferences.getString("root", null)) { "Archive connection has changed." }
                    val root = Uri.parse(rootValue)
                    validateRoot(root)
                    val source = call.argument<String>("source") ?: error("Missing source")
                    val profileId = call.argument<String>("profileId") ?: error("Missing profile ID")
                    val recordId = call.argument<String>("recordId") ?: error("Missing record ID")
                    require(profileId.isNotBlank() && recordId.isNotBlank() && source.toByteArray(Charsets.UTF_8).size <= MAX_BYTES)
                    val json = JSONObject(source)
                    require(json.getString("type") == "profile_history" && json.getString("history_schema_version") == "1.0.0")
                    require(json.getString("record_id") == recordId && json.getJSONObject("result_profile").getString("profile_id") == profileId)
                    val profile = folder(root, document(root), "Profile")
                    val history = folder(root, profile, "History")
                    val directory = folder(root, history, "profile-${digest(profileId)}")
                    appendFile(root, directory, "record-${digest(recordId)}.json", source)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 53) return false
        val result = selection ?: return true
        selection = null
        val root = data?.data
        if (resultCode != Activity.RESULT_OK || root == null) { result.success(null); return true }
        work(result) {
            validateRoot(root)
            require(((data?.flags ?: 0) and accessFlags) == accessFlags) { "Read and write access are required." }
            activity.contentResolver.takePersistableUriPermission(root, accessFlags)
            if (!preferences.edit().putString("root", root.toString()).commit()) error("Could not save archive connection.")
            root.toString()
        }
        return true
    }

    private fun validateRoot(root: Uri) {
        require(DocumentsContract.isTreeUri(root)) { "Select a document tree." }
        val provider = root.authority?.let { activity.packageManager.resolveContentProvider(it, 0)?.packageName }
        require(provider == "com.google.android.apps.docs") { "Select the folder in Google Drive." }
        activity.contentResolver.query(document(root), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            require(it.moveToFirst() && it.getString(0) == "Recipe Cooking Navigator") { "Select Recipe Cooking Navigator, not Inbox." }
        } ?: error("Archive folder is unavailable.")
    }

    private fun document(root: Uri) = DocumentsContract.buildDocumentUriUsingTree(root, DocumentsContract.getTreeDocumentId(root))
    private data class Child(val uri: Uri, val mime: String, val name: String)
    private fun child(root: Uri, parent: Uri, name: String): Child? {
        val matches = children(root, parent).filter { it.name == name }
        require(matches.size <= 1) { "Multiple documents share the archive name." }
        return matches.singleOrNull()
    }
    private fun children(root: Uri, parent: Uri): List<Child> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(root, DocumentsContract.getDocumentId(parent))
        val found = ArrayList<Child>()
        activity.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use {
            var count = 0
            while (it.moveToNext()) {
                require(++count <= 2000) { "Archive directory is too large." }
                found.add(Child(DocumentsContract.buildDocumentUriUsingTree(root, it.getString(0)), it.getString(2), it.getString(1)))
            }
        } ?: error("Could not list archive folder.")
        return found
    }
    private fun folder(root: Uri, parent: Uri, name: String): Uri {
        val existing = child(root, parent, name)
        if (existing != null) {
            require(existing.mime == DocumentsContract.Document.MIME_TYPE_DIR) { "Expected an archive directory." }
            return existing.uri
        }
        val created = DocumentsContract.createDocument(activity.contentResolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, name)
            ?: error("Could not create archive directory.")
        val verified = child(root, parent, name)
        require(verified != null && verified.mime == DocumentsContract.Document.MIME_TYPE_DIR &&
            DocumentsContract.getDocumentId(verified.uri) == DocumentsContract.getDocumentId(created)) {
            "Provider changed the archive directory name or created a conflicting directory."
        }
        return created
    }
    private fun read(uri: Uri): String {
        return activity.contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val size = input.read(buffer)
                if (size < 0) break
                require(output.size() + size <= MAX_BYTES) { "Archive file exceeds limit." }
                output.write(buffer, 0, size)
            }
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(output.toByteArray())).toString()
        } ?: error("Could not read archived Feedback.")
    }
    private fun digest(value: String) = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    private fun appendFile(root: Uri, parent: Uri, name: String, source: String): String {
        val existing = child(root, parent, name)
        if (existing != null) {
            require(existing.mime != DocumentsContract.Document.MIME_TYPE_DIR && read(existing.uri) == source) {
                "Existing Profile history differs. It was not overwritten."
            }
            return "already_exists"
        }
        val created = DocumentsContract.createDocument(activity.contentResolver, parent, "application/json", name)
            ?: error("Could not create Profile history.")
        val verified = child(root, parent, name)
        require(verified != null && verified.mime != DocumentsContract.Document.MIME_TYPE_DIR &&
            DocumentsContract.getDocumentId(verified.uri) == DocumentsContract.getDocumentId(created)) {
            "Provider changed the Profile history name or created a conflict."
        }
        activity.contentResolver.openOutputStream(created, "w")?.use {
            it.write(source.toByteArray(Charsets.UTF_8)); it.flush()
        } ?: error("Could not write Profile history.")
        require(read(created) == source) { "Profile history verification failed. The incomplete record was retained." }
        return "created"
    }
    private fun work(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                main.post { if (!closed) result.success(value) }
            } catch (error: Exception) {
                val code = if (error is SecurityException) "permission_lost" else "archive_failed"
                main.post { if (!closed) result.error(code, "Archive operation failed; existing files were not overwritten.", null) }
            }
        }
    }
    fun dispose() {
        closed = true
        channel.setMethodCallHandler(null)
        selection?.error("cancelled", "Activity closed.", null)
        selection = null
        executor.shutdownNow()
    }
    companion object { private const val MAX_BYTES = 1024 * 1024 }
}
