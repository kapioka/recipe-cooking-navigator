import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:rcn_siwc_poc/siwc_contract.dart';

void main() {
  List<String> completedLines(String text) => [
    'data: ${jsonEncode({
      'type': 'response.completed',
      'response': {
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          },
        ],
      },
    })}',
    '',
  ];

  test('recipe stream can exceed the old PoC limit without a large answer', () async {
    final lines = [
      for (var i = 0; i < 350; i++) ...[
        'data: ${jsonEncode({'type': 'response.in_progress', 'padding': 'a' * 4096})}',
        '',
      ],
      ...completedLines('completed recipe'),
    ];
    expect(lines.join().length, greaterThan(1024 * 1024));
    expect(
      await collectCompletedResponse(Stream.fromIterable(lines)),
      'completed recipe',
    );
  });

  test('completed answer returns while the HTTP stream remains open', () async {
    var cancelled = false;
    final stream = StreamController<String>(onCancel: () => cancelled = true);
    final pending = collectCompletedResponse(stream.stream);
    for (final line in completedLines('completed')) {
      stream.add(line);
    }
    try {
      expect(await pending.timeout(const Duration(seconds: 1)), 'completed');
      expect(cancelled, true);
    } finally {
      await stream.close();
    }
  });

  test(
    'stream and text budgets remain bounded and never return a partial answer',
    () async {
      for (final lines in [
        ['data: {"type":"response.output_text.delta","delta":"four"}', ''],
        ['data: {"type":"response.output_text.done","text":"four"}', ''],
        completedLines('four'),
      ]) {
        await expectLater(
          collectCompletedResponse(Stream.fromIterable(lines), maxTextChars: 3),
          throwsA(
            isA<SiwcFailure>().having(
              (e) => e.kind,
              'kind',
              SiwcFailureKind.responseTooLarge,
            ),
          ),
        );
      }
      await expectLater(
        collectCompletedResponse(
          Stream.fromIterable(completedLines('small')),
          maxStreamChars: 8,
        ),
        throwsA(
          isA<SiwcFailure>().having(
            (e) => e.kind,
            'kind',
            SiwcFailureKind.responseTooLarge,
          ),
        ),
      );
      await expectLater(
        collectCompletedResponse(
          Stream<String>.error(TimeoutException('secret-request')),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

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

  test('recipe format instructions are explicit and bounded', () {
    final body = inferenceBody(
      'detected-model',
      '{"wish":"egg"}',
      instructions: 'Return Recipe JSON only.',
    );
    expect(body['instructions'], 'Return Recipe JSON only.');
    expect(body['input'], [
      {'role': 'user', 'content': '{"wish":"egg"}'},
    ]);
    expect(body.containsKey('text'), isFalse);
    expect(body['store'], isFalse);
    expect(body['stream'], isTrue);
    expect(body.containsKey('max_output_tokens'), isFalse);
    expect(
      () => inferenceBody(
        'model',
        'short',
        instructions: 'oversize',
        maxChars: 8,
      ),
      throwsA(isA<SiwcFailure>()),
    );
  });

  test('stream text is retained but requires a validated completion', () async {
    final delta =
        'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'こんにちは'})}';
    final done =
        'data: ${jsonEncode({'type': 'response.output_text.done', 'text': 'こんにちは'})}';
    final completed =
        'data: ${jsonEncode({
          'type': 'response.completed',
          'response': {'status': 'completed', 'output': []},
        })}';
    for (final textEvents in [
      [delta, ''],
      [delta, '', done, ''],
    ]) {
      expect(
        await collectCompletedResponse(
          Stream.fromIterable([...textEvents, completed, '']),
        ),
        'こんにちは',
      );
      await expectLater(
        collectCompletedResponse(Stream.fromIterable(textEvents)),
        throwsA(isA<SiwcFailure>()),
      );
      await expectLater(
        collectCompletedResponse(
          Stream.fromIterable([
            ...textEvents,
            'data: {"type":"response.failed"}',
            '',
          ]),
        ),
        throwsA(isA<SiwcFailure>()),
      );
    }
    final full =
        'data: ${jsonEncode({
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'こんにちは'},
                ],
              },
            ],
          },
        })}';
    expect(
      await collectCompletedResponse(
        Stream.fromIterable([delta, '', done, '', full, '']),
      ),
      'こんにちは',
    );
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
    ]) {
      await expectLater(
        collectCompletedResponse(Stream.fromIterable(lines)),
        throwsA(isA<SiwcFailure>()),
      );
    }
  });
}
