import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

typedef RecipePhotoPicker = Future<Uint8List?> Function();

Future<Uint8List?> pickRecipePhoto() async {
  const images = XTypeGroup(
    label: '料理の写真',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
    mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
  );
  final file = await openFile(acceptedTypeGroups: const [images]);
  if (file == null) return null;
  if (await file.length() > 30 * 1024 * 1024) {
    throw const FormatException('Photo exceeds the input size limit');
  }
  return file.readAsBytes();
}
