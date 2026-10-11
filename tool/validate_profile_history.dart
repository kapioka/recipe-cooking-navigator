import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:json_schema/json_schema.dart';

import 'package:recipe_cooking_navigator/domain/feedback_validator.dart';
import 'package:recipe_cooking_navigator/domain/preference_evidence.dart';
import 'package:recipe_cooking_navigator/domain/profile_history.dart';

/// Read-only bridge for Work or a local operator. Input is a complete observed
/// History directory or a JSON array of records. stdout is Profile JSON only.
Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1) {
      throw const FormatException(
        'Usage: dart run tool/validate_profile_history.dart <History directory or record-array file>',
      );
    }
    final project = File.fromUri(Platform.script).parent.parent;
    final schemas = <String, dynamic>{};
    for (final name in [
      'recipe-v2',
      'feedback-v2',
      'feedback-evidence-v1',
      'cooking-profile-v1',
      'cooking-profile-v1.1',
      'preference-candidates-v1',
      'preference-operation-v1',
      'profile-history-v1',
    ]) {
      schemas['$name.schema.json'] = jsonDecode(
        await File('${project.path}/schemas/$name.schema.json').readAsString(),
      );
    }
    final schema = JsonSchema.create(
      schemas['profile-history-v1.schema.json'],
      schemaVersion: SchemaVersion.draft2020_12,
      refProvider: RefProvider.sync(
        (ref) => schemas[Uri.parse(ref).pathSegments.last],
      ),
    );
    final validator = FeedbackValidator.fromSchemaStrings(
      feedbackSchemaSource: jsonEncode(schemas['feedback-v2.schema.json']),
      recipeSchemaSource: jsonEncode(schemas['recipe-v2.schema.json']),
    );
    final input = arguments.single;
    final kind = await FileSystemEntity.type(input, followLinks: false);
    final values = <Object?>[];
    var bytes = 0;
    Future<Object?> read(File file, int limit) async {
      final length = await file.length();
      if (length > limit || bytes + length > 5 * 1024 * 1024) {
        throw const FormatException('History input exceeds the read limit.');
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (buffer.length + chunk.length > limit ||
            bytes + buffer.length + chunk.length > 5 * 1024 * 1024) {
          throw const FormatException('History input exceeds the read limit.');
        }
        buffer.add(chunk);
      }
      bytes += buffer.length;
      return jsonDecode(utf8.decode(buffer.takeBytes()));
    }

    Future<List<FileSystemEntity>> entries(
      Directory directory,
      int limit,
    ) async {
      final found = <FileSystemEntity>[];
      await for (final entry in directory.list(followLinks: false)) {
        if (found.length >= limit) {
          throw const FormatException(
            'History directory exceeds the entry limit.',
          );
        }
        found.add(entry);
      }
      return found;
    }

    if (kind == FileSystemEntityType.file) {
      final array = await read(File(input), 5 * 1024 * 1024);
      if (array is! List || array.length > 100) {
        throw const FormatException(
          'The input must be a record array of at most 100 documents.',
        );
      }
      values.addAll(array);
    } else if (kind == FileSystemEntityType.directory) {
      final directories = await entries(Directory(input), 20);
      if (directories.length > 20 || directories.any((e) => e is! Directory)) {
        throw const FormatException(
          'History must contain at most 20 Profile directories and no loose files or links.',
        );
      }
      for (final directory in directories.cast<Directory>()) {
        final files = await entries(directory, 2000);
        if (files.length > 2000 || files.any((e) => e is! File)) {
          throw const FormatException(
            'A Profile directory has unsupported entries.',
          );
        }
        for (final file in files.cast<File>().where(
          (f) => f.path.toLowerCase().endsWith('.json'),
        )) {
          if (values.length >= 100) {
            throw const FormatException(
              'History contains more than 100 documents.',
            );
          }
          values.add(await read(file, 1024 * 1024));
        }
      }
    } else {
      throw const FormatException(
        'The History path is missing or is a symbolic link.',
      );
    }
    final records = <ProfileHistoryRecord>[];
    for (final value in values) {
      if (value is! Map<String, dynamic> ||
          utf8.encode(canonicalPreferenceJson(value)).length > 1024 * 1024 ||
          !schema.validate(value).isValid) {
        throw const FormatException(
          'A Profile history document failed Schema validation.',
        );
      }
      records.add(ProfileHistoryRecord.fromJson(value, validator));
    }
    final history = ProfileHistory.validate(records);
    stdout.writeln(canonicalPreferenceJson(history.head.result.toJson()));
  } catch (error) {
    stderr.writeln(
      error is FormatException
          ? error.message
          : 'History could not be read or validated. No Profile was emitted.',
    );
    exitCode = 2;
  }
}
