import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:siwc_client/siwc_contract.dart';

import '../application/ai_recipe_import.dart';
import '../application/recipe_ai_client.dart';
import '../application/recipe_library_controller.dart';
import '../domain/ai_recipe_prompt.dart';
import '../domain/ai_recipe_request.dart';
import '../domain/ai_recipe_response_diagnostic.dart';

class ConnectedRecipeScreen extends StatefulWidget {
  const ConnectedRecipeScreen({
    required this.request,
    required this.library,
    this.client,
    this.prompt,
    super.key,
  });
  final AiRecipeRequest request;
  final RecipeLibraryController library;
  final RecipeAiClient? client;
  final AiRecipePrompt? prompt;
  @override
  State<ConnectedRecipeScreen> createState() => _ConnectedRecipeScreenState();
}

class _ConnectedRecipeScreenState extends State<ConnectedRecipeScreen> {
  late final RecipeAiClient _client;
  late final TextEditingController _text;
  bool _busy = false, _ready = false;
  String _status = '接続の準備中…';
  List<({String slug, String name})> _models = [];
  String? _model;
  RecipeImportPreview? _preview;
  @override
  void initState() {
    super.initState();
    _client = widget.client ?? AndroidRecipeAiClient();
    _text = TextEditingController(text: widget.request.directText);
    _run(() async {
      await _client.initialize();
      if (!mounted) return;
      _ready = true;
      if (_client.canInfer) await _loadModels();
      _status = _client.canInfer
          ? '接続済みです。希望を確認して送信してください。'
          : '「ChatGPTに接続」を押し、ブラウザでの手続き後に「アプリに戻る」を押してください。';
    });
  }

  void _discardPreview() {
    final preview = _preview;
    if (preview != null) widget.library.cancelPreparedImport(preview);
    _preview = null;
  }

