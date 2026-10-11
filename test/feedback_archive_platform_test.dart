import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_evidence.dart';
import 'package:recipe_cooking_navigator/domain/profile_history.dart';
import 'package:recipe_cooking_navigator/platform/feedback_archive_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('recipe/feedback_archive_test');
  const platform = AndroidFeedbackArchivePlatform(channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('history append sends exact immutable record identifiers and confirms the result', () async {
    final validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
          .readAsStringSync(),
      recipeSchemaSource: File('schemas/recipe-v2.schema.json')
          .readAsStringSync(),
    );
    final json = (jsonDecode(
      File('examples/profile-history-explicit-example.json').readAsStringSync(),
    ) as List).last;
    final record = ProfileHistoryRecord.fromJson(
      json as Map<String, dynamic>,
      validator,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'appendHistory');
      expect(call.arguments, {
        'root': 'content://drive/tree/root',
        'profileId': record.result.id,
        'recordId': record.id,
        'source': canonicalPreferenceJson(record.toJson()),
      });
      return 'already_exists';
    });
    expect(
      await platform.appendHistory('content://drive/tree/root', record),
      isFalse,
    );
    messenger.setMockMethodCallHandler(channel, (_) async => 'unknown');
    await expectLater(
      platform.appendHistory('content://drive/tree/root', record),
      throwsFormatException,
    );
  });
  PreferenceEvidence evidence() {
    final validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: File('schemas/feedback-v2.schema.json')
          .readAsStringSync(),
      recipeSchemaSource: File('schemas/recipe-v2.schema.json')
          .readAsStringSync(),
    );
    return PreferenceEvidence.create(
      feedbackId: 'feedback-test',
      createdAt: DateTime.utc(2026, 10, 4),
      feedback: jsonDecode(
        File('examples/feedback-example.json').readAsStringSync(),
      ) as Map<String, dynamic>,
      validator: validator,
    );
  }

  test('folder cancellation is distinct from an invalid response', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await platform.selectRoot(), isNull);
    messenger.setMockMethodCallHandler(channel, (_) async => 'file:///wrong');
    await expectLater(platform.loadRoot(), throwsFormatException);
  });
  test('Evidence scan validates its envelope, count and byte limits', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readEvidence');
      expect(call.arguments, {'root': 'content://drive/tree/root'});
      return [
        {'name': '2026/one.json', 'source': '{}'},
        {'name': '2026/two.json', 'error': 'unreadable'},
      ];
    });
    final items = await platform.readEvidence('content://drive/tree/root');
    expect(items.first.source, '{}');
    expect(items.last.error, 'unreadable');
    for (final invalid in [
      [
        {'name': 'file', 'source': '{}', 'error': 'conflict'},
      ],
      List.generate(101, (_) => {'name': 'file', 'source': '{}'}),
      [
        {'name': 'file', 'source': 'a' * (1024 * 1024 + 1)},
      ],
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => invalid);
      await expectLater(
        platform.readEvidence('content://drive/tree/root'),
        throwsFormatException,
      );
    }
  });

  test('history scans use a separate bounded read-only operation', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readHistory');
      expect(call.arguments, {'root': 'content://drive/tree/root'});
      return [
        {'name': 'profile/update.json', 'source': '{}'},
      ];
    });
    expect(
      (await platform.readHistory('content://drive/tree/root')).single.source,
      '{}',
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => List.generate(101, (_) => {'name': 'x', 'source': '{}'}),
    );
    await expectLater(
      platform.readHistory('content://drive/tree/root'),
      throwsFormatException,
    );
  });
  test(
    'Profile reads are separate from Feedback writes and preserve the source',
    () async {
      final source = File('examples/cooking-profile-example.json')
          .readAsStringSync();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'readProfile');
        expect(call.arguments, {'root': 'content://drive/tree/root'});
        return source;
      });
      expect(await platform.readProfile('content://drive/tree/root'), source);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await platform.readProfile('content://drive/tree/root'), isNull);
    },
  );
  test(
    'append transfers archive envelope with unchanged Feedback and exact root',
    () async {
      final row = evidence();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'append');
        final args = call.arguments as Map;
        expect(args['root'], 'content://drive/tree/root');
        expect(args['year'], '2026');
        expect(args['feedbackId'], row.id);
        expect(jsonDecode(args['source'] as String), row.toJson());
        return 'created';
      });
      expect(await platform.append('content://drive/tree/root', row), isTrue);
    },
  );
  test('saved evidence, unavailable permissions and unknown success remain distinct', () async {
    final row = evidence();
    messenger.setMockMethodCallHandler(channel, (_) async => 'already_exists');
    expect(await platform.append('content://drive/tree/root', row), isFalse);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'permission_lost'),
    );
    await expectLater(
      platform.append('content://drive/tree/root', row),
      throwsA(isA<PlatformException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => 'pending');
    await expectLater(
      platform.append('content://drive/tree/root', row),
      throwsFormatException,
    );
  });
}
