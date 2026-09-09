import 'package:flutter/services.dart';

import '../domain/recipe_inbox.dart';

class AndroidRecipeInboxPlatform implements RecipeInboxPlatform {
  const AndroidRecipeInboxPlatform([
    this._channel = const MethodChannel('recipe/inbox'),
  ]);

  final MethodChannel _channel;

  @override
  Future<RecipeInboxFolder?> selectFolder() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'selectFolder',
      );
      if (result == null) {
        return null;
      }
      final treeUri = result['treeUri'];
      final displayName = result['displayName'];
      if (treeUri is! String ||
          treeUri.isEmpty ||
          displayName is! String ||
          displayName.isEmpty) {
        throw const RecipeInboxException(
          'invalid_response',
          '選択したInboxフォルダの情報を確認できませんでした。',
        );
      }
      return RecipeInboxFolder(treeUri: treeUri, displayName: displayName);
    } on PlatformException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<List<RecipeInboxFile>> readFiles(RecipeInboxFolder folder) async {
    try {
      final result = await _channel.invokeListMethod<Object?>(
        'scan',
        <String, Object?>{'treeUri': folder.treeUri},
      );
      return (result ?? const <Object?>[])
          .map((item) {
            if (item is! Map<Object?, Object?>) {
              throw const RecipeInboxException(
                'invalid_response',
                'Inboxの読み取り結果を確認できませんでした。',
              );
            }
            final documentId = item['documentId'];
            final name = item['name'];
            final source = item['source'];
            final sha256 = item['sha256'];
            final readError = item['readError'];
            if (documentId is! String ||
                documentId.isEmpty ||
                name is! String) {
              throw const RecipeInboxException(
                'invalid_response',
                'Inbox内のファイル情報を確認できませんでした。',
              );
            }
            return RecipeInboxFile(
              documentId: documentId,
              name: name,
              source: source is String ? source : null,
              sha256: sha256 is String ? sha256 : null,
              readError: readError is String ? readError : null,
            );
          })
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw _translate(error);
    }
  }

  RecipeInboxException _translate(PlatformException error) {
    final message = switch (error.code) {
      'permission_lost' => 'Inboxフォルダのアクセス権が失われました。もう一度選択してください。',
      'folder_unavailable' => 'Inboxフォルダを読み込めませんでした。接続状態を確認してください。',
      'selection_failed' => 'Inboxフォルダを選択できませんでした。',
      'busy' => 'フォルダ選択の処理中です。',
      _ => 'Inboxを利用できませんでした。もう一度お試しください。',
    };
    return RecipeInboxException(error.code, message, error);
  }
}
