# ChatGPT連携仕様

## 1. 目的

ChatGPTはレシピ内容の生成・改善を担当し、Recipe Cooking Navigatorは表示・進行・記録・共有を担当する。

両者の責務を分離し、アプリが自由文を解析して意味を推測することを避ける。

## 2. ChatGPT → App

ChatGPTは`type: "recipe"`のRecipe JSONを生成する。

アプリ側は受信後にRecipe Schema v1で検証する。

### 受信フロー

1. ChatGPTでRecipe JSONを生成
2. Android SharesheetでRecipe Cooking Navigatorへ共有
3. アプリがJSONとしてparse
4. `schema_version`と`type`を確認
5. JSON Schema検証
6. 合格した場合のみ保存
7. 調理前画面へ表示

不正JSONや未知Schemaは推測補完しない。

## 3. App → ChatGPT

調理後にユーザーが改善を希望する場合、アプリは`type: "recipe_feedback"`のFeedback JSONを生成する。

Feedback JSONには最低限次を含める。

- 改善対象Recipeのsnapshot
- Cook Session
- Evaluation
- 次回希望
- Revision依頼条件

Android SharesheetからChatGPTへ共有する。

MVPではOpenAI APIを直接呼ばない。

## 4. Recipe生成時のChatGPT責務

ChatGPT Project側では次を保証する。

- 材料一覧を先頭付近に配置するデータを作る
- 全体工程を詳細Stepとは別に生成する
- 事前準備を独立タスクとして生成する
- 各Stepで使用材料とそのStepで使う分量を再掲する
- 火加減、時間、完了判断を必要に応じて生成する
- 器具の使い回しを安全性の範囲で考慮する
- 安全な並行作業だけを生成する
- 次工程予告を必要に応じて生成する
- AI想定難易度1〜5と理由を付ける
- Schemaに存在しない独自フィールドを勝手に追加しない

## 5. Revision生成時のChatGPT責務

Feedback JSONを受け取った場合、ChatGPTは元Recipe snapshotを基準にRevisionを作る。

原則：

1. ユーザーが明示した問題を優先する
2. `changes_made`で実際に有効だった変更を考慮する
3. `next_time_intent`を直接的な改善要求として扱う
4. 問題と直接関係しない良好な部分は不必要に変更しない
5. 食品安全上必要な変更は例外として優先する
6. Recipe IDは維持する
7. Recipe revisionを1増やす
8. Schema versionはSchema変更時以外増やさない

## 6. 単発評価と嗜好の区別

Feedbackに、ある料理で「甘味 +1」と記録されていても、ユーザーが全料理で甘さ控えめを好むとは断定しない。

個別Cook Sessionから導けるのは、原則としてそのRecipe Revisionの改善だけ。

将来Preference Profileを使う場合は、複数回・複数料理のEvidenceを別途評価する。

## 7. Recommended revision prompt behavior

Feedback JSONを受け取ったChatGPTは、概念的に次の契約で処理する。

```text
このFeedback documentに含まれる元Recipeと実調理評価を使い、
次回希望と実際に有効だった変更を優先してRecipeを改善する。

良かった部分を不必要に変更しない。
食品安全を損なう変更は採用しない。
Recipe IDを維持し、revisionを1増やす。
出力は対応Recipe Schemaに適合するRecipe JSONだけにする。
```

実際のProject Instructionsは別リポジトリ`kapioka/ai-prompt-library`で公開する想定。

Recipe / Feedback Schemaの正本はこのリポジトリとする。

## 8. Error / fallback

### ChatGPT出力がSchema不適合

アプリは読み込まず、エラー理由を表示する。

MVPではアプリ側で自由文から自動修復しない。

ユーザーは元JSONをChatGPTへ戻し、Schema適合版の再出力を依頼できる。

### 未対応Schema version

読み込みを停止し、対応アプリ版が必要であることを表示する。

### Feedback共有先にChatGPTがない

Sharesheetで他のテキスト受信アプリへ送れること自体は妨げない。特定アプリへの強制依存を作らない。

## 9. Security / privacy

- APIキーをRecipe JSONへ含めない
- アカウントIDや認証情報をFeedbackへ含めない
- 端末ローカルパスを共有文書へ含めない
- Cook history全体を自動送信しない
- ユーザーが改善を依頼した対象Sessionに必要な情報だけ共有する

## 10. 将来のAPI連携

OpenAI API直接統合はMVP外。

将来導入する場合も、現在のRecipe / Feedback JSON契約を維持し、UIや保存モデルをAPI固有仕様へ直接結合しないことを優先する。
