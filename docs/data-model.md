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

例: `schema_version: "1.0.0"`

フィールド構造や意味が変わるときに更新する。

### Recipe revision

個別レシピの改良履歴を表す。

例: `revision: 1`, `revision: 2`

味付けや手順を改善してもSchema自体が同じならSchema versionは変更しない。

## 3. Recipe document

ChatGPTからアプリへ渡すトップレベル文書。

```json
{
  "schema_version": "1.0.0",
  "type": "recipe",
  "recipe": {}
}
```

ChatGPTとアプリの間は、途中で人間が読むためのMarkdownや説明文を混在させず、Schemaに適合するJSONを正本とする。

## 4. Recipe identity / lineage

Recipeは安定した`id`を持つ。

修正版は同じ`id`を維持し、`revision`を増やす。

新しい別料理として保存する場合は新しい`id`を使う。

`parent_revision`は、そのRevisionを生成するときにベースとしたRevisionを表す。

例:

```text
Revision 1
   ↓
Revision 2
   ├─ Revision 3
   └─ Revision 4
```

Revision 4がRevision 2をベースに再調整された場合、`parent_revision: 2`とする。

## 5. App-side active / latest state

`latest`と`active`はRecipe JSONそのものではなく、アプリのローカル保存状態として管理する。

- `latest_revision`: 最後に取り込まれた最も新しいRevision
- `active_revision`: 次回通常表示・調理に使うRevision

両者は一致しなくてもよい。

例:

```text
Revision 4 = latest
Revision 3 = active
```

ユーザーは過去Revisionを`active`へ戻せる。新しいRevisionを取り込んでも、過去Revisionは削除しない。

## 6. Quantity

料理では`1/2個`、`少々`、`2〜3振り`など機械値だけで表せない量がある。

そのためQuantityは表示値を正本として持ち、可能な場合だけ数値も保持する。

```json
{
  "value": 0.5,
  "unit": "個",
  "display": "1/2個"
}
```

機械値にできない場合:

```json
{
  "value": null,
  "unit": null,
  "display": "ひとつまみ"
}
```

アプリ表示では`display`を優先する。

## 7. IngredientとIngredient Use

材料一覧はRecipe直下に一度定義する。

各工程では`ingredient_id`を参照し、その工程で実際に使う量を`quantity`として再掲する。

これにより、材料総量と工程使用量を分離できる。

## 8. Overview

`overview`は調理開始前に見る全体工程。

詳細手順のコピーではなく、料理全体の流れを短く表現する。

## 9. Preparation

加熱開始前に済ませられる作業を独立タスクとして保持する。

チェック状態そのものはRecipe JSONへ書き戻さず、Cook SessionまたはローカルUI stateとして扱える。

## 10. Stage / Step

Recipeは複数のStageを持てる。

StepはCooking modeで1画面に表示できる実行単位とする。

主要情報:

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

## 11. Timer state

Recipe JSONの`timer_seconds`は推奨時間を表す。実際のタイマー開始・停止・残時間はRecipe本体へ保存しない。

タイマーはユーザーがボタンまたは音声で開始する。Step表示だけでは自動開始しない。

## 12. Voice interaction state

音声認識や読み上げのON/OFF、現在認識中かどうか等はアプリのUI / runtime stateでありRecipe JSONには含めない。

Recipe側は読み上げ可能な構造化情報を保持し、アプリ側が現在Stepから読み上げ文を組み立てる。

## 13. Utensil

器具はRecipe直下で定義し、StepからID参照する。

`reuse_note`で使い回しの流れを説明できる。

器具再利用は食品安全より優先しない。

## 14. Estimated difficulty

AIがレシピ作成時に予測した難易度。

```json
{
  "score": 2,
  "reason": "フライパン1つで完結し、加熱判断が単純"
}
```

1〜5で保存する。

ユーザーが調理後に付ける実難易度とは別物。

## 15. Cook Session

1回の実調理を表す。

同じRecipe revisionを複数回作った場合も、Cook Sessionは毎回追加する。

主な項目:

- session ID
- Recipe ID / revision
- 実調理時間
- 実難易度
- 困ったこと
- レシピから実際に変更したこと

## 16. Evaluation

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

対象例:

- sweetness
- saltiness
- umami
- spiciness
- acidity
- richness
- aroma
- texture

## 17. 一言メモ

短い自由記述を、自分の記録とChatGPT改善材料として保存できるようにする。

SNS共有時にそのまま公開するとは限らない。共有文は別途ユーザーが確認・編集できるようにする。

## 18. Next-time intent

「次回どうしたいか」は評価コメントと分離する。

例:

- 甘味を少し下げる
- 旨味を一段強くする
- 合わせ調味料を加熱前に完成させる

ChatGPTによるRevision生成時の直接的な修正要求として利用する。

## 19. Preference profileとの分離

一回のCook Sessionで得た評価を、恒久的なユーザー嗜好へ自動昇格しない。

将来Preference Profileを実装する場合も、複数の独立したCook Sessionから継続的に確認された傾向と、個別料理だけの評価を分離する。

## 20. Feedback document

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

任意の過去Revisionから改善要求を作成できるため、Feedbackは常に選択されたRevisionのsnapshotを含める。

## 21. Portable recipe / backup data

将来のレシピ書き出しやバックアップでは、内部データモデルを特定クラウドサービスへ依存させない。

- 単一Recipe共有: Recipe documentまたは将来定義するポータブルRecipe container
- 全体バックアップ: Recipe、Revision履歴、Cook Session、Evaluation、active状態を含むバックアップ形式を別途定義

バックアップ形式とRecipe Schemaを同一視しない。

## 22. External URL

SNS共有で使用する任意のレシピURLは、Recipeの正本データではない。

アプリはURLを生成・ホスト・検証・維持しない。必要なら共有画面の一時入力または共有用メタデータとして扱う。

## 23. Platform independence

Recipe / Feedback Schemaと主要ドメインモデルはAndroid/iOS共通とする。

OS固有の次の情報をRecipe JSONへ混ぜない。

- Android `content://` URI
- iOS file bookmark / security-scoped URL
- 端末ローカルパス
- OS固有の共有先識別子
- 音声認識セッションID

## 24. Invariants

- Recipe IDとRevisionを混同しない
- Schema versionとRecipe revisionを混同しない
- latestとactiveを混同しない
- 親Revisionを常に最新Revisionと仮定しない
- AI想定難易度とユーザー実難易度を混同しない
- 個別Evaluationを恒久Preferenceとみなさない
- Ingredient総量とStep使用量を混同しない
- Feedback作成時に選択した元Recipe snapshotを欠落させない
- 不明Schemaを推測で取り込まない
- OS固有データを共有Schemaの正本へ混ぜない
