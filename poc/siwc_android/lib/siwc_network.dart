import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'siwc_contract.dart';

abstract class SiwcNetwork {
  Future<Map<String, dynamic>> getJson(Uri uri, {String? bearer});
  Future<Map<String, dynamic>> postForm(
    Uri uri,
    Map<String, String> fields, {
    bool emptyOk = false,
  });
  Future<String> infer(String bearer, Map<String, dynamic> body);
  void cancel();
}

class HttpSiwcNetwork implements SiwcNetwork {
  HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  Future<HttpClientRequest> _open(String method, Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        (uri.host != 'auth.openai.com' && uri.host != 'api.openai.com')) {
      throw const SiwcFailure('許可されていない接続先です。');
    }
    final request = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    return request;
  }

  Future<Map<String, dynamic>> _json(
    HttpClientResponse response, {
    bool emptyOk = false,
  }) async {
    final bytes = <int>[];
    await for (final part in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(part);
      if (bytes.length > 1024 * 1024) throw const SiwcFailure('認証応答の上限を超えました。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SiwcFailure(
        '公開サービスのHTTP ${response.statusCode}エラーです。認証・利用枠・通信を確認してください。',
      );
    }
    if (emptyOk && bytes.isEmpty) return {};
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const SiwcFailure('公開サービスの応答形式が不正です。');
    }
    return decoded;
  }

  @override
  Future<Map<String, dynamic>> getJson(Uri uri, {String? bearer}) async {
    final request = await _open('GET', uri);
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    return _json(await request.close().timeout(const Duration(seconds: 30)));
  }

  @override
  Future<Map<String, dynamic>> postForm(
    Uri uri,
    Map<String, String> fields, {
    bool emptyOk = false,
  }) async {
    final request = await _open('POST', uri);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    request.write(Uri(queryParameters: fields).query);
    return _json(
      await request.close().timeout(const Duration(seconds: 30)),
      emptyOk: emptyOk,
    );
  }

  @override
  Future<String> infer(String bearer, Map<String, dynamic> body) async {
    final request = await _open('POST', Uri.parse('$resource/responses'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 ||
        response.headers.contentType?.mimeType != 'text/event-stream') {
      await _json(response);
      throw const SiwcFailure('SSE応答ではありません。');
    }
    try {
      return await collectCompletedResponse(
        response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: 40)),
      ).timeout(const Duration(minutes: 2));
    } catch (_) {
      cancel();
      rethrow;
    }
  }

  @override
  void cancel() {
    _client.close(force: true);
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  }
}
