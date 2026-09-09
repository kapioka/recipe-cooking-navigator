import 'dart:convert';
import 'dart:io';

import '../domain/recipe_inbox.dart';

class RecipeInboxReceipt {
  const RecipeInboxReceipt({
    required this.documentId,
    required this.sha256,
    required this.recipeId,
    required this.revision,
  });

  final String documentId;
  final String sha256;
  final String recipeId;
  final int revision;

  String get contentKey => '$documentId\u0000$sha256';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'document_id': documentId,
    'sha256': sha256,
    'recipe_id': recipeId,
    'revision': revision,
  };

  static RecipeInboxReceipt fromJson(Map<String, dynamic> json) {
    final documentId = json['document_id'];
    final sha256 = json['sha256'];
    final recipeId = json['recipe_id'];
    final revision = json['revision'];
    if (documentId is! String ||
        documentId.isEmpty ||
        sha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        recipeId is! String ||
        recipeId.isEmpty ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Invalid inbox receipt.');
    }
    return RecipeInboxReceipt(
      documentId: documentId,
      sha256: sha256,
      recipeId: recipeId,
      revision: revision,
    );
  }
}

class RecipeInboxState {
  const RecipeInboxState({required this.folder, required this.receipts});

  final RecipeInboxFolder? folder;
  final List<RecipeInboxReceipt> receipts;

  static const empty = RecipeInboxState(
    folder: null,
    receipts: <RecipeInboxReceipt>[],
  );
}

abstract interface class RecipeInboxStateStore {
  Future<RecipeInboxState> load();

  Future<void> saveFolder(RecipeInboxFolder folder);

  Future<void> addReceipts(Iterable<RecipeInboxReceipt> receipts);
}

class RecipeInboxStateStorageException implements Exception {
  const RecipeInboxStateStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class FileRecipeInboxStateStore implements RecipeInboxStateStore {
  FileRecipeInboxStateStore(this.file);

  static const storageVersion = 1;

  final File file;

  File get _backupFile => File('${file.path}.bak');
  File get _temporaryFile => File('${file.path}.tmp');

  @override
  Future<RecipeInboxState> load() async {
    final source = await _readableSource();
    if (source == null) {
      return RecipeInboxState.empty;
    }

    try {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['storage_version'] != storageVersion ||
          decoded['receipts'] is! List<dynamic>) {
        throw const FormatException('Unsupported inbox storage structure.');
      }
      final folderValue = decoded['folder'];
      RecipeInboxFolder? folder;
      if (folderValue != null) {
        if (folderValue is! Map<String, dynamic> ||
            folderValue['tree_uri'] is! String ||
            (folderValue['tree_uri'] as String).isEmpty ||
            folderValue['display_name'] is! String ||
            (folderValue['display_name'] as String).isEmpty) {
          throw const FormatException('Invalid inbox folder.');
        }
        folder = RecipeInboxFolder(
          treeUri: folderValue['tree_uri'] as String,
          displayName: folderValue['display_name'] as String,
        );
      }
      final receipts = (decoded['receipts'] as List<dynamic>)
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid inbox receipt entry.');
            }
            return RecipeInboxReceipt.fromJson(item);
          })
          .toList(growable: false);
      return RecipeInboxState(folder: folder, receipts: receipts);
    } catch (error) {
      throw RecipeInboxStateStorageException(
        'Inboxの接続情報を安全に読み込めませんでした。データは変更していません。',
        error,
      );
    }
  }

  @override
  Future<void> saveFolder(RecipeInboxFolder folder) async {
    final current = await load();
    await _write(RecipeInboxState(folder: folder, receipts: current.receipts));
  }

  @override
  Future<void> addReceipts(Iterable<RecipeInboxReceipt> receipts) async {
    final additions = receipts.toList(growable: false);
    if (additions.isEmpty) {
      return;
    }
    final current = await load();
    final byKey = <String, RecipeInboxReceipt>{
      for (final receipt in current.receipts) receipt.contentKey: receipt,
    };
    for (final receipt in additions) {
      byKey[receipt.contentKey] = receipt;
    }
    await _write(
      RecipeInboxState(folder: current.folder, receipts: byKey.values.toList()),
    );
  }

  Future<File?> _readableSource() async {
    if (await file.exists()) {
      return file;
    }
    if (await _backupFile.exists()) {
      return _backupFile;
    }
    return null;
  }

  Future<void> _write(RecipeInboxState state) async {
    try {
      await file.parent.create(recursive: true);
      if (await _temporaryFile.exists()) {
        await _temporaryFile.delete();
      }
      final payload = const JsonEncoder.withIndent('  ')
          .convert(<String, dynamic>{
            'storage_version': storageVersion,
            'folder': state.folder == null
                ? null
                : <String, dynamic>{
                    'tree_uri': state.folder!.treeUri,
                    'display_name': state.folder!.displayName,
                  },
            'receipts': state.receipts
                .map((receipt) => receipt.toJson())
                .toList(growable: false),
          });
      await _temporaryFile.writeAsString(payload, flush: true);

      if (await file.exists()) {
        if (await _backupFile.exists()) {
          await _backupFile.delete();
        }
        await file.rename(_backupFile.path);
      }
      try {
        await _temporaryFile.rename(file.path);
      } catch (_) {
        if (!await file.exists() && await _backupFile.exists()) {
          await _backupFile.rename(file.path);
        }
        rethrow;
      }
      if (await _backupFile.exists()) {
        await _backupFile.delete();
      }
    } catch (error) {
      throw RecipeInboxStateStorageException(
        'Inboxの接続情報を端末へ保存できませんでした。',
        error,
      );
    }
  }
}
