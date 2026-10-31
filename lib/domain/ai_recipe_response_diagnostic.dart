import 'dart:convert';

import 'recipe_validator.dart';

/// Fixed labels and numeric lengths only. Never return parser messages, paths,
/// response excerpts, schema values, or request/account contents.
String describeAiRecipeFailure(String source, RecipeImportErrorCode code) {
  final payload = unwrapRecipeJson(source);
  var kind = switch (code) {
    RecipeImportErrorCode.malformedJson => '構文不正',
    RecipeImportErrorCode.invalidRoot => 'オブジェクト以外',
    RecipeImportErrorCode.unsupportedSchemaVersion => '未対応の形式',
    RecipeImportErrorCode.unexpectedDocumentType => 'レシピ以外',
    RecipeImportErrorCode.schemaViolation => '必須情報・形式・参照の不一致',
  };
  int? offset;
  if (code == RecipeImportErrorCode.malformedJson) {
    if (payload.isEmpty) {
      kind = '本文なし';
    } else if (!payload.startsWith('{') && !payload.startsWith('[')) {
      kind = '説明文・対応外の囲み';
    } else {
      try {
        jsonDecode(payload);
      } on FormatException catch (error) {
        offset = error.offset;
        if (error.message.contains('Unexpected end')) kind = '本文末尾で途切れ';
      }
    }
  }
  return 'AIの回答が対応するレシピ形式になっていません。保存していません。この画面で形式を直して作り直せます。'
      '\n形式確認: $kind / 受信文字: ${source.length}'
      '${offset == null ? '' : ' / 構文位置: $offset'}';
}
