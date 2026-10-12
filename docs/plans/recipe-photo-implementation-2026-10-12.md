# 丸い料理写真の実装 — 2026-10-12

## 範囲と保存方式

本人の依頼に基づき、ホームのお皿アイコンから任意の写真を選び、丸く切り抜いて保存・変更・削除できるようにする。既存のボタン配置とRecipe / Feedback Schemaは維持する。クリーム色・深いグリーンの画面全体への適用と、アプリアイコンの選定は別の作業である。

写真はRecipe IDごとに1枚、Revision間で共通。app support内の `recipe-photos-v1/<SHA256(Recipe ID)>.png` へ保存する。入力30 MB以下、decode最大辺1536 pixels、確定画像512×512 PNG、保存最大2 MB。元写真の変更や元ファイルURIの永続保持は行わない。写真は機械受け渡しJSON、外部共有、Drive同期、Android自動バックアップ・端末移行に含めない。

保存は既存library mutationと直列化し、tmpをflushして旧画像をbakへ退避してから置換する。置換失敗では旧画像を復元する。primary欠落時はbakを読める。写真だけの読込失敗はRecipe表示を妨げず、写真の明示変更・削除を案内する。Recipe完全削除では写真も削除する。写真追加は新しい任意の保存領域で、既存Recipeデータのmigrationは不要。

ロールバックは今回の写真関連UI・store・注入・backup除外の追加を外す。先行する作成UIの変更と既存データは戻さない。写真フォルダはデータとして残す。

## 主要ファイル

- `lib/data/recipe_photo_store.dart`: app-owned PNG保存、回復、削除。
- `lib/platform/recipe_photo_picker.dart`: 既存file_selectorで写真選択。
- `lib/ui/recipe_photo_crop_screen.dart`: pan / zoom / 丸いPNG生成。
- `lib/ui/recipe_photo_avatar.dart`: お皿・写真表示と追加・変更・削除。
- `lib/application/recipe_library_controller.dart`、`lib/main.dart`、`lib/ui/home_screen.dart`: library保存とホーム連携。
- Android backup XML: 写真保存領域を自動backup・移行から除外。
- `test/recipe_photo_test.dart`: pixels・永続化・取消・失敗・削除・幅320と文字倍率2の検証。

## 機械検証

- `dart format --output=none --set-exit-if-changed lib test`: 103ファイル、差分なし。
- `pwsh -NoProfile -File tool/flutterw.ps1 analyze --no-pub`: 問題なし。
- `pwsh -NoProfile -File tool/flutterw.ps1 test --no-pub --reporter expanded`: 233件すべて成功（写真機能13件を含む）。
- 写真テストでは透明な角・選んだ領域のpixel、実file保存と再読込、backup回復、無効画像拒否、取消・二重操作・保存失敗・削除・Recipe JSON維持を確認した。

## 正式署名と本番更新

- `pwsh -NoProfile -File tool/build-release.ps1 -PublicAiV2Ready`: 成功。公開AI契約7ファイル照合、署名・登録済み鍵・zipalign・非debuggableを確認。
- Pixel 10a / Android 17の既存APKと署名証明書SHA-256が一致してから `adb install -r` で本番packageを更新。データ消去なし。
- 更新後APKを端末から取得してbuild成果物との一致を確認。SHA-256: `83498F49CC5838FCD1FE2DE1739C7D1957B67B43AED54BF1265324053527FFF8`。
- 更新日時2026-10-12 13:48:13、初回インストール日時を維持。本番起動と再起動が成功、更新以降のAndroidRuntime fatalは0件。写真選択の実機操作は未実施。
- 起動前・起動中・終了後の回転設定は `accelerometer_rotation=0 / user_rotation=0` のまま。SIWC PoC package不在を再確認。
- secret scanner warningモード: 860対象、50検出。40件は既存署名3スクリプトの変数参照、10件は生成Android resource / manifestの定義・参照。追加コードに秘密実値の検出なし。`git diff --check` 成功。

## ユーザーQA

本番更新後、お皿をタップ→料理写真を選択→写真を動かす／拡大→保存し、丸い写真が表示されることを確認する。アプリを閉じて再度開いて写真が残ること、写真変更中に戻ると前の写真が残ること、写真を外すとお皿へ戻ることを確認する。

端末の写真選択画面、実際の写真の向き、実機での指操作・TalkBackは本人の確認対象。機械テストはこれらの実機操作の合格を意味しない。問題時は写真の形式・容量、問題が選択／切り抜き／保存／再起動のどこか、端末の文字サイズを知らせる。個人写真そのものの提出は不要。
