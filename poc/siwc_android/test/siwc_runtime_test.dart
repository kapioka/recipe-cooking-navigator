import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:rcn_siwc_poc/siwc_contract.dart';
import 'package:rcn_siwc_poc/siwc_network.dart';
import 'package:rcn_siwc_poc/siwc_runtime.dart';

class FakePlatform implements PocPlatform {
  String? saved;
  String? speech;
  Uri? auth;
  String? callbackPage;
  String? callbackType;
  @override
  Future<String?> readSecure() async => saved;
  @override
  Future<void> writeSecure(String document) async {
    saved = document;
  }

  @override
  Future<String?> dictate() async => speech;
  @override
  Future<void> openBrowser(String url) async {
    auth = Uri.parse(url);
    final q = auth!.queryParameters;
    final callback = Uri.parse(q['redirect_uri']!).replace(
      queryParameters: {
        'state': q['state']!,
        'code': 'fake-code',
        'client_id': 'issued',
      },
    );
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(callback)).close();
      callbackType = response.headers.contentType?.mimeType;
      callbackPage = await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

class FakeNetwork implements SiwcNetwork {
  FakeNetwork(this.platform);
  final FakePlatform platform;
  final key = JsonWebKey.generate('RS256', keyBitLength: 2048);
  int refreshes = 0;
  int inferences = 0;
  int modelRequests = 0;
  String? refreshScope;
  bool revokeFailure = false;
  bool grant = true;
  SocketException? discoveryFailure;
  SocketException? exchangeFailure;
  String subject = 'account';
  Completer<void>? refreshHold;
  Map<String, dynamic>? sent;
  @override
  Future<Map<String, dynamic>> getJson(Uri uri, {String? bearer}) async {
    if (uri.path.endsWith('openid-configuration')) {
      if (discoveryFailure != null) throw discoveryFailure!;
      return {
        'issuer': issuer,
        'jwks_uri': '$issuer/jwks',
        'revocation_endpoint': '$issuer/revoke',
      };
    }
    if (uri.path.endsWith('jwks')) {
      final pub = key.toJson();
      return {
        'keys': [
          {'kty': pub['kty'], 'n': pub['n'], 'e': pub['e']},
        ],
      };
    }
    modelRequests++;
    return {
      'models': [
        {
          'slug': 'detected',
          'display_name': 'Detected model',
          'visibility': 'list',
        },
        {'slug': 'hidden', 'display_name': 'Hidden', 'visibility': 'hidden'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> postForm(
    Uri uri,
    Map<String, String> fields, {
    bool emptyOk = false,
  }) async {
    if (uri.path == '/revoke') {
      if (revokeFailure) throw const SiwcFailure('offline');
      return {};
    }
    if (fields['grant_type'] == 'refresh_token') {
      refreshes++;
      await refreshHold?.future;
      return {
        'access_token': 'fake-new-access',
        'refresh_token': 'fake-rotated-refresh',
        'expires_in': 3600,
        'token_type': 'Bearer',
        if (refreshScope != null) 'scope': refreshScope,
      };
    }
    expect(fields['client_id'], 'issued');
    if (exchangeFailure != null) throw exchangeFailure!;
    expect(
      fields['redirect_uri'],
      platform.auth!.queryParameters['redirect_uri'],
    );
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        'iss': issuer,
        'aud': 'issued',
        'sub': subject,
        'nonce': platform.auth!.queryParameters['nonce'],
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      }
      ..addRecipient(key, algorithm: 'RS256');
    return {
      'id_token': builder.build().toCompactSerialization(),
      'access_token': 'fake-access',
      'refresh_token': 'fake-refresh',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'scope': grant ? scopes : 'openid profile email',
    };
  }

  @override
  Future<String> infer(String bearer, Map<String, dynamic> body) async {
    inferences++;
    sent = body;
    return 'completed';
  }

  @override
  void cancel() {}
}

void main() {
  test(
    'native connection failure prevents browser auth and permits safe retry',
    () async {
      final platform = FakePlatform();
      final network = FakeNetwork(platform)
        ..discoveryFailure = const SocketException(
          'Failed host lookup: secret-host?code=secret-code',
          osError: OSError('secret OS detail', 7),
        );
      final runtime = SiwcRuntime(platform, network);
      await runtime.initialize();
      final before = platform.saved;
      await expectLater(
        runtime.signIn(),
        throwsA(
          isA<SiwcFailure>().having(
            (error) => error.message,
            'safe connection diagnosis',
            allOf(
              contains('接続確認'),
              contains('接続先の名前'),
              contains('OS 7'),
              isNot(contains('secret')),
            ),
          ),
        ),
      );
      expect(platform.auth, isNull);
      expect(platform.saved, before);
      expect(runtime.connected, false);
      network.discoveryFailure = null;
      await runtime.signIn();
      expect(runtime.canInfer, true);
    },
  );

  test('exchange socket diagnosis exposes only stage and OS number', () async {
    final platform = FakePlatform();
    final network = FakeNetwork(platform)
      ..exchangeFailure = const SocketException(
        'secret-token secret-code secret-url',
        osError: OSError('secret account address', 101),
      );
    final runtime = SiwcRuntime(platform, network);
    await runtime.initialize();
    await expectLater(
      runtime.signIn(),
      throwsA(
        isA<SiwcFailure>().having(
          (error) => error.message,
          'safe exchange diagnosis',
          allOf(
            contains('認証コードの交換'),
            contains('OS 101'),
            isNot(contains('secret')),
          ),
        ),
      ),
    );
    expect(runtime.connected, false);
    expect((jsonDecode(platform.saved!) as Map)['pending_client_id'], 'issued');
  });

  test('local loopback sign-in, protected persistence, model discovery and text only request', () async {
    final platform = FakePlatform();
    final network = FakeNetwork(platform);
    final runtime = SiwcRuntime(platform, network);
    await runtime.initialize();
    final host = (jsonDecode(platform.saved!) as Map)['host_id'];
    await runtime.signIn();
    expect(platform.callbackType, 'text/html');
    expect(platform.callbackPage, contains('アプリに戻る'));
    expect(platform.callbackPage, contains('package=com.kapioka.rcn_siwc_poc'));
    expect(platform.callbackPage, isNot(contains('fake-code')));
    expect(
      platform.callbackPage,
      isNot(contains(platform.auth!.queryParameters['state']!)),
    );
    expect(runtime.canInfer, true);
    expect(runtime.accounts.single.id, 'issued');
    expect((await runtime.listModels()).map((m) => m.slug), ['detected']);
    expect(await runtime.infer('detected', 'confirmed'), 'completed');
    expect(network.sent?['input'], [
      {'role': 'user', 'content': 'confirmed'},
    ]);
    final reopened = SiwcRuntime(platform, network);
    await reopened.initialize();
    expect(reopened.connected, true);
    expect((jsonDecode(platform.saved!) as Map)['host_id'], host);
    await reopened.signIn();
    expect(platform.auth!.queryParameters['client_id'], 'issued');
    expect(
      platform.auth!.queryParameters.containsKey('agent_name_hint'),
      false,
    );
    expect(reopened.accounts, hasLength(1));
  });

  test('identity-only consent cannot invoke plan usage', () async {
    final platform = FakePlatform();
    final network = FakeNetwork(platform)..grant = false;
    final runtime = SiwcRuntime(platform, network);
    await runtime.initialize();
    await runtime.signIn();
    expect(runtime.connected, true);
    expect(runtime.canInfer, false);
    await expectLater(
      runtime.infer('detected', 'text'),
      throwsA(isA<SiwcFailure>()),
    );
    expect(network.inferences, 0);
  });

  test('wrong returning identity preserves existing credentials', () async {
    final platform = FakePlatform();
    final network = FakeNetwork(platform);
    final runtime = SiwcRuntime(platform, network);
    await runtime.initialize();
    await runtime.signIn();
    final before = platform.saved;
    network.subject = 'other';
    await expectLater(runtime.signIn(), throwsA(isA<SiwcFailure>()));
    expect(platform.saved, before);
  });

  test(
    'reduced refresh consent blocks model discovery and inference',
    () async {
      for (final models in [true, false]) {
        final platform = FakePlatform();
        final network = FakeNetwork(platform)
          ..refreshScope = 'openid profile email';
        final runtime = SiwcRuntime(platform, network);
        await runtime.initialize();
        await runtime.signIn();
        final document = jsonDecode(platform.saved!) as Map<String, dynamic>;
        (document['profiles'] as List).single['expires_at'] = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toIso8601String();
        platform.saved = jsonEncode(document);
        final reopened = SiwcRuntime(platform, network);
        await reopened.initialize();
        await expectLater(
          models
              ? reopened.listModels()
              : reopened.infer('detected', 'confirmed'),
          throwsA(isA<SiwcFailure>()),
        );
        expect(network.refreshes, 1);
        expect(reopened.canInfer, false);
        expect(network.modelRequests, 0);
        expect(network.inferences, 0);
      }
    },
  );

  test(
    'parallel refresh coalesces and persists rotating credentials together',
    () async {
      final platform = FakePlatform();
      final network = FakeNetwork(platform);
      final runtime = SiwcRuntime(platform, network);
      await runtime.initialize();
      await runtime.signIn();
      network.refreshHold = Completer<void>();
      final a = runtime.refresh(force: true);
      final b = runtime.refresh(force: true);
      network.refreshHold!.complete();
      await Future.wait([a, b]);
      expect(network.refreshes, 1);
      final record = (jsonDecode(platform.saved!) as Map)['profiles'][0] as Map;
      expect(record['access_token'], 'fake-new-access');
      expect(record['refresh_token'], 'fake-rotated-refresh');
    },
  );

  test('disconnect clears tokens but keeps registration when remote revocation fails', () async {
    final platform = FakePlatform();
    final network = FakeNetwork(platform)..revokeFailure = true;
    final runtime = SiwcRuntime(platform, network);
    await runtime.initialize();
    await runtime.signIn();
    expect(await runtime.disconnect(), false);
    expect(runtime.connected, false);
    final record = (jsonDecode(platform.saved!) as Map)['profiles'][0] as Map;
    expect(record['client_id'], 'issued');
    expect(record.containsKey('access_token'), false);
    expect(record.containsKey('refresh_token'), false);
    expect(record.containsKey('id_token'), false);
  });
}
