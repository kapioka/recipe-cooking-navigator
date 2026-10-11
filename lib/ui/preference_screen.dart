import 'package:flutter/material.dart';

import '../application/preference_controller.dart';
import '../domain/preference_candidate.dart';
import '../domain/preference_evidence.dart';
import '../domain/recipe_document.dart';
import 'explicit_preference_dialog.dart';

class PreferenceScreen extends StatefulWidget {
  const PreferenceScreen({
    required this.controller,
    this.recipes = const [],
    super.key,
  });
  final PreferenceController controller;
  final List<RecipeDocument> recipes;
  @override
  State<PreferenceScreen> createState() => _PreferenceScreenState();
}

class _PreferenceScreenState extends State<PreferenceScreen> {
  static const labels = {
    'sweetness': '甘味',
    'saltiness': '塩味',
    'umami': 'うま味',
    'spiciness': '辛味',
    'acidity': '酸味',
    'richness': 'コク',
    'aroma': '香り',
    'texture': '食感',
  };
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  String scopeLabel(Map<String, dynamic> scope) {
    if (scope['kind'] == 'global') return '全料理';
    if (scope['kind'] == 'recipe') {
      final recipe = widget.recipes
          .where((r) => r.id == scope['value'])
          .firstOrNull;
      return recipe?.title ?? 'レシピ：${scope['value']}';
    }
    return '${scope['value']}の料理';
  }

  Future<void> _registerExplicit() async {
    final profile = widget.controller.snapshot?.profile;
    if (profile == null) return;
    final choice = await showDialog<ExplicitPreferenceChoice>(
      context: context,
      builder: (_) => ExplicitPreferenceDialog(
        profile: profile,
        labels: labels,
        recipes: widget.recipes,
      ),
    );
    if (choice == null || !mounted) return;
    await widget.controller.registerExplicit(
      scope: choice.scope,
      dimension: choice.dimension,
      direction: choice.direction,
      declaration: choice.declaration,
      expectedRevision: profile.revision,
    );
  }

  Future<void> _startDriveHistory() async {
    final controller = widget.controller;
    final root = controller.archiveRoot;
    if (root == null) return;
    final legacy = controller.cachedProfile?.root == root
        ? controller.cachedProfile?.profile
        : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Driveの好みの保存を始めますか？'),
        content: Text(
          legacy == null
              ? '空の好みから保存を始めます。端末で登録した好みは、その後に選んで反映できます。'
              : '確認済みのDriveの好み（${legacy.revision}版）を引き継ぎます。以降の更新は履歴に残します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            key: const Key('confirm_start_drive_history'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('始める'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.startDriveHistory(expectedRoot: root, legacy: legacy);
    }
  }

