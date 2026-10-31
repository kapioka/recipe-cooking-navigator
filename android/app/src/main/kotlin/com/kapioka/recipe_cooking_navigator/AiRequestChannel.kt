package com.kapioka.recipe_cooking_navigator

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Standard Android sharesheet and public website only; no private deep links. */
class AiRequestChannel(activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "recipe/ai-request").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "share" -> {
                        val text = call.arguments as? String
                        require(!text.isNullOrBlank() && text.toByteArray(Charsets.UTF_8).size <= 1024 * 1024)
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        activity.startActivity(Intent.createChooser(send, "共有先を選択"))
                        result.success(null)
                    }
                    "openAppUpdates" -> {
                        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/kapioka/recipe-cooking-navigator/releases/latest")))
                        result.success(null)
                    }
                    "openChatGpt" -> {
                        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://chatgpt.com/")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("unavailable", "共有またはChatGPTを開けません。コピーした依頼文を貼り付けてください。", null)
            }
        }
    }
}
