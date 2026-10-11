import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'siwc_contract.dart';

/// Display fixed labels and an OS number, never exception text/addresses.
String safeSocketFailure(SocketException error) {
  final description = error.message.startsWith('Failed host lookup:')
      ? '接続先の名前を確認できません。ネット接続を確認して再接続してください。'
      : '通信に接続できません。ネット接続を確認して再接続してください。';
  final code = error.osError?.errorCode;
  return code == null || code == OSError.noErrorCode
      ? description
      : '$description（通信診断: OS $code）';
}

String safeNetworkFailure(Object error) => switch (error) {
  SocketException() => safeSocketFailure(error),
  HandshakeException() => '安全な通信を確立できません。（通信診断: TLS）',
  TimeoutException() => '通信が時間切れになりました。（通信診断: Timeout）',
  HttpException() => 'HTTP通信の応答を受け取れませんでした。（通信診断: HTTP）',
  FormatException() => '回答の形式を確認できません。（通信診断: Format）',
  _ => '処理を完了できません。秘密情報を表示せず停止しました。',
};

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
  HttpSiwcNetwork({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }
  HttpClient _client;

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
    final payload = utf8.encode(jsonEncode(body));
    request.contentLength = payload.length;
    request.add(payload);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _json(response);
    }
    final mime = response.headers.contentType?.mimeType.toLowerCase();
    // Some successful responses omit Content-Type. They still must pass the
    // bounded SSE parser and a validated response.completed; never infer JSON.
    if (mime != null && mime != 'text/event-stream') {
      final kind = switch (mime) {
        'application/json' => 'JSON',
        'text/html' => 'HTML',
        _ => 'その他',
      };
      cancel();
      throw SiwcFailure(
        'ストリーム回答ではありません。（HTTP ${response.statusCode} / 応答: $kind）',
      );
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
