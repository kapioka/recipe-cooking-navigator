# レシピ作成画面・採用アイコンの反映 — 2026-10-12

## 完了条件と範囲

本人が採用した作成画面の3案目を既存Flutter画面へ反映し、採用済みの本と鍋のアイコンをAndroid launcherへ組み込む。正式署名版を既存のPixel 10aの本番packageへデータ保持で更新する。作成・取消・下書き・内容確認・保存・写真機能とSchemaは維持する。Gitの公開・mainへのmergeは対象外。

基準は [3案目](../design/recipe-creation-directions-2026-10-12/03-sage-group.png)、[アイコン修正版](../design/app-icon-directions-2026-10-12/03-recipe-notebook-pot-v2.png)、現在のFlutterコードと製品仕様。比較画像・プロンプトは各designディレクトリに保存済み。

## 変更

- `lib/ui/recipe_theme.dart`: クリーム・セージ・深いグリーンの共通Theme。ホームと作成画面に同じ配色を使い、カードとボタンを丸くする。既存画面のボタンサイズは維持する。
- `lib/ui/ai_recipe_request_screen.dart`: 基本条件をセージ色の面へまとめ、白い入力欄と外側ラベルを使う。人数・時間は縦の2行。任意条件を独立した白いカードへまとめる。下部の主操作と既存の動作を維持する。
- `lib/ui/recipe_creation_progress.dart`: 条件・作成中・内容確認を3段階で示す。色と文字、読み上げ用の現在位置を併用する。
- `lib/main.dart`: 共通Themeをアプリへ適用。
- `android/app/src/main/res/`: 通常launcher PNGを5密度で置き換え、adaptive iconの背景色と透明前景を追加。
- `test/recipe_creation_flow_test.dart`: 幅320/360/412と文字倍率1/1.3/2の9条件を本番Themeで検証。

数値入力は既存の範囲・自由入力を維持する。利用可能幅285未満または16の文字が21を超える文字拡大では、人数・時間のラベルと入力を上下に置く。フォントは既存Android sans-serif、接続表示は既存Materialアイコンを使う。モックに描かれたロゴや文字の微細な形をそのまま画像化しない。

## アイコンの出力

採用画像から内蔵Image Genで背景のみを透明にした `03-recipe-notebook-pot-foreground.png` を作成。プロンプト: “Remove only the cream background and preserve the approved sage recipe notebook, cream/terracotta pot pictogram, dark green outlines and orange bookmark. Keep all artwork proportions, shapes and colors unchanged. Transparent background, no new elements.”

Flutterの画像codec/canvasで密度別のAndroidリソースを出力した。通常版は48/72/96/144/192 px、adaptive前景は108/162/216/324/432 px。前景の透明な四隅、出力サイズ、全可視pixelが中心66dpの範囲内であることを包装時の機械検証で確認した。通常のカラーlauncherとadaptiveを対象にし、monochrome専用リソースは作成していない。

Androidのlayer構成の参照: [Android公式Adaptive iconガイド](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。

## 検証

- 変更したDartファイルをformat済み。
- `tool/flutterw.ps1 analyze --no-pub`: No issues found。
- `tool/flutterw.ps1 test --no-pub`: 233件成功。基本入力・作成中・内容確認・空ホームの9表示条件、保存・取消・Schema拒否・写真の既存回帰を含む。
- launcherの密度・透過・safe area検証: 成功。
- 共通ボタンの高さを拡大した初期実装では、詳細タグが初期viewportの外に移る既存テストが失敗した。共通サイズを元に戻し、作成画面の主操作だけ56の高さにして全件成功。
- secret scanner warning mode: 50件。既存の署名スクリプト40件と生成Android manifest/resourceの10件で前回と同じ。新しい秘密値の検出なし。

## 正式build・本番更新

- `tool/build-release.ps1 -PublicAiV2Ready`: 成功。公開AI v2契約は `8bc338da1cecfa38387d462b7f7ec592ab00cf2b` の7ファイルと一致。
- APK署名有効、zipalign済み、debuggable=false、package `com.kapioka.recipe_cooking_navigator`、versionName 0.1.0 / versionCode 1。
- APK SHA256: `5ABC143CA7D5CDE7EB26000081FC0C4C4744EDD8BE21EF8CCB809B61A07FE774`。
- Pixel 10a の既存APKと証明書SHA256が一致: `a2135ccbd3e5ed2053746ce102d8d12e6346032065ccf052ea8e27452402d779`。
- `adb install -r`: Success。更新後に端末からpullしたAPKのhashが成果物と一致。
- lastUpdateTime: 2026-10-12 14:22:33。初回インストール日時を保持。アンインストール・データ消去なし。
- 起動・force-stop後の再起動: Status ok。更新時刻以降のAndroidRuntime fatalなし。
- 自動回転 `accelerometer_rotation=0` / 固定方向 `user_rotation=0` は更新前・起動中・終了後で同一。
- `com.kapioka.rcn_siwc_poc` は端末に存在しない。

端末の起動確認まで実施。実際のChatGPTへの作成依頼や写真選択、最終的な見た目の確認は今回の機械検証に含めない。233件のテストは模擬clientによる作成・保存を含む。

## 端末での最小確認

ホームから「レシピを作る」を開き、基本条件のまとまり、人数と時間、白い任意条件欄の見やすさを確認する。「こだわりを追加」を開いて閉じ、入力が残ることを確認する。普段の文字サイズで入力中も下部の主操作へ進めることを確認する。端末での最終的な見た目・写真や実際のChatGPT生成の操作QAは本人が行う。

不具合があれば画面名、端末の文字サイズ、見えない／操作できない欄を記録する。以前の機能変更を戻さず、今回のTheme・フォーム配置・launcher resourceだけを前の状態へ戻すことで切り戻せる。
