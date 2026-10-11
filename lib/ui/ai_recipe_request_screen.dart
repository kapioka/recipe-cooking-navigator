import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/ai_recipe_request.dart';
import '../platform/ai_request_platform.dart';

class AiRecipeRequestScreen extends StatefulWidget {
  const AiRecipeRequestScreen({
    this.improvementRequest,
    this.platform = const AndroidAiRequestPlatform(),
    this.publicReady = publicAiV2Ready,
    super.key,
  });

  final AiRecipeRequest? improvementRequest;
  final AiRequestPlatform platform;
  final bool publicReady;

  @override
  State<AiRecipeRequestScreen> createState() => _AiRecipeRequestScreenState();
}

class _AiRecipeRequestScreenState extends State<AiRecipeRequestScreen> {
  final _ingredients = TextEditingController();
  final _servings = TextEditingController(text: '2');
  final _utensils = TextEditingController();
  final _taste = TextEditingController();
  final _minutes = TextEditingController(text: '30');
  final _instructions = TextEditingController();
  AiRecipeRequest? _request;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _request = widget.improvementRequest;
  }

  @override
  void dispose() {
    for (final field in [
      _ingredients,
      _servings,
      _utensils,
      _taste,
      _minutes,
      _instructions,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  void _preview() {
    try {
      final request = AiRecipeRequest.generate(
        ingredients: _ingredients.text,
        servings: int.tryParse(_servings.text) ?? 0,
        utensils: _utensils.text,
        taste: _taste.text,
        timeMinutes: int.tryParse(_minutes.text) ?? 0,
        instructions: _instructions.text,
      );
      setState(() {
        _request = request;
        _message = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _request = null;
        _message = error.message;
      });
    }
  }

  Future<void> _send({required bool copy}) async {
    final request = _request;
    if (request == null || _busy || !widget.publicReady) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (copy) {
        await Clipboard.setData(ClipboardData(text: request.text));
        if (!mounted) return;
        setState(() => _message = '依頼文をコピーしました。ChatGPTで貼り付けて送信してください。');
        try {
          await widget.platform.openChatGpt();
        } catch (_) {
          if (mounted) {
            setState(
              () => _message = 'コピー済みです。ChatGPTアプリまたはブラウザを開いて貼り付けてください。',
            );
          }
        }
      } else {
        await widget.platform.share(request.text);
        if (mounted) {
          setState(() => _message = '共有先でChatGPTを選び、内容を確認して送信してください。');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '共有・コピーを開始できませんでした。コピーして開く操作をお試しください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String name,
    TextEditingController controller, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: Key('ai_$name'),
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.multiline,
      maxLines: number ? 1 : 3,
      minLines: 1,
      maxLength: number ? 4 : 4000,
      decoration: InputDecoration(
        labelText: name,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      onChanged: (_) => setState(() => _request = null),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.improvementRequest == null ? 'ChatGPTでレシピを作る' : 'ChatGPTでレシピを改善',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '選択した内容だけを共有します。ChatGPTの回答をコピーし、レシピ一覧の「レシピを貼り付け」で取り込んでください。',
        ),
        const SizedBox(height: 16),
        if (!widget.publicReady) ...[
          const Text(
            publicAiPendingMessage,
            key: Key('ai_publication_pending'),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.improvementRequest == null) ...[
          _field('食材', _ingredients),
          _field('人数', _servings, number: true),
          _field('調理時間（分）', _minutes, number: true),
          _field('調理器具', _utensils),
          _field('味の方向性', _taste),
          _field('その他の希望', _instructions),
          FilledButton(
            onPressed: _busy ? null : _preview,
            child: const Text('依頼内容を確認'),
          ),
        ],
        if (_request case final request?) ...[
          const SizedBox(height: 16),
          const Text('送信する依頼文'),
          SelectableText(request.text, key: const Key('ai_request_preview')),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('share_ai_request'),
            onPressed: _busy || !widget.publicReady
                ? null
                : () => _send(copy: false),
            icon: const Icon(Icons.share_outlined),
            label: const Text('ChatGPTへ共有'),
          ),
          OutlinedButton.icon(
            key: const Key('copy_ai_request'),
            onPressed: _busy || !widget.publicReady
                ? null
                : () => _send(copy: true),
            icon: const Icon(Icons.copy),
            label: const Text('依頼文をコピーしてChatGPTを開く'),
          ),
        ],
        if (_message case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message, key: const Key('ai_request_message')),
          ),
      ],
    ),
  );
}
