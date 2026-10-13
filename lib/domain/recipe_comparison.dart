import 'dart:collection';

import 'recipe_document.dart';

class RecipeContentChange {
  const RecipeContentChange(
    this.section,
    this.label,
    this.before,
    this.after, {
    this.contentKey,
  });
  final String section, label;
  final String? before, after;
  final String? contentKey;
  String get kind => before == null
      ? '追加'
      : after == null
      ? '削除'
      : '変更';
}

/// Compare readable cooking content, not revision bookkeeping or AI claims.
class RecipeComparison {
  RecipeComparison(RecipeDocument before, RecipeDocument after)
    : beforeRevision = before.revision,
      afterRevision = after.revision {
    if (before.id != after.id) {
      throw const FormatException('同じレシピのバージョンだけを比較できます。');
    }
    final oldRows = _content(before);
    final newRows = _content(after);
    final exactKeys = newRows.map((row) => row.key).toSet();
    final byKey = {for (final row in oldRows) row.key: row};
    final byValue = <(String, String, String), Queue<_ContentRow>>{};
    for (final row in oldRows) {
      if (!exactKeys.contains(row.key)) {
        byValue
            .putIfAbsent((
              row.key.split(':').first,
              row.section,
              row.text,
            ), Queue.new)
            .add(row);
      }
    }
    final used = <_ContentRow>{};
    final result = <RecipeContentChange>[];
    for (final row in newRows) {
      var old = byKey[row.key];
      if (old == null) {
        final matches =
            byValue[(row.key.split(':').first, row.section, row.text)];
        while (matches != null &&
            matches.isNotEmpty &&
            used.contains(matches.first)) {
          matches.removeFirst();
        }
        old = matches?.isNotEmpty == true ? matches!.removeFirst() : null;
      }
      if (old != null && used.contains(old)) old = null;
      if (old != null) used.add(old);
      if (old?.text != row.text) {
        result.add(
          RecipeContentChange(
            row.section,
            row.label,
            old?.text,
            row.text,
            contentKey: row.key,
          ),
        );
      }
    }
    for (final row in oldRows.where((row) => !used.contains(row))) {
      result.add(
        RecipeContentChange(
          row.section,
          row.label,
          row.text,
          null,
          contentKey: row.key,
        ),
      );
    }
    changes = List.unmodifiable(result);
  }
  final int beforeRevision, afterRevision;
  late final List<RecipeContentChange> changes;

  RecipeContentChange? changeFor(String key) {
    for (final change in changes) {
      if (change.contentKey == key) return change;
    }
    return null;
  }

  static List<_ContentRow> _content(RecipeDocument document) {
    final data = document.recipeData;
    final context = document.contextFor(document.servings);
    String render(dynamic text) => text == null
        ? ''
        : document.renderText(text as List, context).displayText;
    String amounts(Map<String, dynamic> item) =>
        document.ingredientsFor(item, context).join('／');
    final rows = <_ContentRow>[];
    void add(String key, String section, String label, String text) {
      if (text.isNotEmpty) rows.add(_ContentRow(key, section, label, text));
    }

    add('title', '概要', '料理名', document.title);
    add('servings', '概要', '人数', '${document.servings}人分');
    add('time', '概要', '調理時間', '${document.totalTimeMinutes}分');
    add(
      'difficulty',
      '概要',
      'AIの難易度目安',
      '${document.estimatedDifficulty} / 5\n${data['estimated_difficulty']['reason']}',
    );
    add(
      'serving_adjustment',
      '概要',
      '人数変更の範囲・注意',
      '${document.minServings}〜${document.maxServings}人分\n${document.servingAdjustmentNote}',
    );
    for (final ingredient in document.ingredients) {
      add(
        'ingredient:${ingredient.id}',
        '材料',
        ingredient.name,
        '${ingredient.name}${ingredient.note == null ? '' : '\n${render(ingredient.note)}'}',
      );
    }
    for (final amount in document.amounts) {
      final quantity = amount.quantity;
      add(
        'amount:${amount.id}',
        '材料',
        '分量・${amount.label}',
        '${document.amountLine(amount.id, context)}\n用途: ${amount.label}\n'
            '${quantity['kind'] == 'measured'
                ? quantity['scaling'] == 'fixed'
                      ? '人数によらず同量'
                      : '人数に合わせて換算'
                : ''}'
            '${quantity['adjustment_note'] == null ? '' : '\n${quantity['adjustment_note']}'}',
      );
      if (amount.note != null) {
        add(
          'amount_note:${amount.id}',
          '材料',
          '分量の注意・${amount.label}',
          render(amount.note),
        );
      }
    }
    for (final (index, text) in document.overview.indexed) {
      add('overview:$index', '全体工程', '工程 ${index + 1}', render(text));
    }
    final utensilNames = <String, String>{};
    for (final utensil in data['utensils'] as List) {
      utensilNames[utensil['id'] as String] = utensil['name'] as String;
      add(
        'utensil:${utensil['id']}',
        '器具',
        utensil['name'] as String,
        '${utensil['name']} ${utensil['quantity']}個${utensil['reuse_note'] == null ? '' : '\n${render(utensil['reuse_note'])}'}',
      );
    }
    for (final (index, item) in (data['preparation'] as List).indexed) {
      add(
        'prep:${item['id']}',
        '事前準備',
        '準備 ${index + 1}',
        '準備 ${index + 1}: ${render(item['text'])}\n材料: ${amounts(Map<String, dynamic>.from(item as Map))}',
      );
    }
    var stepNumber = 0;
    for (final stage in data['stages'] as List) {
      add('stage:${stage['id']}', '調理の工程', '工程のまとまり', stage['title'] as String);
      for (final step in stage['steps'] as List) {
        stepNumber++;
        void stepRow(String field, String label, String text) => add(
          '$field:${step['id']}',
          '調理の工程',
          '工程 $stepNumber・${step['title']} / $label',
          text,
        );
        stepRow('step', '順番・工程名', '工程 $stepNumber: ${step['title']}');
        stepRow('step_stage', '工程のまとまり', stage['title'] as String);
        stepRow('instruction', '調理の説明', render(step['instruction']));
        stepRow(
          'step_amounts',
          '材料',
          amounts(Map<String, dynamic>.from(step as Map)),
        );
        stepRow('heat', '火加減', render(step['heat']));
        stepRow(
          'timer',
          'タイマー',
          step['timer_seconds'] == null ? '' : '${step['timer_seconds']}秒',
        );
        stepRow('done', '完了の目安', render(step['done_when']));
        stepRow(
          'step_utensils',
          '器具',
          (step['utensil_ids'] as List).map((id) => utensilNames[id]).join('／'),
        );
        for (final (index, task) in (step['parallel_tasks'] as List).indexed) {
          stepRow('parallel_$index', '並行作業 ${index + 1}', render(task));
        }
        stepRow('next', '次の工程', render(step['next_preview']));
      }
    }
    for (final (index, item) in (data['adjustments'] as List).indexed) {
      add(
        'adjustment:$index',
        '調整・注意',
        '調整 ${index + 1}',
        '${render(item['condition'])}\n${render(item['action'])}',
      );
    }
    add('storage', '調整・注意', '保存の注意', render(data['storage_note']));
    add('lunchbox', '調整・注意', 'お弁当の注意', render(data['lunchbox_note']));
    return rows;
  }
}

class _ContentRow {
  const _ContentRow(this.key, this.section, this.label, this.text);
  final String key, section, label, text;
}
