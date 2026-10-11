# Phase 8 実装・検証チェックポイント — 2026-10-04

ブランチ: `codex/plan-schema-v2-servings`。既存の未commit作業を保持し、端末更新・公開・mainへのmergeは行っていない。実機確認はユーザーの指示で後日に延期している。

## 実装済みの範囲

- 評価画面でカテゴリと任意の次回方向を明示し、未変更のFeedback v2をEvidenceとして端末に蓄積する。
- 異なる調理・Recipeを使った決定的集計、category / global候補の提示、承認・却下、更新元revision照合、Profile履歴の保持。
- Driveのアプリ用ルートをInboxと別に選択し、Evidenceを追記する。既存内容の比較、書込後の読戻し、部分成功の表示。
- Drive Evidenceの明示読込。正常ファイルの追加、同一内容のスキップ、不正・未対応・ID競合の個別拒否。元ファイルを変更せず、再読込でscoreを増やさない。
- Drive ProfileのSchema・ドメイン検証と読み取り専用キャッシュ。同revision競合・巻戻り・破損・権限失効では最後の有効な記録を保持する。端末内の承認履歴とは混合しない。
- 本人が明示した好みの登録（全料理・カテゴリ・個別レシピ）、Profile 1.1、旧保存原文を保持したstorage v2移行。候補承認・却下・明示登録を順序付き操作から再現する。
- ユーザー承認によりDrive履歴を正本に変更。bootstrap移行、digest・連結・操作再生の検証、明示登録・候補の承認した変更だけをremote headへ適用し、immutable recordを追記する。
- `profile-write-v1.json`で確認待ち送信を保持。同ID・同内容の再確認、stale更新元拒否、同時分岐の両方保持、読戻し・キャッシュ保存後の完了確定。cache v3はrecord全体のdigestを保存し、各updateも親record全体のdigestを保持する。根拠だけを改変した既知履歴と途中の祖先の改変も拒否する。
- Work向けread-only検証CLI。成功時だけ単一headのProfileを出し、分岐・欠落・改変・未知Schemaではexit 2とstdout空。

主要ファイル:

| 責務 | ファイル |
|---|---|
| 不変Evidence・集計・Profile | `lib/domain/preference_evidence.dart`、`preference_candidate.dart`、`cooking_profile.dart`、`preference_operation.dart`、`profile_history.dart` |
| 端末保存・キャッシュ | `lib/data/preference_store.dart`、`cooking_profile_cache_store.dart`、`profile_history_writer.dart` |
| 操作・表示 | `lib/application/preference_controller.dart`、`lib/ui/preference_screen.dart`、`preference_record_dialog.dart`、`explicit_preference_dialog.dart`、`feedback_screen.dart` |
| Android Drive adapter | `lib/platform/feedback_archive_platform.dart`、`android/app/src/main/kotlin/com/kapioka/recipe_cooking_navigator/FeedbackArchiveChannel.kt` |
| 接続・契約 | `lib/main.dart`、`pubspec.yaml`、Evidence / Profile 1.0・1.1 / Candidate / Operation / History Schemaと完全例 |

## 自動検証

- `dart format --output=none --set-exit-if-changed lib test`: `lib test`は79ファイル、CLIを含め80ファイル、差分なし。
- `pwsh -File .\tool\flutterw.ps1 analyze lib test tool/validate_profile_history.dart --no-pub`: No issues found。
- `pwsh -File .\tool\flutterw.ps1 test --no-pub --reporter expanded`: 全189テスト合格。Work CLIは正常配列・正常ディレクトリ・分岐・欠落・未知Schema・digest改変の6 smokeが合格。
- `pwsh -File .\tool\flutterw.ps1 build apk --debug --no-pub`: 最終adapter変更を含めて成功（25.8秒）。
- APK: `build/app/outputs/flutter-apk/app-debug.apk`。SHA-256: `515AA26AF3AE5DD9F0CAB7EC14B510388765877AF3AE714D64E4C4B0A68372E5`。
- ログ: `build/phase8-profile-write-tests.log`、`build/phase8-profile-write-analyze.log`、`build/phase8-profile-write-build.log`、`build/phase8-work-cli-checks.log`。

