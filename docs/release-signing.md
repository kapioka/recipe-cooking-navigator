# Android release署名手順

この手順は、GitHub Releaseで配布するAPKを専用鍵で署名し、将来も同じアプリとして更新できる状態を維持するためのものです。

## 安全境界

- keystoreとパスワードをリポジトリへ保存しない。
- 鍵作成・buildスクリプトは、リポジトリ内のkeystoreパスを拒否する。
- keystoreとパスワードを別々の安全な場所へバックアップする。
- 公開前に、バックアップから復旧できることを確認する。
- release署名情報が不足した場合、debug鍵へfallbackせずbuildを失敗させる。
- APKへ署名した秘密鍵は共有しない。証明書fingerprintは公開してよい。
- 端末に異なる鍵の同一packageが入っている場合、明示承認なしでアンインストールしない。

## 1. 初回だけ既存鍵を登録する

プロジェクト直下の `Setup-Signing.cmd` をダブルクリックする。外部PowerShellのファイル選択で、現在の正式版に使っている既存鍵を選ぶ。更新用の鍵を新しく生成しない。

aliasを確認し、`Keystore password (masked with asterisks)` でパスワードを登録する。キーのパスワードが同じなら次の入力はEnterだけでよい。文字が見える入力欄では中止する。Codex内のターミナルやチャットへパスワードを入力しない。

鍵は `C:\AndroidSigning\recipe-release.p12` へコピーされ、署名設定は同じフォルダの `recipe.signing.clixml` へ保存される。パスワードはWindows DPAPIで暗号化し、同じPC・Windowsユーザーでのみ復号する。保存先のアクセス権は現在のユーザー・SYSTEM・Administratorsに限定する。平文 `.env` や永続環境変数は使わない。鍵と復旧パスワードは別途安全にバックアップする。暗号化設定だけでは別PCへ移行できないため、新しいPCでは再登録する。

## 2. 毎回の正式署名ビルド

プロジェクト直下の `Build-Release.cmd` をダブルクリックする。Codexからは次の同じ入口を使う。

```powershell
pwsh -NoProfile -File .\tool\build-release.ps1
```

登録済みパスワードを自動取得し、既存Flutter wrapperでビルドする。署名情報は子プロセス用の一時環境変数にだけ設定し、終了・失敗時に元の値へ戻す。Gradle daemonとconfiguration cacheを無効化する。

Issue #7の共有/コピー依頼を有効にする場合は、`pwsh -NoProfile -File .\tool\build-release.ps1 -PublicAiV2Ready`を使う。公開mainのAI入口・Workflow・v2 Schema・連携仕様・参照例がこのアプリと一致することを検証してから、同じ正式署名処理へ進む。不一致や取得失敗時は停止する。

未登録、鍵の欠落・変更、署名証明書の不一致は停止する。手入力やdebug署名へ自動的に切り替えない。初回に選んだ鍵とAPKの証明書を照合するが、端末の既存版との照合はインストール前に別途必要。

成功時の出力:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/flutter-apk/SHA256SUMS.txt`

旧 `build-release-interactive.ps1` も登録済み設定での同じビルドに接続する。

## 3. APKを再検証する

buildスクリプトは自動で検証します。単独で再検証する場合は次を実行します。

```powershell
pwsh -File .\tool\verify-release.ps1 `
  -ApkPath .\build\app\outputs\flutter-apk\app-release.apk `
  -WriteChecksum
```

検証内容:

- APK署名が有効
- 署名者が`Android Debug`ではない
- zipalign済み
- packageが`com.kapioka.recipe_cooking_navigator`
- APKがdebuggableではない
- versionName / versionCode
- SHA-256 checksum

## 4. Pixel 10aで確認する

Pixel 10aには専用鍵で署名したAPKが入っています。更新時は同じ鍵で署名したAPKの証明書を端末の既存APKと照合し、`adb install -r`でデータを保持して更新します。debug鍵版は署名が異なるため上書きに使いません。

アンインストールやデータ消去は、端末内のRecipe、タグ、進行状態、Cook Sessionを失う可能性があるため行いません。

## 5. GitHub Releaseを公開する

実機検証後、次をすべて確認してからtagとReleaseを作成します。

- Apache License 2.0、NOTICEの帰属表示、食品安全上の注意が配布物から確認できること
- keystoreと復旧情報のバックアップ
- 公開対象commitとAPK生成元commitの一致。mainへのmergeは別途明示承認を受ける
- tag、APK versionName、`pubspec.yaml`のversionの一致と、前回より大きいversionCode
- APKと`SHA256SUMS.txt`
- Release notes、対応範囲、未実装範囲、インストール手順

版ごとの更新内容は`docs/releases/`、配布APKのchecksum・署名・生成元commitはGitHub Releaseへ記録します。初回公開の記録は[GitHub Issue #3](https://github.com/kapioka/recipe-cooking-navigator/issues/3)を参照してください。
