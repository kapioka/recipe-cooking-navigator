import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/preference_evidence.dart';
import '../domain/profile_history.dart';

class FeedbackArchiveItem {
  const FeedbackArchiveItem(this.name, {this.source, this.error});
  final String name;
  final String? source;
  final String? error;
}

abstract class FeedbackArchivePlatform {
  Future<String?> selectRoot();
  Future<String?> loadRoot();
  Future<String?> readProfile(String root);
  Future<List<FeedbackArchiveItem>> readEvidence(String root);
  Future<List<FeedbackArchiveItem>> readHistory(String root);
  Future<bool> append(String root, PreferenceEvidence evidence);
  Future<bool> appendHistory(String root, ProfileHistoryRecord record);
}

class AndroidFeedbackArchivePlatform implements FeedbackArchivePlatform {
  const AndroidFeedbackArchivePlatform([
    this.channel = const MethodChannel('recipe/feedback_archive'),
  ]);
  final MethodChannel channel;
  static const timeout = Duration(seconds: 30);
  @override
  Future<bool> appendHistory(String root, ProfileHistoryRecord record) async {
    final result = await channel
        .invokeMethod<String>('appendHistory', {
          'root': root,
          'profileId': record.result.id,
          'recordId': record.id,
          'source': canonicalPreferenceJson(record.toJson()),
        })
        .timeout(timeout);
    if (result == 'created') return true;
    if (result == 'already_exists') return false;
    throw const FormatException('Drive履歴の保存結果を確認できませんでした。');
  }

  Future<String?> _root(String method) async {
    final root = await channel.invokeMethod<String>(method);
    if (root != null &&
        (Uri.tryParse(root)?.scheme != 'content' || root.isEmpty)) {
      throw const FormatException('Driveフォルダの情報が正しくありません。');
    }
    return root;
  }

  @override
  Future<String?> selectRoot() => _root('selectRoot');
  @override
  Future<String?> loadRoot() => _root('loadRoot').timeout(timeout);
  @override
  Future<String?> readProfile(String root) => channel
      .invokeMethod<String>('readProfile', {'root': root})
      .timeout(timeout);
  @override
  Future<List<FeedbackArchiveItem>> readEvidence(String root) =>
      _readItems('readEvidence', root);
  @override
  Future<List<FeedbackArchiveItem>> readHistory(String root) =>
      _readItems('readHistory', root);
  Future<List<FeedbackArchiveItem>> _readItems(
    String method,
    String root,
  ) async {
    final raw = await channel
        .invokeMethod<Object>(method, {'root': root})
        .timeout(timeout);
    if (raw is! List || raw.length > 100) {
      throw const FormatException('Driveの評価一覧が正しくありません。');
    }
    var bytes = 0;
    final result = <FeedbackArchiveItem>[];
    for (final item in raw) {
      if (item is! Map ||
          item.length != 2 ||
          item['name'] is! String ||
          (item['name'] as String).trim().isEmpty ||
          ((item['source'] is String) == (item['error'] is String))) {
        throw const FormatException('Driveの評価ファイル情報が正しくありません。');
      }
      final source = item['source'] as String?;
      if (source != null) {
        final size = utf8.encode(source).length;
        bytes += size;
        if (size > 1024 * 1024 || bytes > 5 * 1024 * 1024) {
          throw const FormatException('Driveの評価ファイルが読込上限を超えています。');
        }
      }
      result.add(
        FeedbackArchiveItem(
          item['name'] as String,
          source: source,
          error: item['error'] as String?,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  @override
  Future<bool> append(String root, PreferenceEvidence evidence) async {
    final json = evidence.toJson();
    final result = await channel
        .invokeMethod<String>('append', {
          'root': root,
          'feedbackId': evidence.id,
          'year': DateTime.parse(json['created_at'] as String)
              .toUtc()
              .year
              .toString(),
          'source': canonicalPreferenceJson(json),
        })
        .timeout(timeout);
    if (result == 'created') return true;
    if (result == 'already_exists') return false;
    throw const FormatException('Driveへの保存結果を確認できませんでした。');
  }
}
