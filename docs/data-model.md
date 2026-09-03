# データモデル

## 1. 基本方針

Recipe Cooking Navigatorでは、次の概念を分離する。

```text
Recipe
 └─ Recipe Revision
      ├─ Cook Session 1
      │    └─ Evaluation
      ├─ Cook Session 2
      │    └─ Evaluation
      └─ Cook Session 3
           └─ Evaluation
```

レシピそのもの、実際に作った記録、感想・評価を同じオブジェクトへ上書きしない。

## 2. Versionの区別

### Schema version

データ形式の互換性を表す。

例：`schema_version: "1.0.0"`

フィールド構造や意味が変わるときに更新する。

### Recipe revision

個別レシピの改良履歴を表す。

例：`revision: 1`, `revision: 2`

味付けを変えたり手順を改善しても、Schema自体が同じならSchema versionは変更しない。

## 3. Recipe document

ChatGPTからアプリへ渡すトップレベル文書。

```json
{
  "schema_version": "1.0.0",
  "type": "recipe",
  "recipe": {}
}
```

`type`は将来別の文書種別を追加しても判別できるよう固定する。

## 4. Recipe identity

Recipeは安定した`id`を持つ。

修正版は同じ`id`を維持し、`revision`を増やす。

新しい別料理として保存する場合は新しい`id`を使う。

MVPではUUID等の一意IDを推奨するが、Schemaでは実装側が生成できる文字列IDとして扱う。

## 5. Quantity

料理では`1/2個`、`少々`、`2〜3振り`など機械値だけで表せない量がある。

そのためQuantityは表示値を正本として持ち、可能な場合だけ数値も保持する。

```json
{
  "value": 0.5,
  "unit": "個",
  "display": "1/2個"
}
```

機械値にできない場合：

```json
{
  "value": null,
  "unit": null,
  "display": "ひとつまみ"
}
```

アプリ表示では`display`を優先する。

## 6. IngredientとIngredient Use

材料一覧はRecipe直下に一度定義する。

各工程では`ingredient_id`を参照し、その工程で実際に使う量を`quantity`として再掲する。

これにより、材料総量と工程使用量を分離できる。

例：しょうゆ大さじ2のうち、大さじ1を途中、大さじ1を仕上げで使うケースに対応できる。

## 7. Overview

`overview`は調理開始前に見る全体工程。

詳細手順のコピーではなく、料理全体の流れを短く表現する。

## 8. Preparation

加熱開始前に済ませられる作業を独立タスクとして保持する。

MVPではチェック状態そのものはRecipe JSONへ書き戻さず、Cook Session側のUI stateとして扱ってよい。

## 9. Stage / Step

Recipeは複数のStageを持てる。

例：

- 下準備
- 加熱
- 仕上げ

各Stageは複数Stepを持つ。

StepはCooking modeで1画面に表示できる実行単位とする。

### Stepの主要情報

- `id`
- `title`
- `instruction`
- `ingredient_uses`
- `heat`
- `timer_seconds`
- `done_when`
- `utensil_ids`
- `parallel_tasks`
- `next_preview`

`heat`や`timer_seconds`は不要な工程では省略できる。

`done_when`は原則として時間以外の実状態を示す。

## 10. Utensil

器具はRecipe直下で定義し、StepからID参照する。

`reuse_note`で使い回しの流れを人間向けに説明できる。

器具再利用は食品安全より優先しない。

## 11. Estimated difficulty

AIがレシピ作成時に予測した難易度。

```json
{
  "score": 2,
  "reason": "フライパン1つで完結し、加熱判断が単純"
}
```

1〜5で保存する。

ユーザーが調理後に付ける実難易度とは別物。

## 12. Cook Session

1回の実調理を表す。

同じRecipe revisionを複数回作った場合も、Cook Sessionは毎回追加する。

主な項目：

- session ID
- Recipe ID / revision
- 実調理時間
- 実難易度
- 困ったこと
- レシピから実際に変更したこと

## 13. Evaluation

Cook Sessionに対するユーザー評価。

### Overall

1〜5の総合満足度。

### Taste deviation

各味覚軸は「強度」ではなく「理想との差」を -2〜+2 で保存する。

```text
-2 かなり弱い
-1 少し弱い
 0 ちょうどよい
+1 少し強い
+2 かなり強い
```

`dimension`は固定enumにしすぎず、v1では一般的な軸をenumとして用意する。

- sweetness
- saltiness
- umami
- spiciness
- acidity
- richness
- aroma
- texture

## 14. Next-time intent

「次回どうしたいか」は評価コメントと分離する。

例：

- 甘味を少し下げる
- 旨味を一段強くする
- 合わせ調味料を加熱前に完成させる

ChatGPTによるRevision生成時の直接的な修正要求として利用する。

## 15. Preference profileとの分離

一回のCook Sessionで得た評価を、恒久的なユーザー嗜好へ自動昇格しない。

将来Preference Profileを実装する場合も、複数の独立したCook Sessionから継続的に確認された傾向と、個別料理だけの評価を分離する。

## 16. Feedback document

アプリからChatGPTへ戻すトップレベル文書。

```json
{
  "schema_version": "1.0.0",
  "type": "recipe_feedback",
  "recipe_snapshot": {},
  "cook_session": {},
  "evaluation": {},
  "revision_request": {}
}
```

`recipe_snapshot`には改善対象となるRecipe documentを含める。

これにより、ChatGPT側が過去会話や外部保存状態を前提とせず、Feedback document単独で修正できる。

## 17. Invariants

- Recipe IDとRevisionを混同しない
- Schema versionとRecipe revisionを混同しない
- AI想定難易度とユーザー実難易度を混同しない
- 個別Evaluationを恒久Preferenceとみなさない
- Ingredient総量とStep使用量を混同しない
- Feedback作成時に元Recipe snapshotを欠落させない
- 不明Schemaを推測で取り込まない
