# ロードマップ / ToDo

このファイルは、現時点で決まっている仕様と、次回以降に進める作業を分けて管理する。

## Current status

実装技術はFlutterに決定済み。Android初期版として、Recipeファイル取り込み、Schema検証、端末内保存、レシピ一覧・検索・タグ・詳細、Cooking mode、音声操作・TTS、タイマー、画面常時点灯、中断・再開、調理完了まで実装済み。

2026-09-06: 自動テスト26件、formatter、static analysis、Android debug buildが成功。Pixel 10a（Android 17 / API 37）へ更新し、既存Recipeデータ、文字サイズ、画面回転設定を保持したまま、検索、調理操作、途中再開、読み上げ、音声操作受付、タイマー調整・リセット、調理完了を確認した。タグ編集・再起動後の永続化、調理雑音下の実声認識、TalkBackは実機未検証。

2026-09-07: 専用のrelease署名鍵と、debug鍵へfallbackしないbuild・検証手順を整備し、署名済み`0.1.0 (1)` APKを生成・検証した。一般公開には、鍵の復旧バックアップ、ライセンス決定、専用署名APKの実機検証、tag・GitHub Release公開が残っている。

### Initial public version scope

初期公開版`0.1.0`の完了点は、「ChatGPTが生成したRecipeをファイルから取り込み、調理前確認を行い、1工程ずつ調理し、明示操作で調理完了を記録する」までとする。

調理後Evaluation、Feedback JSON共有、`active` Revision管理、過去Versionからの改善ループは次版以降のスコープとし、初期版の完了を妨げない。

方針:

- 当面はAndroid版のみを作る
- Flutterで実装する
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
- [x] Android実装技術をFlutterに決定
- [x] 読むモード／作るモード、左右30%・中央40%タップ、左右スワイプの基本設計
- [x] 工程一覧、進捗表示、同じrevisionからの途中再開の基本設計

### 次に決める

- [x] Android初期版の主要画面遷移を確定
- [x] Cooking mode 1画面の情報配置を確定
- [x] 音声操作UIと認識失敗時の基本表示を確定
- [ ] 調理雑音下の誤認識結果を反映した追加挙動を確定
- [ ] 音声読み上げ文の組み立てルールを確定
- [ ] Recipe import時の確認画面を確定
- [ ] Version履歴画面とactive切替UIを確定
- [ ] 評価画面の入力項目と省略可能項目を確定
- [ ] SNS共有プレビュー画面を確定
- [ ] ポータブルRecipeファイルの拡張子・MIME type・内容を決定
- [x] 当面の永続化方式をアプリ内のversion付きJSONファイルに決定（将来のDB移行余地は保持）
- [x] OS非依存ドメインとAndroid固有連携を分離
- [ ] ライセンスを決定

## Phase 1 — Android core MVP

### App shell / home

- [x] Androidプロジェクト初期化
- [x] ホーム = レシピ一覧
- [x] 「ChatGPTレシピを取り込む」を目立つ位置へ配置
- [x] レシピ詳細画面
- [x] 基本ナビゲーション
- [x] ホーム上部にレシピ検索欄を配置
- [x] 料理名・食材名・ユーザータグの部分一致検索
- [x] 料理名・食材名・タグ別の検索候補表示
- [x] 候補選択による検索結果の絞り込み
- [x] 検索語が空の場合に通常一覧へ戻す

### Local tags

- [x] Recipe ID単位でユーザータグを最大5個保存
- [x] タグの追加・編集・削除UI
- [x] タグを全Revisionで共通利用
- [x] 空文字と正規化後の重複を拒否
- [x] Recipe importでローカルタグを上書きしない
- [x] Recipe / Feedback Schemaへタグを混ぜない

### Import / validation / storage

- [ ] Android SharesheetからRecipeを受信
- [x] ファイルからRecipeを読み込み
- [x] Recipe Schema validation
- [x] 不正データをfail-closedで拒否
- [x] ローカル保存
- [x] Recipe ID単位のVersion履歴保存
- [x] latest Revision管理
- [ ] active Revision管理
- [ ] 過去Versionをactiveへ戻す
- [x] 同一Revision重複importの扱いを決定・実装（同一内容はno-op、異なる内容は拒否）

### Pre-cook view

- [x] 材料一覧
- [x] 全体工程
- [x] 器具一覧 / 使い回しメモ
- [ ] 事前準備チェック
- [x] 想定調理時間
- [x] AI想定難易度
- [ ] active Version表示

### Cooking mode

