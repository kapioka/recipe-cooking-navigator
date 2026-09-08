import 'package:flutter/material.dart';

void showAppInformationDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('このアプリについて'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recipe Cooking Navigator',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('安全に関する注意', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text(
              'このアプリおよび取り込んだレシピは、内容の正確性や安全性を保証しません。'
              '食材表示、アレルギー、交差汚染、加熱状態、火や器具の取扱い、保存方法を利用者自身で確認し、食品安全を優先してください。',
            ),
            SizedBox(height: 16),
            Text('ライセンス', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text(
              'Apache License 2.0\n'
              'Copyright 2026 kapioka\n'
              'Recipe Cooking Navigatorプロジェクトで開発されたソフトウェアです。',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('open_source_licenses_button'),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            showLicensePage(
              context: context,
              applicationName: 'Recipe Cooking Navigator',
              applicationVersion: '0.1.0',
              applicationLegalese:
                  'Copyright 2026 kapioka\n'
                  'Licensed under the Apache License 2.0\n\n'
                  'This product includes software developed as part of the\n'
                  'Recipe Cooking Navigator project.\n'
                  'https://github.com/kapioka/recipe-cooking-navigator',
            );
          },
          child: const Text('ライセンスを見る'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}
