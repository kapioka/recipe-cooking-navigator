import 'recipe_section.dart';
import 'recipe_theme.dart';
import 'recipe_heading.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/recipe_library_controller.dart';
import '../domain/feedback_document.dart';
import '../domain/ai_recipe_request.dart';
import '../domain/feedback_validator.dart';
import '../domain/recipe_document.dart';
import '../domain/session_assessment.dart';
import '../platform/feedback_share_platform.dart';
import 'preference_scope.dart';
import 'preference_record_dialog.dart';
import 'ai_recipe_request_screen.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    required this.recipeId,
    required this.controller,
    this.initialImprovementRevision,
    this.sharePlatform = const AndroidFeedbackSharePlatform(),
    super.key,
  });

  final String recipeId;
  final RecipeLibraryController controller;
  final int? initialImprovementRevision;
  final FeedbackSharePlatform sharePlatform;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const _tasteLabels = <String, String>{
    'sweetness': '甘味',
    'saltiness': '塩味',
    'umami': '旨味',
    'spiciness': '辛味',
    'acidity': '酸味',
    'richness': 'コク',
    'aroma': '香り',
    'texture': '食感',
  };

  final _time = TextEditingController();
  final _difficultyComment = TextEditingController();
  final _issues = TextEditingController();
  final _changes = TextEditingController();
  final _comment = TextEditingController();
  final _nextTime = TextEditingController();
  final _goal = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, int?> _taste = {};
  List<Map<String, dynamic>> _sessions = [];
  String? _sessionId;
  int? _improvementRevision;
  int? _preferredImprovementRevision;
  int? _difficulty;
  int? _overall;
  String? _message;
  bool _loading = true;
  bool _busy = false;
  bool _preserveSuccessfulParts = true;

  @override
  void initState() {
    super.initState();
    _preferredImprovementRevision = widget.initialImprovementRevision;
    _load();
  }

  @override
  void dispose() {
    for (final field in [
      _time,
      _difficultyComment,
      _issues,
      _changes,
      _comment,
      _nextTime,
      _goal,
      _notes,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.controller.cookingStore.read();
      final sessions =
          (data['sessions'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .where((session) => session['recipe_id'] == widget.recipeId)
              .toList()
            ..sort(
              (a, b) => (b['completed_at'] as String).compareTo(
                a['completed_at'] as String,
              ),
            );
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
        _message = null;
      });
      if (sessions.isNotEmpty) {
        _selectSession(sessions.first['session_id'] as String);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '調理記録を読み込めません。保存データは変更していません。';
      });
    }
  }

  Map<String, dynamic>? get _selectedSession {
    for (final session in _sessions) {
      if (session['session_id'] == _sessionId) return session;
    }
    return null;
  }

  void _selectSession(String id) {
    final session = _sessions.firstWhere((item) => item['session_id'] == id);
    final assessment = session['assessment'] is Map<String, dynamic>
        ? SessionAssessment.fromJson(
            session['assessment'] as Map<String, dynamic>,
          )
        : null;
    final started = DateTime.parse(session['started_at'] as String);
    final completed = DateTime.parse(session['completed_at'] as String);
    final elapsed = completed.difference(started).inMinutes;
    final cookedRevision = session['revision'] as int;
    final revisions = widget.controller.revisionsFor(widget.recipeId);
    setState(() {
      _sessionId = id;
      _improvementRevision =
          revisions.any((r) => r.revision == _preferredImprovementRevision)
          ? _preferredImprovementRevision
          : revisions.any((r) => r.revision == cookedRevision)
          ? cookedRevision
          : (revisions.isEmpty ? null : revisions.first.revision);
      _time.text =
          '${assessment?.actualTimeMinutes ?? (elapsed < 1 ? 1 : elapsed)}';
      _difficulty = assessment?.difficultyScore;
      _difficultyComment.text = assessment?.difficultyComment ?? '';
      _issues.text = assessment?.issues.join('\n') ?? '';
      _changes.text =
          assessment?.changesMade
              .map((change) => change['description'])
              .join('\n') ??
          '';
      _overall = assessment?.overall;
      _taste
        ..clear()
        ..addEntries(
          assessment?.taste.map(
                (rating) => MapEntry(
                  rating['dimension'] as String,
                  rating['deviation'] as int,
                ),
              ) ??
              const Iterable<MapEntry<String, int>>.empty(),
        );
      _comment.text = assessment?.comment ?? '';
      _nextTime.text = assessment?.nextTimeIntent.join('\n') ?? '';
      _message = null;
    });
  }

  static List<String> _lines(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  SessionAssessment _assessmentFromFields() {
    final minutes = int.tryParse(_time.text.trim());
    if (minutes == null || _difficulty == null || _overall == null) {
      throw const FormatException('実調理時間・実難易度・総合評価を入力してください。');
    }
    final assessment = SessionAssessment(
      actualTimeMinutes: minutes,
      difficultyScore: _difficulty!,
      difficultyComment: _difficultyComment.text.trim(),
      issues: _lines(_issues.text),
      changesMade: [
        for (final text in _lines(_changes.text)) {'description': text},
      ],
      overall: _overall!,
      taste: [
        for (final entry in _taste.entries)
          if (entry.value != null)
            {'dimension': entry.key, 'deviation': entry.value, 'comment': ''},
      ],
      comment: _comment.text.trim(),
      nextTimeIntent: _lines(_nextTime.text),
    );
    assessment.validate();
    return assessment;
  }

  void _report(String message) {
    if (!mounted) return;
    setState(() => _message = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<SessionAssessment?> _saveAssessment() async {
    if (_busy || _sessionId == null) return null;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final assessment = _assessmentFromFields();
      await widget.controller.cookingStore.saveAssessment(
        _sessionId!,
        assessment,
      );
      final session = _selectedSession;
      if (session != null) session['assessment'] = assessment.toJson();
      _report('評価を保存しました。');
      return assessment;
    } catch (error) {
      _report(
        error is FormatException
            ? error.message
            : '評価を保存できませんでした。保存データは変更していません。',
      );
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share({bool asAiRequest = false}) async {
    if (await _saveAssessment() == null || !mounted) return;
    final session = _selectedSession;
    final revisions = widget.controller.revisionsFor(widget.recipeId);
    RecipeDocument? improvement;
    for (final recipe in revisions) {
      if (recipe.revision == _improvementRevision) improvement = recipe;
    }
    if (session == null || improvement == null) {
      _report('調理記録または改善元バージョンが見つかりません。');
      return;
    }
    if (_goal.text.trim().isEmpty) {
      _report('ChatGPTへの改善依頼を入力してください。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feedbackを共有しますか？'),
        content: Text(
          '調理したバージョン ${session['revision']}を評価し、'
          'バージョン ${improvement!.revision}を改善元にします。'
          '評価と一言メモを共有します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirm_share_feedback'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('共有画面へ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final recipeSchema = await rootBundle.loadString(
        'schemas/recipe-v2.schema.json',
      );
      final feedbackSchema = await rootBundle.loadString(
        'schemas/feedback-v2.schema.json',
      );
      final validator = FeedbackValidator.fromSchemaStrings(
        feedbackSchemaSource: feedbackSchema,
        recipeSchemaSource: recipeSchema,
      );
      final document = FeedbackDocumentBuilder(validator).build(
        completedSession: session,
        improvementRecipe: improvement,
        knownRevisions: revisions,
        goal: _goal.text,
        preserveSuccessfulParts: _preserveSuccessfulParts,
        notes: _notes.text,
      );
      if (asAiRequest) {
        final request = AiRecipeRequest.improve(
          feedback: document,
          validator: validator,
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AiRecipeRequestScreen(
              improvementRequest: request,
              library: widget.controller,
            ),
          ),
        );
      } else {
        await widget.sharePlatform.shareJson(jsonEncode(document));
        _report('共有画面を開きました。送信先を確認してください。');
      }
    } catch (_) {
      _report('Feedbackを検証または共有できませんでした。評価は保存されています。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveForPreferences() async {
    final preferences = PreferenceControllerScope.maybeOf(context);
    if (preferences == null || await _saveAssessment() == null || !mounted) {
      return;
    }
    final session = _selectedSession;
    final revisions = widget.controller.revisionsFor(widget.recipeId);
    final improvement = revisions
        .where((r) => r.revision == _improvementRevision)
        .firstOrNull;
    if (session == null || improvement == null) return;
    final choice = await showDialog<PreferenceRecordChoice>(
      context: context,
      builder: (_) => PreferenceRecordDialog(dimensions: _tasteLabels),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final validator = preferences.store.validator;
      final document = FeedbackDocumentBuilder(validator).build(
        completedSession: session,
        improvementRecipe: improvement,
        knownRevisions: revisions,
        goal: _goal.text.trim().isEmpty ? '次回の調理へ評価を反映する。' : _goal.text,
        preserveSuccessfulParts: _preserveSuccessfulParts,
        notes: _notes.text,
      );
      final saved = await preferences.record(
        document,
        categories: {choice.category},
        confirmedIntents: choice.intents,
      );
      _report(
        saved
            ? '好みの記録に残しました。候補は「料理の好み」で確認できます。'
            : preferences.error ?? '記録できませんでした。',
      );
    } catch (_) {
      _report('好みの記録を保存できませんでした。調理の評価は保存されています。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    Key? key,
    int lines = 1,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: key,
      controller: controller,
      maxLines: lines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _score(
    Key key,
    String label,
    int? value,
    ValueChanged<int?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButton<int>(
        key: key,
        style: RecipeTheme.readingBody,
        value: value,
        isExpanded: true,
        itemHeight: null,
        hint: const Text('選択してください'),
        underline: const SizedBox.shrink(),
        items: [
          for (var score = 1; score <= 5; score++)
            DropdownMenuItem(value: score, child: Text('$score')),
        ],
        onChanged: _busy ? null : onChanged,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final revisions = widget.controller.revisionsFor(widget.recipeId);
    final session = _selectedSession;
    final evaluatedRecipe = session == null
        ? null
        : widget.controller.revisionFor(
            widget.recipeId,
            session['revision'] as int,
          );
    return Scaffold(
      appBar: AppBar(title: const Text('調理後の評価')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Theme(
              data: Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.copyWith(
                  bodyMedium: RecipeTheme.readingBody,
                  bodyLarge: RecipeTheme.readingBody,
                ),
                inputDecorationTheme: Theme.of(context).inputDecorationTheme
                    .copyWith(fillColor: RecipeTheme.cream),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_message != null)
                    RecipeSection(
                      color: RecipeTheme.sage,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _message!,
                            key: const Key('feedback_message'),
                          ),
                        ),
                      ],
                    ),
                  if (_sessions.isEmpty)
                    const RecipeSection(
                      title: '調理後の評価',
                      titleStyle: RecipeTheme.readingHeading,
                      icon: Icons.rate_review_outlined,
                      children: [Text('完了した調理記録がありません。調理を完了すると評価できます。')],
                    )
                  else ...[
                    RecipeSection(
                      title: '今回の調理',
                      titleStyle: RecipeTheme.readingHeading,
                      icon: Icons.receipt_long_outlined,
                      children: [
                        if (evaluatedRecipe != null) ...[
                          RecipeHeading(
                            recipe: evaluatedRecipe,
                            controller: widget.controller,
                          ),
                          const SizedBox(height: 16),
                        ],
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '評価する調理記録',
                          ),
                          child: DropdownButton<String>(
                            key: const Key('feedback_session'),
                            style: RecipeTheme.readingBody,
                            value: _sessionId,
                            isExpanded: true,
                            itemHeight: null,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final session in _sessions)
                                DropdownMenuItem(
                                  value: session['session_id'] as String,
                                  child: Text(
                                    'バージョン ${session['revision']}・'
                                    '${DateTime.parse(session['completed_at'] as String).toLocal().toString().substring(0, 16)}',
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (id) {
                                    if (id != null) _selectSession(id);
                                  },
                          ),
                        ),
                        const SizedBox(height: 16),
                        _field(
                          _time,
                          '実調理時間（分）',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                    RecipeSection(
                      title: '作ってみた感想',
                      titleStyle: RecipeTheme.readingHeading,
                      icon: Icons.favorite_border,
                      children: [
                        const Text(
                          '今回感じた難しさと、全体の満足度を記録します。',
                          style: RecipeTheme.readingNote,
                        ),
                        const SizedBox(height: 12),
                        _score(
                          const Key('feedback_difficulty'),
                          '実難易度（1〜5）',
                          _difficulty,
                          (value) => setState(() => _difficulty = value),
                        ),
                        _field(_difficultyComment, '実難易度のメモ'),
                        _score(
                          const Key('feedback_overall'),
                          '総合評価（1〜5）',
                          _overall,
                          (value) => setState(() => _overall = value),
                        ),
                      ],
                    ),
                    RecipeSection(
                      title: '味のふり返り',
                      titleStyle: RecipeTheme.readingHeading,
                      icon: Icons.restaurant_outlined,
                      children: [
                        const Text(
                          '自分の理想を基準に、0は「ちょうどよい」です。',
                          style: RecipeTheme.readingNote,
                        ),
                        const SizedBox(height: 12),
                        for (final entry in _tasteLabels.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: entry.value,
                              ),
                              child: DropdownButton<int>(
                                key: Key('taste_${entry.key}'),
                                style: RecipeTheme.readingBody,
                                value: _taste[entry.key] ?? 9,
                                isExpanded: true,
                                itemHeight: null,
                                underline: const SizedBox.shrink(),
                                items: const [
                                  DropdownMenuItem(
                                    value: 9,
                                    child: Text('未評価'),
                                  ),
                                  DropdownMenuItem(
                                    value: -2,
                                    child: Text('-2 強く不足'),
                                  ),
                                  DropdownMenuItem(
                                    value: -1,
                                    child: Text('-1 少し不足'),
                                  ),
                                  DropdownMenuItem(
                                    value: 0,
                                    child: Text('0 ちょうどよい'),
                                  ),
                                  DropdownMenuItem(
                                    value: 1,
                                    child: Text('+1 少し強い'),
                                  ),
                                  DropdownMenuItem(
                                    value: 2,
                                    child: Text('+2 強すぎる'),
                                  ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(
                                        () => _taste[entry.key] = value == 9
                                            ? null
                                            : value,
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    RecipeSection(
                      title: '今回のメモ',
                      titleStyle: RecipeTheme.readingHeading,
                      icon: Icons.edit_note,
                      children: [
                        _field(_issues, '困ったこと（1行に1件）', lines: 3),
                        _field(_changes, '実際に変更したこと（1行に1件）', lines: 3),
                        _field(_comment, '一言メモ', lines: 3),
                        _field(_nextTime, '次回どうしたいか（1行に1件）', lines: 3),
                      ],
                    ),
                    FilledButton(
                      key: const Key('save_assessment'),
                      onPressed: _busy ? null : _saveAssessment,
                      child: const Text('評価を保存'),
                    ),
                    if (PreferenceControllerScope.maybeOf(context) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          key: const Key('archive_preference_feedback'),
                          onPressed: _busy ? null : _archiveForPreferences,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('好みの記録に残す'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    RecipeSection(
                      title: 'ChatGPTで改善',
                      titleStyle: RecipeTheme.readingHeading,
                      icon: Icons.auto_awesome_outlined,
                      color: RecipeTheme.sage,
                      children: [
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '改善元バージョン',
                          ),
                          child: DropdownButton<int>(
                            key: const Key('feedback_improvement_revision'),
                            style: RecipeTheme.readingBody,
                            value: _improvementRevision,
                            isExpanded: true,
                            itemHeight: null,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final revision in revisions)
                                DropdownMenuItem(
                                  value: revision.revision,
                                  child: Text(
                                    'バージョン ${revision.revision}・${revision.title}',
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _preferredImprovementRevision = value;
                                    _improvementRevision = value;
                                  }),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _field(
                          _goal,
                          '改善してほしいこと',
                          key: const Key('feedback_goal'),
                          lines: 3,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('良かった部分を維持する'),
                          value: _preserveSuccessfulParts,
                          onChanged: _busy
                              ? null
                              : (value) => setState(
                                  () => _preserveSuccessfulParts = value,
                                ),
                        ),
                        _field(_notes, '補足（任意）', lines: 2),
                        FilledButton.icon(
                          key: const Key('improve_with_chatgpt'),
                          onPressed: _busy
                              ? null
                              : () => _share(asAiRequest: true),
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('選択した評価でChatGPTに改善を依頼'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('share_feedback'),
                          onPressed: _busy ? null : _share,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Feedbackを共有'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
