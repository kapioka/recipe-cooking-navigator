import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:rcn_siwc_poc/siwc_contract.dart';

void main() {
  test(
    'dynamic registration uses stable host/fresh PKCE and exact loopback',
    () {
      final host = newHostId();
      final a = OAuthAttempt(hostId: host, port: 54321);
      final b = OAuthAttempt(hostId: host, port: 12345, clientId: 'issued');
      expect(
        a.authorizationUri.queryParameters['client_id'],
        'dynamic_agent_client',
      );
      expect(a.authorizationUri.queryParameters['ext_agent_host_id'], host);
      expect(
        a.authorizationUri.queryParameters['code_challenge_method'],
        'S256',
      );
      expect(a.challenge, isNot(contains('=')));
      expect(a.state, isNot(b.state));
      expect(a.nonce, isNot(b.nonce));
      expect(a.verifier, isNot(b.verifier));
      expect(
        b.authorizationUri.queryParameters.containsKey('agent_name_hint'),
        false,
      );
      final result = a.validateCallback(
        Uri.parse(
          '${a.redirectUri}?state=${a.state}&code=code&client_id=issued',
        ),
      );
      final form = a.exchangeForm(result.code, result.clientId);
      expect(form['client_id'], 'issued');
      expect(form['redirect_uri'], a.redirectUri);
      expect(form['resource'], resource);
    },
  );

  test('wrong state, duplicate values, rejected consent, missing/different client and paths fail closed', () {
    final a = OAuthAttempt(hostId: newHostId(), port: 1455);
    for (final url in [
      '${a.redirectUri}?state=wrong&code=c&client_id=issued',
      '${a.redirectUri}?state=${a.state}&state=${a.state}&code=c&client_id=issued',
      '${a.redirectUri}?state=${a.state}&error=access_denied',
      '${a.redirectUri}?state=${a.state}&code=c',
      '${a.redirectUri}?state=${a.state}&code=c&client_id=dynamic_agent_client',
      'http://127.0.0.1:1455/callback?state=${a.state}&code=c&client_id=issued',
      'http://localhost:1455/auth/callback?state=${a.state}&code=c&client_id=issued',
    ]) {
      expect(
        () => a.validateCallback(Uri.parse(url)),
        throwsA(isA<SiwcFailure>()),
      );
    }
    final returning = OAuthAttempt(
      hostId: newHostId(),
      port: 1455,
      clientId: 'saved',
    );
    expect(
      returning
          .validateCallback(
            Uri.parse(
              '${returning.redirectUri}?state=${returning.state}&code=c',
            ),
          )
          .clientId,
      'saved',
    );
    expect(
      () => returning.validateCallback(
        Uri.parse(
          '${returning.redirectUri}?state=${returning.state}&code=c&client_id=other',
        ),
      ),
      throwsA(isA<SiwcFailure>()),
    );
  });

  test(
    'ID token signature, issuer, aud, nonce, expiry and subject are verified',
    () async {
      final key = JsonWebKey.generate('RS256', keyBitLength: 2048);
      final pub = key.toJson();
      final jwks = {
        'keys': [
          {'kty': pub['kty'], 'n': pub['n'], 'e': pub['e']},
        ],
      };
      final claims = <String, dynamic>{
        'iss': issuer,
        'aud': 'issued',
        'sub': 'account',
        'nonce': 'fresh',
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      };
      String signed(Map<String, dynamic> data, [JsonWebKey? signingKey]) {
        final builder = JsonWebSignatureBuilder()
          ..jsonContent = data
          ..addRecipient(signingKey ?? key, algorithm: 'RS256');
        return builder.build().toCompactSerialization();
      }

      Future<Map<String, dynamic>> validate(String token) => validateIdToken(
        token: token,
        jwks: jwks,
        clientId: 'issued',
        nonce: 'fresh',
        subject: 'account',
      );
      expect((await validate(signed(claims)))['sub'], 'account');
      for (final pair in [
        ('iss', 'https://invalid.example'),
        ('aud', 'other'),
        ('nonce', 'wrong'),
        ('sub', 'other'),
        ('exp', 1),
      ]) {
        await expectLater(
          validate(signed({...claims, pair.$1: pair.$2})),
          throwsA(isA<SiwcFailure>()),
        );
      }
      await expectLater(
        validate(
          signed(claims, JsonWebKey.generate('RS256', keyBitLength: 2048)),
        ),
        throwsA(isA<SiwcFailure>()),
      );
      final segments = signed(claims).split('.');
      segments[0] = base64Url
          .encode(utf8.encode('{"alg":"none"}'))
          .replaceAll('=', '');
      await expectLater(
        validate(segments.join('.')),
        throwsA(isA<SiwcFailure>()),
      );
    },
  );

  test('HTTP body uses only supported explicit text request fields', () {
    final body = inferenceBody('detected-model', 'confirmed');
    expect(body, {
      'model': 'detected-model',
      'input': [
        {'role': 'user', 'content': 'confirmed'},
      ],
      'store': false,
      'stream': true,
    });
    expect(() => inferenceBody('model', ' '), throwsA(isA<SiwcFailure>()));
  });

  test('SSE succeeds only after validated completed and rejects truncation/failure/incomplete', () async {
    final terminal = {
      'type': 'response.completed',
      'response': {
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'Hello'},
            ],
          },
        ],
      },
    };
    expect(
      await collectCompletedResponse(
        Stream.fromIterable([
          ': keepalive',
          'data: ${jsonEncode(terminal)}',
          '',
          'data: [DONE]',
          '',
        ]),
      ),
      'Hello',
    );
    for (final lines in [
      ['data: {"type":"response.output_text.delta","delta":"partial"}', ''],
      [
        'data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}',
        '',
      ],
      ['data: {"type":"response.incomplete"}', ''],
      ['data: [DONE]', ''],
      ['data: ${jsonEncode(terminal)}', '', 'data: {"type":"error"}', ''],
    ]) {
      await expectLater(
        collectCompletedResponse(Stream.fromIterable(lines)),
        throwsA(isA<SiwcFailure>()),
      );
    }
  });
}
