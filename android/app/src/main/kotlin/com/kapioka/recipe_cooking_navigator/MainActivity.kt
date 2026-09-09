package com.kapioka.recipe_cooking_navigator

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.WindowManager
import java.util.Locale

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var inboxChannel: RecipeInboxChannel? = null
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var voiceWanted = false
    private var speaking = false
    private var cooking = false
    private var cancellingRecognition = false
    private var recognitionActive = false
    private var suppressTtsError = false
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recipe/cooking")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "wake" -> {
                    cooking = true
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "voice" -> {
                    voiceWanted = call.arguments == true
                    if (!voiceWanted) {
                        cancelRecognition()
                        event("voiceState", "音声OFF")
                    } else if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 41)
                    } else listen()
                    result.success(null)
                }
                "speak" -> {
                    if (!ttsReady) { result.error("tts", "日本語読み上げを準備できません。", null) }
                    else {
                        speaking = true
                        event("speakingState", true)
                        cancelRecognition()
                        if (voiceWanted) {
                            event("voiceState", "読み上げ中（音声停止を受付）")
                            handler.postDelayed({ listen() }, 400)
                        } else {
                            event("voiceState", "読み上げ中（音声操作OFF）")
                        }
                        val status = tts!!.speak(call.arguments as String, TextToSpeech.QUEUE_FLUSH, null, "step")
                        if (status == TextToSpeech.ERROR) {
                            speaking = false
                            event("speakingState", false)
                            result.error("tts", "読み上げを開始できません。", null)
                        } else result.success(null)
                    }
                }
                "stopSpeaking" -> {
                    stopSpeakingIntentionally()
                    if (voiceWanted) {
                        cancelRecognition()
                        event("voiceState", "音声再開中")
                        handler.postDelayed({ listen() }, 350)
                    } else event("voiceState", "音声OFF")
                    result.success(null)
                }
                "close" -> { closeCooking(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        inboxChannel = RecipeInboxChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val language = tts?.setLanguage(Locale.JAPAN)
                ttsReady = language != TextToSpeech.LANG_MISSING_DATA && language != TextToSpeech.LANG_NOT_SUPPORTED
            }
        }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) { runOnUiThread {
                event("speakingState", true)
            } }
            override fun onDone(id: String?) { runOnUiThread {
                speaking = false
                event("speakingState", false)
                suppressTtsError = false
                if (voiceWanted && cooking) {
                    cancelRecognition()
                    event("voiceState", "音声再開中")
                    handler.postDelayed({ listen() }, 350)
                } else event("voiceState", "音声OFF")
            } }
            @Deprecated("Deprecated in Java")
            override fun onError(id: String?) { runOnUiThread {
                speaking = false
                event("speakingState", false)
                if (suppressTtsError) {
                    suppressTtsError = false
                } else {
                    voiceWanted = false
                    event("voiceError", "読み上げに失敗しました。")
                }
            } }
        })
    }

    private fun event(method: String, value: Any) { channel.invokeMethod(method, value) }

    private fun listen() {
        if (!voiceWanted || !cooking || recognitionActive) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            voiceWanted = false; event("voiceError", "端末の音声認識を利用できません。"); return
        }
        if (recognizer == null) {
            recognizer = if (android.os.Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this))
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this) else SpeechRecognizer.createSpeechRecognizer(this)
            recognizer!!.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    recognitionActive = true
                    event(
                        "voiceState",
                        if (speaking) "読み上げ中（音声停止を受付）" else "音声受付中",
                    )
                }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    recognitionActive = false
                    event("voiceState", if (speaking) "音声停止を確認中" else "音声確認中")
                }
                override fun onError(error: Int) {
                    recognitionActive = false
                    if (cancellingRecognition) return
                    if (!voiceWanted || !cooking) return
                    if (speaking) {
                        event("voiceState", "読み上げ中（音声停止を受付）")
                        handler.postDelayed({ listen() }, 350)
                        return
                    }
                    voiceWanted = false
                    event("voiceError", "音声受付を停止しました。もう一度ONにしてください。（$error）")
                }
                override fun onResults(results: Bundle?) {
                    recognitionActive = false
                    if (!voiceWanted || !cooking) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    if (speaking) {
                        if (text != null && isSpeakingStopCommand(text)) {
                            event("recognized", text)
                        } else {
                            handler.postDelayed({ listen() }, 250)
                        }
                        return
                    }
                    if (text != null) event("recognized", text)
                    handler.postDelayed({ listen() }, 500)
                }
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ja-JP")
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        try {
            recognitionActive = true
            recognizer!!.startListening(intent)
        }
        catch (e: Exception) {
            recognitionActive = false
            if (speaking && voiceWanted && cooking) {
                handler.postDelayed({ listen() }, 500)
            } else {
                voiceWanted = false
                event("voiceError", "音声認識を開始できません。")
            }
        }
    }

    private fun isSpeakingStopCommand(text: String): Boolean {
        val command = text.replace(Regex("[\\s。、！!？?]"), "")
        return command == "音声停止" || command == "読み上げ停止"
    }

    private fun cancelRecognition() {
        cancellingRecognition = true
        recognitionActive = false
        recognizer?.cancel()
        handler.postDelayed({ cancellingRecognition = false }, 300)
    }

    private fun stopSpeakingIntentionally() {
        suppressTtsError = true
        tts?.stop()
        speaking = false
        event("speakingState", false)
        handler.postDelayed({ suppressTtsError = false }, 300)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 41) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) listen()
            else { voiceWanted = false; event("voiceError", "マイクの許可が必要です。") }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        inboxChannel?.onActivityResult(requestCode, resultCode, data)
    }
    private fun closeCooking() {
        cooking = false; voiceWanted = false; speaking = false
        cancelRecognition(); stopSpeakingIntentionally()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    override fun onStop() {
        voiceWanted = false; cancelRecognition(); stopSpeakingIntentionally()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        event("voiceState", "音声OFF")
        super.onStop()
    }
    override fun onStart() {
        super.onStart()
        if (cooking) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    override fun onDestroy() {
        inboxChannel?.dispose()
        closeCooking(); recognizer?.destroy(); tts?.shutdown(); super.onDestroy()
    }
}
