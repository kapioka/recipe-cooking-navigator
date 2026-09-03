# ロードマップ / ToDo

このファイルは、現時点で決まっている仕様と、次回以降に進める作業を分けて管理する。

## Current status

現在は仕様策定段階。Androidアプリ実装は未開始。

方針:

- 当面はAndroid版のみを作る
- Android版完成後にiPhone版を判断する
- iPhone対応を妨げない共通データ設計を維持する
- 専用サーバー、ホスティング、ユーザーアカウントを前提にしない
- 外部公開・レシピURL管理はユーザー責任とする

## Phase 0 — Specification

### 完了

- [x] 製品目的を定義
- [x] Recipe / Cook Session / Evaluationを分離
- [x] Recipe Schema v1を定義
- [x] Feedback Schema v1を定義
- [x] ChatGPTとのJSON往復を定義
- [x] サンプルJSONを用意
- [x] Recipe revisionとSchema versionを分離
- [x] `parent_revision`によるRevision lineageを定義
- [x] latestとactiveの概念を分離
- [x] 過去Versionから再度ChatGPTへ改善できる方針を定義
- [x] タイマーはユーザー起動と決定
- [x] 音声操作をMVP必須へ変更
- [x] 現在工程の音声読み上げをMVP必須へ変更
- [x] 外部SNS共有は対応、アプリ内SNSは作らないと決定
- [x] レシピURLの発行・ホスティング・生存管理をアプリ責任外と決定
- [x] Android先行 / iOS将来対応方針を定義

### 次に決める

- [ ] Android MVPの画面遷移を確定
- [ ] Cooking mode 1画面の情報配置を確定
- [ ] 音声操作UIと誤認識時の挙動を確定
- [ ] 音声読み上げ文の組み立てルールを確定
- [ ] Recipe import時の確認画面を確定
- [ ] Version履歴画面とactive切替UIを確定
- [ ] 評価画面の入力項目と省略可能項目を確定
- [ ] SNS共有プレビュー画面を確定
- [ ] ポータブルRecipeファイルの拡張子・MIME type・内容を決定
- [ ] ローカルDB/永続化方式を決定
- [ ] Android実装技術を決定
- [ ] iOS将来対応を考慮した共通化方針を実装技術へ反映
- [ ] ライセンスを決定

## Phase 1 — Android core MVP

### App shell / home

- [ ] Androidプロジェクト初期化
- [ ] ホーム = レシピ一覧
- [ ] 「ChatGPTレシピを取り込む」を目立つ位置へ配置
- [ ] レシピ詳細画面
- [ ] 基本ナビゲーション

### Import / validation / storage

- [ ] Android SharesheetからRecipeを受信
- [ ] ファイルからRecipeを読み込み
- [ ] Recipe Schema validation
- [ ] 不正データをfail-closedで拒否
- [ ] ローカル保存
- [ ] Recipe ID単位のVersion履歴保存
- [ ] latest Revision管理
- [ ] active Revision管理
- [ ] 過去Versionをactiveへ戻す
- [ ] 同一Revision重複importの扱いを決定・実装

### Pre-cook view

- [ ] 材料一覧
- [ ] 全体工程
- [ ] 器具一覧 / 使い回しメモ
- [ ] 事前準備チェック
- [ ] 想定調理時間
- [ ] AI想定難易度
- [ ] active Version表示

### Cooking mode

- [ ] 1工程表示
- [ ] 前へ / 次へ
- [ ] 工程ごとの材料・分量表示
- [ ] 火加減
- [ ] 完了判断
- [ ] 次工程予告
- [ ] 並行作業表示
- [ ] ユーザー起動タイマー
- [ ] タイマー終了時に自動で次Stepへ進まない
- [ ] Cooking mode中の画面常時点灯
- [ ] Cooking mode終了時に常時点灯解除

### Voice / TTS — MVP必須

- [ ] 音声操作ON/OFF
- [ ] 「次」
- [ ] 「戻る」
- [ ] 「材料」
- [ ] 「全体工程」
- [ ] 「調理画面」
- [ ] 「タイマー開始」
- [ ] 「タイマー停止」
- [ ] 「残り時間」
- [ ] 「読んで」 / 「もう一度」
- [ ] 現在StepのTTS読み上げ
- [ ] 認識結果の短い視覚/音声フィードバック
- [ ] 換気扇・水道・調理音のある環境で誤認識テスト
- [ ] TTS再生音を音声認識が誤検知しないか検証

## Phase 2 — Feedback / Revision loop

- [ ] Cook Session保存
- [ ] 実難易度1〜5
- [ ] 総合評価1〜5
- [ ] 味の偏り -2〜+2
- [ ] 実際の変更点
- [ ] 困ったこと
- [ ] 一言メモ
- [ ] 次回希望
- [ ] Feedback JSON生成
- [ ] 選択した過去VersionのsnapshotをFeedbackへ含める
- [ ] SharesheetからChatGPTへ共有
- [ ] 修正版Recipeの再import
- [ ] `parent_revision`を使った履歴表示
- [ ] 新Versionをactive候補にする
- [ ] 過去Versionから再調整する操作

