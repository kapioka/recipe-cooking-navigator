package com.kapioka.recipe_cooking_navigator

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject

class KitchenNotificationPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.NewIntentListener {
    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingTimerId: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        KitchenTimerNotifications.ensureChannel(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addOnNewIntentListener(this)
        acceptNotificationIntent(binding.activity.intent, notifyDart = false)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() = detachFromActivity()

    private fun detachFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        pendingPermissionResult?.error(
            "activity_detached",
            "通知権限の確認中に画面が閉じられました。",
            null,
        )
        pendingPermissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        when (call.method) {
            "status" -> {
                val context = activity?.applicationContext
                    ?: return result.error("activity_missing", "Android画面を確認できません。", null)
                result.success(KitchenTimerNotifications.status(context))
            }

            "sync" -> {
                val context = activity?.applicationContext
                    ?: return result.error("activity_missing", "Android画面を確認できません。", null)
                try {
                    @Suppress("UNCHECKED_CAST")
                    val timers = call.arguments as? List<Map<String, Any?>>
                        ?: throw IllegalArgumentException("Timer list is required.")
                    result.success(KitchenTimerNotifications.sync(context, timers))
                } catch (error: Exception) {
                    result.error("notification_sync", error.message, null)
                }
            }

            "requestNotificationPermission" -> requestNotificationPermission(result)
            "openExactAlarmSettings" -> {
                if (activity == null) {
                    result.error("activity_missing", "Android画面を確認できません。", null)
                } else {
                    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                        data = Uri.parse("package:${activity.packageName}")
                    }
                    activity.startActivity(intent)
                    result.success(null)
                }
            }

            "openNotificationSettings" -> {
                if (activity == null) {
                    result.error("activity_missing", "Android画面を確認できません。", null)
                } else {
                    val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                        putExtra(Settings.EXTRA_CHANNEL_ID, KitchenTimerNotifications.CHANNEL_ID)
                    }
                    activity.startActivity(intent)
                    result.success(null)
                }
            }

            "takeNotificationTimerId" -> {
                val timerId = pendingTimerId
                pendingTimerId = null
                result.success(timerId)
            }

            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
            ?: return result.error("activity_missing", "Android画面を確認できません。", null)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "通知権限を確認中です。", null)
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    override fun onNewIntent(intent: Intent): Boolean =
        acceptNotificationIntent(intent, notifyDart = true)

    private fun acceptNotificationIntent(intent: Intent?, notifyDart: Boolean): Boolean {
        if (intent?.action != KitchenTimerNotifications.OPEN_ACTION) return false
        val timerId = intent.getStringExtra(KitchenTimerNotifications.EXTRA_TIMER_ID)
            ?.takeIf { it.isNotBlank() } ?: return false
        pendingTimerId = timerId
        if (notifyDart) channel?.invokeMethod("notificationTapped", timerId)
        return true
    }

    companion object {
        const val CHANNEL_NAME = "recipe/kitchen_notifications"
        private const val NOTIFICATION_PERMISSION_REQUEST = 42
    }
}

class KitchenTimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        KitchenTimerNotifications.deliverDue(
            context,
            intent.getStringExtra(KitchenTimerNotifications.EXTRA_TIMER_ID),
            intent.getIntExtra(KitchenTimerNotifications.EXTRA_GENERATION, -1),
        )
    }
}

class KitchenTimerSilenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val timerId = intent.getStringExtra(KitchenTimerNotifications.EXTRA_TIMER_ID) ?: return
        KitchenTimerNotifications.cancelVisibleNotification(context, timerId)
    }
}

class KitchenExactAlarmPermissionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) {
            KitchenTimerNotifications.rescheduleRegistered(context)
        }
    }
}

private data class NativeTimerRecord(
    val id: String,
    val name: String,
    val state: String,
    val generation: Int,
    val deadlineElapsedMillis: Long,
    val delivered: Boolean,
) {
    fun toJson(): String = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("state", state)
        .put("generation", generation)
        .put("deadline", deadlineElapsedMillis)
        .put("delivered", delivered)
        .toString()

    companion object {
        fun fromJson(value: String): NativeTimerRecord {
            val json = JSONObject(value)
            return NativeTimerRecord(
                id = json.getString("id"),
                name = json.getString("name"),
                state = json.getString("state"),
                generation = json.getInt("generation"),
                deadlineElapsedMillis = json.getLong("deadline"),
                delivered = json.getBoolean("delivered"),
            )
        }
    }
}

