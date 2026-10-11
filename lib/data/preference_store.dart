import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/cooking_profile.dart';
import '../domain/feedback_validator.dart';
import '../domain/preference_candidate.dart';
import '../domain/preference_evidence.dart';
import '../domain/preference_operation.dart';

class PreferenceSnapshot {
  PreferenceSnapshot({
    required Iterable<PreferenceEvidence> evidence,
    required Iterable<CookingProfile> history,
    required Iterable<PreferenceCandidate> decisions,
    Iterable<PreferenceOperation> operations = const [],
    this.legacySource,
  }) : evidence = List.unmodifiable(evidence),
       history = List.unmodifiable(history),
       decisions = List.unmodifiable(decisions),
       operations = List.unmodifiable(operations);
  final List<PreferenceEvidence> evidence;
  final List<CookingProfile> history;
  final List<PreferenceCandidate> decisions;
  final List<PreferenceOperation> operations;
  final String? legacySource;
  CookingProfile? get profile => history.isEmpty ? null : history.last;
}

/// Single-process local archive. A shared queue serializes instances for one path.
/// Drive writes and multi-device revision conflicts belong to a separate adapter.
class PreferenceStore {
  PreferenceStore(this.file, this.validator);
  final File file;
  final FeedbackValidator validator;
  static final _queues = <String, Future<void>>{};

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final key = file.absolute.path.toLowerCase();
    final prior = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    await prior;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  Future<PreferenceSnapshot> load() => _serialized(_load);

