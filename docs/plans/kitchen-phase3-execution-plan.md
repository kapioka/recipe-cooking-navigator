# Kitchen Phase 3 execution checkpoint

2026-09-21。GitHub `kapioka/personal-context/agents/prompts/codex-long-run-autonomous-execution.md` と execution-efficiency / work-breakdown を適用。WBS LITE。

## Contract

- Goal: Recipeなしで時計・単独タイマーを使い、同じKitchen内のRecipe閲覧中も保持する。
- Source of Truth: 今回のユーザー指示 → AGENTS → `docs/kitchen-mode-design.md` → 関連仕様・現在コード。
- ユーザー指示により表示・操作・実機QAは担当者が実施。Phase 1の未確認を合格に変更せずPhase 3実装を先行する。
- Scope: 現在のfeature branch `codex/plan-schema-v2-servings`。既存の未commit v2変更を保持。publish / merge / 署名 / installは行わない。
- Rollback: 開始前に触れる既存ファイルを `%TEMP%/recipe-kitchen-phase3-before-20260921` に保存。今回の追加・差分だけ戻し、既存dirty変更や端末データをresetしない。
- Validation: timer/domain/controllerの決定的テスト、format、analyze、既存自動回帰、debug build。画面操作・画面比較は実施しない。
- 継続: 画面確認はユーザー担当として、独立して実装可能な次WPへ進む。通知・再起動復元の端末受入を自動テストだけで保証しない。

## Work packages

| ID | Deliverable / boundary | Depends | Done condition / evidence | Status |
|---|---|---|---|---|
| K3-1 | OS非依存Timer、配列store、KitchenSession controller | 既存timer下書き | 独立ID・期限・終了確認・退出・壁時計非依存のunit tests | done |
| K3-2 | foreground点灯所有者・単調時計Android bridge | K3-1 | 通常Cookingと所有者分離、非表示/破棄時解除、analyze/build | done |
| K3-3 | Kitchen入口、時計・単独timer、内側Recipe閲覧 | K3-1,K3-2 | 同じcontroller所有、旧調理への重複導線を遮断、analyze | done |
| K3-4 | 必要な回帰・debug APK・進捗記録 | K3-3 | 自動検証結果とユーザー担当QAを明確化 | done |

Sequential。ローカル委譲routerが不在のためnative子agentを起動せずmanager実行。外部手順のモデル分担は、repositoryのmanager-only write境界を優先する。

## Phase 3 checkpoint（履歴）

