import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/kitchen_timer_file_store.dart';
import 'package:recipe_cooking_navigator/domain/kitchen_timer.dart';

void main() {
  KitchenTimer timer(String id) => KitchenTimer.create(
    id: id,
    name: id,
    configuredDuration: const Duration(minutes: 1),
    source: const KitchenTimerSource.standalone(),
    now: Duration.zero,
  ).start(now: Duration.zero);
  KitchenTimerSnapshot snapshot([String id = 'one']) =>
      KitchenTimerSnapshot(bootId: 'boot-1', timers: [timer(id)]);

  test('snapshots roundtrip all timer states and recipe source', () {
    final running = timer('running');
    final values = [
      running,
      timer('paused').pause(now: const Duration(seconds: 10)),
      timer('cancelled').cancel(now: const Duration(seconds: 1)),
      timer('ready').reset(now: const Duration(seconds: 1)),
      timer('finished')
          .reachDeadline(now: const Duration(minutes: 1))
          .acknowledgeFinished(now: const Duration(seconds: 61)),
      KitchenTimer.create(
        id: 'recipe',
        name: '煮る',
        configuredDuration: const Duration(minutes: 5),
        source: KitchenTimerSource.recipeStep(
          recipeId: 'r1',
          recipeRevision: 2,
          stepId: 's1',
          recipeDisplayName: 'カレー',
          stepDisplayName: '煮る',
        ),
        now: Duration.zero,
      ),
    ];
    final original = KitchenTimerSnapshot(bootId: 'boot-1', timers: values);
    expect(
      KitchenTimerSnapshot.decode(original.encode()).encode(),
      original.encode(),
    );
  });

  test('same boot expires once; different boot requires explicit review', () {
    final original = snapshot();
    final restored = original.restore(
      currentBootId: 'boot-1',
      now: const Duration(minutes: 2),
    );
    expect(restored.single.state, KitchenTimerState.finished);
    expect(restored.single.notificationGeneration, 1);
    expect(
      () => original.restore(currentBootId: 'boot-2', now: Duration.zero),
      throwsStateError,
    );
    final stopped = original.timers.single.stopAfterReboot(now: Duration.zero);
    expect(stopped.state, KitchenTimerState.cancelled);
    expect(stopped.configuredDuration, const Duration(minutes: 1));
    expect(stopped.reset(now: Duration.zero).state, KitchenTimerState.ready);
    expect(original.timers.single.state, KitchenTimerState.running);
  });

  test('malformed state, duplicate IDs and unknown version fail closed', () {
    final original = jsonDecode(snapshot().encode()) as Map<String, dynamic>;
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (data) => data['storage_version'] = 2,
      (data) => (data['timers'] as List).add((data['timers'] as List).first),
      (data) => data['timers'][0]['deadline_us'] = null,
      (data) => data['timers'][0]['paused_us'] = 20,
      (data) => data['timers'][0]['state'] = 'unknown',
      (data) => data['timers'][0]['generation'] = -1,
    ]) {
      final data = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      mutation(data);
      expect(
        () => KitchenTimerSnapshot.decode(jsonEncode(data)),
        throwsFormatException,
      );
    }
  });

  group('files', () {
    late Directory directory;
    late File file;
    late KitchenTimerFileStore store;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('kitchen-store-test-');
      file = File('${directory.path}/timers.json');
      store = KitchenTimerFileStore(file);
    });
    tearDown(() => directory.delete(recursive: true));

    test(
      'serialized saves keep the newest primary and previous backup',
      () async {
        await Future.wait([
          store.save(snapshot('one')),
          store.save(snapshot('two')),
        ]);
        expect((await store.load())!.timers.single.id, 'two');
        final backup = await File('${file.path}.bak').readAsString();
        expect(KitchenTimerSnapshot.decode(backup).timers.single.id, 'one');
        await file.delete();
        expect((await store.load())!.timers.single.id, 'one');
      },
    );

    test(
      'corrupt primary and backup are preserved instead of overwritten',
      () async {
        await store.save(snapshot('one'));
        await store.save(snapshot('two'));
        final backup = await File('${file.path}.bak').readAsString();
        await file.writeAsString('broken');
        await expectLater(store.load(), throwsFormatException);
        await expectLater(store.save(snapshot('three')), throwsFormatException);
        expect(await file.readAsString(), 'broken');
        expect(await File('${file.path}.bak').readAsString(), backup);
      },
    );

    test('write failure does not replace a committed snapshot', () async {
      await store.save(snapshot());
      final original = await file.readAsString();
      await Directory('${file.path}.tmp').create();
      await expectLater(
        store.save(snapshot('two')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsString(), original);
    });
  });
}
