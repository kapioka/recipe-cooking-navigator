# ロードマップ / ToDo

このファイルは、製品として到達したい状態と未達Outcomeを管理する。実行ログや固定された逐次手順ではない。

## Current-state contract

- Implementation baseline: `52384ba2e72b144deb0db61c4c852bb69dfd3395`
- Reconciled: 2026-09-27
- 現在の実装状態そのものは`main`のコード、tests、build結果が正本。
- このroadmapは、その状態を短く再開できるように要約する現在地・未達Outcomeの正本。
- Issue、PR、commit、Releaseは履歴・証拠であり、現在の再開地点を決める正本ではない。

Implementation baselineは「roadmapを最後に編集したcommit」ではなく、**Current statusとcheck状態を最後に照合した実装commit**を指す。roadmap自身の文書commitでmarkerを更新しない。

再開時は、baseline以降の差分を最初から全文再読しない。まず変更pathだけを確認する。

- baseline以降がroadmap、Issue整理、説明文など現在実装の意味を変えない文書変更だけなら、Current statusを再調査しない。
- application source、tests、schemas、build/runtime設定など現在実装の意味を変え得る差分がある場合だけ、その差分と影響testsを確認し、Current status / check状態を再同期する。
- 過去判断の理由が必要になった場合だけIssue / PR / commit履歴へ戻る。

roadmapとコードが矛盾する場合は、確認できたコード・testsの実状態を優先し、このroadmapを訂正する。古いroadmap記述に合わせて実装を戻さない。

## Current status

Flutter / Android版。初期公開版`0.1.0`は専用署名APKとして公開済み。

現在の`main`では、初期MVPに加えてGoogle Drive Recipe Inbox、Recipe ID単位のVersion履歴、latest / active Revisionの分離、過去Revisionへのactive切替、`parent_revision`を使った履歴表示まで実装済み。

実機・人間環境でのみ意味のある確認として、調理雑音下の音声認識、TTS音声の誤検知、TalkBack、継続的な実料理利用、バッテリー等が残っている。これらは独立したmachine-readyな実装を止める理由にはしない。

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


## Execution notes

一般的なoutcome-first、Plan / Goalの使い分け、cohesive batching、machine-first Acceptance、user visual/manual QA handoffは上位のCodex global AGENTS / active execution policyを正本とし、このroadmapへ重複定義しない。

この製品固有の追加ルール:

- Phaseは製品領域と成熟度を整理する区分であり、厳密なblocking gateではない。
- 前段のmanual/device QA待ちでも、その結果へ依存しないmachine-readyなReady workは進めてよい。
- 前段の実使用結果によって設計・食品安全・UX判断が変わる場合は先回り実装しない。
- 実機でしか判定できない項目は未確認のまま残し、成功扱いしない。


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
- [x] Version履歴画面とactive切替UIを確定
- [ ] 評価画面の入力項目と省略可能項目を確定
- [ ] SNS共有プレビュー画面を確定
- [ ] ポータブルRecipeファイルの拡張子・MIME type・内容を決定
- [x] 当面の永続化方式をアプリ内のversion付きJSONファイルに決定（将来のDB移行余地は保持）
- [x] OS非依存ドメインとAndroid固有連携を分離
- [x] Apache License 2.0、NOTICE、食品安全上の注意を採用

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
- [x] active Revision管理
- [x] 過去Versionをactiveへ戻す
- [x] 同一Revision重複importの扱いを決定・実装（同一内容はno-op、異なる内容は拒否）

### Google Drive Recipe Inbox

Google Driveをクラウド同期ではなく、WorkからアプリへRecipeファイルを渡す任意の手動受信箱として使う。

- [x] 初期スコープと一方向データフローを仕様化
- [x] 重複、競合、不正ファイル、取込結果の処理契約を仕様化
- [x] Drive文書IDと内容SHA-256を含む端末内取込記録を仕様化
- [x] Androidのシステムフォルダ選択で`Recipe Cooking Navigator/Inbox`を接続
- [x] フォルダアクセス権を端末内に保持し、失効時に安全な再選択を案内
- [x] ホームへ`新しいレシピを確認`ボタンを追加
- [x] 既存の`ChatGPTレシピを取り込む`単一ファイル取込を独立したバックアップ導線として維持
- [x] Inbox未設定、権限失効、provider / 通信 / Work障害時も単一ファイル取込を利用可能にする
- [x] 単一ファイル取込とInbox取込を同じSchema検証・重複判定・Recipe保存処理へ合流
- [x] Inbox直下の`.json`ファイルを手動で非再帰一括走査
- [x] 各ファイルを独立してparse・Schema検証し、正常ファイルだけ保存
- [x] 同一内容をスキップし、同一Recipe ID・revisionの内容違いを拒否
- [x] 取込、保存済みスキップ、拒否の件数とファイル別結果を表示
- [x] 取込後もInboxファイルを削除、移動、名前変更、上書きしない
- [x] 取込記録をRecipe / Feedbackとは別の端末内JSONへ永続化
- [x] Work → アプリだけとし、Feedback Outboxを追加しない
- [x] Google Drive API、独自OAuth、スプレッドシート、SQLを追加しない
- [x] 複数正常ファイル、正常＋不正混在、保存済み重複、競合Revision、権限失効、再起動後再確認のテスト
- [x] Work / Inbox障害中の単一ファイル取込と、両経路間の重複・競合回帰テスト
- [x] 実機でアプリ起動前、起動中、終了後の`accelerometer_rotation` / `user_rotation`が同一であることを確認
- [x] Google Drive providerと`Inbox`フォルダを検証し、以前のフォルダ権限を安全に解除
- [x] 走査の30秒timeout、100ファイル、1ファイル1 MB、合計5 MBの上限を追加
- [x] Inbox処理と状態保存を直列化し、古いreceiptからの再取り込みを可能にする
- [x] Inbox確認中も単一ファイル取込を利用可能にする

### Pre-cook view

- [x] 材料一覧
- [x] 全体工程
- [x] 器具一覧 / 使い回しメモ
- [ ] 事前準備チェック
- [x] 想定調理時間
- [x] AI想定難易度
- [x] active Version表示

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
- [x] `parent_revision`を使った履歴表示
- [x] 新Versionをactive候補にする
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

仕様と依存関係が確定しているmachine-ready部分は先に実装してよい。Android端末間の実ファイル受け渡しや将来iOSとの相互importなど、実環境でしか確認できない項目はmanual/device acceptanceとして後でまとめて検証する。

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

Phaseは固定された逐次実行順ではない。実際の依存関係、仕様の確定度、変更リスク、検証可能性を見て、現在安全に進められるOutcomeを選ぶ。

前段のmanual QAが必要でも、後続機能がその結果へ依存せずmachine-verifiableに実装できるなら先へ進めてよい。逆に、前段結果によって設計が変わる場合は先回り実装しない。

機能数やcheckbox消化数ではなく、次の摩擦が減ったかを評価する。

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
