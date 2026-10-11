import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/preference_store.dart';
import '../data/cooking_profile_cache_store.dart';
import '../data/profile_history_writer.dart';
import '../domain/cooking_profile.dart';
import '../domain/preference_operation.dart';
import '../domain/preference_candidate.dart';
import '../domain/preference_evidence.dart';
import '../domain/feedback_validator.dart';
import '../domain/profile_history.dart';
import '../platform/feedback_archive_platform.dart';

class PreferenceController extends ChangeNotifier {
  PreferenceController(
    this.store, {
    DateTime Function()? now,
    this.archive,
    this.profileCache,
    this.profileWriter,
  }) : _now = now ?? DateTime.now;
  final PreferenceStore store;
  final DateTime Function() _now;
  final FeedbackArchivePlatform? archive;
  final CookingProfileCacheStore? profileCache;
  final ProfileHistoryWriter? profileWriter;
  bool hasPendingProfileWrite = false;
  CachedCookingProfile? cachedProfile;
  String? profileMessage;
  String? importMessage;
  List<String> importErrors = const [];
  String? archiveRoot;
  String? archiveMessage;
  PreferenceSnapshot? _snapshot;
  PreferenceSnapshot? get snapshot => _snapshot;
  bool isBusy = false;
  String? error;

  List<PreferenceCandidate> get proposals {
    final snapshot = _snapshot;
    if (snapshot == null) return const [];
    final categories =
        snapshot.evidence.expand((e) => e.categories).toSet().toList()..sort();
    const engine = PreferenceCandidateEngine();
    return List.unmodifiable([
      for (final category in categories)
        ...engine.propose(
          snapshot.evidence,
          scope: PreferenceScope(PreferenceScopeKind.category, category),
          previous: snapshot.decisions,
        ),
      ...engine.propose(
        snapshot.evidence,
        scope: PreferenceScope(PreferenceScopeKind.global, '*'),
        previous: snapshot.decisions,
      ),
    ]);
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (isBusy) return false;
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      _snapshot = await store.load();
      return true;
    } catch (e) {
      error = e is FormatException
          ? e.message
          : e is StateError
          ? e.message
          : e is PlatformException && e.code == 'permission_lost'
          ? 'Driveのアクセス権が失われました。保存先を選び直してください。端末の記録は保持しています。'
          : '記録を保存・読込できませんでした。Driveの場合は接続先と通信状態を確認してください。端末の記録は保持しています。';
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> load() => _run(() async {
    _snapshot = await store.load();
    if (profileWriter != null) {
      hasPendingProfileWrite = await profileWriter!.pending() != null;
    }
    if (archive != null) {
      try {
        archiveRoot = await archive!.loadRoot();
      } catch (_) {
        archiveMessage = 'Drive接続を確認できません。端末内の記録は利用できます。';
      }
    }
    if (profileCache != null) {
      try {
        final cached = await profileCache!.load();
        cachedProfile = cached?.root == archiveRoot ? cached : null;
      } catch (_) {
        profileMessage = '保存済みのDriveの好みを検証できません。元のファイルは保持しています。';
      }
    }
  });

  Future<bool> connectArchive() => _run(() async {
    final platform = archive;
    if (platform == null) throw StateError('この環境ではDrive接続を利用できません。');
    final root = await platform.selectRoot();
    if (root != null) {
      if (root != archiveRoot) cachedProfile = null;
      archiveRoot = root;
      archiveMessage = 'Driveのアプリ用フォルダを接続しました。';
      profileMessage = null;
    }
  });

  Future<bool> refreshProfile() => _run(() async {
    final platform = archive;
    final root = archiveRoot;
    final cache = profileCache;
    if (platform == null || root == null || cache == null) {
      throw StateError('Driveのアプリ用フォルダを選択してください。');
    }
    profileMessage = null;
    try {
      final items = await platform.readHistory(root);
      String? source;
      String? historyRecordId;
      String? recordDigest;
      if (items.isNotEmpty) {
        final records = <ProfileHistoryRecord>[];
        for (final item in items) {
          if (item.source == null) {
            throw const FormatException('Profile履歴を読み込めません。既存の記録を保持します。');
          }
          final json = jsonDecode(item.source!);
          if (json is! Map<String, dynamic>) {
            throw const FormatException('Profile履歴の先頭構造が正しくありません。');
          }
          records.add(ProfileHistoryRecord.fromJson(json, store.validator));
        }
        final history = ProfileHistory.validate(records);
        _checkHistoryCache(history, root, await cache.load());
        source = canonicalPreferenceJson(history.head.result.toJson());
        historyRecordId = history.head.id;
        recordDigest = historyRecordDigest(history.head);
      } else {
        source = await platform.readProfile(root);
      }
      if (source == null) {
        throw StateError('DriveのProfile/cooking-profile.jsonが見つかりません。');
      }
      final validated = await cache.save(
        root,
        source,
        historyRecordId: historyRecordId,
        historyRecordDigest: recordDigest,
      );
      if (archiveRoot != root) throw StateError('Driveの接続先が変わりました。再読込してください。');
      cachedProfile = validated;
      profileMessage = historyRecordId == null
          ? '履歴へ移行する前のDriveの好みを検証しました。読み取り専用で確認できます。'
          : 'Driveの履歴を検証して好みを保存しました。読み取り専用で確認できます。';
    } catch (_) {
      profileMessage = 'Driveの好みを更新できません。最後に検証した記録は保持しています。';
      rethrow;
    }
  });

  Future<bool> importEvidence() => _run(() async {
    final platform = archive;
    final root = archiveRoot;
    if (platform == null || root == null) {
      throw StateError('Driveのアプリ用フォルダを選択してください。');
    }
    importMessage = null;
    importErrors = const [];
    final items = await platform.readEvidence(root);
    final known = (await store.load()).evidence.map((e) => e.id).toSet();
    var added = 0;
    var existing = 0;
    final failures = <String>[];
    for (final item in items) {
      if (item.source == null) {
        failures.add('${item.name}：${item.error ?? '読み込めませんでした。'}');
        continue;
      }
      try {
        final json = jsonDecode(item.source!);
        if (json is! Map<String, dynamic>) {
          throw const FormatException('評価記録の先頭構造が正しくありません。');
        }
        final evidence = PreferenceEvidence.fromJson(json, store.validator);
        await store.append(evidence);
        if (known.add(evidence.id)) {
          added++;
        } else {
          existing++;
        }
      } catch (e) {
        final reason = e is FormatException
            ? e.message
            : e is FeedbackValidationException
            ? e.message
            : e is StateError
            ? e.message
            : '端末へ保存できませんでした。';
        failures.add('${item.name}：$reason');
      }
    }
    importErrors = List.unmodifiable(failures);
    importMessage =
        '$added件を追加、$existing件は取込済み、${failures.length}件を拒否しました。Driveの元ファイルは変更していません。';
  });

  Future<bool> exportEvidence() => _run(() async {
    final platform = archive;
    final root = archiveRoot;
    if (platform == null || root == null) {
      throw StateError('Driveのアプリ用フォルダを選択してください。');
    }
    final current = await store.load();
    var created = 0;
    var existing = 0;
    archiveMessage = null;
    try {
      for (final evidence in current.evidence) {
        if (await platform.append(root, evidence)) {
          created++;
        } else {
          existing++;
        }
      }
      archiveMessage =
          '$created件をDrive保存先へ追記、$existing件は保存済みです。クラウドへの同期はDriveで確認してください。';
    } catch (_) {
      archiveMessage =
          '$created件を追記、$existing件は保存済み。残りは保存結果を確認できませんでした。再実行時も既存ファイルを上書きしません。';
      rethrow;
    }
  });

  Future<bool> record(
    Map<String, dynamic> feedback, {
    required Set<String> categories,
    Map<String, int> confirmedIntents = const {},
  }) => _run(() async {
    await store.record(
      feedback: feedback,
      categories: categories,
      confirmedIntents: confirmedIntents,
      now: _now(),
    );
  });

  Future<bool> decide(
    PreferenceCandidate candidate, {
    required bool accept,
    required int expectedRevision,
  }) => _run(() async {
    await store.decide(
      candidate,
      accept: accept,
      expectedRevision: expectedRevision,
      now: _now(),
    );
  });

  Future<bool> initialize() => _run(() async {
    final current = await store.load();
    if (current.profile == null) {
      await store.initialize(newPreferenceIdentifier('profile'), _now());
    }
  });

  Future<bool> registerExplicit({
    required PreferenceScope scope,
    required String dimension,
    required int direction,
    required String declaration,
    required int expectedRevision,
  }) => _run(() async {
    await store.registerExplicit(
      scope: scope,
      dimension: dimension,
      direction: direction,
      declaration: declaration,
      expectedRevision: expectedRevision,
      now: _now(),
    );
  });

  Future<void> _commitProfile(String root, ProfileHistoryRecord record) async {
    final writer = profileWriter!;
    try {
      final verified = await writer.commit(root, record);
      _checkHistoryCache(verified, root, await profileCache!.load());
      cachedProfile = await profileCache!.save(
        root,
        canonicalPreferenceJson(verified.head.result.toJson()),
        historyRecordId: verified.head.id,
        historyRecordDigest: historyRecordDigest(verified.head),
      );
      await writer.acknowledge(root, record.id);
      profileMessage = '好みの更新をDrive履歴へ保存し、読み戻して確認しました。クラウド同期はDriveで確認してください。';
    } finally {
      hasPendingProfileWrite = await writer.pending() != null;
    }
  }

  Future<bool> startDriveHistory({
    required String expectedRoot,
    CookingProfile? legacy,
  }) => _run(() async {
    if (archiveRoot != expectedRoot ||
        profileWriter == null ||
        profileCache == null) {
      throw StateError('Driveの接続先が変わっています。再読込してください。');
    }
    final profile =
        legacy ??
        CookingProfile.create(newPreferenceIdentifier('profile'), _now());
    final record = ProfileHistoryRecord.bootstrap(
      profile,
      id: newPreferenceIdentifier('bootstrap'),
      validator: store.validator,
    );
    await _commitProfile(expectedRoot, record);
  });

  Future<bool> publishExplicit(
    Map<String, dynamic> preference, {
    required String expectedRoot,
    required String expectedHeadId,
  }) => _run(() async {
    final writer = profileWriter;
    if (archiveRoot != expectedRoot ||
        writer == null ||
        profileCache == null ||
        preference['source_kind'] != 'explicit_user') {
      throw StateError('Drive接続と反映する好みを再確認してください。');
    }
    final history = await writer.read(expectedRoot);
    if (history == null || history.head.id != expectedHeadId) {
      throw StateError('Driveの好みが更新されています。再読込してください。');
    }
    await _checkConfirmedPreference(
      preference,
      history,
      expectedRoot,
      expectedHeadId,
    );
    final rawScope = preference['scope'] as Map<String, dynamic>;
    final operation = PreferenceOperation.explicit(
      id: newPreferenceIdentifier('operation'),
      baseRevision: history.head.result.revision,
      now: _now(),
      scope: PreferenceScope(
        PreferenceScopeKind.values.byName(rawScope['kind'] as String),
        rawScope['value'] as String,
      ),
      dimension: preference['dimension'] as String,
      direction: preference['direction'] as int,
      declaration: preference['declaration'] as String,
    );
    await _commitProfile(
      expectedRoot,
      ProfileHistoryRecord.update(
        history.head,
        operation,
        validator: store.validator,
      ),
    );
  });

  void _checkHistoryCache(
    ProfileHistory history,
    String root,
    CachedCookingProfile? previous,
  ) {
    if (previous?.root != root || previous?.historyRecordId == null) return;
    final known = history.records
        .where((r) => r.id == previous!.historyRecordId)
        .firstOrNull;
    if (known == null) throw StateError('以前に確認したProfile履歴が欠けています。既存の記録を保持します。');
    if (canonicalPreferenceJson(known.result.toJson()) !=
            canonicalPreferenceJson(previous!.profile.toJson()) ||
        (previous.historyRecordDigest != null &&
            previous.historyRecordDigest != historyRecordDigest(known))) {
      throw StateError('以前に確認したProfile履歴の内容が変わっています。既存の記録を保持します。');
    }
  }

  Future<void> _checkConfirmedPreference(
    Map<String, dynamic> preference,
    ProfileHistory history,
    String root,
    String expectedHeadId,
  ) async {
    final cached = cachedProfile;
    _checkHistoryCache(history, root, cached);
    if (cached?.root != root ||
        cached?.historyRecordId != expectedHeadId ||
        canonicalPreferenceJson(cached!.profile.toJson()) !=
            canonicalPreferenceJson(history.head.result.toJson())) {
      throw StateError('確認したDriveの好みと現在の内容が違います。再読込してください。');
    }
    final local =
        (await store.load()).profile?.toJson()['preferences'] as List?;
    if (local == null ||
        !local.any(
          (p) =>
              canonicalPreferenceJson(p) == canonicalPreferenceJson(preference),
        )) {
      throw StateError('端末で登録した好みが変更されています。再確認してください。');
    }
  }

  Future<bool> publishCandidate(
    Map<String, dynamic> preference, {
    required String expectedRoot,
    required String expectedHeadId,
  }) => _run(() async {
    final writer = profileWriter;
    if (writer == null ||
        profileCache == null ||
        archiveRoot != expectedRoot ||
        preference['source_kind'] == 'explicit_user') {
      throw StateError('Drive接続と反映する好みを再確認してください。');
    }
    final history = await writer.read(expectedRoot);
    if (history == null || history.head.id != expectedHeadId) {
      throw StateError('Driveの好みが更新されています。再読込してください。');
    }
    await _checkConfirmedPreference(
      preference,
      history,
      expectedRoot,
      expectedHeadId,
    );
    final rawScope = preference['scope'] as Map<String, dynamic>;
    final ids = (preference['feedback_ids'] as List).cast<String>().toSet();
    final rows = (await store.load()).evidence
        .where((e) => ids.contains(e.id))
        .toList();
    final previous = history.records
        .map((r) => r.operation?.decision)
        .whereType<PreferenceCandidate>()
        .toList();
    final candidate = const PreferenceCandidateEngine()
        .propose(
          rows,
          scope: PreferenceScope(
            PreferenceScopeKind.values.byName(rawScope['kind'] as String),
            rawScope['value'] as String,
          ),
          previous: previous,
        )
        .where(
          (c) =>
              c.dimension == preference['dimension'] &&
              c.direction == preference['direction'] &&
              c.evidenceIds.length == ids.length &&
              ids.containsAll(c.evidenceIds),
        )
        .firstOrNull;
    if (candidate == null) {
      throw StateError('候補の根拠が変わったか、同じ根拠が既にDriveへ反映されています。再確認してください。');
    }
    final operation = PreferenceOperation.candidate(
      candidate.decide(PreferenceCandidateStatus.accepted),
      id: newPreferenceIdentifier('operation'),
      baseRevision: history.head.result.revision,
      now: _now(),
    );
    await _commitProfile(
      expectedRoot,
      ProfileHistoryRecord.update(
        history.head,
        operation,
        validator: store.validator,
        evidence: rows,
        previous: previous,
      ),
    );
  });

  Future<bool> retryProfileWrite() => _run(() async {
    final writer = profileWriter;
    if (writer == null || profileCache == null) {
      throw StateError('Drive履歴の送信は利用できません。');
    }
    final pending = await writer.pending();
    if (pending == null) {
      hasPendingProfileWrite = false;
      return;
    }
    if (pending.root != archiveRoot) {
      throw StateError('確認待ちの更新を作成したDrive保存先へ再接続してください。');
    }
    await _commitProfile(pending.root, pending.record);
  });
}
