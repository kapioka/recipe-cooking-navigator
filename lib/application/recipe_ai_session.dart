import 'package:flutter/foundation.dart';

import '../data/recipe_creation_store.dart';
import 'recipe_ai_client.dart';

/// One runtime shared by settings and creation. Closing settings never cancels it.
class RecipeAiSession extends ChangeNotifier {
  RecipeAiSession(this.client, this.store);
  final RecipeAiClient client;
  final RecipeCreationStore store;
  Future<void>? _initialization;
  bool _initialized = false;
  List<({String slug, String name})> models = [];
  String? model;
  bool voiceExplained = false;
  Map<String, dynamic>? draft;
  bool interruptedResult = false;
  String? persistenceWarning;

  Future<void> initialize() => _initialized
      ? Future.value()
      : _initialization ??= _initialize().catchError((Object error) {
          _initialization = null;
          throw error;
        });
  Future<void> _initialize() async {
    try {
      final data = await store.load();
      model = data['model'] is String ? data['model'] as String : null;
      voiceExplained = data['voiceExplained'] == true;
      draft = data['draft'] is Map
          ? Map<String, dynamic>.from(data['draft'] as Map)
          : null;
      interruptedResult = draft?['hasResult'] == true;
    } catch (_) {
      persistenceWarning = '条件の下書きを読み込めませんでした。';
    }
    await client.initialize();
    if (client.canInfer) await refreshModels();
    _initialized = true;
  }

  Future<void> refreshModels() async {
    models = [];
    notifyListeners();
    final available = await client.listModels();
    models = available;
    if (!models.any((m) => m.slug == model)) {
      model = models.isEmpty ? null : models.first.slug;
    }
    notifyListeners();
  }

  Future<void> selectModel(String value) async {
    if (!models.any((m) => m.slug == value)) return;
    model = value;
    await persist('model', value);
    notifyListeners();
  }

  Future<void> persist(String key, Object? value) async {
    try {
      await store.update(key, value);
    } catch (_) {
      persistenceWarning = '下書き・設定を端末に保存できませんでした。この画面の入力は残っています。';
      notifyListeners();
    }
  }

  Future<void> saveDraft(Map<String, dynamic>? value) {
    draft = value;
    return persist('draft', value);
  }

  @override
  void dispose() {
    client.cancel();
    super.dispose();
  }
}
