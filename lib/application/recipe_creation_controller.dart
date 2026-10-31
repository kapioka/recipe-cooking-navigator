import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:siwc_client/siwc_contract.dart';

import '../domain/ai_recipe_prompt.dart';
import '../domain/ai_recipe_request.dart';
import '../domain/ai_recipe_response_diagnostic.dart';
import '../domain/recipe_validator.dart';
import 'ai_recipe_import.dart';
import 'recipe_ai_session.dart';
import 'recipe_library_controller.dart';

enum RecipeCreationStage {
  editing,
  starting,
  generating,
  validating,
  preview,
  saving,
  saved,
}

class RecipeCreationController extends ChangeNotifier {
  RecipeCreationController(this.session, this.library);
  final RecipeAiSession session;
  final RecipeLibraryController library;
  RecipeCreationStage stage = RecipeCreationStage.editing;
  RecipeImportPreview? preview;
  AiRecipeRequest? candidateRequest;
  String? candidateModel;
  String? candidateConditions;
  String? conditionsSaveWarning;
  String get candidateConditionsDescription {
    final feedback = candidateRequest?.feedback;
    final recreation = candidateRequest?.recreation;
    return [
      candidateModel == null
          ? '貼り付けた回答を形式検証して表示しています。生成元や送信完了はアプリでは確認できません。'
          : 'ChatGPTの回答を受信し、レシピの形式を検証して表示しています。\n使用モデル: $candidateModel',
      if (feedback != null) ...[
        '改善元: バージョン ${(feedback['recipe_snapshot'] as Map)['recipe']['revision']}',
        '評価から引き継いだ改善の希望\n${(feedback['revision_request'] as Map)['goal']}',
        candidateModel == null
            ? '共有用の依頼には、選択した調理後の評価も含めました。'
            : '選択した調理後の評価も一緒に送っています。',
      ],
      if (recreation != null)
        '作り直し元: Version ${(recreation['recipe_snapshot'] as Map)['recipe']['revision']}（調理評価なし）',
      candidateConditions ?? 'この回答の送信条件は記録されていません。',
    ].join('\n\n');
  }

  String? rejectedSource, rejectedConditions, rejectedProblem;
  AiRecipeRequest? rejectedRequest;
  RecipeImportException? importIssue;
  bool get canRepair =>
      rejectedSource != null &&
      rejectedRequest != null &&
      importIssue?.needsAppUpdate != true;

  void restoreRejected() {
    final data = session.rejectedRecipe;
    if (data == null) return;
    try {
      rejectedSource = data['source'] as String;
      rejectedConditions = data['conditions'] as String;
      rejectedProblem = data['problem'] as String?;
      rejectedRequest = AiRecipeRequest.fromJson(
        Map<String, dynamic>.from(data['request'] as Map),
      );
      final code = data['code'] as String?;
      importIssue = RecipeImportException(
        RecipeImportErrorCode.values.firstWhere(
          (c) => c.name == code,
          orElse: () => RecipeImportErrorCode.schemaViolation,
        ),
        data['message'] as String,
        receivedSchemaVersion: data['schema_version'] as String?,
      );
      message = '${importIssue!.message}\n前の回答を保持しています。自動送信はしていません。';
    } catch (_) {
      message = '前の回答を復元できませんでした。条件から作り直せます。';
    }
  }

  Future<void> rejectAnswer(
    AiRecipeRequest request,
    String source,
    String conditions,
    RecipeImportPreparation prepared,
  ) async {
    rejectedSource = source.length <= 1024 * 1024 ? source : null;
    rejectedConditions = conditions;
    rejectedRequest = request;
    importIssue = prepared.issue;
    rejectedProblem = [prepared.message, ...?importIssue?.details].join('\n');
    message = prepared.issue?.message ?? prepared.message;
    diagnostic = prepared.errorCode == null
        ? prepared.message
        : describeAiRecipeFailure(source, prepared.errorCode!);
    if (rejectedSource != null) {
      await session.saveRejectedRecipe({
        'source': source,
        'conditions': conditions,
        'request': request.toJson(),
        'message': message,
        'code': prepared.errorCode?.name,
        'schema_version': importIssue?.receivedSchemaVersion,
        'problem': rejectedProblem,
      });
    }
  }

  Future<void> repair(Future<AiRecipePrompt> Function() loadPrompt) async {
    if (!canRepair || busy) return;
    final request = rejectedRequest!.repairAnswer(
      rejectedSource!,
      rejectedProblem ?? message ?? '形式不一致',
      rejectedConditions!,
    );
    await generate(request, rejectedConditions!, loadPrompt);
  }

  Future<void> clearRejected() async {
    rejectedSource = rejectedConditions = rejectedProblem = null;
    rejectedRequest = null;
    importIssue = null;
    await session.saveRejectedRecipe(null);
  }