  Future<PreferenceSnapshot> _load() async {
    final backup = File('${file.path}.bak');
    final source = await file.exists() ? file : backup;
    if (!await source.exists()) {
      if (await File('${file.path}.tmp').exists()) {
        throw const FormatException('保存中断データがあります。自動初期化しません。');
      }
      return PreferenceSnapshot(evidence: [], history: [], decisions: []);
    }
    final sourceText = await source.readAsString();
    final raw = jsonDecode(sourceText);
    final legacy = raw is Map && raw['storage_version'] == 1;
    if (raw is! Map<String, dynamic> ||
        raw.length != 4 ||
        !{1, 2}.contains(raw['storage_version']) ||
        raw['evidence'] is! List ||
        raw['profile_history'] is! List ||
        raw[legacy ? 'decisions' : 'operations'] is! List) {
      throw const FormatException('好みの保存データが破損または未対応です。');
    }
    final evidence = (raw['evidence'] as List)
        .map(
          (e) => PreferenceEvidence.fromJson(
            Map<String, dynamic>.from(e as Map),
            validator,
          ),
        )
        .toList();
    final history = (raw['profile_history'] as List)
        .map(
          (e) => CookingProfile.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (evidence.map((e) => e.id).toSet().length != evidence.length) {
      throw const FormatException('根拠の重複があります。');
    }
    for (var i = 0; i < history.length; i++) {
      if (history[i].revision != i + 1 ||
          history[i].id != history.first.id ||
          (legacy &&
              history[i].toJson()['profile_schema_version'] != '1.0.0')) {
        throw const FormatException('Profileの履歴が連続していません。');
      }
    }
    final knownIds = evidence.map((e) => e.id).toSet();
    if (history.any(
      (p) => (p.toJson()['preferences'] as List).any(
        (v) =>
            v['source_kind'] != 'explicit_user' &&
            !knownIds.containsAll((v['feedback_ids'] as List).cast<String>()),
      ),
    )) {
      throw const FormatException('Profileの根拠Feedbackが欠けています。');
    }
    const PreferenceCandidateEngine().propose(
      evidence,
      scope: PreferenceScope(PreferenceScopeKind.global, '*'),
    );
    final operations = <PreferenceOperation>[];
    if (legacy) {
      var revision = 1;
      for (final item in raw['decisions'] as List) {
        final decision = PreferenceCandidate.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        final accepted = decision.status == PreferenceCandidateStatus.accepted;
        if (accepted && history.length <= revision) {
          throw const FormatException('承認したProfileの履歴が欠けています。');
        }
        operations.add(
          PreferenceOperation.candidate(
            decision,
            id: 'legacy-${history.isEmpty ? 'unknown' : history.first.id}-${operations.length + 1}',
            baseRevision: revision,
            now: accepted
                ? DateTime.parse(
                    history[revision].toJson()['updated_at'] as String,
                  )
                : null,
          ),
        );
        if (accepted) revision++;
      }
    } else {
      operations.addAll(
        (raw['operations'] as List).map(
          (e) =>
              PreferenceOperation.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      );
    }
    if (operations.map((o) => o.id).toSet().length != operations.length ||
        (history.isEmpty && operations.isNotEmpty) ||
        (history.isNotEmpty &&
            ((history.first.toJson()['preferences'] as List).isNotEmpty ||
                (history.first.toJson()['explicit_constraints'] as List)
                    .isNotEmpty ||
                history.first.toJson()['profile_schema_version'] != '1.0.0'))) {
      throw const FormatException('Profileの初期状態または操作履歴が一致しません。');
    }
    final decisions = <PreferenceCandidate>[];
    var index = 0;
    if (history.isNotEmpty) {
      var current = history.first;
      for (final operation in operations) {
        try {
          final next = operation.apply(current, evidence, decisions);
          if (operation.changesProfile) {
            index++;
            if (index >= history.length ||
                canonicalPreferenceJson(next.toJson()) !=
                    canonicalPreferenceJson(history[index].toJson())) {
              throw const FormatException('Profileの内容と操作履歴が一致しません。');
            }
            current = next;
          }
          if (operation.decision != null) decisions.add(operation.decision!);
        } on ArgumentError {
          throw const FormatException('Profileの操作履歴が正しくありません。');
        } on StateError {
          throw const FormatException('Profileの更新履歴が正しくありません。');
        }
      }
    }
    if (history.isNotEmpty && history.length != index + 1) {
      throw const FormatException('Profileの更新履歴が欠けています。');
    }
    return PreferenceSnapshot(
      evidence: evidence,
      history: history,
      decisions: decisions,
      operations: operations,
      legacySource: legacy ? sourceText : null,
    );
  }

  Future<void> append(PreferenceEvidence evidence) => _serialized(() async {
    final snapshot = await _load();
    for (final old in snapshot.evidence) {
      if (old.id != evidence.id) continue;
      if (canonicalPreferenceJson(old.toJson()) !=
          canonicalPreferenceJson(evidence.toJson())) {
        throw StateError('同じFeedback IDの内容を上書きできません。');
      }
      return;
    }
    // Also reject one cook being assigned to different recipes.
    const PreferenceCandidateEngine().propose([
      ...snapshot.evidence,
      evidence,
    ], scope: PreferenceScope(PreferenceScopeKind.global, '*'));
    await _write(
      PreferenceSnapshot(
        evidence: [...snapshot.evidence, evidence],
        history: snapshot.history,
        decisions: snapshot.decisions,
        operations: snapshot.operations,
        legacySource: snapshot.legacySource,
      ),
    );
  });

  Future<PreferenceEvidence> record({
    required Map<String, dynamic> feedback,
    required Set<String> categories,
    required Map<String, int> confirmedIntents,
    required DateTime now,
  }) => _serialized(() async {
    final snapshot = await _load();
    final payload = validator.validateDocument(feedback);
    final sortedCategories = categories.toList()..sort();
    for (final old in snapshot.evidence) {
      final json = old.toJson();
      if (canonicalPreferenceJson(json['feedback']) ==
              canonicalPreferenceJson(payload) &&
          canonicalPreferenceJson(json['categories']) ==
              canonicalPreferenceJson(sortedCategories) &&
          canonicalPreferenceJson(json['confirmed_intents']) ==
              canonicalPreferenceJson(confirmedIntents)) {
        return old;
      }
    }
    final ids = snapshot.evidence.map((e) => e.id).toSet();
    var feedbackId = newPreferenceIdentifier('feedback');
    while (ids.contains(feedbackId)) {
      feedbackId = newPreferenceIdentifier('feedback');
    }
    final evidence = PreferenceEvidence.create(
      feedbackId: feedbackId,
      createdAt: now,
      feedback: payload,
      validator: validator,
      categories: categories,
      confirmedIntents: confirmedIntents,
    );
    const PreferenceCandidateEngine().propose([
      ...snapshot.evidence,
      evidence,
    ], scope: PreferenceScope(PreferenceScopeKind.global, '*'));
    await _write(
      PreferenceSnapshot(
        evidence: [...snapshot.evidence, evidence],
        history: snapshot.history,
        decisions: snapshot.decisions,
        operations: snapshot.operations,
        legacySource: snapshot.legacySource,
      ),
    );
    return evidence;
  });

  Future<void> initialize(String profileId, DateTime now) =>
      _serialized(() async {
        final snapshot = await _load();
        if (snapshot.profile != null) throw StateError('Profileは既に存在します。');
        await _write(
          PreferenceSnapshot(
            evidence: snapshot.evidence,
            history: [CookingProfile.create(profileId, now)],
            decisions: snapshot.decisions,
            operations: snapshot.operations,
            legacySource: snapshot.legacySource,
          ),
        );
      });

  Future<void> decide(
    PreferenceCandidate proposal, {
    required bool accept,
    required int expectedRevision,
    required DateTime now,
  }) => _serialized(() async {
    final snapshot = await _load();
    final profile = snapshot.profile;
    if (profile == null || profile.revision != expectedRevision) {
      throw StateError('Profileが更新されています。再読込してください。');
    }
    final fresh = const PreferenceCandidateEngine().propose(
      snapshot.evidence,
      scope: proposal.scope,
      previous: snapshot.decisions,
    );
    if (!fresh.any(
      (candidate) =>
          canonicalPreferenceJson(candidate.toJson()) ==
          canonicalPreferenceJson(proposal.toJson()),
    )) {
      throw StateError('候補の根拠が変わりました。再集計してください。');
    }
    if (now.isBefore(
      DateTime.parse(profile.toJson()['updated_at'] as String),
    )) {
      throw ArgumentError('Profile time moved backwards.');
    }
    final decision = proposal.decide(
      accept
          ? PreferenceCandidateStatus.accepted
          : PreferenceCandidateStatus.rejected,
    );
    await _write(
      PreferenceSnapshot(
        evidence: snapshot.evidence,
        history: [
          ...snapshot.history,
          if (accept)
            profile.accept(
              proposal,
              expectedRevision: expectedRevision,
              now: now,
            ),
        ],
        decisions: [...snapshot.decisions, decision],
        operations: [
          ...snapshot.operations,
          PreferenceOperation.candidate(
            decision,
            id: newPreferenceIdentifier('operation'),
            baseRevision: expectedRevision,
            now: now,
          ),
        ],
        legacySource: snapshot.legacySource,
      ),
    );
  });

  Future<void> registerExplicit({
    required PreferenceScope scope,
    required String dimension,
    required int direction,
    required String declaration,
    required int expectedRevision,
    required DateTime now,
  }) => _serialized(() async {
    final snapshot = await _load();
    final profile = snapshot.profile;
    if (profile == null || profile.revision != expectedRevision) {
      throw StateError('Profileが更新されています。再読込してください。');
    }
    final operation = PreferenceOperation.explicit(
      id: newPreferenceIdentifier('operation'),
      baseRevision: expectedRevision,
      now: now,
      scope: scope,
      dimension: dimension,
      direction: direction,
      declaration: declaration,
    );
    final next = operation.apply(
      profile,
      snapshot.evidence,
      snapshot.decisions,
    );
    await _write(
      PreferenceSnapshot(
        evidence: snapshot.evidence,
        history: [...snapshot.history, next],
        decisions: snapshot.decisions,
        operations: [...snapshot.operations, operation],
        legacySource: snapshot.legacySource,
      ),
    );
  });

  Future<void> _write(PreferenceSnapshot snapshot) async {
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await file.parent.create(recursive: true);
    if (snapshot.legacySource != null) {
      final original = File('${file.path}.legacy-v1');
      if (await original.exists()) {
        if (await original.readAsString() != snapshot.legacySource) {
          throw StateError('旧データの保全先に別の原文があります。移行を停止しました。');
        }
      } else {
        await original.writeAsString(snapshot.legacySource!, flush: true);
      }
    }
    final data = {
      'storage_version': 2,
      'evidence': snapshot.evidence.map((e) => e.toJson()).toList(),
      'profile_history': snapshot.history.map((p) => p.toJson()).toList(),
      'operations': snapshot.operations.map((o) => o.toJson()).toList(),
    };
    await temp.writeAsString(jsonEncode(data), flush: true);
    // Keep the preceding valid generation until the new primary is installed.
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }
}
