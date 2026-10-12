import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract interface class RecipePhotoStore {
  Future<Uint8List?> read(String recipeId);
  Future<void> save(String recipeId, Uint8List? png);
}

class MemoryRecipePhotoStore implements RecipePhotoStore {
  final _photos = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String recipeId) async => _photos[recipeId];
  @override
  Future<void> save(String recipeId, Uint8List? png) async {
    if (png == null) {
      _photos.remove(recipeId);
    } else {
      _photos[recipeId] = Uint8List.fromList(png);
    }
  }
}

/// App-owned thumbnails, separate from Recipe/Feedback JSON and original photos.
class FileRecipePhotoStore implements RecipePhotoStore {
  FileRecipePhotoStore(this.directory);
  final Directory directory;
  static const maxBytes = 2 * 1024 * 1024;
  File _file(String id) {
    if (id.isEmpty) throw const FormatException('Missing recipe identity');
    final name = sha256.convert(utf8.encode(id)).toString();
    return File('${directory.path}/$name.png');
  }

  void _validate(Uint8List png) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (png.length > maxBytes ||
        png.length < signature.length ||
        !List.generate(
          signature.length,
          (i) => png[i] == signature[i],
        ).every((v) => v)) {
      throw const FormatException('Invalid photo thumbnail');
    }
  }

  @override
  Future<Uint8List?> read(String recipeId) async {
    final target = _file(recipeId);
    final backup = File('${target.path}.bak');
    final source = await target.exists() ? target : backup;
    if (!await source.exists()) return null;
    if (await source.length() > maxBytes) {
      throw const FormatException('Photo too large');
    }
    final bytes = await source.readAsBytes();
    _validate(bytes);
    return bytes;
  }

  @override
  Future<void> save(String recipeId, Uint8List? png) async {
    final target = _file(recipeId);
    final backup = File('${target.path}.bak');
    final temp = File('${target.path}.tmp');
    if (png == null) {
      // Remove recovery data first so an interrupted removal cannot resurrect it.
      if (await backup.exists()) await backup.delete();
      if (await temp.exists()) await temp.delete();
      if (await target.exists()) await target.delete();
      return;
    }
    _validate(png);
    await directory.create(recursive: true);
    await temp.writeAsBytes(png, flush: true);
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    }
    try {
      await temp.rename(target.path);
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
    // A cleanup failure does not make a committed photo save fail.
    try {
      if (await backup.exists()) await backup.delete();
    } catch (_) {}
  }
}