object KitchenTimerNotifications {
    const val CHANNEL_ID = "kitchen_timer_ends_v1"
    const val OPEN_ACTION = "com.kapioka.recipe_cooking_navigator.OPEN_KITCHEN_TIMER"
    const val EXTRA_TIMER_ID = "timer_id"
    const val EXTRA_GENERATION = "generation"
    private const val PREFS = "kitchen_timer_notifications_v1"
    private const val IDS = "timer_ids"
    private const val RECORD_PREFIX = "timer:"
    private const val GROUP_KEY = "kitchen_timer_finished"
    private const val SUMMARY_TAG = "kitchen-timer-summary"
    private const val NOTIFICATION_ID = 4100

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "キッチンタイマー終了",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "キッチンタイマーが終了したときに音と振動で知らせます。"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 350, 180, 350)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    fun status(context: Context): Map<String, Any> {
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.getNotificationChannel(CHANNEL_ID)
        } else {
            null
        }
        val notificationPermission =
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED) && manager.areNotificationsEnabled()
        val channelEnabled = channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE
        val exactAlarmAllowed = exactAlarmAllowed(context)
        val audio = context.getSystemService(AudioManager::class.java)
        val alarmVolumeAudible = audio.getStreamVolume(AudioManager.STREAM_ALARM) > 0
        return mapOf(
            "notificationPermission" to notificationPermission,
            "channelEnabled" to channelEnabled,
            "exactAlarmAllowed" to exactAlarmAllowed,
            "soundEnabled" to ((channel == null || channel.sound != null) && alarmVolumeAudible),
            "vibrationEnabled" to (channel?.shouldVibrate() ?: true),
        )
    }

    fun sync(context: Context, timers: List<Map<String, Any?>>): Map<String, Any> {
        ensureChannel(context)
        val previous = readRecords(context)
        val next = linkedMapOf<String, NativeTimerRecord>()
        for (timer in timers) {
            val id = timer["id"] as? String
                ?: throw IllegalArgumentException("Timer id is missing.")
            val name = timer["name"] as? String
                ?: throw IllegalArgumentException("Timer name is missing.")
            val state = timer["state"] as? String
                ?: throw IllegalArgumentException("Timer state is missing.")
            val generation = (timer["generation"] as? Number)?.toInt()
                ?: throw IllegalArgumentException("Timer generation is missing.")
            require(id.isNotBlank() && name.isNotBlank() && generation >= 0)
            if (state != "running" && state != "finished") continue
            val old = previous[id]
            val deadline = if (state == "running") {
                (timer["deadlineElapsedMillis"] as? Number)?.toLong()
                    ?: throw IllegalArgumentException("Running timer deadline is missing.")
            } else {
                old?.deadlineElapsedMillis ?: SystemClock.elapsedRealtime()
            }
            val sameEvent = old?.generation == generation &&
                old.deadlineElapsedMillis == deadline
            next[id] = NativeTimerRecord(
                id = id,
                name = name,
                state = state,
                generation = generation,
                deadlineElapsedMillis = deadline,
                delivered = sameEvent && old.delivered,
            )
        }

        writeRecords(context, next)
        for ((id, record) in previous) {
            val replacement = next[id]
            if (replacement == null || replacement.generation != record.generation) {
                cancelAlarm(context, id)
                cancelVisibleNotification(context, id)
            }
        }

        val currentStatus = status(context)
        val ready = currentStatus["notificationPermission"] == true &&
            currentStatus["channelEnabled"] == true &&
            currentStatus["exactAlarmAllowed"] == true
        if (!ready) {
            for (id in next.keys) cancelAlarm(context, id)
            return currentStatus + mapOf("scheduledCount" to 0)
        }

        val now = SystemClock.elapsedRealtime()
        for (record in next.values) {
            when {
                record.delivered -> Unit
                record.state == "finished" || record.deadlineElapsedMillis <= now -> Unit
                else -> scheduleExact(context, record)
            }
        }
        deliverDue(context, null, -1)
        val refreshed = readRecords(context)
        return currentStatus + mapOf(
            "scheduledCount" to refreshed.values.count {
                it.state == "running" && !it.delivered && it.deadlineElapsedMillis > now
            },
        )
    }

    fun rescheduleRegistered(context: Context) {
        if (!exactAlarmAllowed(context)) return
        val currentStatus = status(context)
        if (currentStatus["notificationPermission"] != true ||
            currentStatus["channelEnabled"] != true
        ) return
        val now = SystemClock.elapsedRealtime()
        for (record in readRecords(context).values) {
            if (record.state == "running" && !record.delivered && record.deadlineElapsedMillis > now) {
                scheduleExact(context, record)
            }
        }
        deliverDue(context, null, -1)
    }

    fun deliverDue(context: Context, expectedId: String?, expectedGeneration: Int) {
        val records = readRecords(context)
        if (expectedId != null) {
            val expected = records[expectedId] ?: return
            if (expected.generation != expectedGeneration) return
        }
        val now = SystemClock.elapsedRealtime()
        val due = records.values.filter {
            !it.delivered &&
                (it.state == "finished" ||
                    (it.state == "running" && it.deadlineElapsedMillis <= now))
        }
        if (due.isEmpty()) return
        val currentStatus = status(context)
        if (currentStatus["notificationPermission"] != true ||
            currentStatus["channelEnabled"] != true
        ) return

        val updated = records.toMutableMap()
        for (record in due) {
            updated[record.id] = record.copy(delivered = true)
            cancelAlarm(context, record.id)
        }
        writeRecords(context, updated)

        val manager = context.getSystemService(NotificationManager::class.java)
        val grouped = due.size > 1
        for (record in due) {
            manager.notify(
                notificationTag(record.id),
                NOTIFICATION_ID,
                buildNotification(context, record, grouped),
            )
        }
        if (grouped) {
            manager.notify(
                SUMMARY_TAG,
                NOTIFICATION_ID,
                buildSummaryNotification(context, due),
            )
        }
    }

    fun cancelVisibleNotification(context: Context, timerId: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(notificationTag(timerId), NOTIFICATION_ID)
        manager.cancel(SUMMARY_TAG, NOTIFICATION_ID)
    }

    private fun buildNotification(
        context: Context,
        record: NativeTimerRecord,
        grouped: Boolean,
    ): Notification {
        val builder = notificationBuilder(context)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(record.name)
            .setContentText("タイマーが終了しました")
            .setCategory(Notification.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(openPendingIntent(context, record.id))
            .setGroup(GROUP_KEY)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    "音を止める",
                    silencePendingIntent(context, record.id),
                ).build(),
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && grouped) {
            builder.setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
        }
        return builder.build()
    }

    private fun buildSummaryNotification(
        context: Context,
        records: List<NativeTimerRecord>,
    ): Notification {
        val builder = notificationBuilder(context)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("${records.size}件のタイマーが終了しました")
            .setContentText(records.joinToString("、") { it.name })
            .setCategory(Notification.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)
            .setContentIntent(openPendingIntent(context, records.first().id))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
        }
        return builder.build()
    }

    @Suppress("DEPRECATION")
    private fun notificationBuilder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
        }

    private fun scheduleExact(context: Context, record: NativeTimerRecord) {
        if (!exactAlarmAllowed(context)) return
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            record.deadlineElapsedMillis,
            alarmPendingIntent(context, record),
        )
    }

    private fun cancelAlarm(context: Context, timerId: String) {
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            alarmIntent(context, timerId, 0),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(pending)
        pending.cancel()
    }

    private fun alarmPendingIntent(context: Context, record: NativeTimerRecord): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            alarmIntent(context, record.id, record.generation),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun alarmIntent(context: Context, timerId: String, generation: Int) =
        Intent(context, KitchenTimerAlarmReceiver::class.java).apply {
            data = Uri.parse("rcn://kitchen-timer/alarm/${Uri.encode(timerId)}")
            putExtra(EXTRA_TIMER_ID, timerId)
            putExtra(EXTRA_GENERATION, generation)
        }

    private fun openPendingIntent(context: Context, timerId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = OPEN_ACTION
            data = Uri.parse("rcn://kitchen-timer/open/${Uri.encode(timerId)}")
            putExtra(EXTRA_TIMER_ID, timerId)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun silencePendingIntent(context: Context, timerId: String): PendingIntent {
        val intent = Intent(context, KitchenTimerSilenceReceiver::class.java).apply {
            data = Uri.parse("rcn://kitchen-timer/silence/${Uri.encode(timerId)}")
            putExtra(EXTRA_TIMER_ID, timerId)
        }
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun exactAlarmAllowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    private fun readRecords(context: Context): Map<String, NativeTimerRecord> {
        val prefs = prefs(context)
        val records = linkedMapOf<String, NativeTimerRecord>()
        for (id in prefs.getStringSet(IDS, emptySet()).orEmpty().toSet()) {
            val encoded = prefs.getString(RECORD_PREFIX + id, null) ?: continue
            try {
                records[id] = NativeTimerRecord.fromJson(encoded)
            } catch (_: Exception) {
                // Corrupt native metadata cannot create or revive a timer.
            }
        }
        return records
    }

    private fun writeRecords(context: Context, records: Map<String, NativeTimerRecord>) {
        val prefs = prefs(context)
        val previousIds = prefs.getStringSet(IDS, emptySet()).orEmpty().toSet()
        val editor = prefs.edit()
        for (id in previousIds - records.keys) editor.remove(RECORD_PREFIX + id)
        for ((id, record) in records) editor.putString(RECORD_PREFIX + id, record.toJson())
        editor.putStringSet(IDS, records.keys.toSet())
        if (!editor.commit()) throw IllegalStateException("Native timer metadata could not be saved.")
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun notificationTag(timerId: String) = "kitchen-timer:$timerId"
}