  String? message;
  String? diagnostic;
  SiwcFailureKind? failureKind;
  int _attempt = 0;
  bool _disposed = false;
  int elapsedSeconds = 0;
  bool receivingAnswer = false;
  Timer? _timer;
  bool get generating => [
    RecipeCreationStage.starting,
    RecipeCreationStage.generating,
    RecipeCreationStage.validating,
  ].contains(stage);
  bool get busy => generating || stage == RecipeCreationStage.saving;
  bool _current(int id) => !_disposed && id == _attempt;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> generate(
    AiRecipeRequest request,
    String conditions,
    Future<AiRecipePrompt> Function() loadPrompt,
  ) async {
    if (busy) return;
    final model = session.model;
    if (!session.client.canInfer ||
        model == null ||
        !session.models.any((m) => m.slug == model)) {
      message = 'ChatGPT連携で接続と使用するモデルを確認してください。';
      _changed();
      return;
    }
    final id = ++_attempt;
    stage = RecipeCreationStage.starting;
    message = diagnostic = null;
    failureKind = null;
    elapsedSeconds = 0;
    receivingAnswer = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds++;
      _changed();
    });
    _changed();
    try {
      final prompt = await loadPrompt();
      if (!_current(id)) return;
      final submission = prompt.build(request, conditions);
      stage = RecipeCreationStage.generating;
      _changed();
      final source = await session.client.infer(
        model,
        submission.input,
        instructions: submission.instructions,
        onReceiving: () {
          if (!_current(id) ||
              stage != RecipeCreationStage.generating ||
              receivingAnswer) {
            return;
          }
          receivingAnswer = true;
          _changed();
        },
      );
      if (!_current(id)) return;
      stage = RecipeCreationStage.validating;
      _changed();
      final prepared = await prepareAiRecipe(
        library,
        request,
        source,
        replacing: preview,
      );
      if (!_current(id)) {
        if (prepared.preview case final abandoned?) {
          library.cancelPreparedImport(abandoned);
        }
        return;
      }
      if (prepared.preview == null) {
        await rejectAnswer(request, source, conditions, prepared);
        if (!_current(id)) return;
        stage = RecipeCreationStage.editing;
      } else {
        await clearRejected();
        if (!_current(id)) return;
        preview = prepared.preview;
        candidateRequest = request;
        candidateModel = model;
        candidateConditions = conditions;
        diagnostic = '受信したレシピ本文: ${source.length}文字';
        stage = RecipeCreationStage.preview;
      }
    } on SiwcFailure catch (error) {
      if (!_current(id)) return;
      failureKind = error.kind;
      diagnostic = error.message;
      message = switch (error.kind) {
        SiwcFailureKind.authentication => 'ChatGPTへの接続が切れました。条件は残っています。',
        SiwcFailureKind.permission => 'このアカウントでは現在作成できません。利用状況を確認してください。',
        SiwcFailureKind.request => '作成の依頼を受け付けられませんでした。別の方法でも作れます。',
        SiwcFailureKind.network => '回答を受け取れませんでした。条件は残っています。送信済みの可能性があります。',
        SiwcFailureKind.timeout =>
          '回答の受信が時間切れになりました。条件は残っています。通信を確認するか、モデルを変更して再試行できます。',
        SiwcFailureKind.responseTooLarge =>
          '回答の受信量が上限を超えたため中止しました。条件は残っています。改善内容を絞るか、モデルを変更して再試行できます。',
        _ => '作成を完了できませんでした。条件は残っています。',
      };
      stage = RecipeCreationStage.editing;
    } catch (_) {
      if (!_current(id)) return;
      message = '作成を完了できませんでした。条件は残っています。';
      stage = RecipeCreationStage.editing;
    } finally {
      if (_current(id)) {
        _timer?.cancel();
        _changed();
      }
    }
  }

  void cancel() {
    if (!generating) return;
    ++_attempt;
    _timer?.cancel();
    session.client.cancel();
    stage = RecipeCreationStage.editing;
    message = '作成を中止しました。サービス側の処理・利用枠は取り消せない場合があります。';
    _changed();
  }

  void edit() {
    if (busy) return;
    stage = RecipeCreationStage.editing;
    _changed();
  }

  void showPreview() {
    if (busy || preview == null) return;
    stage = RecipeCreationStage.preview;
    _changed();
  }

  Future<RecipeImportResult?> save() async {
    if (busy || preview == null || stage == RecipeCreationStage.saved) {
      return null;
    }
    stage = RecipeCreationStage.saving;
    message = null;
    conditionsSaveWarning = null;
    _changed();
    final prepared = await library.reprepareImport(preview!);
    RecipeImportResult result;
    if (prepared.preview == null) {
      result = RecipeImportResult(RecipeImportStatus.failed, prepared.message);
    } else {
      preview = prepared.preview;
      result = await library.confirmPreparedImport(
        preview!,
        preserveActive: true,
      );
    }
    if (_disposed) return result;
    if (result.status == RecipeImportStatus.imported ||
        result.status == RecipeImportStatus.alreadyExists) {
      if (candidateRequest != null) {
        conditionsSaveWarning = await library.recordCreationConditions(
          preview!.recipeId,
          preview!.revision,
          candidateConditionsDescription,
        );
      }
      if (_disposed) return result;
      stage = RecipeCreationStage.saved;
    } else {
      stage = RecipeCreationStage.preview;
      message = 'レシピを保存できませんでした。内容はこの画面に残っています。';
      diagnostic = result.message;
    }
    _changed();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_attempt;
    _timer?.cancel();
    if (generating) session.client.cancel();
    if (preview case final value?) {
      scheduleMicrotask(() => library.cancelPreparedImport(value));
    }
    super.dispose();
  }
}
