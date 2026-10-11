# Issue #7 → #8 current checkpoint

2026-10-11。PR #9をmain `6beee26983a019c2a94028c20e331da73a46d1d5`へmerge済み。戻り方案内はPR #10をmain `822676710980fb73933e1eef939d39bdd3dd45d9`へmerge済み。

## 許可と保存境界

ユーザーは実装済みの既存変更（Recipe/Feedback v2、Kitchen、Profile、署名設定）を含むmainへの反映とPixel 10aへのインストールを明示許可した。元のdirty作業ツリーを保持し、別worktreeでremote mainの再開ポリシーを取り込んだ。実機の認証アカウント選択・同意はユーザー操作とする。GitHub Release/tag公開やデータ消去は行わない。

## 機械検証と実装

- #7: 条件入力→依頼プレビュー→標準共有/コピー、選択Feedback改善、Recipe全体または一つの外側jsonフェンスの貼付、共通Validator→プレビュー→確認保存を実装。本体全195テスト、formatter、analyze、debug APK build成功。
- #8: 公式SIWC仕様調査、別packageのFlutter/Android OAuth・署名/identity検証・安全保管・モデル取得・完了SSEテキスト推論、音声入力→編集→確定を実装。全16テスト、formatter、analyze、debug APK build成功。token/認証URL/コードを診断表示しない。
- 公開用worktreeでも本体195テスト、両projectのanalyzeが合格。PoCは別依存を解決して検証する。
- PoC実機試行でloopback callback到達後、「認証コードの交換」で名前解決失敗（SocketException / OS 7）が発生。ユーザーがWi-Fiからモバイル回線へ切り替えても同じ結果。認証前のnative HTTPSは通り、callback後の交換はブラウザ表示中に始まっていた。アプリのforeground復帰後に交換する版へ修正・インストールし、ユーザーの再確認待ち。16テストで復帰前の未交換・キャンセルを確認。原因・解決を断定せず、認証成功とは扱わない。
- 本体の既存署名SHA256は `A2135CCBD3E5ED2053746CE102D8D12E6346032065CCF052EA8E27452402D779`。既存APKにv2 Schemaがあることを確認した。PoCは別package `com.kapioka.rcn_siwc_poc` としてインストール済み。
- Pixel 10aへの両APK更新成功。本体の起動・継続process・致命的例外なしを確認。画面回転設定は開始時・起動中・Home復帰後・PoC更新後とも `accelerometer_rotation=0` / `user_rotation=0`。帰還リンクのAndroid activity解決も確認。ユーザーデータを消す操作は行っていない。

## 残るゲート

1. #7: 公開mainの7ファイル一致を確認し、`tool/build-release.ps1 -PublicAiV2Ready`で正式署名APKを作成済み。0.1.0+1、60865980 bytes、SHA256 `F1EC07DE294674763859F91F1D460725C9985540AACC2912E54B90E34F9D1CAC`。登録証明書と現端末の既存版を再照合し、署名・zipalign・非debuggableを確認。2026-10-11 17:23 JSTに `adb install -r` 成功。
2. #7: [端末QA](issue7-device-qa.md)に従い共有/コピーとChatGPT生成結果の往復を確認する。
3. #8: [調査と端末QA](issue8-siwc-research-and-qa.md)に従い実機OAuth・モデル一覧・`response.completed`を確認する。成立後にだけWP-04の本体生成/Revision改善へ進む。失敗時は非公開APIへ迂回せず#7を維持する。
4. 初心者向けにブラウザの日本語「アプリに戻る」ボタン、具体的なAndroid戻り操作、固定した画面上部の状態表示を実装してインストール済み。帰還リンクは秘密情報を持たず、OAuth callbackはloopbackを維持。全16テスト、analyze、debug buildが合格。ユーザーはアプリへ戻れたと回答。認証成功は未確認。

#7/#8のIssueは端末QA・本体統合まで完了していない。再開heartbeatはPAUSED。状態が変わらない間の再実行・通知は行わない。

最新PoC APK: `build/app/outputs/flutter-apk/app-siwc-poc-foreground-debug.apk`（元作業フォルダーへ保存）。170241544 bytes、SHA256 `FBBB2735686EC72F793805E6B09702F3E931AC1668495D8D65947FD785F35446`。署名SHA256は初回PoCと同じ `7AA732625167931013B4B19A40D358D2A4273AD181BBC8ADC04DDE5FDE40D7C2`。本体APKは同フォルダーの `app-release-issues7-8.apk`。
