import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:jose/jose.dart';

const issuer = 'https://auth.openai.com';
const authorizeEndpoint = '$issuer/api/accounts/authorize';
const tokenEndpoint = '$issuer/api/accounts/oauth/token';
const resource = 'https://api.openai.com/v1';
const scopes =
    'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';

enum SiwcFailureKind {
  unknown,
  authentication,
  permission,
  request,
  network,
  timeout,
  responseTooLarge,
}

class SiwcFailure implements Exception {
  const SiwcFailure(this.message, {this.kind = SiwcFailureKind.unknown});
  final String message;
  final SiwcFailureKind kind;
  @override
  String toString() => message;
}

String randomUrlToken([int count = 32]) => base64Url
    .encode(List<int>.generate(count, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

String newHostId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'urn:uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class OAuthAttempt {
  OAuthAttempt({
    required this.hostId,
    required this.port,
    this.clientId,
    this.idTokenHint,
  }) : state = randomUrlToken(),
       nonce = randomUrlToken(),
       verifier = randomUrlToken(48);

  final String hostId;
  final int port;
  final String? clientId;
  final String? idTokenHint;
  final String state;
  final String nonce;
  final String verifier;
  String get redirectUri => 'http://127.0.0.1:$port/auth/callback';
  String get challenge => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
  Uri get authorizationUri => Uri.parse(authorizeEndpoint).replace(
    queryParameters: {
      'client_id': clientId ?? 'dynamic_agent_client',
      if (clientId == null)
        'agent_name_hint': 'Recipe Cooking Navigator SIWC PoC',
      'ext_agent_host_id': hostId,
      'id_token_hint': ?idTokenHint,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': scopes,
      'resource': resource,
      'state': state,
      'nonce': nonce,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
    },
  );

  ({String code, String clientId}) validateCallback(Uri uri) {
    if (uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.port != port ||
        uri.path != '/auth/callback' ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters['state'] != state) {
      throw const SiwcFailure('認証callbackのstate・URIが一致しません。');
    }
    if (uri.queryParameters.containsKey('error')) {
      throw const SiwcFailure('認証が拒否またはキャンセルされました。');
    }
    final issued = uri.queryParameters['client_id'] ?? clientId;
    final code = uri.queryParameters['code'];
    if (issued == null ||
        issued.isEmpty ||
        issued == 'dynamic_agent_client' ||
        (clientId != null && issued != clientId) ||
        code == null ||
        code.isEmpty) {
      throw const SiwcFailure('登録client_idまたは認証codeを確認できません。');
    }
    return (code: code, clientId: issued);
  }

  Map<String, String> exchangeForm(String code, String issuedClientId) => {
    'grant_type': 'authorization_code',
    'client_id': issuedClientId,
    'code': code,
    'code_verifier': verifier,
    'redirect_uri': redirectUri,
    'resource': resource,
  };
}

Future<Map<String, dynamic>> validateIdToken({
  required String token,
  required Map<String, dynamic> jwks,
  required String clientId,
  String? nonce,
  String? subject,
  DateTime? now,
}) async {
  try {
    final keys = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(jwks));
    final jwt = await JsonWebToken.decodeAndVerify(
      token,
      keys,
      allowedArguments: ['RS256'],
    );
    final claims = jwt.claims.toJson();
    final audience = claims['aud'];
    final audiences = audience is String
        ? [audience]
        : audience is List
        ? audience
        : [];
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    if (claims['iss'] != issuer ||
        !audiences.contains(clientId) ||
        claims['exp'] is! num ||
        (claims['exp'] as num) <= current ||
        (claims['nbf'] is num && (claims['nbf'] as num) > current + 30) ||
        claims['sub'] is! String ||
        (claims['sub'] as String).isEmpty ||
        (nonce != null && claims['nonce'] != nonce) ||
        (subject != null && claims['sub'] != subject) ||
        (audiences.length > 1 && claims['azp'] != clientId)) {
      throw const SiwcFailure('ID tokenのidentity・期限・nonce検証に失敗しました。');
    }
    return Map<String, dynamic>.from(claims);
  } catch (_) {
    throw const SiwcFailure('ID tokenの署名またはidentityを検証できません。');
  }
}

