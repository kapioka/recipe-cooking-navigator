import 'dart:convert';
import 'dart:io';

/// Local conditions only. Credentials and generated answers never enter this file.
class RecipeCreationStore {
  RecipeCreationStore([this.file]);
  final File? file;
  Map<String, dynamic> _data = {};
  Future<void>? _tail;

  Future<Map<String, dynamic>> load() async {
    if (file != null && await file!.exists()) {
      final value = jsonDecode(await file!.readAsString());
      if (value is! Map<String, dynamic>) throw const FormatException();
      _data = value;
    }
    return Map.of(_data);
  }

  Future<void> update(String key, Object? value) {
    final next = (_tail ?? Future<void>.value()).catchError((Object _) {}).then(
      (_) async {
        final updated = {..._data, key: value};
        if (file case final target?) {
          await target.parent.create(recursive: true);
          final temp = File('${target.path}.tmp');
          await temp.writeAsString(jsonEncode(updated), flush: true);
          await temp.rename(target.path);
        }
        _data = updated;
      },
    );
    _tail = next;
    return next.whenComplete(() {
      if (identical(_tail, next)) _tail = null;
    });
  }
}
