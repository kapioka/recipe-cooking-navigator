class RecipeInboxFolder {
  const RecipeInboxFolder({required this.treeUri, required this.displayName});

  final String treeUri;
  final String displayName;
}

class RecipeInboxFile {
  const RecipeInboxFile({
    required this.documentId,
    required this.name,
    this.source,
    this.sha256,
    this.readError,
  });

  final String documentId;
  final String name;
  final String? source;
  final String? sha256;
  final String? readError;

  bool get isReadable => source != null && sha256 != null && readError == null;
}

abstract interface class RecipeInboxPlatform {
  Future<RecipeInboxFolder?> selectFolder();

  Future<List<RecipeInboxFile>> readFiles(RecipeInboxFolder folder);
}

class RecipeInboxException implements Exception {
  const RecipeInboxException(this.code, this.message, [this.cause]);

  final String code;
  final String message;
  final Object? cause;

  bool get requiresFolderSelection =>
      code == 'not_configured' || code == 'permission_lost';

  @override
  String toString() => message;
}
