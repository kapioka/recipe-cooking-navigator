# Recipe Cooking Navigator

ChatGPTなどで生成した構造化レシピをスマートフォンへ取り込み、調理前の全体把握、ハンズフリー調理、調理後評価、ChatGPTによる再改善までを一続きで支援することを目指す公開プロジェクトです。

> Status: Android initial version (`0.1.0`) / レシピのファイル取り込みから調理完了まで実装済み

ChatGPT側で対応Recipeを生成するための公開Packageは、[Recipe Cooking Navigator — ChatGPT Project Package](https://github.com/kapioka/ai-prompt-library/tree/main/prompts/food-drink/recipe-cooking-navigator)で配布しています。

## 目的

通常のレシピは読み物としては分かりやすくても、調理中には「分量確認のため前へ戻る」「次工程が見えず準備が遅れる」「器具の使い回しや並行作業を判断しづらい」「手が汚れてスマートフォンへ触れない」「画面が消える」「作った後の感想が次回へ残らない」といった摩擦があります。

Recipe Cooking Navigatorは、レシピを文章ではなく**実行可能な調理データ**として扱い、次を目指します。

- 調理開始前に材料・全体工程・器具・事前準備を俯瞰する
- 調理中は1工程ずつ、必要な材料と分量をその場で確認する
- 火加減、時間、完了判断、次工程予告を同じ画面で確認する
- 安全な範囲で器具の使い回しや並行作業を把握する
- 音声で「次」「戻る」「読んで」「もう一度」「タイマー開始」等を操作する
- 現在工程を音声読み上げできる
- 調理モード中だけ画面消灯を防止する
- 調理後に難易度、味、一言メモ、実際の変更、次回希望を記録する
- 任意の過去Versionを次回使用版として選び、そのVersionから再度ChatGPTへ改善を依頼できる
- 外部SNS向けに料理写真・評価・味の好み・一言・任意URLを含む共有素材を作る

## 基本フロー

```text
ChatGPT
  ↓ Recipe JSON（機械間データ。途中で人が読むことを前提にしない）
Recipe Cooking Navigator
  ↓
レシピ保存 / Version管理
  ↓
材料・全体工程・事前準備
  ↓
調理モード
  ├─ 音声操作
  ├─ 音声読み上げ
  ├─ 手動開始タイマー
  └─ 画面常時点灯
  ↓
Cook Session / Evaluation / 一言メモ
  ↓ Feedback JSON
ChatGPTへ共有
  ↓
新しいRecipe Versionを追加
```

## プラットフォーム方針

- **当面はAndroid版だけを実装する**
- 最終的にはiPhone版も提供できる構造を維持する
- Recipe / Feedback Schema、保存モデル、Version履歴、評価モデルはAndroid/iOSで共通にする
- iPhone実装はAndroid版完成後に再判断する
- Mac購入、Xcode、実機/TestFlight検証はiPhone開発へ進む段階で判断する

詳細: [プラットフォーム方針](docs/platform-strategy.md)

## ドキュメント

- [製品仕様](docs/product-spec.md)
- [データモデル](docs/data-model.md)
- [ChatGPT連携](docs/chatgpt-integration.md)
- [プラットフォーム方針](docs/platform-strategy.md)
- [ロードマップ / ToDo](docs/roadmap.md)
- [ChatGPT Project Package](https://github.com/kapioka/ai-prompt-library/tree/main/prompts/food-drink/recipe-cooking-navigator)

## JSON Schema

- [Recipe Schema v1](schemas/recipe-v1.schema.json)
- [Feedback Schema v1](schemas/feedback-v1.schema.json)

## サンプル

- [Recipe JSON例](examples/recipe-example.json)
- [Feedback JSON例](examples/feedback-example.json)

## Android初期版

現在の初期版は、レシピを取り込んでから調理を完了するまでの主要フローを実装しています。

- Recipeファイルの取り込み、Schema検証、fail-closedでの拒否
- 端末内保存と同一Recipeの複数Revision保持
- レシピ一覧、料理名・食材・タグ検索、ローカルタグ編集
- 材料、器具、事前準備、全体工程の確認
- 1工程ずつのCooking mode、工程一覧、中断位置の保存・再開
- 音声操作、現在工程の読み上げ、ユーザー起動タイマー
- Cooking mode中の画面常時点灯と終了時の解除
- 調理完了時の最小Cook Session記録

次の主要バージョンでは、Android Sharesheet受信、`active` Revision管理、事前準備のチェック、調理後評価、Feedback JSON共有、過去Versionからの改善ループを追加します。詳細は[ロードマップ](docs/roadmap.md)を参照してください。

## 共有方針

### 外部SNS共有

アプリ内SNSは作りません。Android/iOSの共有機能を利用して既存SNSへ共有します。

共有候補:

- 料理写真（任意）
- 料理名
- Recipe Cooking Navigatorを使ったこと
- 総合評価
- 実調理難易度
- 味の好み・評価
- 一言メモの公開用内容
- ユーザーが自分で用意したレシピURL（任意）

### レシピファイル

Recipe JSONはユーザーに「JSON」と意識させず、UIでは「ChatGPTレシピ」「レシピを取り込む」「レシピを書き出す」等の表現を優先します。

将来、ポータブルなレシピファイルとして書き出せるようにします。

### ホスティング責任

Recipe Cooking Navigatorは以下を行いません。

- レシピファイルのホスティング
- 公開URLの発行
- 外部ストレージの公開設定
- URLの有効性・生存確認
- 公開期間の保証

ファイルの保存先、公開範囲、URL取得、URL維持はユーザーと利用する外部サービスの責任です。

## 将来のバックアップ

専用クラウド同期を最初から作りません。まずはレシピ、Version履歴、Cook Session、Evaluationをバックアップファイルへ書き出し、ユーザーが端末、Google Drive、OneDrive等の任意の保存先を選べる方式を検討します。

## 非目標

必要性が確認されるまで、次は実装対象にしません。

- アプリ内SNS / フォロー / コメント / ランキング
- 専用レシピホスティング
- 専用クラウドアカウント
- リアルタイム端末間同期
- 買い物リスト
- 栄養管理
- スーパー在庫 / 価格取得
- カメラ常時監視
- 複雑なAgent構成

## 設計原則

1. 調理中に前の画面へ戻らなくても作業できる。
2. 調理開始前に全体像を把握できる。
3. 次工程を予測できる。
4. 手が塞がる・汚れる工程でもハンズフリーで進められる。
5. 器具と作業を無駄に増やさない。
6. 食品安全を効率化より優先する。
7. AI推定とユーザー実評価を区別する。
8. 一度の評価からユーザー全体の嗜好を断定しない。
9. 人間向けUIと機械間JSONを分離する。
10. Recipe revisionとSchema versionを分離する。
11. 最新Versionと次回使用Versionを同一視しない。
12. 外部公開・ホスティング責任をアプリが抱え込まない。
13. Android先行でもiOS移植を不必要に難しくする設計を避ける。
14. 必要性が確認されるまで複雑な機能を追加しない。

## 現在の状態

FlutterによるAndroid初期版を実装済みです。Pixel 10aでファイル取り込み、保存データを維持した更新、Cooking mode、TTS、音声操作、タイマー、中断・再開を確認しています。

調理後評価、Feedback JSON共有、`active` Revision切り替え、SNS共有、バックアップ、iOS版は未実装です。また、調理雑音下での音声認識精度は引き続き実機検証が必要です。

## 開発・検証

Windowsでは、Android Gradle Pluginが親パスの非ASCII文字を拒否するため、リポジトリ付属の`tool/flutterw.ps1`を使用します。

```powershell
dart format --output=none --set-exit-if-changed lib test
pwsh -File .\tool\flutterw.ps1 analyze
pwsh -File .\tool\flutterw.ps1 test
pwsh -File .\tool\flutterw.ps1 build apk --debug
```

## ライセンス

未決定です。ライセンスを確定するまでは、公開されているソースや文書の利用条件が明示されていない状態として扱ってください。
