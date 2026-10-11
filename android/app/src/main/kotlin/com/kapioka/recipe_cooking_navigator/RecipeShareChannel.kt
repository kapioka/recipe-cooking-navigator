package com.kapioka.recipe_cooking_navigator

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.ArrayDeque
import java.util.concurrent.Executors

class RecipeShareChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "recipe/share")
    private val pending = ArrayDeque<Intent>()
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var reading = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "takeNext") {
                result.notImplemented()
            } else if (reading) {
                result.error("busy", "A shared recipe is being read.", null)
            } else {
                val next = if (pending.isEmpty()) null else pending.removeFirst()
                if (next == null) {
                    result.success(null)
                } else {
                    reading = true
                    executor.execute {
                        try {
                            val source = readSource(next)
                            mainHandler.post {
                                reading = false
                                result.success(source)
                            }
                        } catch (error: Exception) {
                            mainHandler.post {
                                reading = false
                                result.error("read_failed", "Could not read the shared recipe.", null)
                            }
                        }
                    }
                }
            }
        }
    }

    fun accept(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND && intent?.action != Intent.ACTION_VIEW) return
        pending.addLast(intent)
        channel.invokeMethod("incoming", null)
    }

    @Suppress("DEPRECATION")
    private fun readSource(intent: Intent): String {
        if (intent.type !in setOf("application/json", "text/json", "text/plain", "application/octet-stream")) {
            throw IllegalArgumentException("Unsupported shared type")
        }
        val stream = if (intent.action == Intent.ACTION_VIEW) {
            intent.data ?: throw IllegalArgumentException("No opened document")
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        if (stream != null) {
            if (stream.scheme != "content") throw IllegalArgumentException("Not a content URI")
            val input = activity.contentResolver.openInputStream(stream)
                ?: throw IllegalArgumentException("No shared stream")
            val bytes = input.use {
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > MAX_BYTES) throw IllegalArgumentException("Shared file too large")
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            return Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString()
        }
        if (intent.action != Intent.ACTION_SEND) throw IllegalArgumentException("No opened document")
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: throw IllegalArgumentException("No shared content")
        if (text.toByteArray(Charsets.UTF_8).size > MAX_BYTES) {
            throw IllegalArgumentException("Shared text too large")
        }
        return text
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending.clear()
        executor.shutdownNow()
    }

    companion object {
        private const val MAX_BYTES = 1_000_000
    }
}
