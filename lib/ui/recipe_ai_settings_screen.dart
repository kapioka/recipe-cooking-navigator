import 'package:flutter/material.dart';
import 'package:siwc_client/siwc_contract.dart';

import '../application/recipe_ai_session.dart';
import 'recipe_section.dart';
import 'recipe_theme.dart';

class RecipeAiSettingsScreen extends StatefulWidget {
  const RecipeAiSettingsScreen({required this.session, super.key});
  final RecipeAiSession session;
  @override
  State<RecipeAiSettingsScreen> createState() => _RecipeAiSettingsScreenState();
}

class _RecipeAiSettingsScreenState extends State<RecipeAiSettingsScreen> {
  bool _busy = false;
  String? _message;
  RecipeAiSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    _run(session.initialize);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on SiwcFailure catch (error) {
      _message = error.message;
    } catch (_) {
      _message = '接続状態を確認できませんでした。もう一度お試しください。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('ChatGPT連携')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RecipeSection(
            color: RecipeTheme.sage,
            children: [
              Text(
                session.client.canInfer ? '接続済み' : 'ChatGPTへの接続が必要です',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text('選択した条件と改善元の評価だけを送ります。会話履歴やMemoryは取得しません。'),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(_message!)),
            ],
          ),
          RecipeSection(
            title: 'アカウントとモデル',
            icon: Icons.person_outline,
            children: [
              if (session.client.accounts.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('account-${session.client.activeAccount}'),
                  initialValue: session.client.activeAccount,
                  decoration: const InputDecoration(labelText: 'アカウント'),
                  items: [
                    for (final a in session.client.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) => _run(() async {
                          if (id == null) return;
                          await session.client.selectAccount(id);
                          await session.refreshModels();
                        }),
                ),
              if (!session.client.canInfer)
                FilledButton(
                  key: const Key('connected_ai_login'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          setState(
                            () => _message = 'ブラウザで接続し、「アプリに戻る」を押してください。',
                          );
                          await session.client.signIn();
                          if (session.client.canInfer) {
                            await session.refreshModels();
                          }
                          _message = session.client.canInfer
                              ? '接続できました。戻って条件を確認し、作成ボタンを押してください。'
                              : 'このアカウントには作成の権限がありません。利用状況を確認してください。';
                        }),
                  child: const Text('ChatGPTに接続'),
                ),
              const SizedBox(height: 16),
              if (session.models.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('model-${session.model}'),
                  initialValue: session.model,
                  decoration: const InputDecoration(labelText: '使用するモデル'),
                  items: [
                    for (final m in session.models)
                      DropdownMenuItem(
                        value: m.slug,
                        child: Text(m.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => _run(() async {
                          if (value != null) await session.selectModel(value);
                        }),
                ),
              TextButton(
                onPressed: _busy ? null : () => _run(session.refreshModels),
                child: const Text('モデル一覧を更新'),
              ),
            ],
          ),
          RecipeSection(
            title: '接続の管理',
            icon: Icons.settings_outlined,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _run(session.client.openUsage),
                child: const Text('ChatGPTの利用状況を確認'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await session.client.signIn(newAccount: true);
                        if (session.client.canInfer) {
                          await session.refreshModels();
                        }
                      }),
                child: const Text('アカウントを追加'),
              ),
              if (session.client.connected)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final revoked = await session.client.disconnect();
                          session.models = [];
                          _message = revoked ? '接続を解除しました。' : '端末内の接続を解除しました。遠隔失効は未確認です。ChatGPTの設定でも確認してください。';
                        }),
                  child: const Text('接続解除'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
