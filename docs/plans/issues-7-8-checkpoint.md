# Issue #7 → #8 current checkpoint

2026-10-11。PR #9/#10/#11/#12をmain `35c67c1b46fdaf8be841b92d0cb35507a672f8db`までmerge済み。現在は別worktreeの`codex/siwc-recipe-integration`でWP-04本体連携を修正中。PR #13はDraft。本体生成の実機QAでRecipe読込エラーの報告があり、mergeは保留している。

## 許可と保存境界

ユーザーは実装済みの既存変更（Recipe/Feedback v2、Kitchen、Profile、署名設定）を含むmainへの反映とPixel 10aへのインストールを明示許可した。元のdirty作業ツリーを保持し、別worktreeでremote mainの再開ポリシーを取り込んだ。実機の認証アカウント選択・同意はユーザー操作とする。GitHub Release/tag公開やデータ消去は行わない。

## 機械検証と実装

- #7: 条件入力→依頼プレビュー→標準共有/コピー、選択Feedback改善、Recipe全体または一つの外側jsonフェンスの貼付、共通Validator→プレビュー→確認保存を実装。本体全195テスト、formatter、analyze、debug APK build成功。
- #8: 公式SIWC仕様調査、別packageのFlutter/Android OAuth・署名/identity検証・安全保管・モデル取得・完了SSEテキスト推論、音声入力→編集→確定を実装。全21テスト、formatter、analyze、debug APK build成功。token/認証URL/コードを診断表示しない。
- 公開用worktreeでも本体195テスト、両projectのanalyzeが合格。PoCは別依存を解決して検証する。
- PoC実機試行でloopback callback到達後、「認証コードの交換」で名前解決失敗（SocketException / OS 7）。Wi-Fiとモバイル回線で再現。アプリのforeground復帰後に交換するnative処理を追加。Gradleの別checkout/R:参照残存で一度古いnative classがAPKに入ったため、stable ASCII pathと分離したGradleプロセスへ修正し、APKのnative method存在も確認した。修正版で認証・モデル一覧まで到達したとユーザーが確認。
- 推論は「AIへの送信・回答の受信」でFormatエラー。HTTP診断版で `HTTP 200 / Content-Type指定なし` を確認。JSON推測はせず、UTF-8 byte数をContent-Lengthとして明示し、Content-Type省略時もbounded SSE・response.completedを検証する版へ更新。空本文・通常JSON・HTML・未完了を成功にしない。response.completedに到達したが「完了応答にテキストがありません」と表示され、料理の文章でも同じ結果だった。公式SDKのdelta受信＋完了確認の流れに合わせ、delta/doneテキストを保持して検証済み完了時だけ表示する修正を追加。途中失敗・未完了を拒否し、同じ回答を重複表示しないテストが合格。最新版を端末へ更新し、ユーザーが回答の受信を確認した。実機OAuth・モデル取得・完了テキスト推論のゲートを通過し、WP-04本体統合へ進める。
- 本体の既存署名SHA256は `A2135CCBD3E5ED2053746CE102D8D12E6346032065CCF052EA8E27452402D779`。既存APKにv2 Schemaがあることを確認した。PoCは別package `com.kapioka.rcn_siwc_poc` としてインストール済み。
- Pixel 10aへの両APK更新成功。本体の起動・継続process・致命的例外なしを確認。画面回転設定は開始時・起動中・Home復帰後・PoC更新後とも `accelerometer_rotation=0` / `user_rotation=0`。帰還リンクのAndroid activity解決も確認。ユーザーデータを消す操作は行っていない。

## 残るゲート

1. #7: 公開mainの7ファイル一致を確認し、`tool/build-release.ps1 -PublicAiV2Ready`で正式署名APKを作成済み。0.1.0+1、60865980 bytes、SHA256 `F1EC07DE294674763859F91F1D460725C9985540AACC2912E54B90E34F9D1CAC`。登録証明書と現端末の既存版を再照合し、署名・zipalign・非debuggableを確認。2026-10-11 17:23 JSTに `adb install -r` 成功。
2. #7: [端末QA](issue7-device-qa.md)に従い共有/コピーとChatGPT生成結果の往復を確認する。
3. #8: [調査と端末QA](issue8-siwc-research-and-qa.md)に従い実機OAuth・モデル一覧・`response.completed`を確認する。OAuth・モデル取得・完了回答は実機で確認済み。WP-04の本体生成/Revision改善を実装し、機械検証・正式署名APK更新を完了。本体での生成と保存を実機QAで確認する。失敗時は非公開APIへ迂回せず#7を維持する。
4. 初心者向けの日本語「アプリに戻る」、具体的なAndroid戻り操作、画面上部の状態表示を実装。ユーザーは戻り操作とモデル一覧を確認。入力欄直下を「音声で入力」「確定して送信」の2ボタンへ変更し、枠内で修正できる説明をボタンの下へ配置。全21テスト、analyze、debug buildが合格し、インストール済み。

