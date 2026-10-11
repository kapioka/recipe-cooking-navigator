import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'siwc_contract.dart';
import 'siwc_network.dart';

abstract class PocPlatform {
  Future<String?> readSecure();
  Future<void> writeSecure(String document);
  Future<void> openBrowser(String uri);
  Future<void> waitForForeground();
  Future<String?> dictate();
}

class AndroidPocPlatform implements PocPlatform {
  static const _channel = MethodChannel('siwc/poc');
  @override
  Future<String?> readSecure() => _channel.invokeMethod<String>('readSecure');
  @override
  Future<void> writeSecure(String document) =>
      _channel.invokeMethod<void>('writeSecure', document);
  @override
  Future<void> openBrowser(String uri) =>
      _channel.invokeMethod<void>('openBrowser', uri);
  @override
  Future<void> waitForForeground() =>
      _channel.invokeMethod<void>('waitForForeground');
  @override
  Future<String?> dictate() => _channel.invokeMethod<String>('dictate');
}

/// Public SIWC adapter. Tokens stay inside this runtime/native encrypted storage;
/// only verified display labels and model slugs are exposed to the UI.
class SiwcRuntime {
  SiwcRuntime(
    this.platform,
    this.network, {
    this.returnScheme = 'rcn-siwc-poc',
    this.returnPackage = 'com.kapioka.rcn_siwc_poc',
    this.returnAppName = 'Recipe SIWC PoC',
    this.maxInputChars = 4000,
  });
  final String returnScheme;
  final String returnPackage;
  final String returnAppName;
  final int maxInputChars;
  final PocPlatform platform;
  final SiwcNetwork network;
  Map<String, dynamic> _document = {};
  HttpServer? _listener;
  Completer<Uri?>? _callback;
  Future<void>? _refreshing;
  int _epoch = 0;
  bool _ready = false;

  List<Map<String, dynamic>> get _profiles =>
      (_document['profiles'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic>? get _active {
    if (!_ready) return null;
    for (final profile in _profiles) {
      if (profile['client_id'] == _document['active_client_id']) return profile;
    }
    return null;
  }

  String? get activeClientId => _active?['client_id'] as String?;
  bool get connected => _active?['access_token'] is String;
  bool get canInfer =>
      connected &&
      (_active?['scopes'] as List? ?? []).contains(
        'chatgpt.tokens.use.direct',
      ) &&
      (_active?['scopes'] as List? ?? []).contains('resource.invoke');
  List<({String id, String label})> get accounts => !_ready
      ? []
      : [
          for (final p in _profiles)
            (id: p['client_id'] as String, label: p['label'] as String),
        ];

  Future<void> initialize() async {
    final raw = await platform.readSecure();
    if (raw == null) {
      _document = {
        'version': 1,
        'host_id': newHostId(),
        'profiles': <Map<String, dynamic>>[],
      };
      await _save();
    } else {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['host_id'] is! String ||
          decoded['profiles'] is! List) {
        throw const SiwcFailure('安全保管の形式を確認できません。自動初期化は行いません。');
      }
      _document = decoded;
      for (final p in _profiles) {
        if (p['client_id'] is! String ||
            p['subject'] is! String ||
            p['label'] is! String ||
            p['client_id'] == 'dynamic_agent_client') {
          throw const SiwcFailure('保存された登録identityが不正です。');
        }
      }
    }
    _ready = true;
  }

  Future<void> _save() => platform.writeSecure(jsonEncode(_document));
  void _check(int epoch) {
    if (!_ready || epoch != _epoch) throw const SiwcFailure('操作をキャンセルしました。');
  }

  void selectAccount(String clientId) {
    if (!accounts.any((p) => p.id == clientId)) {
      throw const SiwcFailure('登録がありません。');
    }
    cancel();
    _document['active_client_id'] = clientId;
    // The UI awaits persistSelection before starting the next request.
  }

  Future<void> persistSelection() => _save();

  Future<Map<String, dynamic>> _discovery() async {
    final metadata = await network.getJson(
      Uri.parse('$issuer/.well-known/openid-configuration'),
    );
    if (metadata['issuer'] != issuer) {
      throw const SiwcFailure('OIDC issuerが一致しません。');
    }
    return metadata;
  }

  Uri _authUri(dynamic value) {
    if (value is! String) throw const SiwcFailure('OIDC endpointがありません。');
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host != 'auth.openai.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port != 443) {
      throw const SiwcFailure('OIDC endpointを信頼できません。');
    }
    return uri;
  }

