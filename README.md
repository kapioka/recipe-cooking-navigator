# Recipe Cooking Navigator

ChatGPTなどで生成した構造化レシピをスマートフォンへ取り込み、調理前の全体把握、ハンズフリー調理、調理後評価、ChatGPTによる再改善までを一続きで支援することを目指す公開プロジェクトです。

> Status: Android version (`0.2.0`) / レシピ作成・取り込み、調理、評価・改善の主要フローを実装済み

Android用APKは[GitHub Release](https://github.com/kapioka/recipe-cooking-navigator/releases/tag/v0.2.0)からダウンロードできます。

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

- [Recipe Schema v2](schemas/recipe-v2.schema.json)
- [Feedback Schema v2](schemas/feedback-v2.schema.json)

v1 Schemaは公開済み履歴として残しています。現行アプリはv1を自動変換せず、v2用の指示で再作成したRecipeを別保存領域へ取り込みます。

## サンプル

- [Recipe JSON例](examples/recipe-example.json)
- [Feedback JSON例](examples/feedback-example.json)

## Android初期版

現在の初期版は、レシピを取り込んでから調理を完了するまでの主要フローを実装しています。

- Recipeファイルの取り込み、Schema検証、fail-closedでの拒否
- 端末内保存と同一Recipeの複数Revision保持
- レシピ一覧、料理名・食材・タグ検索、ローカルタグ編集
- 材料、器具、事前準備、全体工程の確認
- 対応範囲内の人数変更と、材料・工程・TTSで一貫した分量表示
- 1工程ずつのCooking mode、工程一覧、中断位置の保存・再開
- 音声操作、現在工程の読み上げ、ユーザー起動タイマー
- Cooking mode中の画面常時点灯と終了時の解除
- 調理完了時のCook Session記録、調理後評価、Feedback JSON共有
- 最新Versionと次回使用Versionを分けた履歴管理と、選択Versionからの改善依頼
- Kitchen modeの時計・共通タイマーと料理の好みの記録

### 0.2.0の更新

ホームのクリーム色・深いグリーンを基準に、レシピ作成、内容確認、詳細、履歴、評価、好み、設定、調理、Kitchenの見た目を統一しました。内容ごとのまとまりをやわらかな角丸の面で示し、主なボタンの配置と操作の流れを保っています。

- 本と鍋を組み合わせた新しいアプリアイコン
- 「条件 → 作成中 → 内容確認」で進むレシピ作成と、確認してから保存する取り込み
- Sign in with ChatGPT連携を本体へ統合し、接続状態・モデルの設定を専用画面へ整理
- 入力途中の条件を保持し、取消や保存失敗から戻れる作成画面
- お皿アイコンから任意の料理写真を選び、位置・拡大率を調整して丸く切り抜く機能
- 狭い画面や文字拡大時にも読みやすい入力欄・材料表示・操作欄
- 一覧の検索欄の下に「キッチンツールを開く」と「アーカイブ」のボタンを並べ、アーカイブを直接開けるように変更
- 一覧・詳細の難易度を5段階のバロメーターで表示し、詳細では材料・器具・準備・全工程の後に調理と評価の操作を配置
- 最終工程の下部に「調理完了」を表示し、一覧の三点メニューからも調理後の評価へ移動
- ホームの「︙」から保存済みの最新版レシピへ切替。過去Versionと調理途中の記録は保持

料理写真は端末内に保存し、同じRecipeのVersion間で共通に使います。Recipe / Feedback JSON、Drive共有、Android自動バックアップには含めません。レシピに写真がない場合も、お皿アイコンで表示します。

更新内容と対応範囲は[0.2.0のリリースノート](docs/releases/0.2.0.md)、今後の対象は[ロードマップ](docs/roadmap.md)を参照してください。

### 次回更新に向けた改善

改善したレシピの内容確認と保存後の詳細で、改善元と変わった項目を比較できるようにしました。変更後を色付きで示し、変更前や追加・削除も確認できます。左右スワイプで過去のバージョンを見比べ、表示中のレシピを「今後使うレシピにする」で選べます。閲覧だけでは使用中のバージョンや調理途中の記録は変わりません。

今回から作成するレシピは、送った条件、評価から引き継いだ改善の希望、使用モデルを保存後も確認できます。以前のレシピに作成条件の記録がない場合は、その旨を表示します。

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

FlutterによるAndroid版を実装済みです。現行版はRecipe / Feedback Schema v2に対応し、人数変更、Version履歴、調理後評価・Feedback共有・改善依頼、Kitchen、料理の好みの記録を実装しています。公開ChatGPT Project Packageのv2契約を照合した正式署名APKを配布します。

Sign in with ChatGPTは本体へ統合済みで、Pixel 10aで認証、レシピ生成、確認・保存を確認しています。PoCは開発用の独立プロジェクトとして残していますが、本体の利用に別のPoCアプリは不要です。今回の画面更新はunit / widget tests、静的解析、正式署名buildで検証しています。写真選択・切り抜き・一覧への反映も利用者と実機で確認しました。各画面の最終的な見た目と写真表示の微調整は、利用者による確認が残っています。

SNS共有素材、ファイルによるバックアップ、iOS版は未実装です。調理雑音下での音声認識精度、TalkBack、長時間点灯、Kitchenの背景動作、Profileの実運用は未確認です。

## 開発・検証

Windowsでは、Android Gradle Pluginが親パスの非ASCII文字を拒否するため、リポジトリ付属の`tool/flutterw.ps1`を使用します。

```powershell
dart format --output=none --set-exit-if-changed lib test
pwsh -File .\tool\flutterw.ps1 analyze
pwsh -File .\tool\flutterw.ps1 test
pwsh -File .\tool\flutterw.ps1 build apk --debug
```

一般公開用APKはdebug鍵へfallbackしない専用手順で作成します。鍵の作成、正式署名build、検証方法は[Android release署名手順](docs/release-signing.md)を参照してください。

## ライセンス

このプロジェクトは[Apache License 2.0](LICENSE)で公開しています。再配布する派生物では、ライセンス条件に従って[NOTICE](NOTICE)の帰属表示を保持してください。

レシピ内容や調理支援機能に関する無保証、食品安全上の注意、責任制限については[Disclaimer / 安全上の注意](DISCLAIMER.md)も確認してください。
