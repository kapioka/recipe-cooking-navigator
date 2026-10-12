import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:siwc_client/siwc_contract.dart';

import '../application/recipe_ai_client.dart';
import '../application/recipe_ai_session.dart';
import '../application/recipe_creation_controller.dart';
import '../application/ai_recipe_import.dart';
import '../application/recipe_library_controller.dart';
import '../data/recipe_creation_store.dart';
import '../domain/ai_recipe_prompt.dart';
import '../domain/ai_recipe_request.dart';
import '../platform/ai_request_platform.dart';
import 'recipe_ai_scope.dart';
import 'recipe_ai_settings_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_import_screen.dart';
import 'recipe_preview_content.dart';
import 'recipe_creation_progress.dart';
import 'recipe_theme.dart';
import 'recipe_section.dart';

class AiRecipeRequestScreen extends StatefulWidget {
  const AiRecipeRequestScreen({
    this.improvementRequest,
    this.initialRequest,
    this.platform = const AndroidAiRequestPlatform(),
    this.publicReady = publicAiV2Ready,
    this.library,
    this.session,
    this.client,
    this.prompt,
    super.key,
  });
  final AiRecipeRequest? improvementRequest, initialRequest;
  final AiRequestPlatform platform;
  final bool publicReady;
  final RecipeLibraryController? library;
  final RecipeAiSession? session;
  final RecipeAiClient? client;
  final AiRecipePrompt? prompt;
  @override
  State<AiRecipeRequestScreen> createState() => _AiRecipeRequestScreenState();
}