#7/#8のIssueは端末QA・本体統合まで完了していない。再開heartbeatはPAUSED。状態が変わらない間の再実行・通知は行わない。

最新PoC APK: `build/app/outputs/flutter-apk/app-siwc-poc-stream-text-debug.apk`（元作業フォルダーへ保存）。170245486 bytes、SHA256 `80FA0425ABFBFDAC27C728AD2958180334FB1D0A65FEE18C601CC378AC0E3AFF`。署名SHA256は初回PoCと同じ `7AA732625167931013B4B19A40D358D2A4273AD181BBC8ADC04DDE5FDE40D7C2`。本体APKは同フォルダーの `app-release-issues7-8.apk`。旧 `app-siwc-poc-foreground-debug.apk` はnative処理欠落のため使わない。

## WP-04の実装と再開点

実装正本は C:\Users\akiso\.codex\worktrees\issues-7-8-publish\recipe-cooking-navigator の feature branch。元のdirty作業ツリーを上書きせず保持している。本体から生成/改善する画面を追加し、正本Schema/Workflowを同梱して本文へ添付、共通Validatorと保存前プレビューへ合流した。AIの普通の回答は保存しない。保存時もactiveと過去Revisionを保持する。PoCは一般の通信確認だけであり、雛形を強制する本体生成とは区別する。本体全200テスト、formatter、analyze、debug build、正式署名build合格。PoC21テスト、analyze、共有adapter化後のdebug buildも合格。releaseキャッシュに残る旧R:参照で一度失敗したが、生成済みキャッシュを退避しstable pathで再生成して解消。正本Schema/Workflow等6 assetのAPK内一致、native channelと復帰待ちmethodを確認した。現端末の既存証明書と照合してadb install -rで更新し、起動processと致命的例外なし、return intentの本体activity解決を確認。回転設定は0/0を保持。本体OAuth/Recipe生成実機QAはユーザー操作待ち。

本体連携APK: build/app/outputs/flutter-apk/app-release-siwc-recipe-integration.apk（元作業フォルダー）。66039623 bytes、SHA256 AFFE43EFCCC81C6F0C14412C889F7F8E65C63A47F0B73836A4C28933EDC3995B。0.1.0+1。既存と同じ正式証明書。旧本体APKとPoC APKも保持する。ユーザーに本体の「ChatGPTでレシピを作る」→条件入力→「依頼内容を確認」→「アプリ内で生成する」→本体初回接続→「確定して送信」→プレビュー→「確認して保存」を案内済み。

## 本体生成QAの修復

ユーザーが「レシピ内容が読み取れない。正しい形式で書き出して」と報告した。
本文を記録していないため原因の分類は未確定。送信を`instructions`（正本形式・Workflow）と
`input`（確認済み希望・選択Feedback）へ分離した。JSON object出力指定も追加したが、
その版ではユーザーがHTTP 400を報告したため、追加の`text.format`は除去した。
サーバーの拒否項目は未確定。明示許可されたinstructionsと元のmodel/input/store/streamへ戻す。
HTTP 400は既知の拒否項目・codeだけを固定日本語で示し、サーバー本文や未知の値は表示しない。
形式失敗には固定分類・受信文字数・構文位置を追加し、本文やparserの例外内容は表示しない。
Validatorを緩めず、未完了・不正形式・ID不一致は保存しない。
本体201テスト、PoC22テスト、両analyze、formatter（102 files / 変更なし）、正式署名build合格。
既存版の証明書を再取得・照合し、`adb install -r`で本体を更新した。
署名・zipalign・非debuggable、起動processと致命的例外なし、回転設定0/0を確認。
400が出た指定版APKは元作業フォルダーの`build/app/outputs/flutter-apk/app-release-siwc-json-format.apk`。
66039623 bytes、SHA256 `19EDD2D13896B1C94B4570833ACEC936D9541BF454CC1D9848BEE1D8A34842E3`。
0.1.0+1、従来と同じ正式証明書。旧APKも保持。この版の生成QAはHTTP 400で失敗。
出力指定除去版も本体analyze・PoC23テスト/analyze・formatter・正式署名buildが合格。
本体201テストの既存検証を維持し、追加した共有通信診断をPoCで検証した。
最新APKは`build/app/outputs/flutter-apk/app-release-siwc-instructions.apk`（元作業フォルダー）。
66039623 bytes、SHA256 `F5ECC9F59E3255DF39C39ACF088A21A4C8C6C4242D3EC9D86F0509F870B13D41`。
0.1.0+1、既存と同じ正式証明書を再照合し`adb install -r`成功。旧APKも保持。
PR #13はDraftを保持し、修正版での生成→プレビュー→確認保存はユーザーQA待ち。
再開時はこのworktreeの現在の差分とPR #13を使用し、重複PRを作らない。
次のゲートは修正版APK更新後の生成→プレビュー→明示保存。成功までPR #13のmergeを保留。