## Phase 3 — External sharing

アプリ内SNSは作らず、既存SNSへの投稿素材を生成する。

- [ ] 完成写真を任意登録
- [ ] SNS共有用文章を生成
- [ ] 料理名を含める
- [ ] Recipe Cooking Navigator利用表示
- [ ] 総合評価を含める
- [ ] 実難易度を含める
- [ ] 味評価 / 好みを含める
- [ ] 公開する一言を選択・編集
- [ ] 任意のレシピURL入力欄
- [ ] SNS投稿前プレビュー
- [ ] OS Sharesheetへ画像 + 投稿文を渡す
- [ ] レシピファイルを書き出す
- [ ] 保存先選択はOSへ委ねる

### 明示的に実装しない

- [x] アプリ独自のレシピホスティングを作らない
- [x] 公開URLを発行しない
- [x] 保存先が外部公開可能か自動判定しない
- [x] URLの有効性 / 生存確認をしない
- [x] URLの永続性を保証しない

## Phase 4 — Backup / portability

実利用後に必要性を確認して追加する。

- [ ] 単一Recipeのポータブル書き出し / import
- [ ] 全Recipe + Revision履歴のバックアップ形式設計
- [ ] Cook Session / Evaluationをバックアップへ含める
- [ ] active Version状態をバックアップへ含める
- [ ] バックアップ復元
- [ ] バックアップSchema version / migration方針
- [ ] Android端末間でexport/import検証
- [ ] 将来iOSとの相互importを検証

専用クラウド同期はこのPhaseでも必須ではない。Google Drive等への保存はOS / ユーザー選択へ委ねる。

## Phase 5 — Android stabilization

- [ ] 実際の料理で継続利用テスト
- [ ] ハンバーグ等、両手が汚れる料理で音声操作確認
- [ ] 長いレシピでスクロール負荷確認
- [ ] Versionを複数回改善して履歴が破綻しないか確認
- [ ] 過去Versionへ戻した後の再改善を確認
- [ ] Schema不適合時のエラーUX確認
- [ ] Androidの主要画面サイズで表示確認
- [ ] バッテリー消費 / 画面常時点灯の影響確認
- [ ] アクセシビリティ確認
- [ ] 公開方法を決定

## Phase 6 — iPhone decision gate

Android版が完成・安定してから判断する。

### 判断事項

- [ ] Android版に継続利用価値があるか
- [ ] iPhone対応需要が見込めるか
- [ ] Mac購入が妥当か
- [ ] iPhone実機を用意するか、TestFlight協力者で検証するか
- [ ] 共通コード化の現状を確認
- [ ] iOS固有機能の実装量を見積もる
- [ ] Apple Developer Program / App Store公開を行うか判断

### iOS実装へ進む場合

- [ ] macOS / Xcode環境準備
- [ ] iOSターゲット実装
- [ ] Recipe import / export
- [ ] ローカル保存
- [ ] Version管理
- [ ] Cooking mode
- [ ] 画面常時点灯
- [ ] 音声認識
- [ ] TTS読み上げ
- [ ] タイマー
- [ ] iOS Share Sheet
- [ ] Feedback loop
- [ ] SNS共有
- [ ] AndroidとのRecipe互換性テスト
- [ ] Simulatorテスト
- [ ] iPhone実機 / TestFlightテスト

## Later candidates — 実利用で必要なら

- [ ] 複数Cook Sessionからの嗜好傾向分析
- [ ] Preference Profile
- [ ] 複数料理の並行調理支援
- [ ] タブレット最適化
- [ ] Recipe revision差分表示
- [ ] 文字サイズ / 高コントラストの追加調整

## Non-goals until justified

- 専用バックエンド
- ユーザーアカウント
- アプリ内SNS
- フォロー / コメント / ランキング
- サブスクリプション
- 専用レシピホスティング
- リアルタイムクラウド同期
- 買い物リスト
- 栄養管理
- スーパー在庫 / 価格
- カメラ常時監視
- 複雑なAgent構成
- 大規模推薦基盤

## Development rule

各Phaseは前段の利用上の問題を確認してから拡張する。

機能数ではなく、次の摩擦が減ったかを評価する。

- スクロールや戻り操作
- 次工程の見落とし
- 分量確認の迷い
- 手が汚れて操作できない問題
- 読み上げ不足による画面確認
- 調理器具の無駄
- 待ち時間の無駄
- 画面消灯による中断
- Version改善後に以前の方が良かった場合の復帰困難
- 次回へ改善内容が残らない問題
