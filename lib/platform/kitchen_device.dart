import 'package:flutter/services.dart';

import '../domain/kitchen_timer.dart';

class KitchenNotificationStatus {
  const KitchenNotificationStatus({
    required this.notificationPermission,
    required this.channelEnabled,
    required this.exactAlarmAllowed,
    required this.soundEnabled,
    required this.vibrationEnabled,
    this.scheduledCount = 0,
  });

  factory KitchenNotificationStatus.fromMap(Map<Object?, Object?> value) =>
      KitchenNotificationStatus(
        notificationPermission: value['notificationPermission'] == true,
        channelEnabled: value['channelEnabled'] == true,
        exactAlarmAllowed: value['exactAlarmAllowed'] == true,
        soundEnabled: value['soundEnabled'] == true,
        vibrationEnabled: value['vibrationEnabled'] == true,
        scheduledCount: (value['scheduledCount'] as num?)?.toInt() ?? 0,
      );

  final bool notificationPermission;
  final bool channelEnabled;
  final bool exactAlarmAllowed;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final int scheduledCount;

  bool get readyForBackground =>
      notificationPermission && channelEnabled && exactAlarmAllowed;

  String? get warning {
    if (!notificationPermission) return '通知が許可されていません。';
    if (!channelEnabled) return 'キッチンタイマーの通知チャネルが無効です。';
    if (!exactAlarmAllowed) return '正確なアラームが許可されていません。';
    if (!soundEnabled && !vibrationEnabled) return '通知の音と振動が無効です。';
    if (!soundEnabled) return '通知音が無効、またはアラーム音量が0です。';
    if (!vibrationEnabled) return '通知の振動が無効です。';
    return null;
  }
}

class KitchenDevice {
  static const channel = MethodChannel('recipe/kitchen');
  static const notificationChannel = MethodChannel(
    'recipe/kitchen_notifications',
  );
  final Stopwatch _elapsed = Stopwatch()..start();
  Duration _offset = Duration.zero;
  Duration _last = Duration.zero;

  Duration now() {
    final current = _offset + _elapsed.elapsed;
    if (current > _last) _last = current;
    return _last;
  }

  /// Android elapsedRealtime includes deep sleep and ignores wall-clock edits.
  Future<void> synchronizeClock() async {
    final millis = await channel.invokeMethod<int>('elapsedRealtime');
    if (millis == null) throw StateError('Monotonic clock is unavailable.');
    _offset = Duration(milliseconds: millis);
    _elapsed.reset();
  }

  Future<void> setAwake(bool awake) =>
      channel.invokeMethod<void>('setAwake', awake);

  Future<String> bootId() async {
    final value = await channel.invokeMethod<int>('bootCount');
    if (value == null || value < 0) {
      throw StateError('Boot identity unavailable.');
    }
    return 'android-boot-$value';
  }

  Future<KitchenNotificationStatus> notificationStatus() async {
    final value = await notificationChannel.invokeMapMethod<Object?, Object?>(
      'status',
    );
    if (value == null) {
      throw StateError('Notification status is unavailable.');
    }
    return KitchenNotificationStatus.fromMap(value);
  }

  Future<KitchenNotificationStatus> syncTimerNotifications(
    Iterable<KitchenTimer> timers,
  ) async {
    final value = await notificationChannel.invokeMapMethod<Object?, Object?>(
      'sync',
      timers.map((timer) {
        final state = timer.state.name;
        return <String, Object?>{
          'id': timer.id,
          'name': timer.name,
          'state': state,
          'generation': timer.notificationGeneration,
          if (timer.deadline != null)
            'deadlineElapsedMillis': timer.deadline!.inMilliseconds,
        };
      }).toList(),
    );
    if (value == null) {
      throw StateError('Notification synchronization failed.');
    }
    return KitchenNotificationStatus.fromMap(value);
  }

  Future<bool> requestNotificationPermission() async =>
      await notificationChannel.invokeMethod<bool>(
        'requestNotificationPermission',
      ) ??
      false;

  Future<void> openExactAlarmSettings() =>
      notificationChannel.invokeMethod<void>('openExactAlarmSettings');

  Future<void> openNotificationSettings() =>
      notificationChannel.invokeMethod<void>('openNotificationSettings');

  static Future<String?> takeNotificationTimerId() =>
      notificationChannel.invokeMethod<String>('takeNotificationTimerId');

  static void setNotificationTapHandler(Future<void> Function(String) handler) {
    notificationChannel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped' && call.arguments is String) {
        await handler(call.arguments as String);
      }
    });
  }

  static void clearNotificationTapHandler() {
    notificationChannel.setMethodCallHandler(null);
  }
}
