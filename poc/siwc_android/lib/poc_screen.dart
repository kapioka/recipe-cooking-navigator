import 'package:flutter/material.dart';

import 'siwc_contract.dart';
import 'siwc_network.dart';
import 'siwc_runtime.dart';

void main() => runApp(
  MaterialApp(
    home: PocScreen(
      runtime: SiwcRuntime(AndroidPocPlatform(), HttpSiwcNetwork()),
    ),
  ),
);

class PocScreen extends StatefulWidget {
  const PocScreen({required this.runtime, super.key});
  final SiwcRuntime runtime;
  @override
  State<PocScreen> createState() => _PocScreenState();
}

class _PocScreenState extends State<PocScreen> {
  final _text = TextEditingController(
    text: 'Reply with exactly: Hello, world!',
  );
  final _focus = FocusNode();
  bool _busy = false;
  bool _ready = false;
  String _message = '安全保管を準備中…';
  String? _response;
  String? _model;
  List<({String slug, String name})> _models = [];

  @override
  void initState() {
    super.initState();
    _run(() async {
      await widget.runtime.initialize();
      _ready = true;
      if (widget.runtime.canInfer) await _loadModels();
      _message = widget.runtime.canInfer
          ? 'ChatGPTに接続しています。文章を確認し「確定して送信」を押してください。'
          : 'まず「ChatGPTに接続」を押してください。ブラウザでの手続き後、このアプリに戻ります。';
    });
  }

  @override
  void dispose() {
    widget.runtime.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _response = null;
    });
    try {
      await action();
    } on SiwcFailure catch (error) {
      _message = error.message;
    } catch (_) {
      _message = '通信・認証・安全保管に失敗しました。秘密情報をログへ出さず、接続状態を確認してください。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadModels() async {
    _models = await widget.runtime.listModels();
    _model = _models.isEmpty ? null : _models.first.slug;
  }

  Future<void> _login({bool newAccount = false}) => _run(() async {
    setState(
      () => _message = 'ネット接続を確認しています。ブラウザが開いたら手続きし、その後「アプリに戻る」を押すか、Androidの「戻る」操作でここへ戻ってください。',
    );
    await widget.runtime.signIn(newAccount: newAccount);
    _models = [];
    _model = null;
    if (widget.runtime.canInfer) await _loadModels();
    _message = widget.runtime.canInfer
        ? 'ChatGPTへの接続が完了しました。文章を確認し「確定して送信」を押してください。'
        : '本人確認はできましたが、ChatGPTの利用権限がありません。利用枠・権限を確認して再接続してください。';
  });
  Future<void> _dictate() => _run(() async {
    final recognized = await widget.runtime.platform.dictate();
    if (!mounted) return;
    if (recognized == null || recognized.trim().isEmpty) {
      _message = '音声入力はキャンセルまたは空でした。送信していません。';
    } else {
      _text.text = recognized.trim();
      _message = '認識文を確認してください。「修正」で編集し、「確定して送信」で初めてAIへ送ります。';
    }
  });
  Future<void> _send() => _run(() async {
    final selected = _model;
    if (selected == null || !_models.any((m) => m.slug == selected)) {
      throw const SiwcFailure('実接続で取得したモデルを選んでください。');
    }
    _response = await widget.runtime.infer(selected, _text.text);
    _message = '完了した回答を受信しました。下の回答を確認してください。';
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recipe SIWC PoC')),
    body: Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _busy ? '処理中です' : '接続と操作の状況',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(_message, key: const Key('status')),
                if (_busy) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '検証専用・別アプリ。ChatGPT Plus/Proの適格性と同意が必要です。利用枠は契約側で管理されます。会話履歴やMemoryは取得しません。',
              ),
              const SizedBox(height: 12),
              if (widget.runtime.accounts.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('account-${widget.runtime.activeClientId}'),
                  initialValue: widget.runtime.activeClientId,
                  decoration: const InputDecoration(labelText: '登録済みアカウント'),
                  items: [
                    for (final account in widget.runtime.accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(
                          account.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) {
                          if (id != null) {
                            _run(() async {
                              widget.runtime.selectAccount(id);
                              await widget.runtime.persistSelection();
                              _models = [];
                              _model = null;
                              if (widget.runtime.canInfer) await _loadModels();
                              _message = 'アカウントを切り替えました。';
                            });
                          }
                        },
                ),
              FilledButton(
                key: const Key('login'),
                onPressed: _busy || !_ready ? null : () => _login(),
                child: const Text('ChatGPTに接続'),
              ),
              TextButton(
                onPressed: _busy || !_ready
                    ? null
                    : () => _login(newAccount: true),
                child: const Text('アカウントを追加'),
              ),
              if (widget.runtime.connected) ...[
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.runtime.refresh(force: true);
                          _message = 'token更新完了（安全保管済み）。';
                        }),
                  child: const Text('期限更新を検証'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final revoked = await widget.runtime.disconnect();
                          _models = [];
                          _model = null;
                          _message = revoked ? '接続解除済み。登録とhost IDは保持しています。' : '端末内tokenを削除しました。遠隔失効は未確認です。ChatGPT設定でも接続解除してください。';
                        }),
                  child: const Text('接続解除'),
                ),
              ],
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.runtime.platform.openBrowser(
                          'https://chatgpt.com/settings/usage',
                        );
                      }),
                child: const Text('ChatGPTの利用枠・権限を確認'),
              ),
              if (_models.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'model-${widget.runtime.activeClientId}-$_model',
                  ),
                  initialValue: _model,
                  decoration: const InputDecoration(labelText: '利用可能なモデル'),
                  items: [
                    for (final model in _models)
                      DropdownMenuItem(
                        value: model.slug,
                        child: Text(model.name),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _model = value),
                ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('confirmed_text'),
                controller: _text,
                focusNode: _focus,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'AIへ送るテキスト（編集可能）',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {
                  _response = null;
                  _message = '入力は未送信です。内容を確認して確定してください。';
                }),
              ),
              const Text(
                '音声認識はAndroidのサービスを使います。サービス・端末によってはネット通信があります。音声生データはこのOpenAI連携へ送信しません。',
              ),
              OutlinedButton(
                key: const Key('dictate'),
                onPressed: _busy || !_ready ? null : _dictate,
                child: const Text('音声で文字入力'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const Key('edit'),
                      onPressed: _busy
                          ? null
                          : () {
                              _focus.requestFocus();
                              setState(() {
                                _response = null;
                                _message = '修正中です。確定するまで送信しません。';
                              });
                            },
                      child: const Text('修正'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      key: const Key('confirm_send'),
                      onPressed:
                          _busy ||
                              !widget.runtime.canInfer ||
                              _model == null ||
                              _text.text.trim().isEmpty
                          ? null
                          : _send,
                      child: const Text('確定して送信'),
                    ),
                  ),
                ],
              ),
              if (_busy)
                TextButton(
                  key: const Key('cancel'),
                  onPressed: widget.runtime.cancel,
                  child: const Text('操作をキャンセル'),
                ),
              if (_response case final response?)
                SelectableText(response, key: const Key('completed_text')),
              const SizedBox(height: 16),
              const Text('非対応・利用枠不足の場合は本体アプリの共有／コピー／ファイル取り込みを利用してください。'),
            ],
          ),
        ),
      ],
    ),
  );
}
