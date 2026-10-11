# Issue #7 → #8 current checkpoint

2026-10-11。PR #9/#10/#11をmain `21e38c88a123338a47e29cf19d56731594a52972`までmerge済み。本再開点はPR #12のPoC復帰・通信・入力UI修正を含む。

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
3. #8: [調査と端末QA](issue8-siwc-research-and-qa.md)に従い実機OAuth・モデル一覧・`response.completed`を確認する。OAuth・モデル取得・完了回答は実機で確認済み。次はWP-04の本体生成/Revision改善へ進む。失敗時は非公開APIへ迂回せず#7を維持する。
4. 初心者向けの日本語「アプリに戻る」、具体的なAndroid戻り操作、画面上部の状態表示を実装。ユーザーは戻り操作とモデル一覧を確認。入力欄直下を「音声で入力」「確定して送信」の2ボタンへ変更し、枠内で修正できる説明をボタンの下へ配置。全21テスト、analyze、debug buildが合格し、インストール済み。

#7/#8のIssueは端末QA・本体統合まで完了していない。再開heartbeatはPAUSED。状態が変わらない間の再実行・通知は行わない。

最新PoC APK: `build/app/outputs/flutter-apk/app-siwc-poc-stream-text-debug.apk`（元作業フォルダーへ保存）。170245486 bytes、SHA256 `80FA0425ABFBFDAC27C728AD2958180334FB1D0A65FEE18C601CC378AC0E3AFF`。署名SHA256は初回PoCと同じ `7AA732625167931013B4B19A40D358D2A4273AD181BBC8ADC04DDE5FDE40D7C2`。本体APKは同フォルダーの `app-release-issues7-8.apk`。旧 `app-siwc-poc-foreground-debug.apk` はnative処理欠落のため使わない。
