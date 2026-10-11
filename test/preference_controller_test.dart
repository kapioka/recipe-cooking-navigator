import 'package:recipe_cooking_navigator/domain/profile_history.dart';
import 'package:recipe_cooking_navigator/domain/cooking_profile.dart';
import 'package:recipe_cooking_navigator/domain/preference_operation.dart';
import 'package:recipe_cooking_navigator/domain/preference_candidate.dart';
import 'package:recipe_cooking_navigator/data/profile_history_writer.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/preference_controller.dart';
import 'package:recipe_cooking_navigator/data/preference_store.dart';
import 'package:recipe_cooking_navigator/data/cooking_profile_cache_store.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_evidence.dart';
import 'package:recipe_cooking_navigator/platform/feedback_archive_platform.dart';

class _Archive implements FeedbackArchivePlatform {
  @override
  Future<bool> appendHistory(String root, ProfileHistoryRecord record) async {
    history.add(
      FeedbackArchiveItem(
        '${record.id}.json',
        source: jsonEncode(record.toJson()),
      ),
    );
    return true;
  }

  String? root = 'content://drive/tree/archive';
  String? selection;
  bool failLoad = false;
  String? remoteProfile;
  bool failProfile = false;
  bool failEvidence = false;
  int? failAt;
  final ids = <String>{};
  final attempted = <String>[];
  List<FeedbackArchiveItem> evidence = [];
  List<FeedbackArchiveItem> history = [];
  @override
  Future<List<FeedbackArchiveItem>> readHistory(String root) async => history;
  @override
  Future<List<FeedbackArchiveItem>> readEvidence(String root) async {
    if (failEvidence) throw PlatformException(code: 'permission_lost');
    return evidence;
  }

  @override
  Future<String?> selectRoot() async => selection;
  @override
  Future<String?> readProfile(String root) async {
    if (failProfile) throw PlatformException(code: 'permission_lost');
    return remoteProfile;
  }

  @override
  Future<String?> loadRoot() async {
    if (failLoad) throw PlatformException(code: 'permission_lost');
    return root;
  }

  @override
  Future<bool> append(String root, PreferenceEvidence evidence) async {
    attempted.add(evidence.id);
    if (attempted.length == failAt) {
      throw PlatformException(code: 'permission_lost');
    }
    return ids.add(evidence.id);
  }
}

