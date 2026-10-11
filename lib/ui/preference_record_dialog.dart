import 'package:flutter/material.dart';

class PreferenceRecordChoice {
  PreferenceRecordChoice(this.category, Map<String, int> intents)
    : intents = Map.unmodifiable(intents);
  final String category;
  final Map<String, int> intents;
}

class PreferenceRecordDialog extends StatefulWidget {
  const PreferenceRecordDialog({required this.dimensions, super.key});
  final Map<String, String> dimensions;
  @override
  State<PreferenceRecordDialog> createState() => _PreferenceRecordDialogState();
}

class _PreferenceRecordDialogState extends State<PreferenceRecordDialog> {
  final _category = TextEditingController();
  final _directions = <String, int>{};
  bool _categoryMissing = false;
  @override
  void dispose() {
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('好みの記録に残す'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('この調理の評価とメモを端末内に蓄積します。料理のカテゴリは自分で指定してください。'),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            key: const Key('preference_category'),
            decoration: InputDecoration(
              labelText: '料理のカテゴリ（主菜、スープなど）',
              errorText: _categoryMissing ? 'カテゴリを入力してください。' : null,
            ),
          ),
          const SizedBox(height: 12),
          const Text('次回の味の希望（任意）。ここで明示した方向を候補判定に使います。'),
          for (final dimension in widget.dimensions.entries)
            DropdownButtonFormField<int>(
              key: Key('preference_intent_${dimension.key}'),
              initialValue: 0,
              decoration: InputDecoration(labelText: dimension.value),
              items: const [
                DropdownMenuItem(value: 0, child: Text('指定しない')),
                DropdownMenuItem(value: -1, child: Text('控えめにしたい')),
                DropdownMenuItem(value: 1, child: Text('強めにしたい')),
              ],
              onChanged: (value) {
                if (value == null || value == 0) {
                  _directions.remove(dimension.key);
                } else {
                  _directions[dimension.key] = value;
                }
              },
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('戻る'),
      ),
      FilledButton(
        key: const Key('confirm_archive_preference'),
        onPressed: () {
          final category = _category.text.trim();
          if (category.isEmpty) {
            setState(() => _categoryMissing = true);
            return;
          }
          Navigator.pop(context, PreferenceRecordChoice(category, _directions));
        },
        child: const Text('記録する'),
      ),
    ],
  );
}
