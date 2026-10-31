import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:siwc_client/siwc_runtime.dart';
import 'package:siwc_client/siwc_network.dart';

abstract class RecipeAiClient {
  bool get connected;
  bool get canInfer;
  String? get activeAccount;
  List<({String id, String label})> get accounts;
  Future<void> initialize();
  Future<void> signIn({bool newAccount = false});
  Future<void> selectAccount(String id);
  Future<List<({String slug, String name})>> listModels();
  Future<String?> dictate();
  Future<String> infer(
    String model,
    String input, {
    required String instructions,
    void Function()? onReceiving,
  });
  Future<bool> disconnect();
  Future<void> openUsage();
  void cancel();
}

class AndroidRecipeAiClient implements RecipeAiClient {
  AndroidRecipeAiClient()
    : _runtime = SiwcRuntime(
        _Platform(),
        HttpSiwcNetwork(onDiagnostic: (message) => debugPrint(message)),
        returnScheme: 'rcn-siwc',
        returnPackage: 'com.kapioka.recipe_cooking_navigator',
        returnAppName: 'Recipe Cooking Navigator',
        maxInputChars: 256000,
      );
  final SiwcRuntime _runtime;
  @override
  bool get connected => _runtime.connected;
  @override
  bool get canInfer => _runtime.canInfer;
  @override
  String? get activeAccount => _runtime.activeClientId;
  @override
  List<({String id, String label})> get accounts => _runtime.accounts;
  @override
  Future<void> initialize() => _runtime.initialize();
  @override
  Future<void> signIn({bool newAccount = false}) =>
      _runtime.signIn(newAccount: newAccount);
  @override
  Future<void> selectAccount(String id) async {
    _runtime.selectAccount(id);
    await _runtime.persistSelection();
  }

  @override
  Future<List<({String slug, String name})>> listModels() =>
      _runtime.listModels();
  @override
  Future<String?> dictate() => _runtime.platform.dictate();
  @override
  Future<String> infer(
    String model,
    String input, {
    required String instructions,
    void Function()? onReceiving,
  }) => _runtime.infer(
    model,
    input,
    instructions: instructions,
    onReceiving: onReceiving,
  );
  @override
  Future<bool> disconnect() => _runtime.disconnect();
  @override
  Future<void> openUsage() =>
      _runtime.platform.openBrowser('https://chatgpt.com/settings/usage');
  @override
  void cancel() => _runtime.cancel();
}

class _Platform implements PocPlatform {
  static const _channel = MethodChannel('recipe/siwc');
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