Map<String, dynamic> inferenceBody(
  String model,
  String text, {
  int maxChars = 4000,
  String? instructions,
}) {
  if (model.isEmpty ||
      text.trim().isEmpty ||
      text.length + (instructions?.length ?? 0) > maxChars ||
      (instructions != null && instructions.trim().isEmpty) ||
      maxChars > 256000) {
    throw SiwcFailure('モデルと1〜$maxChars文字の確認済みテキストが必要です。');
  }
  return {
    'model': model,
    'instructions': ?instructions,
    'input': [
      {'role': 'user', 'content': text.trim()},
    ],
    'store': false,
    'stream': true,
  };
}

/// Never return a partial result as success. Supports multiline SSE data and
/// requires a completed response object, rather than an HTTP 200 or [DONE].
Future<String> collectCompletedResponse(
  Stream<String> lines, {
  int maxStreamChars = 16 * 1024 * 1024,
  int maxTextChars = 1024 * 1024,
  void Function(int streamChars, int textChars)? onCompleted,
}) async {
  final data = <String>[];
  final streamedText = StringBuffer();
  final doneText = <String>[];
  String? completedText;
  var received = 0;
  var doneTextLength = 0;
  String finish() {
    onCompleted?.call(received, completedText!.length);
    return completedText!;
  }

  void checkTextLength(int length) {
    if (length > maxTextChars) {
      throw const SiwcFailure(
        '回答本文がアプリで扱える上限を超えました。',
        kind: SiwcFailureKind.responseTooLarge,
      );
    }
  }

  void consume() {
    if (data.isEmpty) return;
    final raw = data.join('\n');
    data.clear();
    if (raw == '[DONE]') return;
    final event = jsonDecode(raw) as Map<String, dynamic>;
    final type = event['type'];
    if (type == 'response.output_text.delta') {
      final delta = event['delta'];
      if (delta is! String) throw const SiwcFailure('回答テキストのイベント形式が不正です。');
      checkTextLength(streamedText.length + delta.length);
      streamedText.write(delta);
    }
    if (type == 'response.output_text.done') {
      final text = event['text'];
      if (text is! String) throw const SiwcFailure('確定テキストのイベント形式が不正です。');
      doneTextLength += text.length;
      checkTextLength(doneTextLength);
      doneText.add(text);
    }
    if (type == 'error' ||
        type == 'response.failed' ||
        type == 'response.incomplete') {
      throw const SiwcFailure('推論が未完了です。利用枠・権限・通信状態を確認してください。');
    }
    if (type == 'response.completed') {
      if (completedText != null) throw const SiwcFailure('完了イベントが重複しました。');
      final response = event['response'];
      if (response is! Map ||
          response['status'] != 'completed' ||
          response['output'] is! List) {
        throw const SiwcFailure('推論の完了内容を検証できません。');
      }
      final parts = <String>[];
      for (final item in response['output'] as List) {
        if (item is Map &&
            item['type'] == 'message' &&
            item['content'] is List) {
          for (final content in item['content'] as List) {
            if (content is Map &&
                content['type'] == 'output_text' &&
                content['text'] is String) {
              parts.add(content['text'] as String);
            }
          }
        }
      }
      // SIWC streaming can carry text in events while the terminal object's
      // output is sparse. Match the public SDK's text-delta + completed flow.
      // These buffers are never returned unless terminal status is completed.
      completedText = parts.isNotEmpty
          ? parts.join()
          : doneText.isNotEmpty
          ? doneText.join()
          : streamedText.toString();
      checkTextLength(completedText!.length);
      if (completedText!.trim().isEmpty) {
        throw SiwcFailure(
          '完了応答にテキストがありません。（出力項目: ${(response['output'] as List).length} / 受信文字: ${streamedText.length}）',
        );
      }
    }
  }

  try {
    await for (final line in lines) {
      received += line.length;
      if (received > maxStreamChars) {
        throw const SiwcFailure(
          '回答の受信量がアプリで扱える上限を超えました。',
          kind: SiwcFailureKind.responseTooLarge,
        );
      }
      if (line.isEmpty) {
        consume();
        // response.completed is terminal. Do not wait for the HTTP connection
        // to close, which can discard a valid answer on an idle timeout.
        if (completedText != null) return finish();
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }
    consume();
    if (completedText == null) {
      if (received == 0) throw const SiwcFailure('回答の本文が空でした。完了回答は受信していません。');
      throw const SiwcFailure('response.completedを受信できませんでした。');
    }
    return finish();
  } on SiwcFailure {
    rethrow;
  } on TimeoutException {
    // Preserve transport timeouts so runtime can classify them safely.
    rethrow;
  } catch (_) {
    throw const SiwcFailure('応答形式またはストリームが不正です。');
  }
}
