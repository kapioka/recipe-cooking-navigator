# Recipe Cooking Navigator

ChatGPTなどで生成した構造化レシピをスマートフォンへ共有し、調理前の全体把握から調理後の評価・再改善までを支援する公開プロジェクトです。

> Status: specification-first / app implementation not started

## 目的

通常のレシピは読み物としては分かりやすくても、調理中には「分量を確認するため上へ戻る」「次工程が見えず準備が遅れる」「器具の使い回しや並行作業を判断しづらい」「画面が消える」「作った後の感想が次回へ残らない」といった摩擦があります。

Recipe Cooking Navigatorは、レシピを文章ではなく**実行可能な調理データ**として扱い、次を実現することを目指します。

- 調理開始前に材料・全体工程・器具・事前準備を俯瞰する
- 調理中は1工程ずつ、必要な材料と分量をその場で確認する
- 火加減、時間、完了判断、次工程予告を同じ画面で確認する
- 安全な範囲で器具の使い回しや並行作業を把握する
- 調理モード中だけ画面消灯を防止する
- 調理後に難易度、味、変更点、次回希望を記録する
- 元レシピと評価データをChatGPTへ戻し、修正版レシピを作る

## 基本フロー

```text
ChatGPT
  ↓ Recipe JSON
Android共有
  ↓
レシピ保存
  ↓
材料・全体工程・事前準備
  ↓
調理モード
  ↓
Cook Session / Evaluation
  ↓ Feedback JSON
ChatGPTへ共有
  ↓
修正版 Recipe Revision
```

## ドキュメント

- [製品仕様](docs/product-spec.md)
- [データモデル](docs/data-model.md)
- [ChatGPT連携](docs/chatgpt-integration.md)
- [ロードマップ](docs/roadmap.md)

## JSON Schema

- [Recipe Schema v1](schemas/recipe-v1.schema.json)
- [Feedback Schema v1](schemas/feedback-v1.schema.json)

## サンプル

- [Recipe JSON例](examples/recipe-example.json)
- [Feedback JSON例](examples/feedback-example.json)

## MVPの範囲

初期版ではAndroidを対象に、次を優先します。

1. Recipe JSONの共有受信と検証
2. ローカル保存
3. 材料・全体工程・事前準備の表示
4. 1工程ずつの調理モード
5. タイマー
6. 調理中の画面常時点灯
7. 調理後評価
8. Feedback JSONの生成
9. Android Sharesheet経由でChatGPTへ戻す

初期版ではOpenAI APIキー、専用サーバー、ユーザーアカウント、クラウド同期を必須にしません。

## 設計原則

1. 調理中に前の画面へ戻らなくても作業できる。
2. 調理開始前に全体像を把握できる。
3. 次工程を予測できる。
4. 器具と作業を無駄に増やさない。
5. 食品安全を効率化より優先する。
6. AI推定とユーザー実評価を区別する。
7. 一度の評価からユーザー全体の嗜好を断定しない。
8. データ形式と画面表示を分離する。
9. RecipeのrevisionとSchema versionを分離する。
10. 必要性が確認されるまで複雑な機能を追加しない。

## 現在の状態

現在は仕様策定段階です。アプリコード、CI、クラウド機能はまだ追加していません。

## ライセンス

未決定です。ライセンスを確定するまでは、公開されているソースや文書の利用条件が明示されていない状態として扱ってください。
