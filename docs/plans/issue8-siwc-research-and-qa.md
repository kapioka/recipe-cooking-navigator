# Issue #8: SIWC Android PoC / 実装ゲート

2026-10-11取得の公開一次資料に基づく。実機OAuthはcallbackまで到達したが、認証コード交換の通信に失敗。認証成功・完了推論は未確認。

## 判定と契約

公式OSSフローをFlutter/Androidで試す価値はあるが、公式DevKitのNode/Electron例
はAndroidでのサポート・動作の証明ではない。[Cookbook](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt)
は適格なPlus/Pro、ローカルOSS向けの入口を示す。商用・遠隔ホストは別の条件を
確認する必要がある。[適用範囲](https://developers.openai.com/siwc/token-sharing-open-source)

初回だけdynamic registrationを使用し、発行されたclient IDをtoken交換・再認証へ
使う。host IDはインストール単位で永続化する。state、nonce、PKCE S256を試行ごとに
刷新し、callbackは同じ端末の`http://127.0.0.1:{port}/auth/callback`だけを受ける。
JWKS署名・issuer・audience・expiry・nonce、再認証時のsubjectを検証してから
アカウントをactiveにする。identity認証だけではplan usageを許可しない。
[認証契約](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)

公開OIDC discoveryも2026-10-11にread-onlyで確認した。issuerは
`https://auth.openai.com`、ID token署名はRS256、JWKSは
`https://auth.openai.com/.well-known/jwks.json`、revocationは
`https://auth.openai.com/api/accounts/oauth/revoke`。
PoCはdiscoveryのissuerを照合し、同hostのHTTPS endpointだけを使う。

推論はユーザー同意後のOAuth bearerで公開`/v1/models`と`/v1/responses`を使う。
models配列の表示可能なslugを選び、input配列、store=false、stream=trueで送る。
HTTP成功や部分テキストを成功扱いせず、response.completedと完了responseを検証する。
[モデル/推論](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
音声/文字起こしAPI、previous_response_id、hosted toolsや非対応parameterは使わない。
[Preview制限](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

更新tokenを直列化し、access/refresh/expiry/scopesを一括安全保管する。接続解除時は
遠隔revocationを試み、失敗しても端末tokenを消し「遠隔失効未確認」を表示する。
Plusの5時間枠は他アプリと共有で、Proには同じ5時間制限は適用されない。対象条件・
利用枠は将来変わり得るため、配布前に再確認する。会話履歴・Memoryへはアクセスしない。
[アカウント/利用枠](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)

## 実装候補の比較

| 対象 | 公開/更新の確認 | 経路と安全性 | 判定 |
|---|---|---|---|
| [公式DevKit](https://github.com/openai/sign-in-with-chatgpt-devkit) | 2026-10-11の公開READMEを参照 | 公式OSSのNode/Electron例、公開SIWC | 契約の参照。Flutter SDKとは扱わない |
| [chatgpt_auth_kit](https://pub.dev/packages/chatgpt_auth_kit) / [repo](https://github.com/MobAI-App/chatgpt-auth-kit-flutter) | pub.dev APIでは0.1.0、初回/最新公開とも2026-05-11 | 旧Codex backend、Codex用headerを要求。公式SIWCとの互換性未確認 | 不採用。非公認endpointへ逃げない |
| [flutter_appauth](https://pub.dev/packages/flutter_appauth) | pub.dev APIでは12.1.0、2026-08-29公開 | 一般OAuth/OIDC bridge。Android設定例は独自scheme callback | そのままの設定ではSIWCのloopbackを実証できない |
| Dart HttpServer + native bridge | このPoC | IPv4 loopback、公開OAuth、joseで署名検証、AndroidKeyStore | 実機検証用に採用。正式サポート断定なし |

PoCだけに追加した依存はcrypto 3.0.7、jose 0.3.5+2（pub.dev APIでは2026-03-31公開）。
JOSEの暗号処理を自作せず既存ライブラリで検証する。依存はPoCのpubspec/lockへ
隔離し、本体へ認証dependency・APIキー・Cookie・Codex credentialを追加しない。
パッケージの利用条件はそれぞれの公開licenseに従う。pub.dev metadataはリリース日で
あり、repositoryの最終commit日時やAndroid正式対応の証拠にはしない。
GitHub APIも2026-10-11に確認した。chatgpt-auth-kit-flutterは2026-05-10作成、
最終pushは2026-05-11T13:58:07Z、licenseはMIT。公開記載の古いendpointを
現在の公式対応とみなさない。

## PoCの境界と成果物

- 場所: `poc/siwc_android`。applicationId: `com.kapioka.rcn_siwc_poc`。
- 本体package・Recipe DB・Profile・Cooking modeを読み書きしない。
- Flutter UI、Dart loopback/HTTP、Kotlin system browser・音声Intent・安全保管。
- 安全保管はAndroidKeyStoreのAES-GCMとprivate filesDirのAtomicFile。backup無効。
  token・authorization URL・callback codeをconsole/analyticsへ出さない。
- 音声は[RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent)
  で文字起こしし、同じ編集欄へ入れる。「修正」は編集だけ、「確定して送信」だけが
  推論を開始する。認識providerによるネット通信はあり得ることをUIへ表示する。
- このPoCはテキスト推論だけ。本体のRecipe生成・Revision保存へはまだ接続しない。

## 再現できる機械検証

```powershell
dart format --output=none --set-exit-if-changed poc/siwc_android/lib poc/siwc_android/test
pwsh -NoProfile -File tool/siwc-poc.ps1 analyze --no-pub
pwsh -NoProfile -File tool/siwc-poc.ps1 test --no-pub
pwsh -NoProfile -File tool/siwc-poc.ps1 build apk --debug --no-pub
```

現在の結果は`issues-7-8-checkpoint.md`へ記録する。PoC APKは
`poc/siwc_android/build/app/outputs/flutter-apk/app-debug.apk`。
debug検証専用であり、正式版の署名・公開を意味しない。

## ユーザー実機QA（後日）

1. 別packageのPoC APKをinstallし、本体のデータを保持したまま並存することを確認。
2. 「ChatGPTに接続」→system browserで自分の適格なアカウントと権限を確認。
   ブラウザを開く前にアプリから公開OIDC metadataへの接続を確認する。
   「接続確認」で止まった場合はブラウザ認証を繰り返さず表示メッセージを確認する。
   ブラウザの「アプリに戻る」を押す。開かない場合はAndroidの戻る操作を使う。
   接続状況はアプリ画面上部に表示する。モデル一覧が出ることを確認する。
3. 検証用の短文だけを入力し「確定して送信」。response.completed検証済みの表示と
   「完了した回答を受信しました」と回答が出ることが推論成功の証拠。
   HTTP 200だけでは合格にしない。
4. 音声入力→認識文の「修正」→確定。認識直後/修正中/空/キャンセル時は未送信。
5. 認証の戻る/同意拒否、loopback中のバックグラウンド/復帰、PoC再起動、期限更新、
   再ログイン、account追加/切替、通信断、利用枠不足、接続解除を確認する。
6. 異常時は操作段階とサニタイズされた表示エラーだけを記録する。tokenや認証URL、
   browserアドレスのquery、callback codeをスクリーンショット/ログへ含めない。

端末の自動回転設定・固定方向は変更しない。PoCに常時点灯・Cooking音声/TTSはない。
Androidのloopback listenerの寿命、Chrome復帰、Keystore復号、Recognizer実装差は
build/unit testsだけでは証明できない。

戻りボタンは[ChromeのIntentリンク](https://developer.chrome.com/docs/android/intents)と
[AndroidのBROWSABLE filter](https://developer.android.com/training/app-links/create-deeplinks)
を使い、PoCのpackageを指定する。戻りリンクにtoken/code/stateを含めず、OAuthの
callbackは引き続きloopbackだけで受ける。SingleTaskとFlutter deep-link route無効化で
既存の認証処理へ戻す。自動でブラウザを閉じるとは保証せず、押下と手動戻りを案内する。

通信診断は固定の説明と[Dart SocketException](https://api.dart.dev/dart-io/SocketException-class.html)
のOS errorCode番号だけを表示する。exception本文・接続先address・OS本文は表示しない。
名前解決失敗とその他のsocket失敗を区別するが、番号だけで端末設定を変更しない。

## 次のゲート

WP-01は資料確認済み、WP-02/03は実装と機械検証の結果をチェックポイントへ記録する。
WP-02の実機OAuth+完了推論が成立した後だけWP-04本体統合へ進む。その際は#7の
共通Validator/プレビュー・ユーザー承認、既存Feedback/Revision Storeを再利用する。
公開Schema整合・本体QA・Draft PR/main merge/一般公開は別判断。実機PoCが成立しない
場合は根拠を残して保留し、#7の共有/コピー/手動取込を維持する。
