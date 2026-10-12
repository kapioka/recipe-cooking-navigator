# レシピ作成 UI/UX 改善の実装記録

実装日: 2026-10-12

## 対象と作業場所

基準は [2026-10-11の計画](ui-ux-recipe-creation-plan-2026-10-11.md)。ホームから条件入力、作成中、内容確認、保存済み詳細までを一貫した流れにし、既存の取り込み方法と版管理を維持する。

- 作業ブランチ: `codex/recipe-creation-ux`
- 基点: `da7e8673d043638b7bb26ad09454b022ee510195`（計画が調査対象にした `codex/siwc-recipe-integration`）
- 実装場所: 専用worktree（branch `codex/recipe-creation-ux`）
- 元の開発フォルダー の未コミット変更は保持し、実装は専用worktreeに隔離した。計画書もこちらへ保存した。

今回の認可範囲は実装と機械検証。追加依頼により、Pixel 10aの本番アプリへの上書き更新と独立SIWC PoCアプリの削除も対象となった。commit、push、mainへのmergeは行わない。変更の取り消し・採用判断はこの専用worktreeの差分を単位とし、元の作業を巻き込まない。

## 実装した動作

- ホームは検索・保存済み一覧を中心に、下部へ「レシピを作る」「レシピを取り込む」を縦配置した。アーカイブは一覧表示切替、ChatGPT連携・受け取りフォルダ・料理の好み・アプリ情報は設定にまとめた。
- 作成は条件、作成中、内容確認の3段階。接続済みの正常経路はホーム→作成→保存の3主操作で、生成後は材料・工程を初期表示する。作成中の表示は実際の状態と経過時間を使い、架空の進捗率を出さない。
- 任意条件を折りたたみにまとめ、音声で認識した希望は編集可能な欄に追加する。音声認識や接続完了を契機に自動送信しない。
- ChatGPT設定と作成画面が同じ接続runtimeを使う。設定から戻る際に入力を保ち、使用モデルを記憶する。
- 通常の条件下書きを端末内に1件保存する。明示削除・保存成功で消去し、プロセス再生成後も自動送信しない。生成済みの回答や改善元Feedbackは下書きに保存しない。下書き・モデル設定はAndroidのクラウドバックアップと端末移行から除外した。
- 連打による多重生成・保存を防ぎ、中止後の遅着応答を無視する。条件変更中も既存候補を保持し、再生成が検証成功した場合だけ置き換える。保存失敗は候補を保持し、再試行時は再検証・重複確認だけを行う。
- 作成回答・外部ChatGPTから貼り付ける回答とも、Recipe ID、parent_revision、次revisionと改善元の整合を確認する。不正形式・未対応Schema・不整合を補完して保存しない。
- ファイル、貼り付け、Android共有受信は共通の内容確認画面へ進む。クリップボード読取とフォルダ確認は本人の明示操作で開始する。
- 保存成功後は保存したID・revisionの詳細を開く。改善版保存でも使用中の版を変更せず、版履歴から本人が切り替える。
- 同一内容が既に保存されている場合は保存済みと表示し、「保存済みのレシピを開く」を主操作にする。戻る際に破棄確認を出さない。
- 接続失効、権限、依頼拒否、通信失敗を区別した案内と復帰導線を追加した。HTTP本文や認証情報は利用者向け診断に出さない。

## 主要ファイル

| 責務 | ファイル |
|---|---|
| 作成状態・候補保持 | `lib/application/recipe_creation_controller.dart` |
| 共有接続・下書き | `lib/application/recipe_ai_session.dart`、`lib/data/recipe_creation_store.dart`、`lib/ui/recipe_ai_scope.dart`、`lib/main.dart` |
| 作成・設定 | `lib/ui/ai_recipe_request_screen.dart`、`lib/ui/recipe_ai_settings_screen.dart`、`lib/ui/connected_recipe_screen.dart` |
| 共通内容確認・取り込み | `lib/ui/recipe_preview_content.dart`、`lib/ui/recipe_import_screen.dart`、`lib/application/ai_recipe_import.dart`、`lib/application/recipe_library_controller.dart` |
| ホーム・保存した版の表示 | `lib/ui/home_screen.dart`、`lib/ui/recipe_detail_screen.dart`、`lib/ui/recipe_version_history_screen.dart` |
| 失敗の分類 | `packages/siwc_client/lib/siwc_contract.dart`、`siwc_network.dart`、`siwc_runtime.dart` |
| Android下書き除外 | `android/app/src/main/res/xml/backup_rules.xml`、`data_extraction_rules.xml` |
| 回帰検証 | `test/recipe_creation_flow_test.dart`、既存の作成・接続・widgetテスト |

## 機械検証