既存の共有画面テストは、別テストのfake clockで作られたSchema Futureを再利用しないようキャッシュを破棄し、実イベントと画面のpumpを交互に処理する待機に修正した。共有されたFeedbackの内容・改善元・実調理人数の検証は維持している。

## 後日の実機確認

正式署名版の更新は別作業とし、debug build成功を既存署名APKへの更新成功とは扱わない。

1. 完了した調理の評価画面で「好みの記録に残す」を開く。戻ると記録が増えず、カテゴリを入力して記録するとホームの「料理の好み」に蓄積件数が増える。味を未評価の項目にも明示的な次回方向を指定できる。
2. 同カテゴリ・2種類以上の料理・3回以上の調理で、明示方向2点と偏差1点が正味4点になる評価を蓄積する。候補の根拠で調理日時・Version・偏差・次回希望が分かり、承認前は好みが変わらない。承認時だけ更新番号が増える。
3. Google Driveの`Recipe Cooking Navigator`を保存先として選ぶ。同じ評価を2回保存し、2回目は保存済みと表示される。元ファイルの件数・内容を確認する。既存のInbox取込も利用できることを確認する。
4. 「Driveの評価を読み込む」を2回実行する。取込済みの件数は増えず、候補のscoreも変わらない。不正なテストファイルだけ拒否され、正常な他ファイルを読めることを確認する。
5. 「自分の好みを登録」で対象と説明を入力する。戻ると増えず、確認後だけ登録・更新番号が増える。個別レシピと全料理を混同せず、再起動後も説明が残ることを確認する。
6. Driveの好みを確認し「Driveの好みの保存を始める」を承認する。旧Profileがあれば引き継ぎ、なければ空から始まる。旧snapshotが変更されず、Historyに開始記録が増えることを確認する。
7. 登録済みの好みの「Driveへ反映」で対象・現在値・変更後を確認する。戻ると追記せず、承認後だけrecordが増える。端末のProfile ID・履歴がDriveのIDへ置き換わらないことを確認する。
8. 通信を切るか権限を失効させて送信・再確認する。検証済みキャッシュと端末記録を保持し、結果不明なら「好みの保存結果を再確認」が表示される。再接続後に同じIDで確認し、保存済みrecordを重複追記しない。クラウド同期はDrive側で別に確認する。
9. テスト用の履歴で同じparentの異なるrecordを用意すると、両方残して停止し、元snapshotへ戻らずキャッシュを保持する。日常データへの競合注入は行わない。

providerによる操作、実際のクラウド同期、端末での権限選択は未検証。問題があれば、操作名、画面のエラー・結果文、対象ファイル名を記録する。調理履歴やFeedback全文は原因の切り分けに必要になるまで共有不要。

## 残る設計・実装

- Workの実際のDrive取得・承認済みwriter接続、配布用snapshot再生成、分岐・不完全fileを本人が解決するUI。CLIの検証成功はWork側の接続成功を意味しない。
- 明示的な制約の入力画面。味の明示Preference登録と互換移行は実装済み。
- recipe scopeの自動候補。現行の共通条件「異なるRecipe 2件以上」と両立しないため、category / global以外を自動提案していない。
- 成功した実変更の方向判定、Workによる承認済みProfileの更新運用、Phase 8全体の実機受入。

自由文・総合評価・健康や宗教の制約を推論しない保守的な規則を採用している。Phase 8全体の完了はまだ宣言しない。


## 次回の最小作業

Workの実運用で完全なHistory取得→CLI検証→Recipe生成へ渡す接続を進める。配布用snapshotだけを読む運用を、履歴正本に対応済みと扱わない。複数scope間の矛盾解消と分岐解決は本人の判断を必要とする設計事項として残す。既存189テスト・最終APKは、関連変更がない限り繰り返さない。


## レート終了前の再開点

最後の使用率確認は5時間枠99%、週枠78%。実装・189テスト・CLI 6 smoke・analysis・最終debug APKまで完了し、関連する未実行検証は実機/provider/クラウド同期とWorkの実接続。端末インストール・正式署名・push・merge・公開は行っていない。次回はこの記録と実装の差分から再開し、実機確認の延期を取り消す指示がなければ端末操作を開始しない。