class _AiRecipeRequestScreenState extends State<AiRecipeRequestScreen>
    with WidgetsBindingObserver {
  final _fields = <String, TextEditingController>{
    'ingredients': TextEditingController(),
    'servings': TextEditingController(text: '2'),
    'time_minutes': TextEditingController(text: '30'),
    'utensils': TextEditingController(),
    'taste': TextEditingController(),
    'instructions': TextEditingController(),
  };
  final _focus = <String, FocusNode>{};
  final _errors = <String, String>{};
  final _scroll = ScrollController();
  RecipeAiSession? _session;
  RecipeCreationController? _flow;
  bool _ownsSession = false,
      _ready = false,
      _working = false,
      _external = false;
  bool _allowPop = false, _options = false;
  String? _message;
  final _previewFocus = FocusNode();
  String? _candidateFields;
  RecipeCreationStage? _lastStage;
  AiRecipeRequest? _externalRequest;
  Timer? _draftTimer;
  AiRecipeRequest? get _improvement =>
      (widget.improvementRequest?.feedback != null
          ? widget.improvementRequest
          : null) ??
      (widget.initialRequest?.feedback != null ? widget.initialRequest : null);
  bool get _busy =>
      _working ||
      (_flow?.busy ?? false) ||
      _flow?.stage == RecipeCreationStage.saved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_session != null &&
        _ready &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused)) {
      _draftTimer?.cancel();
      unawaited(_persist());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    _session = widget.session ?? RecipeAiScope.maybeOf(context);
    _ownsSession = _session == null;
    _session ??= RecipeAiSession(
      widget.client ?? AndroidRecipeAiClient(),
      RecipeCreationStore(),
    );
    if (widget.library != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.library!.setCreationOpen(true);
      });
      _flow = RecipeCreationController(_session!, widget.library!)
        ..addListener(_changed);
    }
    for (final key in _fields.keys) {
      _focus[key] = FocusNode();
    }
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _session!.initialize();
    } catch (_) {
      _message = '接続状態を確認できません。ChatGPT連携の設定を確認するか、別の方法で作れます。';
    }
    if (!mounted) return;
    final draft =
        widget.initialRequest?.conditions ??
        widget.improvementRequest?.conditions ??
        (_improvement == null ? _session!.draft : null);
    if (draft != null) {
      for (final entry in _fields.entries) {
        final value = draft[entry.key];
        if (value is String || value is int) entry.value.text = '$value';
      }
      if (_session!.interruptedResult) {
        _message = '条件を復元しました。作成結果は復元できませんでした。自動送信はしていません。';
        _session!.interruptedResult = false;
      }
    }
    setState(() => _ready = true);
  }

  Map<String, dynamic> get _draft => {
    for (final e in _fields.entries) e.key: e.value.text,
    'hasResult': _flow?.preview != null || (_flow?.generating ?? false),
  };
  Future<void> _persist() async {
    if (_improvement == null) await _session!.saveDraft(_draft);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final changedStage = _lastStage != _flow?.stage;
    _lastStage = _flow?.stage;
    if (_flow?.stage == RecipeCreationStage.preview && changedStage) {
      unawaited(_persist());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(0);
          _previewFocus.requestFocus();
        }
      });
    } else if (changedStage && _flow?.message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  AiRecipeRequest? _request({bool validate = true}) {
    _errors.clear();
    if (_improvement != null) return _improvement;
    final servings = int.tryParse(_fields['servings']!.text) ?? 0;
    final minutes = int.tryParse(_fields['time_minutes']!.text) ?? 0;
    if (_fields['ingredients']!.text.trim().isEmpty) {
      _errors['ingredients'] = '使いたい食材を入力してください';
    }
    if (servings < 1 || servings > 100) _errors['servings'] = '1〜100人で入力してください';
    if (minutes < 1 || minutes > 1440) {
      _errors['time_minutes'] = '1〜1440分で入力してください';
    }
    if (_errors.isNotEmpty) {
      if (validate) {
        setState(() {});
        _focus[_errors.keys.first]!.requestFocus();
      }
      return null;
    }
    return AiRecipeRequest.generate(
      ingredients: _fields['ingredients']!.text,
      servings: servings,
      timeMinutes: minutes,
      utensils: _fields['utensils']!.text,
      taste: _fields['taste']!.text,
      instructions: _fields['instructions']!.text,
    );
  }

  String _conditions(AiRecipeRequest request) => _improvement == null
      ? request.directText
      : '${request.directText}\n追加の希望: ${_fields['instructions']!.text}';

  Future<AiRecipePrompt> _prompt() async =>
      widget.prompt ??
      AiRecipePrompt(
        recipeSchema: await rootBundle.loadString(
          'schemas/recipe-v2.schema.json',
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

  Future<void> _generate() async {
    if (_busy) return;
    final request = _request();
    if (request == null) return;
    if (_conditions(request).length > 4000) {
      setState(() => _message = '条件全体を4000文字以内に短くしてください。');
      return;
    }
    FocusScope.of(context).unfocus();
    _message = null;
    final pending = _flow!.generate(request, _conditions(request), _prompt);
    unawaited(_persist());
    await pending;
    if (mounted && _flow!.stage == RecipeCreationStage.preview) {
      setState(
        () => _candidateFields = _fields.values.map((f) => f.text).join('\n'),
      );
    }
  }

  Future<void> _settings() async {
    await _persist();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeAiSettingsScreen(session: _session!),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _dictate() async {
    if (_busy) return;
    if (!_session!.voiceExplained) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('音声で希望を追加'),
          content: const Text(
            'Androidの音声認識サービスを使います。端末やサービスによってネット通信があります。認識した文は編集でき、自動送信はしません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('音声入力を始める'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      _session!.voiceExplained = true;
      unawaited(_session!.persist('voiceExplained', true));
    }
    setState(() {
      _working = true;
      _message = '音声を聞き取っています。';
    });
    try {
      final text = await _session!.client.dictate();
      if (!mounted) return;
      if (text != null && text.trim().isNotEmpty) {
        final field = _fields['instructions']!;
        field.text = [
          field.text,
          text.trim(),
        ].where((s) => s.isNotEmpty).join('\n');
        if (field.text.length > 4000) {
          field.text = field.text.substring(0, 4000);
        }
        _message = '認識した希望を確認・修正してください。未送信です。';
        unawaited(_persist());
      } else {
        _message = '音声入力をキャンセルしました。条件は残っています。';
      }
    } catch (_) {
      _message = '音声入力を開始できませんでした。文字で入力できます。';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _externalSend(bool copy) async {
    if (_busy || !widget.publicReady) return;
    final request = _request();
    if (request == null) return;
    setState(() => _working = true);
    try {
      final text = _improvement == null
          ? request.text
          : '${request.text}\n追加の希望: ${_fields['instructions']!.text}';
      if (copy) {
        await Clipboard.setData(ClipboardData(text: text));
        _message = '依頼文をコピーしました。ChatGPTで貼り付けて送信してください。';
        try {
          await widget.platform.openChatGpt();
        } catch (_) {
          _message = 'コピー済みです。ChatGPTアプリまたはブラウザを開いて貼り付けてください。';
        }
      } else {
        await widget.platform.share(text);
        _message = '共有先でChatGPTを選び、内容を確認して送信してください。';
      }
      _external = true;
      _externalRequest = request;
    } catch (_) {
      _message = '共有・コピーを開始できませんでした。もう一度お試しください。';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _paste() async {
    final source = await showRecipePasteDialog(context);
    if (source == null || !mounted) return;
    // Preserve the existing candidate until an explicit replacement is accepted.
    final request = _externalRequest;
    if (request == null) return;
    final prepared = await prepareAiRecipe(
      widget.library!,
      request,
      source,
      replacing: _flow?.preview,
    );
    if (!mounted) {
      if (prepared.preview case final abandoned?) {
        widget.library!.cancelPreparedImport(abandoned);
      }
      return;
    }
    if (prepared.preview == null) {
      setState(() => _message = prepared.message);
      return;
    }
    _flow!.preview = prepared.preview;
    _flow!.candidateConditions = null;
    _flow!.message = null;
    _flow!.diagnostic = null;
    _candidateFields = null;
    _flow!.showPreview();
  }

  Future<void> _save() async {
    final result = await _flow!.save();
    if (!mounted ||
        result == null ||
        result.status == RecipeImportStatus.failed) {
      return;
    }
    _draftTimer?.cancel();
    if (_improvement == null) await _session!.saveDraft(null);
    if (!mounted) return;
    final preview = _flow!.preview!;
    final recipe = widget.library!.revisionFor(
      preview.recipeId,
      preview.revision,
    );
    if (recipe == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.status == RecipeImportStatus.alreadyExists
              ? '保存済みのレシピを開きました'
              : preview.parentRevision == null
              ? '保存しました'
              : '新しい版を保存しました。使用中の版は変わっていません',
        ),
      ),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(
          recipe: recipe,
          controller: widget.library!,
          showExactRevision: true,
        ),
      ),
    );
  }

  Future<void> _back() async {
    if (_working ||
        _flow?.stage == RecipeCreationStage.saving ||
        _flow?.stage == RecipeCreationStage.saved) {
      return;
    }
    final unsaved =
        _flow?.preview != null &&
        !widget.library!.isStoredPreview(_flow!.preview!);
    if ((_flow?.generating ?? false) || unsaved) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_flow!.generating ? '作成を中止して戻りますか？' : '保存せずに戻りますか？'),
          content: const Text('入力した条件は残ります。作成結果は保存されません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('続ける'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('戻る'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    _flow?.cancel();
    await _persist();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    _flow?.removeListener(_changed);
    _flow?.dispose();
    final library = widget.library;
    scheduleMicrotask(() => library?.setCreationOpen(false));
    if (_ownsSession) _session?.dispose();
    for (final f in _fields.values) {
      f.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _scroll.dispose();
    _previewFocus.dispose();
    super.dispose();
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    bool number = false,
    bool outsideLabel = false,
    String? unit,
    bool spaced = true,
  }) => Padding(
    padding: EdgeInsets.only(bottom: spaced ? 16 : 0),
    child: Semantics(
      label: outsideLabel ? label : null,
      child: TextField(
        key: Key(key == 'instructions' ? 'connected_ai_text' : 'ai_$label'),
        controller: _fields[key],
        focusNode: _focus[key],
        enabled: _ready && !_busy,
        keyboardType: number ? TextInputType.number : TextInputType.multiline,
        minLines: 1,
        maxLines: number ? 1 : 4,
        maxLength: number ? 4 : 4000,
        textAlign: number && outsideLabel ? TextAlign.center : TextAlign.start,
        style: number && outsideLabel
            ? const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)
            : null,
        decoration: InputDecoration(
          labelText: outsideLabel ? null : label,
          hintText: hint,
          suffixText: unit,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          counterText: '',
          errorText: _errors[key],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD7DDD2)),
          ),
        ),
        onChanged: (_) {
          setState(() => _errors.remove(key));
          _draftTimer?.cancel();
          _draftTimer = Timer(const Duration(milliseconds: 250), _persist);
        },
      ),
    ),
  );

  Widget _conditionLabel(IconData icon, String label) => Row(
    children: [
      Icon(icon, color: RecipeTheme.forest, size: 24),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  );

  Widget _numberCondition(
    String key,
    String label,
    String displayLabel,
    String unit,
    IconData icon,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 285 ||
          MediaQuery.textScalerOf(context).scale(16) > 21;
      final input = _field(
        key,
        label,
        number: true,
        outsideLabel: true,
        spaced: false,
        unit: stacked ? unit : null,
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _conditionLabel(icon, displayLabel),
            const SizedBox(height: 10),
            input,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: _conditionLabel(icon, displayLabel)),
          const SizedBox(width: 12),
          SizedBox(width: 108, child: input),
          const SizedBox(width: 10),
          Text(unit),
        ],
      );
    },
  );

  Widget _basicConditions() => Container(
    key: const Key('recipe_basic_conditions'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: RecipeTheme.sage,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '基本の条件',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: RecipeTheme.forest,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        _conditionLabel(Icons.restaurant_outlined, '食材'),
        const SizedBox(height: 10),
        _field('ingredients', '食材', hint: '例: なす、豚肉', outsideLabel: true),
        _numberCondition('servings', '人数', '人数', '人分', Icons.person_outline),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1, color: Colors.white),
        ),
        _numberCondition(
          'time_minutes',
          '調理時間（分）',
          '調理時間',
          '分',
          Icons.schedule,
        ),
      ],
    ),
  );

  Widget _optionalConditions() => Card(
    margin: const EdgeInsets.only(top: 16, bottom: 12),
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ExpansionTile(
      key: const Key('creation_options'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      leading: const Icon(Icons.tune, color: RecipeTheme.forest),
      title: const Text('こだわりを追加（任意）'),
      initiallyExpanded: _options,
      onExpansionChanged: (value) => _options = value,
      subtitle: Text(
        [
              _fields['utensils']!.text,
              _fields['taste']!.text,
              _fields['instructions']!.text,
            ].where((s) => s.isNotEmpty).join('・').isEmpty
            ? '器具・味つけ・その他の希望'
            : [
                _fields['utensils']!.text,
                _fields['taste']!.text,
                _fields['instructions']!.text,
              ].where((s) => s.isNotEmpty).join('・'),
      ),
      children: [
        _field('utensils', '調理器具'),
        _field('taste', '味の方向性'),
        _wishes(),
      ],
    ),
  );

  String _modelName() {
    for (final model in _session!.models) {
      if (model.slug == _session!.model) return model.name;
    }
    return _session!.model ?? '未選択';
  }

  Widget _wishes() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field('instructions', _improvement == null ? 'その他の希望（任意）' : '追加の希望（任意）'),
      OutlinedButton.icon(
        key: const Key('connected_ai_dictate'),
        onPressed: !_ready || _busy ? null : _dictate,
        icon: const Icon(Icons.mic_none),
        label: const Text('音声で希望を追加'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    final showing =
        flow != null &&
        [
          RecipeCreationStage.preview,
          RecipeCreationStage.saving,
          RecipeCreationStage.saved,
        ].contains(flow.stage);
    final generating = flow?.generating ?? false;
    final stage = showing
        ? 3
        : generating
        ? 2
        : 1;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            showing
                ? 'レシピの内容確認'
                : _improvement == null
                ? 'レシピを作る'
                : 'レシピを改善',
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              RecipeCreationProgress(currentStep: stage),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (flow?.message ?? _message case final message?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            message,
                            key: const Key('ai_request_message'),
                          ),
                        ),
                      ),
                    if (showing) ...[
                      if (_candidateFields != null &&
                          _candidateFields !=
                              _fields.values.map((f) => f.text).join('\n'))
                        const Text('表示中のレシピは変更前の条件で作りました。編集した条件はまだ反映されていません。'),
                      Focus(
                        focusNode: _previewFocus,
                        child: RecipePreviewContent(
                          preview: flow.preview!,
                          saved: widget.library!.isStoredPreview(flow.preview!),
                          titleKey: const Key('connected_ai_preview'),
                        ),
                      ),
                      if (flow.candidateConditions case final conditions?)
                        ExpansionTile(
                          title: const Text('このレシピを作った条件'),
                          children: [Text(conditions)],
                        ),
                    ] else if (generating) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 24),
                      Semantics(
                        liveRegion: true,
                        child: Text(switch (flow!.stage) {
                          RecipeCreationStage.starting => '作成を開始しています',
                          RecipeCreationStage.validating => '届いた内容を確認しています',
                          _ => 'レシピを作っています',
                        }, style: Theme.of(context).textTheme.titleLarge),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '経過 ${flow.elapsedSeconds}秒',
                        semanticsLabel: '作成の経過時間',
                      ),
                      Text('使用モデル: ${_modelName()}'),
                      if (flow.elapsedSeconds >= 30)
                        const Text('時間がかかっています。そのまま待つか、中止できます。'),
                      TextButton(
                        onPressed: flow.cancel,
                        child: const Text('作成を中止'),
                      ),
                    ] else ...[
                      if (!_ready) const LinearProgressIndicator(),
                      if (_session?.client.canInfer == true)
                        Card(
                          color: RecipeTheme.sage,
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: const Icon(
                              Icons.link,
                              color: RecipeTheme.forest,
                            ),
                            title: const Text('ChatGPT 接続済み'),
                            subtitle: Text(
                              _session!.model == null
                                  ? '使用するモデルを設定してください'
                                  : '使用モデル: ${_modelName()}',
                            ),
                            trailing: TextButton(
                              onPressed: _busy ? null : _settings,
                              child: const Text('変更'),
                            ),
                          ),
                        )
                      else ...[
                        const Text('ChatGPTを接続すると、この画面でレシピを作れます'),
                        OutlinedButton(
                          onPressed: !_ready || _busy ? null : _settings,
                          child: const Text('接続する'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_improvement == null) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 18),
                          child: Text(
                            '使いたい食材から、今日のひと皿を。',
                            style: TextStyle(
                              color: RecipeTheme.forest,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _basicConditions(),
                        _optionalConditions(),
                      ] else ...[
                        RecipeSection(
                          title: '評価から引き継いだ改善の希望',
                          icon: Icons.auto_stories_outlined,
                          color: RecipeTheme.sage,
                          children: [
                            Text(
                              '改善元: ${((_improvement!.feedback!['recipe_snapshot'] as Map)['recipe'] as Map)['title']}（バージョン ${((_improvement!.feedback!['recipe_snapshot'] as Map)['recipe'] as Map)['revision']}）',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              (_improvement!.feedback!['revision_request']
                                      as Map)['goal']
                                  as String,
                              key: const Key('inherited_improvement_goal'),
                            ),
                            const SizedBox(height: 12),
                            const Text('この改善内容と選択した評価を送ります。下の欄では希望を追加できます。'),
                          ],
                        ),
                      ],
                      if (_improvement != null) _wishes(),
                      if (flow?.preview != null) ...[
                        const Text('前の条件で作ったレシピを保持しています。再作成に成功すると入れ替わります。'),
                        TextButton(
                          onPressed: flow!.showPreview,
                          child: const Text('前のレシピを確認'),
                        ),
                      ],
                      ExpansionTile(
                        key: const Key('alternative_methods'),
                        backgroundColor: Colors.white,
                        collapsedBackgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        leading: const Icon(
                          Icons.article_outlined,
                          color: RecipeTheme.forest,
                        ),
                        title: const Text('別の方法で作る'),
                        children: [
                          if (!widget.publicReady)
                            const Text(
                              publicAiPendingMessage,
                              key: Key('ai_publication_pending'),
                            ),
                          OutlinedButton.icon(
                            key: const Key('share_ai_request'),
                            onPressed: _busy || !widget.publicReady
                                ? null
                                : () => _externalSend(false),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('ChatGPTへ共有'),
                          ),
                          TextButton(
                            key: const Key('copy_ai_request'),
                            onPressed: _busy || !widget.publicReady
                                ? null
                                : () => _externalSend(true),
                            child: const Text('依頼文をコピーしてChatGPTを開く'),
                          ),
                        ],
                      ),
                      if (_external && widget.library != null)
                        OutlinedButton(
                          onPressed: _busy ? null : _paste,
                          child: const Text('回答を貼り付ける'),
                        ),
                      ExpansionTile(
                        title: const Text('詳細'),
                        children: [
                          const Text('音声入力はAndroidのサービスを使い、ネット通信が発生する場合があります。'),
                          TextButton(
                            onPressed: () {
                              final request = _request();
                              if (request == null) return;
                              showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('送信内容の詳細'),
                                  content: SingleChildScrollView(
                                    child: SelectableText(request.text),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('閉じる'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Text('送信内容の詳細'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    for (final e in _fields.entries) {
                                      e.value.text = e.key == 'servings'
                                          ? '2'
                                          : e.key == 'time_minutes'
                                          ? '30'
                                          : '';
                                    }
                                    await _session!.saveDraft(null);
                                    if (mounted) {
                                      setState(
                                        () => _message = '条件の下書きを削除しました。',
                                      );
                                    }
                                  },
                            child: const Text('条件の下書きを削除'),
                          ),
                        ],
                      ),
                    ],
                    if (_session?.persistenceWarning case final warning?)
                      Text(warning),
                    if (!showing &&
                        !generating &&
                        flow?.failureKind == SiwcFailureKind.authentication)
                      TextButton(
                        onPressed: _settings,
                        child: const Text('再接続する'),
                      ),
                    if (!showing &&
                        !generating &&
                        flow?.failureKind == SiwcFailureKind.permission)
                      TextButton(
                        onPressed: () async {
                          try {
                            await _session!.client.openUsage();
                          } catch (_) {}
                        },
                        child: const Text('利用状況を確認'),
                      ),
                    if (flow?.diagnostic case final diagnostic?)
                      ExpansionTile(
                        title: const Text('診断詳細'),
                        children: [Text(diagnostic)],
                      ),
                  ],
                ),
              ),
              if (showing || (!generating && widget.library != null))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!showing) ...[
                        const Text(
                          '入力した条件をChatGPTへ送ります',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        key: Key(
                          showing ? 'connected_ai_save' : 'connected_ai_send',
                        ),
                        onPressed:
                            _busy ||
                                !_ready ||
                                (!showing &&
                                    (_session?.client.canInfer != true ||
                                        _session?.model == null))
                            ? null
                            : showing
                            ? _save
                            : _generate,
                        child: Text(
                          showing
                              ? flow.stage == RecipeCreationStage.saving
                                    ? '保存しています'
                                    : flow.stage == RecipeCreationStage.saved
                                    ? '保存しました'
                                    : flow.message != null
                                    ? '保存を再試行'
                                    : widget.library!.isStoredPreview(
                                        flow.preview!,
                                      )
                                    ? '保存済みのレシピを開く'
                                    : 'このレシピを保存'
                              : 'この条件でレシピを作る',
                        ),
                      ),
                      if (showing)
                        TextButton(
                          onPressed: _busy ? null : flow.edit,
                          child: const Text('条件を変える'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
