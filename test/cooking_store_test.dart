import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/cooking_store.dart';

void main() {
  test(
    'saves progress, keeps its start time, and records completion',
    () async {
      final store = CookingStore();

      await store.savePosition('recipe-1', 2, 'step-1', restart: true);
      final started = await store.read();
      final startedAt =
          ((started['progress'] as Map)['recipe-1'] as Map)['started_at'];

      await store.savePosition('recipe-1', 2, 'step-2');
      final moved = await store.read();
      final progress = (moved['progress'] as Map)['recipe-1'] as Map;
      expect(progress['step_id'], 'step-2');
      expect(progress['started_at'], startedAt);

      await store.complete('recipe-1', 2);
      final completed = await store.read();
      expect(completed['progress'], isEmpty);
      expect(completed['sessions'], hasLength(1));
      expect((completed['sessions'] as List).single['revision'], 2);
    },
  );

  test('persists progress and first-use help state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cooking-store-test-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final file = File('${directory.path}/cooking-v1.json');
    final store = CookingStore(file);

    await store.savePosition('recipe-1', 1, 'step-1');
    await store.markHelpSeen();

    final reopened = await CookingStore(file).read();
    expect(reopened['help_seen'], isTrue);
    expect((reopened['progress'] as Map)['recipe-1']['step_id'], 'step-1');
    expect(await File('${file.path}.bak').exists(), isTrue);
  });

  test('reads a valid backup when the primary file is malformed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cooking-store-backup-test-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final file = File('${directory.path}/cooking-v1.json');
    final store = CookingStore(file);
    await store.savePosition('recipe-1', 1, 'step-1');
    await file.writeAsString('{broken');

    final recovered = await CookingStore(file).read();

    expect((recovered['progress'] as Map)['recipe-1']['step_id'], 'step-1');
  });

  test('rejects invalid progress arguments and malformed sessions', () async {
    final store = CookingStore();
    await expectLater(
      store.savePosition('', 1, 'step-1'),
      throwsFormatException,
    );
    await expectLater(
      store.savePosition('recipe-1', 0, 'step-1'),
      throwsFormatException,
    );
    await expectLater(
      store.savePosition('recipe-1', 1, ''),
      throwsFormatException,
    );

    final directory = await Directory.systemTemp.createTemp(
      'cooking-store-invalid-test-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final file = File('${directory.path}/cooking-v1.json');
    await file.writeAsString(
      jsonEncode({
        'storage_version': 1,
        'progress': <String, dynamic>{},
        'sessions': [
          {'session_id': 'incomplete'},
        ],
      }),
    );

    await expectLater(CookingStore(file).read(), throwsFormatException);
  });
}
