# Issue #8: SIWC Android PoC / 実装ゲート

2026-10-11取得の公開一次資料に基づく。実機OAuthは当初、Wi-Fiとモバイル回線の双方で認証コード交換の名前解決に失敗（OS 7）。アプリへの復帰後に交換する修正版で認証・モデル取得まで到達。推論は完了イベントに到達したがテキストを抽出できず、途中のdelta/doneテキストを保持する修正版を端末へ更新済み。修正版でユーザーが回答の受信を確認し、実機PoCのゲートを通過した。

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
UTF-8本文のbyte数を明示して送信する。成功2xx応答でContent-Typeが省略された場合も
bounded SSEとして検証し、空本文・通常JSON・完了イベントなしは成功にしない。
公式SDK例と同様にdeltaテキストを保持する。完了responseにテキストがある場合はそれを
優先し、省略されている場合だけdone/deltaを使う。いずれもresponse.completedと
status=completedの確認後だけ返し、途中の失敗や未完了は拒否する。
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
JOSEの暗号処理を自作せず既存ライブラリで検証する。PoC段階では依存をPoCへ隔離した。
実機成功後の本体統合では公開SIWC adapterを`packages/siwc_client`へ共通化し、
同じ署名・identity検証と通信テストをPoCから継続実行する。
APIキー・Cookie・Codex credentialは追加しない。
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
  で文字起こしし、同じ編集欄へ入れる。枠内で修正でき、「確定して送信」だけが
  推論を開始する。認識providerによるネット通信はあり得ることをUIへ表示する。
- このPoCは一般のテキスト通信確認だけ。レシピ形式を強制しない。
  本体のRecipe生成・Revision保存は次の統合画面で扱う。

## 本体統合（実機PoC成功後）

- `ConnectedRecipeScreen`は本体の新規依頼、またはユーザーが選択したFeedbackから開く。
  PoCとはpackage・暗号化ファイル・鍵・host ID・登録identityを共有しない。本体での接続同意が必要。
- 公式SIWCではbrowser/hosted toolsを使えないため、URLだけを指定せず、同梱された
  正本Recipe/Feedback Schema・対象Workflow・連携仕様・構造例を依頼へ全文添付する。
  初期テキストと音声入力は枠内で編集でき、確定送信だけが通信を開始する。
- 完了テキストを既存RecipeValidator/prepareImportSourceへ合流させる。普通の回答、
  不正JSON、未対応形式は保存しない。新規は新ID・revision 1・parent null、改善は
  選択ID・改善元parent・要求next_revisionの一致と元履歴の存在を確認する。
- 材料・分量・工程をプレビューし、保存は明示確認のみ。履歴は追加で保持し、
  AI改善版の保存では現在のactiveを維持する。暗黙のlatest選択も追加前に安全保管し、
  その保存に失敗した場合は新Revisionを保存しない。
- 多重送信/保存を抑止し、キャンセル・画面終了後の回答を保存しない。
  起動し直しても確認途中の回答を自動で再送信・保存しない。共有/コピー/手動取込は維持する。
- Androidの安全保管はcloud backupとdevice transferから除外する。Recipe等の保存データは
  変更・消去せず、Cooking音声/TTSが使用中は追加のdictationを始めない。
- 本体でのOAuth→レシピ生成→内容確認→保存、および選択Revision改善は実機QAの次の確認対象。

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
   callback到達後もアプリがforegroundへ復帰するまで認証コード交換を待つ。
   ブラウザの「アプリに戻る」を押す。開かない場合はAndroidの戻る操作を使う。
   接続状況はアプリ画面上部に表示する。モデル一覧が出ることを確認する。
3. 検証用の短文だけを入力し「確定して送信」。response.completed検証済みの表示と
   「完了した回答を受信しました」と回答が出ることが推論成功の証拠。
   HTTP 200だけでは合格にしない。
4. 入力欄直下の「音声で入力」→枠内をタップして認識文を修正→「確定して送信」。
   説明はボタンの下に表示する。認識直後/修正中/空/キャンセル時は未送信。
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

Androidの[Activity lifecycle](https://developer.android.com/guide/components/activities/activity-lifecycle)
に合わせ、ブラウザ表示中にcode交換を開始せず、`onResume`でアプリへの復帰を確認してから
開始する。復帰前のキャンセル後は交換しない。修正版ではモデル一覧まで取得できた。

`tool/siwc-poc.ps1`はASCII worktreeの実pathを維持し、非ASCII pathのときだけR:へ割り当てる。
Gradleプロセスをbuildごとに分離し、別checkoutへ付け替えたR:のnative sourceを使い続けないようにする。
APK内のnative復帰待ちmethodの存在も確認した。旧`app-siwc-poc-foreground-debug.apk`は
native処理が欠落していたため再インストールしない。最新artifactはチェックポイントを参照する。

## 次のゲート

WP-01は資料確認済み、WP-02/03は実装と機械検証の結果をチェックポイントへ記録する。
WP-02の実機OAuth+完了推論が成立した後だけWP-04本体統合へ進む。その際は#7の
共通Validator/プレビュー・ユーザー承認、既存Feedback/Revision Storeを再利用する。
公開Schema整合・本体QA・Draft PR/main merge/一般公開は別判断。実機PoCが成立しない
場合は根拠を残して保留し、#7の共有/コピー/手動取込を維持する。
