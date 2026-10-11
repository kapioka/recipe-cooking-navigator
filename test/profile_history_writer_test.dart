import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/data/profile_history_writer.dart';
import 'package:recipe_cooking_navigator/domain/cooking_profile.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_candidate.dart';
import 'package:recipe_cooking_navigator/domain/preference_evidence.dart';
import 'package:recipe_cooking_navigator/domain/preference_operation.dart';
import 'package:recipe_cooking_navigator/domain/profile_history.dart';
import 'package:recipe_cooking_navigator/platform/feedback_archive_platform.dart';

class _Drive implements FeedbackArchivePlatform {
  final records = <ProfileHistoryRecord>[];
  final attempted = <String>[];
  String? legacy;
  bool failBefore = false;
  bool failAfter = false;
  ProfileHistoryRecord? concurrent;
  @override
  Future<String?> loadRoot() async => 'content://drive/tree/root';
  @override
  Future<String?> selectRoot() async => null;
  @override
  Future<String?> readProfile(String root) async => legacy;
  @override
  Future<List<FeedbackArchiveItem>> readHistory(String root) async => [
    for (final r in records)
      FeedbackArchiveItem('${r.id}.json', source: jsonEncode(r.toJson())),
  ];
  @override
  Future<List<FeedbackArchiveItem>> readEvidence(String root) async => [];
  @override
  Future<bool> append(String root, PreferenceEvidence evidence) async =>
      throw UnimplementedError();
  @override
  Future<bool> appendHistory(String root, ProfileHistoryRecord record) async {
    attempted.add(record.id);
    if (failBefore) throw StateError('offline');
    records.add(record);
    if (concurrent != null) records.add(concurrent!);
    if (failAfter) throw StateError('response lost');
    return true;
  }
}

void main() {
  late Directory directory;
  late ProfileHistoryWriter writer;
  late _Drive drive;
  final validator = FeedbackValidator.fromSchemaStrings(
    feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
        .readAsStringSync(),
    recipeSchemaSource: File('schemas/recipe-v2.schema.json')
        .readAsStringSync(),
  );
  final now = DateTime.utc(2026, 10, 4);
  const connection = 'content://drive/tree/root';
  final root = ProfileHistoryRecord.bootstrap(
    CookingProfile.create('remote', now),
    id: 'bootstrap',
    validator: validator,
  );
  ProfileHistoryRecord next(String id, {int direction = -1}) =>
      ProfileHistoryRecord.update(
        root,
        PreferenceOperation.explicit(
          id: id,
          baseRevision: 1,
          now: now,
          scope: PreferenceScope(PreferenceScopeKind.global, '*'),
          dimension: 'saltiness',
          direction: direction,
          declaration: '自分の塩味の好み',
        ),
        validator: validator,
      );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('profile-outbox-');
    drive = _Drive();
    writer = ProfileHistoryWriter(
      File('${directory.path}/outbox.json'),
      validator,
      drive,
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('empty Drive starts with empty bootstrap; acknowledgement survives backup and restart', () async {
    final result = await writer.commit(connection, root);
    expect(result.head.id, root.id);
    expect((await writer.pending())!.record.id, root.id);
    await writer.acknowledge(connection, root.id);
    final restarted = ProfileHistoryWriter(writer.file, validator, drive);
    expect(await restarted.pending(), isNull);
    expect(await File('${writer.file.path}.bak').exists(), isTrue);
    expect(drive.attempted, [root.id]);
  });

  test('legacy snapshot migration matches current content and leaves the snapshot untouched', () async {
    final profile = CookingProfile.fromJson(
      jsonDecode(
        File('examples/cooking-profile-explicit-example.json')
            .readAsStringSync(),
      ),
    );
    drive.legacy = jsonEncode(profile.toJson());
    final original = drive.legacy;
    final seed = ProfileHistoryRecord.bootstrap(
      profile,
      id: 'migration',
      validator: validator,
    );
    expect(
      (await writer.commit(connection, seed)).head.result.toJson(),
      profile.toJson(),
    );
    expect(drive.legacy, original);
    await writer.acknowledge(connection, seed.id);
    drive.records.clear();
    drive.legacy = jsonEncode(root.result.toJson());
    await expectLater(writer.commit(connection, seed), throwsStateError);
    expect(await writer.pending(), isNull);
  });

  test(
    'lost response is retried with the same immutable ID and no second append',
    () async {
      drive.records.add(root);
      drive.failAfter = true;
      final update = next('approved');
      await expectLater(writer.commit(connection, update), throwsStateError);
      final restarted = ProfileHistoryWriter(writer.file, validator, drive);
      final pending = (await restarted.pending())!;
      expect(pending.record.id, update.id);
      expect(
        (await restarted.commit(pending.root, pending.record)).head.id,
        update.id,
      );
      expect(drive.attempted, [update.id]);
      await restarted.acknowledge(pending.root, pending.record.id);
      expect(await restarted.pending(), isNull);
    },
  );

  test('offline before provider write preserves intent and refuses another update or root', () async {
    drive.records.add(root);
    drive.failBefore = true;
    final update = next('approved');
    await expectLater(writer.commit(connection, update), throwsStateError);
    final before = await writer.file.readAsString();
    await expectLater(
      writer.commit(connection, next('different')),
      throwsStateError,
    );
    await expectLater(
      writer.commit('content://drive/tree/other', update),
      throwsStateError,
    );
    expect(await writer.file.readAsString(), before);
    drive.failBefore = false;
    expect((await writer.commit(connection, update)).head.id, update.id);
    expect(drive.attempted, [update.id, update.id]);
  });

  test('changed head prevents write; concurrent branch preserves both records and pending intent', () async {
    drive.records.addAll([root, next('already-updated')]);
    await expectLater(
      writer.commit(connection, next('stale')),
      throwsStateError,
    );
    expect(drive.attempted, isEmpty);
    expect(await writer.pending(), isNull);
    drive.records.removeLast();
    drive.concurrent = next('other-writer', direction: 1);
    await expectLater(
      writer.commit(connection, next('approved')),
      throwsFormatException,
    );
    expect(drive.records.map((r) => r.id), [
      'bootstrap',
      'approved',
      'other-writer',
    ]);
    expect((await writer.pending())!.record.id, 'approved');
    final before = await writer.file.readAsString();
    await expectLater(
      writer.commit(connection, next('approved')),
      throwsFormatException,
    );
    expect(await writer.file.readAsString(), before);
    expect(drive.attempted, ['approved']);
  });

  test(
    'corrupt primary and isolated temp are never reset or replaced by backup',
    () async {
      await writer.commit(connection, root);
      await writer.file.writeAsString('{broken');
      await expectLater(writer.pending(), throwsFormatException);
      await expectLater(
        writer.commit(connection, next('new')),
        throwsFormatException,
      );
      expect(await writer.file.readAsString(), '{broken');
      await writer.file.delete();
      final backup = File('${writer.file.path}.bak');
      if (await backup.exists()) await backup.delete();
      await File('${writer.file.path}.tmp').writeAsString('{}');
      await expectLater(writer.pending(), throwsFormatException);
    },
  );
}
