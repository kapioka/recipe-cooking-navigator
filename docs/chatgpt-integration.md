# ChatGPT連携仕様

## 1. 目的

ChatGPTはレシピ内容の生成・改善を担当し、Recipe Cooking Navigatorは表示・進行・記録・Version管理・共有を担当する。

両者の責務を分離し、アプリが自由文を解析して意味を推測することを避ける。

## 2. Machine-to-machine first

ChatGPTとアプリの往復データは、途中で人間が読むことを前提にしない。

- ChatGPT → App: Recipe JSON
- App → ChatGPT: Feedback JSON

人間向けMarkdown、説明文、コードフェンス、補足文章を同じpayloadへ混在させない。

ユーザー向けUIでは`JSON`を前面に出さず、「ChatGPTレシピを取り込む」「ChatGPTで改善」等の表現を使う。

## 3. ChatGPT → App

ChatGPTは`type: "recipe"`のRecipe JSONだけを生成する。

アプリ側は受信後にRecipe Schema v1で検証する。

### Android MVP受信フロー

1. ChatGPTでRecipe JSONを生成
2. Android Sharesheetまたはファイル経由でRecipe Cooking Navigatorへ渡す
3. アプリがJSONとしてparse
4. `schema_version`と`type`を確認
5. JSON Schema検証
6. 合格した場合のみ保存
7. 同一Recipe IDがあれば新Revisionとして追加
8. 新Recipeまたは追加Versionをレシピ詳細へ表示

不正JSONや未知Schemaは推測補完しない。

### iOS将来対応

iPhone版でも同一Recipe Schemaを使い、iOS固有の受け渡し方式だけをplatform layerで実装する。Recipe document自体はAndroid/iOSで変更しない。

## 4. App → ChatGPT

調理後にユーザーが改善を希望する場合、アプリは`type: "recipe_feedback"`のFeedback JSONを生成する。

Feedback JSONには最低限次を含める。

- 改善対象としてユーザーが選択したRecipe Revisionのsnapshot
- Cook Session
- Evaluation
- 次回希望
- Revision依頼条件

Android MVPではSharesheetからChatGPTへ共有する。MVPではOpenAI APIを直接呼ばない。

## 5. 任意Versionからの再改善

改善元は常に最新Versionとは限らない。

例:

```text
Version 2 ← 好み
  ├─ Version 3 ← 最新だが好みではない
  └─ Version 4 ← Version 2を再調整
```

ユーザーがVersion 2を選んで「このバージョンをChatGPTで調整」を実行した場合、Feedback JSONにはVersion 2のsnapshotを入れる。

ChatGPTは新Revisionを作成し、`parent_revision`に改善元Revisionを設定する。

## 6. Recipe生成時のChatGPT責務

ChatGPT Project側では次を保証する。

- 材料一覧を構造化する
- 全体工程を詳細Stepとは別に生成する
- 事前準備を独立タスクとして生成する
- 各Stepで使用材料とそのStepで使う分量を再掲する
- 火加減、時間、完了判断を必要に応じて生成する
- 器具の使い回しを安全性の範囲で考慮する
- 安全な並行作業だけを生成する
- 次工程予告を必要に応じて生成する
- AI想定難易度1〜5と理由を付ける
- Schemaに存在しない独自フィールドを勝手に追加しない
- 出力payloadに人間向け前置き・後書き・Markdownを混ぜない

## 7. Revision生成時のChatGPT責務

Feedback JSONを受け取った場合、ChatGPTは元Recipe snapshotを基準にRevisionを作る。

原則:

1. ユーザーが明示した問題を優先する
2. `changes_made`で実際に有効だった変更を考慮する
3. `next_time_intent`を直接的な改善要求として扱う
4. 一言メモを補助Evidenceとして考慮する
5. 問題と直接関係しない良好な部分は不必要に変更しない
6. 食品安全上必要な変更は例外として優先する
7. Recipe IDは維持する
8. 新しいRecipe revisionを作る
9. `parent_revision`は改善元Revisionを指す
10. Schema versionはSchema変更時以外増やさない
11. 出力はRecipe JSONだけにする

## 8. 単発評価と嗜好の区別

Feedbackに、ある料理で「甘味 +1」と記録されていても、ユーザーが全料理で甘さ控えめを好むとは断定しない。

個別Cook Sessionから導けるのは、原則としてそのRecipe Revisionの改善だけ。

将来Preference Profileを使う場合は、複数回・複数料理のEvidenceを別途評価する。

## 9. 推奨Revision処理契約

```text
このFeedback documentに含まれる改善元Recipeと実調理評価を使い、
次回希望と実際に有効だった変更を優先してRecipeを改善する。

良かった部分を不必要に変更しない。
食品安全を損なう変更は採用しない。
Recipe IDを維持する。
新しいrevisionを作り、parent_revisionには改善元revisionを設定する。
出力は対応Recipe Schemaに適合するRecipe JSONだけにする。
```

実際のProject Instructionsは別リポジトリ`kapioka/ai-prompt-library`で公開する想定。

Recipe / Feedback Schemaの正本はこのリポジトリとする。

## 10. Error / fallback

### ChatGPT出力がSchema不適合

アプリは読み込まず、エラー理由を表示する。

MVPではアプリ側で自由文から自動修復しない。

ユーザーは元データをChatGPTへ戻し、Schema適合版の再出力を依頼できる。

### 未対応Schema version

読み込みを停止し、対応アプリ版が必要であることを表示する。

### Feedback共有先にChatGPTがない

OSの共有機能で他のテキスト受信アプリへ送れること自体は妨げない。特定アプリへの強制依存を作らない。

## 11. SNS共有との分離

ChatGPT連携用JSONとSNS投稿用文章は別の成果物とする。

SNS共有時はアプリが人間向け投稿文を生成し、ユーザーが確認・編集してからOSの共有機能へ渡す。

SNS投稿文へ含められる候補:

- 料理名
- アプリを使ったこと
- 総合評価
- 実難易度
- 味評価 / 好み
- 公開用一言メモ
- ユーザーが自分で取得・入力したレシピURL

アプリはそのURLを生成、ホスト、検証、維持しない。

## 12. Security / privacy

- APIキーをRecipe JSONへ含めない
- アカウントIDや認証情報をFeedbackへ含めない
- 端末ローカルパスを共有文書へ含めない
- Android/iOS固有のローカルURIを共有Schemaへ含めない
- Cook history全体を自動送信しない
- ユーザーが改善を依頼した対象Sessionに必要な情報だけ共有する
- 自分用一言メモをSNSへ自動公開しない

## 13. 将来のAPI連携

OpenAI API直接統合はAndroid MVP外。

将来導入する場合も、現在のRecipe / Feedback JSON契約を維持し、UIや保存モデルをAPI固有仕様へ直接結合しないことを優先する。
