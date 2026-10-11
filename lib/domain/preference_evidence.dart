import 'dart:convert';
import 'dart:math';

import 'feedback_validator.dart';
import 'recipe_document.dart';
import 'session_assessment.dart';

/// An immutable archive envelope. The enclosed Feedback v2 is unchanged.
class PreferenceEvidence {
  PreferenceEvidence._(this._json);

  factory PreferenceEvidence.create({
    required String feedbackId,
    required DateTime createdAt,
    required Map<String, dynamic> feedback,
    required FeedbackValidator validator,
    Set<String> categories = const {},
    Map<String, int> confirmedIntents = const {},
  }) {
    return PreferenceEvidence.fromJson({
      'evidence_schema_version': '1.0.0',
      'type': 'feedback_evidence',
      'feedback_id': feedbackId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'categories': categories.toList()..sort(),
      'confirmed_intents': confirmedIntents,
      'feedback': feedback,
    }, validator);
  }

  factory PreferenceEvidence.fromJson(
    Map<String, dynamic> json,
    FeedbackValidator validator,
  ) {
    const keys = {
      'evidence_schema_version',
      'type',
      'feedback_id',
      'created_at',
      'categories',
      'confirmed_intents',
      'feedback',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        json.length != keys.length ||
        json['evidence_schema_version'] != '1.0.0' ||
        json['type'] != 'feedback_evidence' ||
        json['feedback_id'] is! String ||
        (json['feedback_id'] as String).trim().isEmpty ||
        json['created_at'] is! String ||
        DateTime.tryParse(json['created_at'] as String)?.isUtc != true ||
        json['categories'] is! List ||
        json['confirmed_intents'] is! Map<String, dynamic> ||
        json['feedback'] is! Map<String, dynamic>) {
      throw const FormatException('Feedback蓄積データの形式が正しくありません。');
    }
    final categories = json['categories'] as List;
    final intents = json['confirmed_intents'] as Map<String, dynamic>;
    if (categories.any((c) => c is! String || c.trim().isEmpty) ||
        categories.toSet().length != categories.length ||
        intents.entries.any(
          (e) =>
              !SessionAssessment.tasteDimensions.contains(e.key) ||
              e.value is! int ||
              !{-1, 1}.contains(e.value),
        )) {
      throw const FormatException('分類または明示した味の方向が正しくありません。');
    }
    final feedback = validator.validateDocument(
      json['feedback'] as Map<String, dynamic>,
    );
    final seen = <String>{};
    for (final taste in (feedback['evaluation'] as Map)['taste'] as List) {
      if (!seen.add((taste as Map)['dimension'] as String)) {
        throw const FormatException('同じ味の項目を重複して記録できません。');
      }
    }
    return PreferenceEvidence._(RecipeDocument.copyJson(json));
  }

  final Map<String, dynamic> _json;
  String get id => _json['feedback_id'] as String;
  Map<String, dynamic> get feedback =>
      RecipeDocument.copyJson(_json['feedback'] as Map<String, dynamic>);
  String get sessionId =>
      ((_json['feedback'] as Map)['cook_session'] as Map)['id'] as String;
  String get recipeId =>
      ((_json['feedback'] as Map)['cook_session'] as Map)['recipe_id']
          as String;
  List<String> get categories =>
      List.unmodifiable((_json['categories'] as List).cast<String>());
  Map<String, dynamic> toJson() => RecipeDocument.copyJson(_json);

  /// Free text, overall ratings and sensitive constraints are never interpreted.
  Map<String, int> get votes {
    final result = <String, int>{};
    for (final item
        in ((_json['feedback'] as Map)['evaluation'] as Map)['taste'] as List) {
      final taste = item as Map;
      final deviation = taste['deviation'] as int;
      result[taste['dimension'] as String] = -deviation.sign;
    }
    for (final item
        in (_json['confirmed_intents'] as Map<String, dynamic>).entries) {
      result[item.key] = (item.value as int) * 2;
    }
    return Map.unmodifiable(result);
  }
}

/// Stable JSON identity independent of object property order.
String canonicalPreferenceJson(Object? value) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) return item.map(sorted).toList();
    return item;
  }

  return jsonEncode(sorted(value));
}

String newPreferenceIdentifier(String prefix) {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