void main() {
  late Directory directory;
  late File file;
  late _Archive archive;
  late PreferenceController controller;
  final now = DateTime.utc(2026, 10, 4);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preference-export-');
    file = File('${directory.path}/preferences.json');
    final validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
          .readAsStringSync(),
      recipeSchemaSource: File('schemas/recipe-v2.schema.json')
          .readAsStringSync(),
    );
    archive = _Archive();
    controller = PreferenceController(
      PreferenceStore(file, validator),
      now: () => now,
      archive: archive,
      profileCache: CookingProfileCacheStore(
        File('${directory.path}/profile-cache.json'),
        File('schemas/cooking-profile-v1.schema.json').readAsStringSync(),
        explicitSchemaSource: File('schemas/cooking-profile-v1.1.schema.json')
            .readAsStringSync(),
      ),
    );
    await controller.initialize();
    for (var i = 1; i <= 3; i++) {
      final feedback = jsonDecode(
        File('examples/feedback-example.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      feedback['cook_session']['id'] = 'export-session-$i';
      expect(await controller.record(feedback, categories: {'主菜'}), isTrue);
    }
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  test('a rewritten known record is rejected even when a later head replays consistently', () async {
    final records = jsonDecode(
      File('examples/profile-history-explicit-example.json').readAsStringSync(),
    ) as List;
    archive.history = [
      for (final record in records)
        FeedbackArchiveItem('record.json', source: jsonEncode(record)),
    ];
    expect(await controller.refreshProfile(), isTrue);
    final prior = controller.cachedProfile!.profile.toJson();
    final changed = records.last as Map<String, dynamic>;
    changed['operation']['direction'] = 1;
    changed['result_profile']['preferences'][0]['direction'] = 1;
    changed['result_digest'] = profileDigest(
      CookingProfile.fromJson(changed['result_profile']),
    );
    final parent = ProfileHistoryRecord.fromJson(
      changed,
      controller.store.validator,
    );
    final child = ProfileHistoryRecord.update(
      parent,
      PreferenceOperation.explicit(
        id: 'new-head',
        baseRevision: 2,
        now: now.add(const Duration(hours: 3)),
        scope: PreferenceScope(PreferenceScopeKind.global, '*'),
        dimension: 'aroma',
        direction: 1,
        declaration: '香りが強い料理が好き',
      ),
      validator: controller.store.validator,
    );
    archive.history = [
      FeedbackArchiveItem('root.json', source: jsonEncode(records.first)),
      FeedbackArchiveItem('changed.json', source: jsonEncode(changed)),
      FeedbackArchiveItem('child.json', source: jsonEncode(child.toJson())),
    ];
    expect(await controller.refreshProfile(), isFalse);
    expect(controller.cachedProfile!.profile.toJson(), prior);
    expect(controller.error, contains('内容が変わっています'));
  });

  test('confirmed candidate is rebased with its Evidence; the same support cannot be published twice', () async {
    final old = controller;
    controller = PreferenceController(
      old.store,
      now: () => now.add(const Duration(hours: 3)),
      archive: archive,
      profileCache: old.profileCache,
      profileWriter: ProfileHistoryWriter(
        File('${directory.path}/outbox.json'),
        old.store.validator,
        archive,
      ),
    );
    old.dispose();
    await controller.load();
    archive.evidence =
        (jsonDecode(
              File('examples/preference-evidence-series-example.json')
                  .readAsStringSync(),
            ) as List)
            .map(
              (e) =>
                  FeedbackArchiveItem('evidence.json', source: jsonEncode(e)),
            )
            .toList();
    expect(await controller.importEvidence(), isTrue);
    final candidate = controller.proposals
        .where((c) => c.dimension == 'saltiness')
        .single;
    expect(
      await controller.decide(candidate, accept: true, expectedRevision: 1),
      isTrue,
    );
    expect(
      await controller.startDriveHistory(expectedRoot: archive.root!),
      isTrue,
    );
    final rootId = controller.cachedProfile!.historyRecordId!;
    final preference =
        (controller.snapshot!.profile!.toJson()['preferences'] as List).single
            as Map<String, dynamic>;
    expect(
      await controller.publishCandidate(
        preference,
        expectedRoot: archive.root!,
        expectedHeadId: rootId,
      ),
      isTrue,
    );
    final currentId = controller.cachedProfile!.historyRecordId!;
    expect(
      (jsonDecode(archive.history.last.source!)['evidence'] as List),
      hasLength(candidate.evidenceIds.length),
    );
    expect(
      await controller.publishCandidate(
        preference,
        expectedRoot: archive.root!,
        expectedHeadId: currentId,
      ),
      isFalse,
    );
    expect(archive.history, hasLength(2));
    final saved = controller.cachedProfile!.profile.toJson();
    final tampered =
        jsonDecode(archive.history.last.source!) as Map<String, dynamic>;
    tampered['evidence'][0]['feedback']['evaluation']['comment'] = '根拠の説明だけを改変';
    archive.history[1] = FeedbackArchiveItem(
      'rewritten.json',
      source: jsonEncode(tampered),
    );
    expect(await controller.refreshProfile(), isFalse);
    expect(controller.cachedProfile!.profile.toJson(), saved);
    expect(controller.error, contains('内容が変わっています'));
  });

  test('explicit Drive update rebases the approved value onto remote ID without replacing local history', () async {
    archive.remoteProfile = File('examples/cooking-profile-example.json')
        .readAsStringSync();
    final old = controller;
    final originalLocalId = old.snapshot!.profile!.id;
    controller = PreferenceController(
      old.store,
      now: () => now.add(const Duration(hours: 3)),
      archive: archive,
      profileCache: old.profileCache,
      profileWriter: ProfileHistoryWriter(
        File('${directory.path}/outbox.json'),
        old.store.validator,
        archive,
      ),
    );
    old.dispose();
    await controller.load();
    expect(await controller.refreshProfile(), isTrue);
    final legacy = controller.cachedProfile!.profile;
    expect(
      await controller.startDriveHistory(
        expectedRoot: archive.root!,
        legacy: legacy,
      ),
      isTrue,
    );
    final bootstrapId = controller.cachedProfile!.historyRecordId!;
    expect(
      await controller.registerExplicit(
        scope: PreferenceScope(PreferenceScopeKind.global, '*'),
        dimension: 'saltiness',
        direction: -1,
        declaration: '薄味が好き',
        expectedRevision: 1,
      ),
      isTrue,
    );
    final local = controller.snapshot!.profile!.toJson();
    final preference =
        (local['preferences'] as List).single as Map<String, dynamic>;
    expect(
      await controller.publishExplicit(
        preference,
        expectedRoot: archive.root!,
        expectedHeadId: bootstrapId,
      ),
      isTrue,
    );
    expect(controller.cachedProfile!.profile.id, legacy.id);
    expect(controller.cachedProfile!.profile.revision, legacy.revision + 1);
    expect(controller.snapshot!.profile!.id, originalLocalId);
    expect(controller.snapshot!.profile!.toJson(), local);
    expect(controller.hasPendingProfileWrite, isFalse);
    expect(await controller.profileWriter!.pending(), isNull);
    final count = archive.history.length;
    expect(
      await controller.publishExplicit(
        preference,
        expectedRoot: archive.root!,
        expectedHeadId: bootstrapId,
      ),
      isFalse,
    );
    expect(archive.history, hasLength(count));
  });

  test('Drive history is authoritative; branch and missing history retain last verified cache', () async {
    final records = jsonDecode(
      File('examples/profile-history-explicit-example.json').readAsStringSync(),
    ) as List;
    archive.history = [
      for (var i = 0; i < records.length; i++)
        FeedbackArchiveItem('$i.json', source: jsonEncode(records[i])),
    ];
    archive.remoteProfile = '{stale distribution copy';
    expect(await controller.refreshProfile(), isTrue);
    final cached = controller.cachedProfile!.profile.toJson();
    expect(controller.cachedProfile!.historyRecordId, 'explicit-example');
    expect(controller.snapshot!.profile!.revision, 1);
    final branch = jsonDecode(jsonEncode(records.last)) as Map<String, dynamic>;
    branch['record_id'] = 'branch';
    branch['operation']['operation_id'] = 'branch';
    archive.history.add(
      FeedbackArchiveItem('branch.json', source: jsonEncode(branch)),
    );
    expect(await controller.refreshProfile(), isFalse);
    expect(controller.cachedProfile!.profile.toJson(), cached);
    archive.history = [];
    archive.remoteProfile = jsonEncode(cached);
    // A new controller must not forget that history was previously observed.
    final restarted = PreferenceController(
      controller.store,
      archive: archive,
      profileCache: controller.profileCache,
    );
    await restarted.load();
    expect(await restarted.refreshProfile(), isFalse);
    expect(restarted.cachedProfile!.profile.toJson(), cached);
    restarted.dispose();
  });
  test('Evidence import rejects individual files and repeated scans never add score', () async {
    final series = jsonDecode(
      File('examples/preference-evidence-series-example.json')
          .readAsStringSync(),
    ) as List;
    archive.evidence = [
      for (var i = 0; i < series.length; i++)
        FeedbackArchiveItem('2026/row-$i.json', source: jsonEncode(series[i])),
      FeedbackArchiveItem(
        '2026/duplicate.json',
        source: jsonEncode(series.first),
      ),
      const FeedbackArchiveItem('2026/broken.json', source: '{broken'),
      FeedbackArchiveItem(
        '2026/future.json',
        source: jsonEncode({
          ...series.first as Map,
          'evidence_schema_version': '9.0.0',
        }),
      ),
      const FeedbackArchiveItem('2026/unreadable.json', error: '読込失敗'),
    ];
    expect(await controller.importEvidence(), isTrue);
    expect(controller.importMessage, contains('3件を追加、1件は取込済み、3件を拒否'));
    expect(controller.importErrors, hasLength(3));
    final proposal = controller.proposals.single.toJson();
    expect(proposal['score'], 4);
    expect(controller.snapshot!.profile!.revision, 1);
    final before = await file.readAsString();
    expect(await controller.importEvidence(), isTrue);
    expect(controller.importMessage, contains('0件を追加、4件は取込済み'));
    expect(controller.proposals.single.toJson(), proposal);
    expect(await file.readAsString(), before);
  });

  test(
    'conflicting imported ID and permission loss never overwrite evidence',
    () async {
      final original = controller.snapshot!.evidence.first.toJson();
      original['feedback']['evaluation']['comment'] = 'different content';
      archive.evidence = [
        FeedbackArchiveItem('conflict.json', source: jsonEncode(original)),
      ];
      final before = await file.readAsString();
      expect(await controller.importEvidence(), isTrue);
      expect(controller.importErrors.single, contains('上書きできません'));
      expect(await file.readAsString(), before);
      archive.failEvidence = true;
      expect(await controller.importEvidence(), isFalse);
      expect(controller.error, contains('アクセス権が失われました'));
      expect(await file.readAsString(), before);
    },
  );
  test(
    'remote Profile is read-only; invalid or offline reads keep valid cache',
    () async {
      final before = await file.readAsString();
      archive.remoteProfile = File('examples/cooking-profile-example.json')
          .readAsStringSync();
      expect(await controller.refreshProfile(), isTrue);
      final valid = controller.cachedProfile!.profile.toJson();
      for (final source in [null, '{broken']) {
        archive.remoteProfile = source;
        expect(await controller.refreshProfile(), isFalse);
        expect(controller.cachedProfile!.profile.toJson(), valid);
      }
      archive.failProfile = true;
      expect(await controller.refreshProfile(), isFalse);
      expect(controller.cachedProfile!.profile.toJson(), valid);
      expect(controller.profileMessage, contains('最後に検証した記録は保持'));
      expect(await file.readAsString(), before);
      expect(controller.snapshot!.profile!.revision, 1);
      expect(controller.snapshot!.decisions, isEmpty);
    },
  );

  test(
    'export retries only append or compare, without changing local records',
    () async {
      final before = await file.readAsString();
      expect(await controller.exportEvidence(), isTrue);
      expect(archive.ids, hasLength(3));
      expect(controller.archiveMessage, contains('3件をDrive保存先へ追記'));
      expect(await controller.exportEvidence(), isTrue);
      expect(controller.archiveMessage, contains('3件は保存済み'));
      expect(await file.readAsString(), before);
      expect(controller.snapshot!.profile!.revision, 1);
    },
  );

  test(
    'partial permission failure preserves evidence and reports partial result',
    () async {
      final before = await file.readAsString();
      archive.failAt = 2;
      expect(await controller.exportEvidence(), isFalse);
      expect(controller.archiveMessage, contains('1件を追記'));
      expect(controller.error, contains('アクセス権が失われました'));
      expect(await file.readAsString(), before);
      expect(controller.snapshot!.evidence, hasLength(3));
      archive.failAt = null;
      expect(await controller.exportEvidence(), isTrue);
      expect(archive.ids, hasLength(3));
      expect(controller.archiveMessage, contains('1件は保存済み'));
    },
  );

  test('offline connection check and cancelled selection leave local Profile intact', () async {
    final root = controller.archiveRoot;
    archive.failLoad = true;
    expect(await controller.load(), isTrue);
    expect(controller.archiveMessage, contains('端末内の記録は利用できます'));
    expect(await controller.connectArchive(), isTrue);
    expect(controller.archiveRoot, root);
    expect(controller.snapshot!.profile!.revision, 1);
    expect(controller.snapshot!.evidence, hasLength(3));
  });
}
