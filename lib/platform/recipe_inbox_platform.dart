import 'package:flutter/services.dart';

import '../domain/recipe_inbox.dart';

class AndroidRecipeInboxPlatform implements RecipeInboxPlatform {
  const AndroidRecipeInboxPlatform([
    this._channel = const MethodChannel('recipe/inbox'),
  ]);

  final MethodChannel _channel;

  static const _scanTimeout = Duration(seconds: 30);
  static const _releaseTimeout = Duration(seconds: 10);

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
      final parsedTreeUri = Uri.tryParse(treeUri);
      if (parsedTreeUri == null || parsedTreeUri.scheme != 'content') {
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
      final result = await _channel
          .invokeListMethod<Object?>('scan', <String, Object?>{
            'treeUri': folder.treeUri,
          })
          .timeout(
            _scanTimeout,
            onTimeout: () => throw const RecipeInboxException(
              'timeout',
              'Inboxの確認が時間内に完了しませんでした。単一ファイル取込を利用できます。',
            ),
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

  @override
  Future<void> releaseFolder(RecipeInboxFolder folder) async {
    try {
      await _channel
          .invokeMethod<void>('releaseFolder', <String, Object?>{
            'treeUri': folder.treeUri,
          })
          .timeout(
            _releaseTimeout,
            onTimeout: () => throw const RecipeInboxException(
              'timeout',
              '以前のInboxフォルダのアクセス権を解除できませんでした。',
            ),
          );
    } on PlatformException catch (error) {
      throw _translate(error);
    }
  }

  RecipeInboxException _translate(PlatformException error) {
    final message = switch (error.code) {
      'permission_lost' => 'Inboxフォルダのアクセス権が失われました。もう一度選択してください。',
      'folder_unavailable' => 'Inboxフォルダを読み込めませんでした。接続状態を確認してください。',
      'selection_failed' => 'Inboxフォルダを選択できませんでした。',
      'unsupported_provider' => 'Google DriveのInboxフォルダを選択してください。',
      'wrong_folder' => 'Google Drive内の「Inbox」フォルダを選択してください。',
      'timeout' => 'Inboxの処理が時間内に完了しませんでした。',
      'cancelled' => 'Inboxの処理を中止しました。',
      'release_failed' => '以前のInboxフォルダのアクセス権を解除できませんでした。',
      'busy' => 'フォルダ選択の処理中です。',
      _ => 'Inboxを利用できませんでした。もう一度お試しください。',
    };
    return RecipeInboxException(error.code, message, error);
  }
}