- [x] 読むモードから「調理開始」で作るモードへ切り替え
- [x] 左右30%タップ、左右スワイプで前後工程へ移動
- [x] 中央40%タップで音声操作パネルを開く
- [x] 固定操作デッキと独立した音声操作ボタンを常時表示
- [x] スクロール・ボタン・パネル操作との競合および二重遷移を防止
- [x] 現在工程 / 総工程数を常時表示
- [x] 工程一覧から任意工程へ移動（移動と作業完了を分離）
- [x] Recipe ID・revision・Step IDで途中位置を自動保存
- [x] 「続きから」「最初から」、再開参照欠損時のエラー表示
- [x] 先頭・末尾・長文・文字拡大をPixel 10aで検証
- [ ] TalkBackの操作を実機検証

- [x] 1工程表示
- [x] 前へ / 次へ
- [x] 工程ごとの材料・分量表示
- [x] 火加減
- [x] 完了判断
- [x] 次工程予告
- [x] 並行作業表示
- [x] ユーザー起動タイマー（時間追加・追加分リセットを含む）
- [x] タイマー終了時に自動で次Stepへ進まない
- [x] Cooking mode中の画面常時点灯
- [x] Cooking mode終了時に常時点灯解除

### Voice / TTS — MVP必須

- [x] 音声操作ON/OFF
- [x] 「次」 / 「次へ」
- [x] 「戻る」 / 「前へ」
- [x] 「材料」
- [x] 「全体工程」
- [x] 「調理画面」
- [x] 「タイマー開始」
- [x] 「タイマー停止」
- [x] 「残り時間」
- [x] 「読んで」 / 「もう一度」 / 「音声停止」 / 「読み上げ停止」
- [x] 現在StepのTTS読み上げ
- [x] 認識状態と結果の短い視覚フィードバック
- [ ] 換気扇・水道・調理音のある環境で誤認識テスト
- [ ] TTS再生音を音声認識が誤検知しないか検証

## Phase 2 — Feedback / Revision loop

- [x] 最小Cook Session保存（Session ID、Recipe ID、revision、開始・完了時刻）
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
- [x] 修正版Recipeの再importと複数Revision保持
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

### Cooking Profile / プロフィールカード — post-MVP planned

初期MVPには含めず、Recipe / Feedback loopが実用化した後の共有機能として追加を検討する。

Cooking Profileは、ChatGPTのレシピ調整に使う内部情報と、SNS等へ公開してよい情報を分離する。

- [ ] 内部用Cooking Profileを設計する
- [ ] 公開用Cooking Profileを内部用と別に持てるようにする
- [ ] 内部プロフィールを公開プロフィールへ自動で丸ごとコピーしない
- [ ] 公開項目をユーザーが選択できるようにする
- [ ] 表示名
- [ ] 料理スタイル / 味の好みの短い紹介
- [ ] よく作る料理ジャンル
- [ ] 公開用の一言プロフィール
- [ ] プロフィール画像を任意登録
- [ ] Cook Session数から「作った回数」を算出
- [ ] Recipe ID数から「登録レシピ数」を算出
- [ ] Revision履歴から「育てた / 改良したレシピ」の表示方法を検討
- [ ] 統計値は可能な限り既存データから算出し、手入力値との不整合を避ける
- [ ] 外部リンクを`表示名 + URL`で複数登録できるようにする
- [ ] レシピ置き場、SNS、Webサイト等のリンクを任意表示
- [ ] 公開プロフィールカード画像を生成
- [ ] SNS用プロフィール文章を生成
- [ ] カード / 投稿文の共有前プレビューと編集
- [ ] OS Sharesheetから外部SNSへ共有

外部リンクについて、Recipe Cooking Navigatorはリンク先をホスティングせず、公開設定、有効性、生存期間を保証・監視しない。リンクの管理責任はユーザーと利用する外部サービスにある。

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

電子書籍型UIの拡張案と採用条件は[cooking-mode-ui.md](cooking-mode-ui.md)を参照。

- [ ] 調理ロック（解除導線と長文・安全情報へのアクセスを確保）
- [ ] 材料・時間のタップ／長押しによる文脈操作
- [ ] 人数変更、根拠付きの分量・単位・温度換算
- [ ] 材料チェック、工程内メモ・ハイライト、明示的な工程完了表示
- [ ] 写真・図の拡大、テーマ、片手モード
- [ ] 物理ボタンによる工程送り（音量操作との競合を検証）

- [ ] 複数Cook Sessionからの嗜好傾向分析
- [ ] Preference Profile（複数Sessionからの自動推定。手動Cooking Profileとは分離）
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