- Last completed: K3-4。K3-1〜4の実装・自動受入は完了。製品Phase全体の実機受入は未完了。
- Branch: `codex/plan-schema-v2-servings`、未commit。既存v2差分は保持。`lib/domain/kitchen_timer.dart`と既存下書きtestを継続利用。
- Implementation: `lib/application/kitchen_controller.dart`, `lib/data/kitchen_timer_store.dart`, `lib/platform/kitchen_device.dart`, `lib/ui/kitchen_screen.dart`, `lib/ui/kitchen_scope.dart`。入口はHomeScreen、通常Cookingの重複起動はCookingEntryで防ぐ。Android MainActivityは点灯所有者を分離。
- Validation: 変更Dart 11ファイルのformatは差分0。`flutterw.ps1 analyze lib test`はNo issues。`flutterw.ps1 test --reporter compact`は91件合格。`flutterw.ps1 build apk --debug --no-pub`は成功（Gradle 59.6秒）。`git diff --check`合格。
- Evidence: `build/kitchen-phase3-tests.log`, `build/kitchen-phase3-build.log`, `build/app/outputs/flutter-apk/app-debug.apk`。APKはdebug署名。端末へのinstall・正式署名・公開は未実施。
- Analysis exception: repository全体のanalyzeは以前の`build/qa/validate_project_recipe.dart:2`にあるrelative lib importも解析した。今回追加分の指摘修正後はlib/testに絞って合格を確認した。既存生成物や解析設定は変更していない。
- User QA: 0 Recipeでの開始、単独timerとRecipe一覧/詳細の往復、終了時確認、文字拡大/横向き、Activity復帰・点灯解除・回転不変。今回の指示により画面・操作・実機確認は実施していない。画像生成や再比較も行っていない。
- Next: Phase 4の保存/復元・通知adapter。新規画面確認をCodexの再開条件にせず、今回のユーザー指示を引き継ぐ。まずversion付きsnapshot、同一起動の期限復元、再起動要確認状態、保存失敗の順に独立WPへ切る。
- Dependency: 通知を保証する動作・終了後の継続公開にはAndroidでの権限/通知/ロック検証が必要。設計のPhase 4 gateを満たすまで「続けて終了」は追加しない。Phase 5のRecipe工程タイマー統合も未実装。
- Official references checked: [SystemClock](https://developer.android.com/reference/android/os/SystemClock), [AlarmManager](https://developer.android.com/develop/background-work/services/alarms), [通知権限](https://developer.android.com/develop/ui/compose/notifications/notification-permission)。調査をnative通知実装・実機合格の証拠にしない。

## Phase 4への継続

画面確認を待たず進められるK4-1を続行する。通知を有効にする前に保存契約を確定する。

| ID | Deliverable | Depends | Done / Acceptance | Status |
|---|---|---|---|---|
| K4-1 | version付きTimer snapshot・保存破損保護・同一起動復元/再起動分類 | K3-1 | serialize roundtrip、破損・未知version・重複ID・期限超過・再起動、file failure tests | done |
| K4-2 | Android起動識別・保存失敗表示・復元UI・複数操作の接続 | K4-1 | 保存成功後反映、復元は明示Kitchen起動のみ、targeted tests/analyze/build | done |
| K4-3 | Android終了通知・権限・音・振動 | K4-2 | 自動テスト・正式署名APK・Pixel background通知・タップ復帰。画面ロック追加QAはPhase 6 | done |

K4-1はRecipe/CookingContextを変更せず、既存端末の保存形式のmigrationも行わない。

## Latest checkpoint — K4-2完了

- Last completed: K4-1 / K4-2の実装・自動受入。画面確認・実機操作は未実施のまま。
- Current identity: `E:\作ってみた\recipe-cooking-navigator`, branch `codex/plan-schema-v2-servings`, 全変更未commit。先行v2 dirty変更を保持。
- Added: `lib/data/kitchen_timer_file_store.dart`、`test/kitchen_timer_file_store_test.dart`。Timerにstorage codecと再起動確認後の停止復元を追加。controller transactionは保存成功後に状態を公開し、保存中のlifecycle変更を巻き戻さない。
- Connected: KitchenScreenがapplication support directoryの`kitchen-timers-v1.json`を読み書き。BOOT_COUNTで端末再起動を識別し、確認前は旧snapshotを変更しない。複数操作UI・上部最大2件・全一覧を接続。表示tickだけではfile保存もRecipe画面全体の再buildも行わない。
- Validation: Kitchen関連4 test filesの27件合格（domain 8、controller 11、file store 6、device 2）。Phase 3時点で既存含む全体91件合格済み。最終`flutterw.ps1 analyze lib test` No issues、debug build成功（39.5秒）、diff check合格。formatは変更ファイルに実施。
- Final APK: `build/app/outputs/flutter-apk/app-debug.apk`、SHA256 `B175FFFA8DC7598D5B4BF074FC336D71D9CF074443BBE0E664A974D73B29C108`。debug署名、install/正式署名/公開は未実施。
- Logs: `build/kitchen-phase4-tests.log`, `build/kitchen-phase4-build.log`。初回の未定義test matcherとimport挿入位置のcompile errorは修正済み。
- Next Ready WP: K4-3 Android終了通知。まだ通知・終了音・振動は実装していない。「続けて終了」は提供していない。
- Handoff: 同じtask ID `01a0c0d6-090e-7553-8cc1-cffd7080d5a0`へ`send_message_to_thread(model=gpt-5.6-sol, thinking=high)`でK4-3継続指示を送信し、エラーなしの応答を受領した。新しいタスクや子agentは作成していない。送信受付とK4-3実行完了を混同しない。
- Resume reads: このlatest checkpoint、K4-3に関係するKitchen controller/file store/device/MainActivity、`docs/kitchen-mode-design.md`の通知節だけから開始する。全仕様/全履歴の再読や合格済み検証の無条件再実行を避ける。

## Latest checkpoint — K4-3完了 / Phase 5先行実装

- K4-3: `KitchenNotificationPlugin.kt`とAndroid manifestに通知権限、通知チャネル、正確な`ELAPSED_REALTIME_WAKEUP`、世代による古い通知の無効化、同時終了の集約、「音を止める」、通知タップ復帰を実装。権限拒否時も画面内タイマーを継続する。
- Pixel 10a: 通知権限と「アラームとリマインダー」を端末UIから許可。期限どおりの通知、アラーム音URI、振動パターン、通知タップの対象タイマー表示、Kitchen終了時の点灯解除を確認。画面ロック中の追加確認は「画面取得より先に改良」というユーザー指示で停止。
- Formal APK: `app-release.apk` SHA-256 `7EC6913E44F7D38F11011054176633EAC7F5E99773B5E461BDD59112D80CF52A`。外部対話PowerShellで署名し、証明書・v2署名・zipalign・non-debuggableを検証後に、既存データを保持してPixel 10aへ更新。その後のPhase 5差分はまだ署名APKへ再反映していない。

### Phase 5 work packages

| ID | Deliverable | Depends | Done / Acceptance | Status |
|---|---|---|---|---|
| K5-1 | Kitchen内Cooking開始とRecipe Step共通タイマー | K4-3 | source identity、保存transaction、工程移動後継続、CookingContextとの分離をunit/widget test | done |
| K5-2 | v2単一ファイル取込確認 | Phase 1 import | Schema合格後にsummaryを表示し、確定前は保存しない | done |
| K5-3 | Android Sharesheetからv2 Recipe受信 | K5-2 | `ACTION_SEND`/content URIを読取のみで受け、同じ確認とvalidatorへ渡す | done（自動検証） |
| K5-4 | 事前準備チェックの分離保存 | K5-1 | Recipe原本/CookingContextを変更せず再開可能 | done（自動検証） |

- Automated evidence after K5-1〜K5-4: `flutterw.ps1 test --reporter compact --no-pub`は113件合格。`flutterw.ps1 analyze lib test --no-pub`はNo issues、`flutterw.ps1 build apk --debug --no-pub`は成功。共有受信のqueue回帰は後続のtargeted widget testで合格。全体`analyze`は既存の`build/qa/validate_project_recipe.dart`の相対import情報レベル指摘だけが残る。
- K5-3/K5-4: Android共有を1 MB以内の読み取り専用sourceとして受け、既存の確認・validatorへ渡す。事前準備はrevision別の独立storeへ保存し、明示リセットを提供する。共有元providerと表示・操作は実機受入待ち。
- 2026-09-27 Pixel 10a: 旧正式署名APKには共有filterがなく、debug APKだけをbuildしても共有先へ表示されなかった。`SEND`に加えて`content://`の`VIEW`を実装し、同じ専用鍵で署名したAPKを`adb install -r`でデータ保持更新。証明書一致、APK内filter、端末の`query-activities`で両actionの候補登録を確認。ユーザーはDownloadsの同じJSONから共有先に本アプリが出て取込確認画面が開いたことを確認。取込確定後の保存は未確認。
- 2026-09-27 追加のユーザー報告: v2 Recipeはキャンセルと取込の両方が成功。旧形式Recipeの取込では再作成を促すエラーが表示され、既存のRecipe一覧は残った。スクリーンショット内の旧データ案内は端末内の旧v1保存領域の存在表示で、今回の取込結果とは別。`VIEW`経由の実操作は未確認。
- 2026-09-27 続報: ユーザーが「アプリで開く」経由の動作も正常と確認。共有受信に関する実機受入は完了。