  @override
  void dispose() {
    _client.cancel();
    _discardPreview();
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on SiwcFailure catch (error) {
      _status = error.message;
    } on FormatException catch (error) {
      _status = error.message;
    } catch (_) {
      _status = '接続または処理を完了できません。共有・コピーの方法も利用できます。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadModels() async {
    final models = await _client.listModels();
    if (!mounted) return;
    _models = models;
    _model = models.isEmpty ? null : models.first.slug;
  }

  Future<AiRecipePrompt> _loadPrompt() async =>
      widget.prompt ??
      AiRecipePrompt(
        recipeSchema: await rootBundle.loadString(
          'schemas/recipe-v2.schema.json',
        ),
        feedbackSchema: await rootBundle.loadString(
          'schemas/feedback-v2.schema.json',
        ),
        generateWorkflow: await rootBundle.loadString(
          'ai/workflows/generate.md',
        ),
        improveWorkflow: await rootBundle.loadString('ai/workflows/improve.md'),
        integration: await rootBundle.loadString('docs/chatgpt-integration.md'),
        example: await rootBundle.loadString(
          'examples/recipe-v2-split-example.json',
        ),
      );
  Future<void> _send() => _run(() async {
    _discardPreview();
    final model = _model;
    if (!_client.canInfer ||
        model == null ||
        !_models.any((m) => m.slug == model)) {
      throw const SiwcFailure('接続と利用可能なモデルを確認してください。');
    }
    final confirmedText = _text.text;
    final prompt = await _loadPrompt();
    if (!mounted) return;
    setState(() => _status = 'レシピを生成しています。完了後に形式を検証します。');
    final submission = prompt.build(widget.request, confirmedText);
    final result = await _client.infer(
      model,
      submission.input,
      instructions: submission.instructions,
    );
    if (!mounted) return;
    final preparation = await prepareAiRecipe(
      widget.library,
      widget.request,
      result,
    );
    if (!mounted) {
      final preview = preparation.preview;
      if (preview != null) widget.library.cancelPreparedImport(preview);
      return;
    }
    _preview = preparation.preview;
    _status = _preview == null
        ? preparation.errorCode == null
              ? preparation.message
              : describeAiRecipeFailure(result, preparation.errorCode!)
        : '対応形式のレシピを受信しました。内容を確認してから保存してください。';
  });
  Future<void> _save() => _run(() async {
    final preview = _preview;
    if (preview == null) return;
    final result = await widget.library.confirmPreparedImport(
      preview,
      preserveActive: true,
    );
    _preview = null;
    _status = result.message;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.request.feedback == null ? 'アプリ内でレシピを作る' : 'アプリ内でレシピを改善',
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_status, key: const Key('connected_ai_status')),
                  if (_busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'ChatGPTの利用権限と同意が必要です。選択した依頼と改善元の評価だけを送ります。会話履歴やMemoryは取得しません。',
                ),
                if (_client.accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey('connected-account-${_client.activeAccount}'),
                    initialValue: _client.activeAccount,
                    decoration: const InputDecoration(labelText: 'アカウント'),
                    items: [
                      for (final a in _client.accounts)
                        DropdownMenuItem(
                          value: a.id,
                          child: Text(a.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (id) {
                            if (id != null) {
                              _run(() async {
                                _discardPreview();
                                _models = [];
                                _model = null;
                                await _client.selectAccount(id);
                                if (_client.canInfer) await _loadModels();
                                _status = 'アカウントを切り替えました。';
                              });
                            }
                          },
                  ),
                FilledButton(
                  key: const Key('connected_ai_login'),
                  onPressed: _busy || !_ready
                      ? null
                      : () => _run(() async {
                          _discardPreview();
                          _models = [];
                          _model = null;
                          setState(
                            () => _status = 'ブラウザで接続手続きを行い、「アプリに戻る」を押してください。',
                          );
                          await _client.signIn();
                          if (_client.canInfer) await _loadModels();
                          _status = _client.canInfer
                              ? '接続できました。希望を確認して送信してください。'
                              : '本人確認はできましたが、AIの利用権限がありません。利用枠・権限を確認してください。';
                        }),
                  child: const Text('ChatGPTに接続'),
                ),
                TextButton(
                  onPressed: _busy || !_ready
                      ? null
                      : () => _run(() async {
                          _discardPreview();
                          _models = [];
                          _model = null;
                          await _client.signIn(newAccount: true);
                          if (_client.canInfer) await _loadModels();
                          _status = 'アカウントの接続状態を確認してください。';
                        }),
                  child: const Text('アカウントを追加'),
                ),
                if (_client.connected)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            _discardPreview();
                            final revoked = await _client.disconnect();
                            _models = [];
                            _model = null;
                            _status = revoked ? '接続を解除しました。レシピは保持しています。' : '端末内の接続を解除しました。遠隔失効は未確認です。ChatGPTの設定でも確認してください。';
                          }),
                    child: const Text('接続解除'),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _run(_client.openUsage),
                  child: const Text('ChatGPTの利用枠・権限を確認'),
                ),
                if (_models.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey('connected-model-$_model'),
                    initialValue: _model,
                    decoration: const InputDecoration(labelText: '利用可能なモデル'),
                    items: [
                      for (final m in _models)
                        DropdownMenuItem(value: m.slug, child: Text(m.name)),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _model = value),
                  ),
                const SizedBox(height: 16),
                if (widget.request.feedback != null)
                  const Text('選択した改善元レシピと保存した評価を添付します。下の欄で追加の希望を編集できます。'),
                TextField(
                  key: const Key('connected_ai_text'),
                  controller: _text,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'AIへ送る希望',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {
                    _discardPreview();
                    _status = '入力は未送信です。';
                  }),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('connected_ai_dictate'),
                        onPressed: _busy || !_ready
                            ? null
                            : () => _run(() async {
                                final text = await _client.dictate();
                                if (!mounted) return;
                                if (text != null && text.trim().isNotEmpty) {
                                  _discardPreview();
                                  _text.text = text.trim();
                                  _status = '音声入力を確認し、枠内で修正してください。未送信です。';
                                } else {
                                  _status = '音声入力をキャンセルしました。未送信です。';
                                }
                              }),
                        child: const Text('音声で入力'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('connected_ai_send'),
                        onPressed:
                            _busy ||
                                !_ready ||
                                !_client.canInfer ||
                                _model == null ||
                                _text.text.trim().isEmpty
                            ? null
                            : _send,
                        child: const Text('確定して送信'),
                      ),
                    ),
                  ],
                ),
                const Text('枠内をタップして修正できます。「確定して送信」を押すまでAIへ送りません。'),
                const SizedBox(height: 8),
                const Text('音声認識はAndroidのサービスを使います。サービスや端末によってネット通信があります。'),
                if (_busy)
                  TextButton(
                    onPressed: () {
                      _client.cancel();
                      _status = '操作をキャンセルしています。';
                      setState(() {});
                    },
                    child: const Text('処理をキャンセル'),
                  ),
                if (_preview case final preview?)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            preview.title,
                            key: const Key('connected_ai_preview'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Version ${preview.revision}${preview.parentRevision == null ? '' : '（Version ${preview.parentRevision}から改善）'}',
                          ),
                          Text(
                            '${preview.servings}人分・約${preview.totalTimeMinutes}分',
                          ),
                          Text(
                            '材料 ${preview.ingredientCount}件・工程 ${preview.stepCount}件',
                          ),
                          const Text(
                            '保存するまでレシピは追加されません。過去のVersionと使用中のVersionは保持します。',
                          ),
                          ExpansionTile(
                            title: const Text('材料と分量を確認'),
                            children: [
                              for (final line in preview.ingredientDetails)
                                ListTile(title: Text(line)),
                            ],
                          ),
                          ExpansionTile(
                            title: const Text('調理の工程を確認'),
                            children: [
                              for (final line in preview.stepDetails)
                                ListTile(title: Text(line)),
                            ],
                          ),
                          FilledButton(
                            key: const Key('connected_ai_save'),
                            onPressed: _busy ? null : _save,
                            child: const Text('確認して保存'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _discardPreview();
                                    _status = '保存せず取り消しました。';
                                  }),
                            child: const Text('保存せず取り消す'),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('共有・コピーの方法へ戻る'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