  Future<void> _publishPreference(Map<String, dynamic> preference) async {
    final controller = widget.controller;
    final root = controller.archiveRoot;
    final cached = controller.cachedProfile;
    final head = cached?.historyRecordId;
    if (root == null || cached?.root != root || head == null) return;
    final scope = preference['scope'] as Map<String, dynamic>;
    final previous = (cached!.profile.toJson()['preferences'] as List)
        .where(
          (p) =>
              p['scope']['kind'] == scope['kind'] &&
              p['scope']['value'] == scope['value'] &&
              p['dimension'] == preference['dimension'],
        )
        .firstOrNull;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この好みをDriveへ反映しますか？'),
        content: Text(
          '${scopeLabel(scope)}・${labels[preference['dimension']]}\n'
          'Driveの現在値：${previous == null
              ? '未登録'
              : previous['direction'] == -1
              ? '控えめ'
              : '強め'}\n'
          '変更後：${preference['direction'] == -1 ? '控えめ' : '強め'}\n'
          '${preference['source_kind'] == 'explicit_user' ? preference['declaration'] : '評価から確認して登録（根拠${(preference['feedback_ids'] as List).length}件）'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            key: const Key('confirm_publish_explicit'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('反映する'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (preference['source_kind'] == 'explicit_user') {
        await controller.publishExplicit(
          preference,
          expectedRoot: root,
          expectedHeadId: head,
        );
      } else {
        await controller.publishCandidate(
          preference,
          expectedRoot: root,
          expectedHeadId: head,
        );
      }
    }
  }

  String evidenceDescription(PreferenceEvidence evidence, String dimension) {
    final json = evidence.toJson();
    final feedback = evidence.feedback;
    final session = feedback['cook_session'] as Map;
    final taste = ((feedback['evaluation'] as Map)['taste'] as List)
        .where((item) => item['dimension'] == dimension)
        .firstOrNull;
    final intent = (json['confirmed_intents'] as Map)[dimension];
    final deviation = taste == null ? '未評価' : '${taste['deviation']}';
    final direction = intent == null
        ? '指定なし'
        : intent == -1
        ? '控えめ'
        : '強め';
    return '${session['cooked_at']}・Version ${session['recipe_revision']}\n'
        '${labels[dimension]}の偏差：$deviation、次回の希望：$direction';
  }

  Future<void> _decide(PreferenceCandidate candidate, bool accept) async {
    final revision = widget.controller.snapshot?.profile?.revision;
    if (revision == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accept ? 'この好みを登録しますか？' : 'この候補を見送りますか？'),
        content: Text(
          accept
              ? '対象は${scopeLabel(candidate.scope.toJson())}です。端末内の好みとして登録します。DriveへのProfile反映は準備中です。'
              : '同じ調理記録からは再提案しません。新しい評価が蓄積したら再び候補になることがあります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            key: const Key('confirm_preference_decision'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(accept ? '登録する' : '見送る'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.decide(
      candidate,
      accept: accept,
      expectedRevision: revision,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('料理の好み'),
      actions: [
        IconButton(
          tooltip: '再読込',
          onPressed: widget.controller.isBusy ? null : widget.controller.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final snapshot = controller.snapshot;
        final profile = snapshot?.profile;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('評価を重ねて見つかった傾向を、確認してから登録します。候補だけで好みが変更されることはありません。'),
            const SizedBox(height: 16),
            if (controller.isBusy) const LinearProgressIndicator(),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  controller.error!,
                  key: const Key('preference_error'),
                ),
              ),
            Text('蓄積した評価：${snapshot?.evidence.length ?? 0}件'),
            if (snapshot != null && profile == null)
              FilledButton(
                key: const Key('initialize_profile'),
                onPressed: controller.isBusy ? null : controller.initialize,
                child: const Text('好みの登録を始める'),
              ),
            if (profile != null) ...[
              OutlinedButton.icon(
                key: const Key('register_explicit_preference'),
                onPressed: controller.isBusy ? null : _registerExplicit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('自分の好みを登録'),
              ),
              const SizedBox(height: 24),
              Text(
                '登録済みの好み（更新 ${profile.revision}）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if ((profile.toJson()['preferences'] as List).isEmpty)
                const Text('まだ登録されていません。'),
              for (final p in profile.toJson()['preferences'] as List)
                ListTile(
                  trailing:
                      controller.profileWriter != null &&
                          controller.cachedProfile?.historyRecordId != null
                      ? TextButton(
                          onPressed:
                              controller.isBusy ||
                                  controller.hasPendingProfileWrite
                              ? null
                              : () => _publishPreference(
                                  Map<String, dynamic>.from(p as Map),
                                ),
                          child: const Text('Driveへ反映'),
                        )
                      : null,
                  title: Text(
                    '${labels[p['dimension']]}を${p['direction'] == -1 ? '控えめに' : '強めに'}',
                  ),
                  subtitle: Text(
                    '${scopeLabel(Map<String, dynamic>.from(p['scope'] as Map))}'
                    '${p['source_kind'] == 'explicit_user' ? '\n自分で指定：${p['declaration']}' : '\n評価から確認して登録'}',
                  ),
                ),
              const SizedBox(height: 24),
              Text('確認待ちの候補', style: Theme.of(context).textTheme.titleMedium),
              if (controller.proposals.isEmpty)
                const Text('候補はありません。異なる料理の評価を重ねると、傾向を確認できます。'),
              for (final candidate in controller.proposals)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${labels[candidate.dimension]}を${candidate.direction == -1 ? '控えめに' : '強めに'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(scopeLabel(candidate.scope.toJson())),
                        Text(
                          '${candidate.sessionIds.length}回の調理・${candidate.recipeIds.length}種類の料理、差引スコア${candidate.score}',
                        ),
                        ExpansionTile(
                          title: const Text('根拠の評価を見る'),
                          children: [
                            for (final id in candidate.evidenceIds)
                              ListTile(
                                title: Text(id),
                                subtitle: Text(
                                  '${snapshot!.evidence.firstWhere((e) => e.id == id).feedback['cook_session']['recipe_snapshot']['recipe']['title']}\n'
                                  '${evidenceDescription(snapshot.evidence.firstWhere((e) => e.id == id), candidate.dimension)}',
                                ),
                              ),
                          ],
                        ),
                        Wrap(
                          spacing: 12,
                          children: [
                            FilledButton(
                              onPressed: controller.isBusy
                                  ? null
                                  : () => _decide(candidate, true),
                              child: const Text('登録する'),
                            ),
                            TextButton(
                              onPressed: controller.isBusy
                                  ? null
                                  : () => _decide(candidate, false),
                              child: const Text('見送る'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text('登録履歴：${snapshot!.history.length}版。元の評価と過去の好みを保持しています。'),
            ],
            const SizedBox(height: 24),
            if (controller.archive != null) ...[
              Text(
                '評価をDriveに残す',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Google Driveの「Recipe Cooking Navigator」フォルダを選びます。評価とメモをFeedbackフォルダへ追記します。',
              ),
              OutlinedButton.icon(
                key: const Key('connect_feedback_archive'),
                onPressed: controller.isBusy ? null : controller.connectArchive,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  controller.archiveRoot == null
                      ? 'Drive保存先を選ぶ'
                      : 'Drive保存先を選び直す',
                ),
              ),
              if (controller.archiveRoot != null)
                FilledButton.icon(
                  key: const Key('export_feedback_evidence'),
                  onPressed:
                      controller.isBusy || (snapshot?.evidence.isEmpty ?? true)
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('評価をDriveに保存しますか？'),
                              content: Text(
                                '${snapshot!.evidence.length}件の評価とメモを選択したDriveフォルダへ保存します。保存先の公開範囲を確認してください。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('戻る'),
                                ),
                                FilledButton(
                                  key: const Key('confirm_export_feedback'),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('保存する'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await controller.exportEvidence();
                          }
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('蓄積した評価をDriveへ保存'),
                ),
              if (controller.archiveMessage != null)
                Text(controller.archiveMessage!),
              OutlinedButton.icon(
                key: const Key('import_drive_evidence'),
                onPressed: controller.isBusy || controller.archiveRoot == null
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Driveの評価を読み込みますか？'),
                            content: const Text(
                              '蓄積した評価とメモを端末に追加して候補を再集計します。元ファイルと登録済みの好みは変更しません。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('戻る'),
                              ),
                              FilledButton(
                                key: const Key('confirm_import_drive_evidence'),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('読み込む'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await controller.importEvidence();
                        }
                      },
                icon: const Icon(Icons.download_outlined),
                label: const Text('Driveの評価を読み込む'),
              ),
              if (controller.importMessage != null)
                Text(controller.importMessage!),
              if (controller.importErrors.isNotEmpty)
                ExpansionTile(
                  title: const Text('読み込めなかった評価'),
                  children: [
                    for (final error in controller.importErrors)
                      ListTile(title: Text(error)),
                  ],
                ),
              if (controller.profileCache != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('refresh_drive_profile'),
                  onPressed: controller.isBusy || controller.archiveRoot == null
                      ? null
                      : controller.refreshProfile,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Driveの好みを確認する'),
                ),
                if (controller.profileMessage != null)
                  Text(controller.profileMessage!),
                if (controller.profileWriter != null &&
                    controller.archiveRoot != null) ...[
                  if (controller.hasPendingProfileWrite)
                    OutlinedButton(
                      key: const Key('retry_profile_write'),
                      onPressed: controller.isBusy
                          ? null
                          : controller.retryProfileWrite,
                      child: const Text('好みの保存結果を再確認'),
                    )
                  else if (controller.cachedProfile?.historyRecordId == null)
                    OutlinedButton(
                      key: const Key('start_drive_history'),
                      onPressed: controller.isBusy ? null : _startDriveHistory,
                      child: const Text('Driveの好みの保存を始める'),
                    ),
                ],
                if (controller.cachedProfile != null) ...[
                  Text(
                    'Driveで確認した好み（読取専用・更新 ${controller.cachedProfile!.profile.revision}）',
                  ),
                  for (final p
                      in controller.cachedProfile!.profile
                              .toJson()['preferences']
                          as List)
                    ListTile(
                      title: Text(
                        '${labels[p['dimension']]}を${p['direction'] == -1 ? '控えめに' : '強めに'}',
                      ),
                      subtitle: Text(
                        scopeLabel(
                          Map<String, dynamic>.from(p['scope'] as Map),
                        ),
                      ),
                    ),
                  for (final constraint
                      in controller.cachedProfile!.profile
                              .toJson()['explicit_constraints']
                          as List)
                    ListTile(title: Text('明示的な制約：$constraint')),
                ],
              ],
              const Text('登録済みの好みを選んでDriveへ反映できます。端末とDriveのそれぞれに過去の好みを保持します。'),
            ] else
              const Text('記録は端末内に保存しています。'),
          ],
        );
      },
    ),
  );
}
