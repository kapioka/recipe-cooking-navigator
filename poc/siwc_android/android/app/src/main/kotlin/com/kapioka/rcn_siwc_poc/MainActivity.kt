package com.kapioka.rcn_siwc_poc

import io.flutter.embedding.android.FlutterActivity

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.speech.RecognizerIntent
import android.util.AtomicFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var pendingSpeech: MethodChannel.Result? = null
    private var pendingForeground: MethodChannel.Result? = null
    private var resumed = false
    private val credentialFile by lazy { AtomicFile(File(filesDir, "siwc.encrypted")) }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias("siwc-poc")) return store.getKey("siwc-poc", null) as SecretKey
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("siwc-poc", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "siwc/poc").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "readSecure" -> {
                        if (!credentialFile.baseFile.exists() && !File(credentialFile.baseFile.path + ".bak").exists()) result.success(null)
                        else {
                            val raw = credentialFile.readFully()
                            require(raw.size >= 29 && raw[0].toInt() == 1)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw.copyOfRange(1, 13)))
                            result.success(cipher.doFinal(raw.copyOfRange(13, raw.size)).toString(Charsets.UTF_8))
                        }
                    }
                    "writeSecure" -> {
                        val source = call.arguments as String
                        require(source.toByteArray(Charsets.UTF_8).size <= 1024 * 1024)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, key())
                        require(cipher.iv.size == 12)
                        val encrypted = byteArrayOf(1) + cipher.iv + cipher.doFinal(source.toByteArray(Charsets.UTF_8))
                        val output = credentialFile.startWrite()
                        try { output.write(encrypted); credentialFile.finishWrite(output) }
                        catch (error: Exception) { credentialFile.failWrite(output); throw error }
                        result.success(null)
                    }
                    "openBrowser" -> {
                        val uri = Uri.parse(call.arguments as String)
                        require(uri.scheme == "https" && uri.userInfo == null &&
                            ((uri.host == "auth.openai.com" && uri.path == "/api/accounts/authorize") ||
                             (uri.host == "chatgpt.com" && uri.path == "/settings/usage")))
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    }
                    "waitForForeground" -> {
                        check(pendingForeground == null)
                        if (resumed) result.success(null)
                        else pendingForeground = result
                    }
                    "dictate" -> {
                        check(pendingSpeech == null)
                        pendingSpeech = result
                        try {
                            startActivityForResult(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ja-JP")
                                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                                putExtra(RecognizerIntent.EXTRA_PROMPT, "文字入力後に修正・確定します。今は送信しません。")
                            }, 81)
                        } catch (_: Exception) {
                            pendingSpeech = null
                            result.error("speech_unavailable", "音声入力を利用できません。キーボードで入力してください。", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("poc_failed", "安全保管または端末操作に失敗しました。", null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 81) {
            val result = pendingSpeech
            pendingSpeech = null
            val text = if (resultCode == Activity.RESULT_OK)
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null
            result?.success(text)
        }
    }
    override fun onResume() {
        super.onResume()
        resumed = true
        val result = pendingForeground
        pendingForeground = null
        result?.success(null)
    }
    override fun onPause() {
        resumed = false
        super.onPause()
    }
    override fun onDestroy() {
        pendingForeground?.error("activity_destroyed", "アプリへの復帰待ちを終了しました。再接続してください。", null)
        pendingForeground = null
        pendingSpeech?.success(null)
        pendingSpeech = null
        super.onDestroy()
    }
}
