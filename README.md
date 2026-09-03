# Recipe Cooking Navigator

ChatGPTなどで生成した構造化レシピをスマートフォンへ取り込み、調理前の全体把握、ハンズフリー調理、調理後評価、ChatGPTによる再改善までを一続きで支援する公開プロジェクトです。

> Status: specification-first / Android implementation not started

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

## JSON Schema

- [Recipe Schema v1](schemas/recipe-v1.schema.json)
- [Feedback Schema v1](schemas/feedback-v1.schema.json)

## サンプル

- [Recipe JSON例](examples/recipe-example.json)
- [Feedback JSON例](examples/feedback-example.json)

## Android MVP

初期実用版では次を優先します。

1. ホームをレシピ一覧にし、「ChatGPTレシピを取り込む」を目立つ位置に置く
2. Recipe JSONの共有受信・ファイル読み込み・Schema検証
3. ローカル保存とRecipe Version履歴
4. 使用中Versionと最新Versionを分離して管理
5. 材料・全体工程・器具・事前準備の表示
6. 1工程ずつの調理モード
7. 音声操作と現在工程の読み上げ
8. ユーザー起動タイマー
9. 調理中の画面常時点灯
10. 調理後評価と一言メモ
11. Feedback JSONを生成しChatGPTへ戻す
12. 修正版を新Versionとして取り込み、過去Versionへ戻せる

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

現在は仕様策定段階です。Androidアプリコード、CI、クラウド機能、iOSコードはまだ追加していません。

## ライセンス

未決定です。ライセンスを確定するまでは、公開されているソースや文書の利用条件が明示されていない状態として扱ってください。
