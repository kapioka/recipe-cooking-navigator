import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/domain/recipe_comparison.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';

void main() {
  late RecipeValidator validator;
  late Map<String, dynamic> base, next;
  setUpAll(() async {
    validator = RecipeValidator.fromSchemaString(
      await File('schemas/recipe-v2.schema.json').readAsString(),
    );
  });
  setUp(() async {
    base = jsonDecode(
      await File('examples/recipe-example.json').readAsString(),
    ) as Map<String, dynamic>;
    next = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    next['recipe']['revision'] = 2;
    next['recipe']['parent_revision'] = 1;
  });
  RecipeComparison compare() => RecipeComparison(
    validator.validateDocument(base),
    validator.validateDocument(next),
  );

  test('revision and AI summary alone are not cooking changes', () {
    next['recipe']['revision_summary'] = ['全体を改善しました'];
    expect(compare().changes, isEmpty);
  });
  test('highlights only the changed heat, timer and safety fields', () {
    final step = next['recipe']['stages'][0]['steps'][0] as Map;
    step['heat'] = [
      {'type': 'text', 'text': '弱火'},
    ];
    step['timer_seconds'] = 150;
    next['recipe']['storage_note'] = [
      {'type': 'text', 'text': '速やかに冷蔵し、翌日中に十分再加熱する。'},
    ];
    final oldEncoded = jsonEncode(base), newEncoded = jsonEncode(next);
    final changes = compare().changes;
    expect(changes, hasLength(3));
    expect(
      changes.any((item) => item.before == '中火' && item.after == '弱火'),
      isTrue,
    );
    expect(
      changes.any((item) => item.before == '120秒' && item.after == '150秒'),
      isTrue,
    );
    expect(changes.any((item) => item.label.contains('調理の説明')), isFalse);
    expect(jsonEncode(base), oldEncoded);
    expect(jsonEncode(next), newEncoded);
  });
  test(
    'quantity changes are visible in ingredients and referenced instructions',
    () {
      next['recipe']['amounts'][0]['quantity']['value']['numerator'] = 150;
      final changes = compare().changes;
      expect(
        changes.any(
          (item) => item.section == '材料' && item.after!.contains('150g'),
        ),
        isTrue,
      );
      expect(
        changes.any(
          (item) =>
              item.label.contains('調理の説明') && item.after!.contains('150g'),
        ),
        isTrue,
      );
    },
  );
  test('additions, deletions and amount notes are explicit', () {
    next['recipe']['ingredients'].add({'id': 'pepper', 'name': 'こしょう'});
    next['recipe']['amounts'].add({
      'id': 'pepper-all',
      'ingredient_id': 'pepper',
      'label': '仕上げ',
      'quantity': {
        'kind': 'qualitative',
        'text': '少々',
        'adjustment_note': '好みで調整する',
      },
    });
    next['recipe']['stages'][0]['steps'][2]['amount_ids'].add('pepper-all');
    next['recipe']['amounts'][0]['note'] = [
      {'type': 'text', 'text': '脂身は取り除く'},
    ];
    next['recipe'].remove('storage_note');
    final changes = compare().changes;
    expect(
      changes.any((item) => item.kind == '追加' && item.after == 'こしょう'),
      isTrue,
    );
    expect(
      changes.any((item) => item.kind == '追加' && item.after == '脂身は取り除く'),
      isTrue,
    );
    expect(
      changes.any((item) => item.kind == '削除' && item.label == '保存の注意'),
      isTrue,
    );
  });
  test(
    'renaming internal IDs without changing content produces no changes',
    () {
      dynamic rename(dynamic value) {
        if (value is List) return value.map(rename).toList();
        if (value is Map) {
          return {
            for (final entry in value.entries)
              entry.key:
                  entry.key == 'id' && entry.value != base['recipe']['id'] ||
                      entry.key == 'amount_id' ||
                      entry.key == 'ingredient_id'
                  ? 'new-${entry.value}'
                  : entry.key == 'amount_ids' || entry.key == 'utensil_ids'
                  ? (entry.value as List).map((id) => 'new-$id').toList()
                  : rename(entry.value),
          };
        }
        return value;
      }

      next = jsonDecode(jsonEncode(rename(next))) as Map<String, dynamic>;
      expect(compare().changes, isEmpty);
    },
  );
  test('reordering preparations and steps is a visible change', () {
    final prep = next['recipe']['preparation'] as List;
    next['recipe']['preparation'] = prep.reversed.toList();
    final steps = next['recipe']['stages'][0]['steps'] as List;
    next['recipe']['stages'][0]['steps'] = steps.reversed.toList();
    final changes = compare().changes;
    expect(changes.where((item) => item.section == '事前準備'), hasLength(2));
    expect(
      changes.where((item) => item.label.contains('順番・工程名')),
      hasLength(2),
    );
  });
  test('rejects comparing unrelated recipes', () {
    next['recipe']['id'] = 'different-recipe';
    expect(compare, throwsFormatException);
  });
}
