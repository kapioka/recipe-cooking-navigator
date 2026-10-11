import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/kitchen_timer.dart';
import 'package:recipe_cooking_navigator/platform/kitchen_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(KitchenDevice.channel, null);
    messenger.setMockMethodCallHandler(KitchenDevice.notificationChannel, null);
    KitchenDevice.clearNotificationTapHandler();
  });

  test(
    'native resynchronization includes sleep and never reverses time',
    () async {
      var elapsed = 1000;
      messenger.setMockMethodCallHandler(
        KitchenDevice.channel,
        (call) async => elapsed,
      );
      final device = KitchenDevice();
      await device.synchronizeClock();
      final before = device.now();
      elapsed = 601000; // A sleeping Activity returns ten minutes later.
      await device.synchronizeClock();
      final after = device.now();
      expect(after - before, greaterThan(const Duration(minutes: 9)));
      elapsed = 1000; // Stale responses cannot move controller time backwards.
      await device.synchronizeClock();
      expect(device.now(), greaterThanOrEqualTo(after));
    },
  );

  test(
    'missing native clock is reported rather than advertised as ready',
    () async {
      messenger.setMockMethodCallHandler(
        KitchenDevice.channel,
        (_) async => null,
      );
      await expectLater(KitchenDevice().synchronizeClock(), throwsStateError);
    },
  );

  test('notification sync sends generation and monotonic deadline', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(KitchenDevice.notificationChannel, (
      call,
    ) async {
      received = call;
      return <String, Object?>{
        'notificationPermission': true,
        'channelEnabled': true,
        'exactAlarmAllowed': true,
        'soundEnabled': true,
        'vibrationEnabled': true,
        'scheduledCount': 1,
      };
    });
    final timer = KitchenTimer.create(
      id: 'timer-1',
      name: 'ソース',
      configuredDuration: const Duration(seconds: 30),
      source: const KitchenTimerSource.standalone(),
      now: const Duration(seconds: 5),
    ).start(now: const Duration(seconds: 5));

    final status = await KitchenDevice().syncTimerNotifications([timer]);
    expect(status.readyForBackground, isTrue);
    expect(status.scheduledCount, 1);
    expect(received?.method, 'sync');
    final sent =
        (received?.arguments as List<Object?>).single as Map<Object?, Object?>;
    expect(sent['id'], 'timer-1');
    expect(sent['state'], 'running');
    expect(sent['generation'], 1);
    expect(sent['deadlineElapsedMillis'], 35000);
  });

  test('notification status explains each degraded boundary', () async {
    messenger.setMockMethodCallHandler(
      KitchenDevice.notificationChannel,
      (_) async => <String, Object?>{
        'notificationPermission': true,
        'channelEnabled': true,
        'exactAlarmAllowed': false,
        'soundEnabled': false,
        'vibrationEnabled': true,
      },
    );
    final status = await KitchenDevice().notificationStatus();
    expect(status.readyForBackground, isFalse);
    expect(status.warning, contains('正確なアラーム'));
  });

  test('notification taps are forwarded to the active router', () async {
    String? target;
    KitchenDevice.setNotificationTapHandler((timerId) async {
      target = timerId;
    });
    await messenger.handlePlatformMessage(
      KitchenDevice.notificationChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('notificationTapped', 'timer-2'),
      ),
      (_) {},
    );
    expect(target, 'timer-2');
  });
}