| 実行 | 結果 |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test packages/siwc_client/lib` | 101ファイル、変更なし |
| `pwsh -NoProfile -File tool/flutterw.ps1 analyze --no-pub` | 問題なし |
| `pwsh -NoProfile -File tool/flutterw.ps1 test --no-pub --reporter expanded` | 本体220テスト合格 |
| `pwsh -NoProfile -File tool/siwc-poc.ps1 test --no-pub --reporter expanded` | 独立PoC 23テスト合格 |
| `pwsh -NoProfile -File tool/siwc-poc.ps1 analyze --no-pub` | 問題なし |
| `pwsh -NoProfile -File tool/flutterw.ps1 build apk --debug --no-pub` | 成功。保存済み表示の最終調整前に実行し、最終版は下記正式署名buildで確認 |
| `pwsh -NoProfile -File tool/build-release.ps1 -PublicAiV2Ready` | 成功。正式署名・zipalign・非debuggable・登録済み鍵との一致を確認 |
| `git diff --check` | 問題なし |

追加テストは3主操作、保存前の件数、送信連打、キャンセル後の遅着、通常・部分保存失敗の再試行、別候補の保護、下書き・モデル復元、設定往復、改善版の保存後表示、外部回答の改善元整合を扱う。幅320/360/412、文字倍率1/1.3/2、キーボードinsetsについて、入力・生成中・結果・空一覧のoverflowと主操作の最小48 logical pixelsを確認した。

正式署名buildの公開契約照合は公開main `8bc338da1cecfa38387d462b7f7ec592ab00cf2b` の7ファイルと一致。`docs/chatgpt-integration.md` は公開契約のsnapshotを保持し、新しい画面操作の説明は `docs/product-spec.md` と本記録に置いた。

## Pixel 10aの本番更新

- 対象: 接続済みPixel 10a、Android 17。
- 本番package: `com.kapioka.recipe_cooking_navigator`、versionName `0.1.0` / versionCode `1`。
- 端末の既存APKと新APKの署名証明書SHA-256一致を確認してから、`adb install -r`で上書き更新した。データ消去や本番packageのアンインストールは行っていない。
- 端末更新後にAPKを再取得し、生成物とSHA-256が一致した。値は `E65A1E3460A5B64E0424FDED27FFF6D81C2709E42DFFC45644882AB919C16615`。
- 更新日時は2026-10-12 13:11:54。初回インストール日時2026-09-08 07:46:57は維持されていた。
- 本番アプリの起動が成功し、プロセス継続とAndroidRuntimeの起動時fatal 0件を確認した。
- 起動前・起動中・終了後の `accelerometer_rotation` / `user_rotation` はすべて `0 / 0`で変化なし。
- 本番更新・起動確認後、明示依頼に従って `com.kapioka.rcn_siwc_poc`（Recipe SIWC PoC）を削除し、packageが残っていないことを確認した。本番アプリを再度起動した状態で引き渡した。

端末では本番アプリだけが残る。独立PoCのソース・テストは検証資産としてリポジトリに保持し、本番アプリへ追加インストールしない。PoC固有の認証状態の移植は行っていない。本番側が未接続の場合は設定の「ChatGPT連携」で本人が接続する。

公開前secret scanner をwarningモードで実行。最終検査は859ファイル、50件を検出した。40件は変更していない署名関連3スクリプトの変数・環境変数参照、masked入力など、10件は生成されたAndroid manifestのauthoritiesとresource IDの定義・参照だった。検出箇所を確認し、実値の秘密情報の埋め込みはなかった。これはscanner対象形式での検査であり、全種類の秘密を保証するものではない。

## 仕様上の判断と未確認範囲

- Schema、Android回転設定、調理・音声ナビのドメイン仕様、利用可能な外部共有方式は変更しない。
- 難易度の日本語対応は既存定義にないため「AIの難易度目安 1〜5」を使う。
- 旧形式データは既存controllerが有無だけを提供するため、件数を推測せず対象がある場合の短い案内と詳細を表示する。
- 初回の受け取りフォルダ選択は明示確認後の既存選択導線を残す。設定からも変更可能で、自動走査は追加しない。
- 実際のChatGPT認証・利用枠・応答時間、Android共有からの復帰、端末の文字サイズ・TalkBack・音声認識品質は今回の機械検証で確認していない。widget上の表示検証と実機の操作性を区別する。

## ユーザーQAと次の最小作業

本番アプリ更新後は、以下の操作性を本人が確認する。機械検証済みの条件と、実際の認証・音声・画面表示を分けて扱う。

| 最小操作・状態 | 期待する動作 | 問題があった場合の情報 |
|---|---|---|
| 接続済みで「なす・2人・30分」→作成→保存 | 作成中と完成が分かり、材料・工程を読んで保存できる。保存した料理の詳細へ進む | 止まった段階、秘密を含まない画面1枚 |
| 条件入力→ChatGPT設定→戻る | 条件が残る。接続だけでは作成を開始しない | 消えた欄と戻った経路 |
| 作成中に中止→もう一度作成 | 古い結果が後から割り込まない | 操作順とおおよその待ち時間 |
| 過去版から改善→保存→版履歴 | 保存した新版を表示し、使用中の版は元のまま。本人の選択で切り替えられる | 改善元・表示中・使用中の各版番号 |
| 外部ChatGPTへ共有／コピー→戻る→回答を貼り付け | 戻った作成画面で内容確認でき、保存は本人の操作 | 戻り先と利用した方法 |
| 最大文字サイズ・キーボード・TalkBackで条件入力と完成確認 | 主操作が欠けず、読み順と状態通知が理解できる。経過秒数を連続読み上げしない | 文字設定・画面方向・問題箇所 |

食品安全判断、ネットワーク速度の改善、実機で未確認の操作性を合格扱いにしない。
