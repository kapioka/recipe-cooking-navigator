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

## 1. 専用keystoreを作成する

keystoreは必ずリポジトリ外の非公開パスへ作成します。次のコマンドはパスワードを画面へ表示せず、ファイルやコマンド履歴にも保存しません。

```powershell
pwsh -File .\tool\create-release-keystore.ps1 `
  -KeystorePath '<repository-outside-private-path>\recipe-cooking-navigator-release.p12'
```

パスワードは16文字以上とし、パスワードマネージャー等へ保存します。生成後、次を別々にバックアップします。

- `recipe-cooking-navigator-release.p12`
- パスワード
- alias `recipe-cooking-navigator`
- 表示されたSHA-256証明書fingerprint

鍵を失うと、GitHubから直接配布する既存アプリを同じpackageの更新として提供できません。

## 2. 正式署名APKをbuildする

```powershell
pwsh -File .\tool\build-release.ps1 `
  -KeystorePath '<repository-outside-private-path>\recipe-cooking-navigator-release.p12'
```

スクリプトは最初にASCII junction側で依存Package参照を更新し、その後、パスワードを1回だけ非表示で入力します。パスワードは一時的なprocess環境変数だけでGradleへ渡し、build後に削除します。Gradle daemonもこのbuildでは無効化します。

成功すると次を生成します。

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/flutter-apk/SHA256SUMS.txt`

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

現在のPixel 10aにはdebug鍵版が入っています。専用鍵版は署名が異なるため、通常は上書きできません。アンインストールすると端末内のRecipe、タグ、進行状態、Cook Sessionが消える可能性があります。

データを失ってよいという明示承認を得るまで、アンインストールやデータ消去を行いません。

## 5. GitHub Releaseを公開する

実機検証後、次をすべて確認してからtagとReleaseを作成します。

- Apache License 2.0、NOTICEの帰属表示、食品安全上の注意が配布物から確認できること
- keystoreと復旧情報のバックアップ
- PRのmerge commitとAPK生成元commit
- `v0.1.0` tag、APK version `0.1.0`、versionCode `1`
- APKと`SHA256SUMS.txt`
- Release notes、対応範囲、未実装範囲、インストール手順

公開作業の進捗と証拠は[GitHub Issue #3](https://github.com/kapioka/recipe-cooking-navigator/issues/3)へ記録します。
