import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/preference_controller.dart';
import 'package:recipe_cooking_navigator/data/preference_store.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_candidate.dart';
import 'package:recipe_cooking_navigator/domain/cooking_profile.dart';
import 'package:recipe_cooking_navigator/data/cooking_profile_cache_store.dart';
import 'package:recipe_cooking_navigator/data/profile_history_writer.dart';
import 'package:recipe_cooking_navigator/platform/feedback_archive_platform.dart';
import 'package:recipe_cooking_navigator/ui/preference_record_dialog.dart';
import 'package:recipe_cooking_navigator/ui/preference_screen.dart';

void main() {
  late Directory directory;
  late PreferenceController controller;
  final now = DateTime.utc(2026, 10, 4);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('preference-ui-');
    final validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
          .readAsStringSync(),
      recipeSchemaSource: File('schemas/recipe-v2.schema.json')
          .readAsStringSync(),
    );
    controller = PreferenceController(
      PreferenceStore(File('${directory.path}/profile.json'), validator),
      now: () => now,
    );
    await controller.initialize();
    for (var n = 1; n <= 3; n++) {
      final feedback = jsonDecode(
        File('examples/feedback-example.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final recipe = 'recipe-${n % 2}';
      feedback['cook_session']['id'] = 'session-$n';
      feedback['cook_session']['recipe_id'] = recipe;
      feedback['cook_session']['recipe_snapshot']['recipe']['id'] = recipe;
      feedback['recipe_snapshot']['recipe']['id'] = recipe;
      feedback['evaluation']['taste'] = [
        {'dimension': 'saltiness', 'deviation': 1, 'comment': ''},
      ];
      await controller.record(
        feedback,
        categories: {'主菜'},
        confirmedIntents: n == 1 ? {'saltiness': -1} : {},
      );
    }
    final snapshot = controller.snapshot!;
    controller.dispose();
    controller = PreferenceController(
      _WidgetPreferenceStore(snapshot, validator),
      now: () => now,
    );
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> finishStorage(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  testWidgets(
    'render and cancel never approve; explicit acceptance updates Profile',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PreferenceScreen(controller: controller)),
      );
      await finishStorage(tester);
      expect(controller.snapshot!.profile!.revision, 1);
      await tester.ensureVisible(find.text('登録する').first);
      await tester.tap(find.text('登録する').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(controller.snapshot!.profile!.revision, 1);
      await tester.tap(find.text('登録する').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_preference_decision')));
      await finishStorage(tester);
      expect(controller.snapshot!.profile!.revision, 2);
      expect(controller.proposals, isEmpty);
      expect(find.textContaining('登録済みの好み（更新 2）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('rejection keeps Profile unchanged and clears proposal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PreferenceScreen(controller: controller)),
    );
    await finishStorage(tester);
    await tester.ensureVisible(find.text('見送る').first);
    await tester.tap(find.text('見送る').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_preference_decision')));
    await finishStorage(tester);
    expect(controller.snapshot!.profile!.revision, 1);
    expect(controller.snapshot!.profile!.toJson()['preferences'], isEmpty);
    expect(controller.proposals, isEmpty);
  });
  testWidgets('record dialog requires category and returns no guessed intent', (
    tester,
  ) async {
    PreferenceRecordChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<PreferenceRecordChoice>(
                  context: context,
                  builder: (_) => const PreferenceRecordDialog(
                    dimensions: {'saltiness': '塩味'},
                  ),
                );
              },
              child: const Text('記録'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('記録'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_archive_preference')));
    await tester.pumpAndSettle();
    expect(find.text('カテゴリを入力してください。'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(
      find.byKey(const Key('preference_category')),
      ' 主菜 ',
    );
    await tester.tap(find.byKey(const Key('confirm_archive_preference')));
    await tester.pumpAndSettle();
    expect(result!.category, '主菜');
    expect(result!.intents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Drive preview and cancellation never publish; confirmation carries the observed head',
    (tester) async {
      final original = controller;
      final snapshot = original.snapshot!;
      final local = snapshot.profile!.registerExplicit(
        scope: PreferenceScope(PreferenceScopeKind.global, '*'),
        dimension: 'saltiness',
        direction: -1,
        declaration: '薄味が好き',
        expectedRevision: 1,
        now: now,
      );
      final store = _WidgetPreferenceStore(
        PreferenceSnapshot(
          evidence: snapshot.evidence,
          history: [...snapshot.history, local],
          decisions: snapshot.decisions,
        ),
        original.store.validator,
      );
      final consent = _DriveConsentController(
        store,
        CookingProfile.create('remote', now),
      );
      original.dispose();
      controller = consent;
      await tester.pumpWidget(
        MaterialApp(home: PreferenceScreen(controller: consent)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Driveへ反映'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Driveの現在値：未登録'), findsOneWidget);
      expect(consent.published, 0);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(consent.published, 0);
      await tester.tap(find.text('Driveへ反映'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_publish_explicit')));
      await tester.pumpAndSettle();
      expect(consent.published, 1);
      expect(consent.observedHead, 'head-observed');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit registration validates declaration and cancel preserves Profile',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PreferenceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('register_explicit_preference')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_explicit_preference')));
      await tester.pumpAndSettle();
      expect(find.text('対象と、好みの説明を入力してください。'), findsOneWidget);
      expect(controller.snapshot!.profile!.revision, 1);
      await tester.enterText(
        find.byKey(const Key('explicit_preference_declaration')),
        '塩味が控えめな料理が好き',
      );
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(controller.snapshot!.profile!.revision, 1);
      await tester.tap(find.byKey(const Key('register_explicit_preference')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('explicit_preference_declaration')),
        '塩味が控えめな料理が好き',
      );
      await tester.tap(find.byKey(const Key('confirm_explicit_preference')));
      await tester.pumpAndSettle();
      expect(controller.snapshot!.profile!.revision, 2);
      expect(
        controller.snapshot!.profile!.toJson()['preferences'][0]['source_kind'],
        'explicit_user',
      );
      expect(find.textContaining('自分で指定：塩味が控えめな料理が好き'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

// File transactions are exercised in preference_store_test. These widget tests
// isolate user consent and rendering from the test framework's fake I/O zone.
class _WidgetPreferenceStore extends PreferenceStore {
  _WidgetPreferenceStore(this.snapshot, FeedbackValidator validator)
    : super(File('unused'), validator);
  PreferenceSnapshot snapshot;
  @override
  Future<PreferenceSnapshot> load() async => snapshot;
  @override
  Future<void> registerExplicit({
    required PreferenceScope scope,
    required String dimension,
    required int direction,
    required String declaration,
    required int expectedRevision,
    required DateTime now,
  }) async {
    snapshot = PreferenceSnapshot(
      evidence: snapshot.evidence,
      history: [
        ...snapshot.history,
        snapshot.profile!.registerExplicit(
          scope: scope,
          dimension: dimension,
          direction: direction,
          declaration: declaration,
          expectedRevision: expectedRevision,
          now: now,
        ),
      ],
      decisions: snapshot.decisions,
    );
  }

  @override
  Future<void> decide(
    PreferenceCandidate proposal, {
    required bool accept,
    required int expectedRevision,
    required DateTime now,
  }) async {
    final profile = snapshot.profile!;
    if (profile.revision != expectedRevision) throw StateError('stale');
    snapshot = PreferenceSnapshot(
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
      decisions: [
        ...snapshot.decisions,
        proposal.decide(
          accept
              ? PreferenceCandidateStatus.accepted
              : PreferenceCandidateStatus.rejected,
        ),
      ],
    );
  }
}

class _DriveConsentController extends PreferenceController {
  _DriveConsentController(this.memory, CookingProfile remote)
    : super(
        memory,
        archive: const AndroidFeedbackArchivePlatform(),
        profileWriter: ProfileHistoryWriter(
          File('unused-outbox'),
          memory.validator,
          const AndroidFeedbackArchivePlatform(),
        ),
      ) {
    archiveRoot = 'content://drive/tree/root';
    cachedProfile = CachedCookingProfile(
      archiveRoot!,
      remote,
      historyRecordId: 'head-observed',
    );
  }
  final _WidgetPreferenceStore memory;
  int published = 0;
  String? observedHead;
  @override
  PreferenceSnapshot get snapshot => memory.snapshot;
  @override
  Future<bool> load() async => true;
  @override
  Future<bool> publishExplicit(
    Map<String, dynamic> preference, {
    required String expectedRoot,
    required String expectedHeadId,
  }) async {
    published++;
    observedHead = expectedHeadId;
    return true;
  }
}