  Future<Map<String, dynamic>> _verify(
    String token,
    String clientId, {
    String? nonce,
    String? subject,
  }) async {
    final metadata = await _discovery();
    final jwks = await network.getJson(_authUri(metadata['jwks_uri']));
    return validateIdToken(
      token: token,
      jwks: jwks,
      clientId: clientId,
      nonce: nonce,
      subject: subject,
    );
  }

  Future<void> signIn({bool newAccount = false}) async {
    if (!_ready || _listener != null) throw const SiwcFailure('認証を開始できません。');
    final epoch = _epoch;
    final previous = newAccount ? null : _active;
    final pending = _document['pending_client_id'] as String?;
    final clientId = previous?['client_id'] as String? ?? pending;
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _listener = listener;
    final callback = Completer<Uri?>();
    _callback = callback;
    final attempt = OAuthAttempt(
      hostId: _document['host_id'] as String,
      port: listener.port,
      clientId: clientId,
      idTokenHint: previous?['id_token'] as String?,
    );
    listener.listen(
      (request) async {
        final host = request.headers.value(HttpHeaders.hostHeader);
        if (request.method != 'GET' ||
            request.uri.path != '/auth/callback' ||
            host != '127.0.0.1:${listener.port}' ||
            request.uri.queryParameters['state'] != attempt.state) {
          request.response.statusCode = 400;
          request.response.write('Invalid callback.');
        } else {
          request.response.headers.contentType = ContentType.html;
          request.response.headers.set('Cache-Control', 'no-store');
          request.response.headers.set('Referrer-Policy', 'no-referrer');
          request.response.write(
            '<!doctype html><html lang="ja"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>アプリに戻って接続を確認</title>'
            '<style>body{font-family:system-ui,sans-serif;line-height:1.7;'
            'max-width:32rem;margin:3rem auto;padding:0 1.25rem;}'
            'a{display:block;text-align:center;background:#176b48;color:white;'
            'padding:1rem;border-radius:.75rem;text-decoration:none;}</style>'
            '</head><body><h1>アプリに戻って接続を確認</h1>'
            '<p>ブラウザでの手続きが終わりました。接続の結果はアプリでお知らせします。</p>'
            '<a href="intent://auth-return/#Intent;scheme=$returnScheme;'
            'package=$returnPackage;end">アプリに戻る</a>'
            '<p>${const HtmlEscape().convert(returnAppName)}が開きます。</p>'
            '<p>ボタンで開かない場合は、画面端から内側へスワイプするか、'
            '画面下の「戻る」を押してアプリへ戻ってください。</p>'
            '<p>このページを再読み込みする必要はありません。</p></body></html>',
          );
          if (!callback.isCompleted) {
            callback.complete(
              Uri.parse(attempt.redirectUri).replace(query: request.uri.query),
            );
          }
        }
        await request.response.close();
      },
      onError: (_) {
        if (!callback.isCompleted) callback.complete(null);
      },
    );
    var stage = '接続確認';
    try {
      // Fail before asking the user to authenticate when native HTTPS fails.
      // This same metadata is required for the later identity verification.
      await _discovery();
      _check(epoch);
      stage = 'ブラウザ認証';
      await platform.openBrowser(attempt.authorizationUri.toString());
      final uri = await callback.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => null,
      );
      _check(epoch);
      if (uri == null) throw const SiwcFailure('認証がキャンセルまたは時間切れになりました。');
      stage = '認証結果の確認';
      final validated = attempt.validateCallback(uri);
      if (previous == null) {
        stage = '登録情報の安全保管';
        _document['pending_client_id'] = validated.clientId;
        await _save(); // Keep registration through invalid_grant, without making it active.
      }
      _check(epoch);
      // The loopback callback arrives while Chrome is foreground. Resume the
      // Android app before starting authenticated network work.
      stage = 'アプリへの復帰待ち';
      await platform.waitForForeground().timeout(const Duration(minutes: 3));
      _check(epoch);
      stage = '認証コードの交換';
      final tokens = await network.postForm(
        Uri.parse(tokenEndpoint),
        attempt.exchangeForm(validated.code, validated.clientId),
      );
      _check(epoch);
      final idToken = tokens['id_token'];
      if (idToken is! String) throw const SiwcFailure('ID tokenがありません。');
      stage = '本人確認';
      final identity = await _verify(
        idToken,
        validated.clientId,
        nonce: attempt.nonce,
        subject: previous?['subject'] as String?,
      );
      _check(epoch);
      final profile = _tokenProfile(tokens, identity, validated.clientId);
      final profiles =
          _profiles.where((p) => p['client_id'] != validated.clientId).toList()
            ..add(profile);
      final old = Map<String, dynamic>.from(_document);
      _document = {
        ..._document,
        'profiles': profiles,
        'active_client_id': validated.clientId,
      }..remove('pending_client_id');
      try {
        stage = '接続情報の安全保管';
        await _save();
      } catch (_) {
        _document = old;
        rethrow;
      }
    } on SiwcFailure catch (error) {
      throw SiwcFailure('$stage: ${error.message}');
    } on SocketException catch (error) {
      throw SiwcFailure('$stage: ${safeSocketFailure(error)}');
    } on HandshakeException {
      throw SiwcFailure('$stage: 安全な通信を確立できません。証明書検証を省略せず停止しました。');
    } on TimeoutException {
      throw SiwcFailure('$stage: 通信が時間切れになりました。再接続してください。');
    } on PlatformException {
      throw SiwcFailure('$stage: Androidの安全保管またはブラウザ連携を完了できません。');
    } catch (_) {
      throw SiwcFailure('$stage: 認証処理を完了できません。秘密情報を表示せず停止しました。');
    } finally {
      if (!callback.isCompleted) callback.complete(null);
      await listener.close(force: true);
      if (identical(_listener, listener)) {
        _listener = null;
        _callback = null;
      }
    }
  }

  Map<String, dynamic> _tokenProfile(
    Map<String, dynamic> tokens,
    Map<String, dynamic> identity,
    String clientId, {
    Map<String, dynamic>? previous,
  }) {
    final expiry = tokens['expires_in'];
    if (tokens['token_type'] is! String ||
        (tokens['token_type'] as String).toLowerCase() != 'bearer' ||
        tokens['access_token'] is! String ||
        (tokens['access_token'] as String).isEmpty ||
        expiry is! int ||
        expiry < 1 ||
        (previous == null && tokens['scope'] is! String)) {
      throw const SiwcFailure('token応答の必須項目を確認できません。');
    }
    return {
      'client_id': clientId,
      'subject': identity['sub'],
      'label': identity['email'] is String
          ? identity['email']
          : 'ChatGPT account ${identity['sub']}',
      'id_token': tokens['id_token'] ?? previous?['id_token'],
      'access_token': tokens['access_token'],
      'refresh_token': tokens['refresh_token'] ?? previous?['refresh_token'],
      'expires_at': DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiry))
          .toIso8601String(),
      'scopes': tokens['scope'] is String
          ? (tokens['scope'] as String)
                .split(' ')
                .where((s) => s.isNotEmpty)
                .toList()
          : previous?['scopes'] ?? [],
    };
  }

  Future<void> refresh({bool force = false}) {
    if (_refreshing != null) return _refreshing!;
    final future = _refresh(force: force);
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<void> _refresh({required bool force}) async {
    final epoch = _epoch;
    final profile = _active;
    if (profile == null || profile['access_token'] is! String) {
      throw const SiwcFailure('ChatGPTへ接続してください。');
    }
    final expiry = DateTime.parse(profile['expires_at'] as String);
    if (!force &&
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return;
    }
    final refreshToken = profile['refresh_token'];
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw const SiwcFailure('再ログインが必要です。');
    }
    final tokens = await network.postForm(Uri.parse(tokenEndpoint), {
      'grant_type': 'refresh_token',
      'client_id': profile['client_id'] as String,
      'refresh_token': refreshToken,
      'resource': resource,
    });
    _check(epoch);
    var identity = <String, dynamic>{
      'sub': profile['subject'],
      'email': profile['label'],
    };
    if (tokens['id_token'] is String) {
      identity = await _verify(
        tokens['id_token'] as String,
        profile['client_id'] as String,
        subject: profile['subject'] as String,
      );
    }
    _check(epoch);
    final replacement = _tokenProfile(
      tokens,
      identity,
      profile['client_id'] as String,
      previous: profile,
    );
    final old = _document;
    _document = {
      ..._document,
      'profiles': [
        for (final p in _profiles)
          p['client_id'] == replacement['client_id'] ? replacement : p,
      ],
    };
    try {
      await _save();
    } catch (_) {
      _document = old;
      rethrow;
    }
  }

  Future<List<({String slug, String name})>> listModels() async {
    final epoch = _epoch;
    if (!canInfer) throw const SiwcFailure('ChatGPT plan usageの同意・権限が必要です。');
    await refresh();
    _check(epoch);
    if (!canInfer) throw const SiwcFailure('ChatGPT plan usageの同意・権限が必要です。');
    final data = await network.getJson(
      Uri.parse('$resource/models'),
      bearer: _active!['access_token'] as String,
    );
    _check(epoch);
    if (data['models'] is! List) throw const SiwcFailure('モデル一覧の形式が不正です。');
    return [
      for (final model in data['models'] as List)
        if (model is Map &&
            model['visibility'] == 'list' &&
            model['slug'] is String &&
            model['display_name'] is String)
          (
            slug: model['slug'] as String,
            name: model['display_name'] as String,
          ),
    ];
  }

  Future<String> infer(
    String model,
    String confirmedText, {
    String? instructions,
    bool jsonObject = false,
  }) async {
    final body = inferenceBody(
      model,
      confirmedText,
      maxChars: maxInputChars,
      instructions: instructions,
      jsonObject: jsonObject,
    );
    final epoch = _epoch;
    if (!canInfer) throw const SiwcFailure('ChatGPT plan usageの同意・権限が必要です。');
    var stage = '接続情報の更新';
    try {
      await refresh();
      _check(epoch);
      if (!canInfer) throw const SiwcFailure('ChatGPT plan usageの同意・権限が必要です。');
      stage = 'AIへの送信・回答の受信';
      final result = await network.infer(
        _active!['access_token'] as String,
        body,
      );
      _check(epoch);
      return result;
    } on SiwcFailure catch (error) {
      throw SiwcFailure('$stage: ${error.message}');
    } catch (error) {
      throw SiwcFailure('$stage: ${safeNetworkFailure(error)}');
    }
  }

  Future<bool> disconnect() async {
    final profile = _active;
    if (profile == null) return true;
    cancel();
    var revoked = false;
    try {
      if (profile['refresh_token'] is String) {
        final metadata = await _discovery();
        await network.postForm(_authUri(metadata['revocation_endpoint']), {
          'token': profile['refresh_token'] as String,
          'token_type_hint': 'refresh_token',
          'client_id': profile['client_id'] as String,
        }, emptyOk: true);
        revoked = true;
      }
    } catch (_) {
      /* Local sign-out still clears secrets; UI reports unconfirmed revocation. */
    }
    final cleared = {
      'client_id': profile['client_id'],
      'subject': profile['subject'],
      'label': profile['label'],
      'scopes': <String>[],
    };
    _document = {
      ..._document,
      'profiles': [
        for (final p in _profiles)
          p['client_id'] == profile['client_id'] ? cleared : p,
      ],
    };
    await _save();
    return revoked;
  }

  void cancel() {
    _epoch++;
    final callback = _callback;
    if (callback != null && !callback.isCompleted) callback.complete(null);
    network.cancel();
  }
}
