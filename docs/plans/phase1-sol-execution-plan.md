# Phase 1 — Sol向け実行・引き継ぎプラン

作成日: 2026-09-19。対象: Recipe / Feedback Schema v2・人数変更。状態: **P1〜P7のアプリ実装・自動検証・Pixel 10a実機確認完了。配布Packageはローカル出力済み、ChatGPT Project実設定の切替は未実施**。

## 1. 目的と使い方

人数を変更したRecipeの取込、材料・工程・読み上げ、開始・中断・再開・完了を、同じ原本・人数・計算結果で成立させる。Sol（`gpt-5.6-sol`）での実装に渡すタスク専用の実行手順であり、モデル固有の能力や推論設定は前提にしない。モデル設定の変更や実装開始は本書の作成には含まない。

仕様・数値・受入期待値は既存の[詳細計画](recipe-schema-v2-servings-implementation-plan.md)を参照する。本書は実装順、現行コードへの対応、検証の実施時点だけを補う。契約を二重定義しない。ユーザー指示とAGENTSを優先し、v2実装に伴う既存v1仕様の変更は詳細計画で明示された範囲に限る。実装後の構造はSchema、意味はdata-model、挙動はproduct-spec / cooking-mode-uiを正本にする。

今回の作成では本書1ファイルだけを追加した。既存計画、ロードマップ、アプリ、ブランチ・index、外部Package、端末は変更していない。

## 2. 確認済みの開始点

- ローカルHEAD: `52384ba2e72b144deb0db61c4c852bb69dfd3395`。
- ブランチ: `codex/plan-schema-v2-servings`。`docs/roadmap.md`は変更済み、`docs/plans/`と`design-qa.md`は未追跡。既存作業を保持する。
- メインのタスク「ロードマップの次の改良を確認」は、確認時点ではロードマップ説明まで。実装済みの証拠はない。
- 現行Schema、validator、起動時asset、保存先はv1。`RecipeDocument`と画面は`quantity.display`、`ingredient_uses`、文字列の手順を使用している。
- 既存テストはvalidator、保存、Inbox、active、タグ、controller、widgetに分かれている。テスト数や過去の合格を今回の証拠として使わない。

実装開始時にbranch/statusとこのHEAD以降の関連差分を1回確認する。進捗があれば完了済み部分を再実装しない。同じファイルをメイン側が編集中なら、その変更を確定させてから続ける。manager単独で進め、別タスクや子エージェントを自動作成しない。

`work-breakdown.md`は確認時のローカルPersonal Contextに存在しなかった。本書の依存順・出口を作業分解として使い、未読の正式WBS手順へ準拠したとは扱わない。本書を使うだけのために別のWBSファイルを追加しない。

## 3. 範囲と終点

標準の実装範囲はこのrepository内のP1〜P6。P7の実機・配布作業と別repositoryの変更は、実装依頼時点の明示指示に含まれている場合に実行する。既に許可されている同一作業を再確認しない。

| 対象 | 今回の完成範囲 |
|---|---|
| Recipe v2 | Schema、例、検証、分量計算、表示・TTS、取込 |
| 調理状態 | v2保存、原本snapshot・人数・解決量の固定、再開・完了 |
| Feedback v2 | Schema、例、意味validator、保存Sessionから必要情報を取り出す純粋な変換 |
| 関連docs / assets / tests | v2の実装結果との整合 |
| 上流Package | 範囲内なら詳細計画第9章のローカル更新。範囲外なら必要ファイルと切替手順を引き継ぐ |
| 実機 | 範囲内ならP7を実施。未実施なら自動検証と区別して残す |

Kitchen mode、共通タイマー、Drive Feedback保存、Cooking Profile、評価・共有UIは後続Phase。既存の詳細計画第8章・第10章に残る「Phase 2の評価UI」は旧番号で、現ロードマップでは**Phase 7**を指す。現Phase 2はKitchen mode設計。これを理由に評価UIを先行実装しない。

P1〜P6合格は「ローカル実装・自動検証完了」。ロードマップのPhase 1全体の完了は、必要なP7と上流生成→取込の確認まで実績が揃ってから判断する。未実施項目のチェックは付けない。

## 4. 最初に読む範囲

1. AGENTS、現行roadmapのPhase 1、詳細計画の第3〜8章・第10〜12章を一度読む。第9章は上流を扱う時、第13章は復旧を判断する時に参照する。
2. 下の作業表にあるファイルを、担当工程の直前に読む。既読内容は関連変更があるまで再利用する。
3. `docs/data-model.md`のQuantity / Ingredient Use / CookingProgress / Feedback、`docs/product-spec.md`の取込・調理、`docs/cooking-mode-ui.md`の再開、`docs/chatgpt-integration.md`の生成契約を変更対象として照合する。

全repository、全履歴、全端末ログの再調査、開始前の全テスト・buildは通常不要。再現が必要な不具合や環境異常があった場合だけ、その箇所を先に確認する。

## 5. 実装順と出口

詳細計画のP番号を維持する。各工程は合格した対象テストを引き継ぎ、全体検証はP6に集約する。

| 工程 | 必要な変更・順番 | 出口と最小検証 |
|---|---|---|
| P1 契約 | Recipe / Feedback v2 Schemaと完全な例を用意。Recipeの構造・参照・人数・単位、Feedbackのローカル`$ref`を先に確定。関連docsの該当節も同時に更新 | 現在の`json_schema`で正常例と拒否例を検証。ネットワークなしのref解決を確認。Recipe parserの旧型依存は同じ工程で解消する |
| P2 共通処理 | `recipe_document.dart`の数量・文章型をv2へ。有理数、量解決、総量、RecipeText、画面/TTS、CookingContextを実装。Feedbackの再計算照合を接続 | 詳細計画Q01〜Q15を表形式の純粋Dartテストで確認。Feedbackの異revision・改変拒否もここで確認 |
| P3 保存 | `cooking_store.dart`の開始・移動・完了APIを分離。v2 envelope・保存先・asset・起動を切替。Inbox receipt条件、旧ファイル案内を接続 | 保存・復元・失敗時保持・旧ファイル不変・Inbox混在を対象テストで確認 |
| P4 画面 | 詳細人数選択→CookingEntry→CookingScreenへ同一contextを接続。本文、材料、下準備、全体工程、予告、TTSを共通rendererへ | 人数変更→開始→移動→中断→再開→完了をwidgetで確認。active切替、タグ再描画、失敗時の画面不変も含める |
| P5 Feedback / 生成側 | 保存Sessionからidentity / snapshot / contextを取り出す変換を完成。上流更新が範囲内ならSchemaコピー・Instructions・連携仕様を同期 | 実際にstoreへ保存・読込したSessionを変換するテスト1本で接続を確認。上流対象なら最終コピーのhash一致。未実施の外部操作を記録 |
| P6 統合 | format、analyze、全unit/widget、debug build。docsの実施状態を整える | 最終の変更内容に対し各1回合格。失敗修正後は影響した検証だけ再実行 |
| P7 実機 / 切替 | 授権範囲のPixel確認と上流切替。詳細は第8節 | 実機・上流・公開の実施済み／未実施を分けて報告 |

P1で全画面まで完成させる必要はない。P1では構造検証と参照契約を固定し、P2でresolverができてからFeedback contextの厳密再計算テストを通す。P1出口はFeedback全体完成の宣言ではない。P2でAPIを変えた際のconsumerの最小コンパイル追従は同じ変更単位で行い、機能接続はP4で完結させる。途中状態を動かすための製品用v1/v2両対応を増設しない。

既存テストのRecipe fixturesは契約変更に伴ってv2へ追従させる。元の取込・検索・Revision等の期待値は保持し、合格させるために既存テストを削除・skipしない。v1は拒否・旧データ保護テスト用として残す。

## 6. 現行コードから分かった手戻り防止点

### 分量と文章

- `lib/domain/recipe_document.dart`の`RecipeIngredient.quantity`と`ingredientsFor`はv1表示値を読む。名前検索で使う材料名は維持し、画面専用の換算処理を増やさずcontext経由にする。
- `lib/ui/cooking_screen.dart`は本文のString cast、材料シート、`_speechText`、`next_preview`等で生データを読む。本文だけの置換では不足する。詳細計画第4.5章のフィールド表を移行チェックリストにする。
- 原本の分子・分母は整数、解決済みcontextの分子・分母は数字文字列。表示丸めの値を保存・再計算へ戻さない。
- 検証済みRecipeからcontextを生成する方向を固定する。RecipeValidatorがFeedbackValidatorを呼び戻す循環を作らない。FeedbackValidatorと保存読込は同じcontext検証を再利用する。
- 総量はamount定義から一度ずつ集計する。下準備や複数工程から同じamountを参照しても二重計上しない。

### 保存と再開

- 現行`CookingStore.savePosition`はMapを毎回作り直すため、フィールド追加だけではcontextが消える。開始で原本・人数・量を保存し、移動はStep / updated_atだけを更新する。
- 現行`complete`は最小項目だけをSessionへ保存する。新Sessionへ同じsnapshot/contextをコピーし、永続化成功後の状態だけをUIへ反映する。
- `CookingEntry._start(true)`で新しい人数からcontextを作り直さない。保存revision・Step・人数・量を復元し、ライブラリの同revision原本とも照合する。
- 詳細画面の選択人数はRecipe ID / revisionが変わった時だけ基準へ戻す。タグ保存によるcontroller再通知でリセットしない。
- progress / Sessionの不正snapshot、未知algorithm、量の改変は読込時に拒否する。有効なbackupがあれば既存の復旧順を使い、全候補が壊れていたら書込を禁止する。破損データの一括削除や新しい復旧UIは追加しない。
- `main.dart`では詳細計画第7.1章の保存先表をそのまま適用する。タグ・active・Inboxの`storage_version`まで一律に2へ変えない。

### Inbox

- 現行`RecipeLibraryController._checkInboxOnce`は「receipt一致＋同ID/revisionがライブラリに存在」で検証前にskipする。
- v1 receiptを保持して新しいv2ライブラリを使うため、同ID/revisionをv2でも使ったケースでは、Inboxに残るv1まで保存済み扱いにし得る。旧receiptだけを根拠にv2検証を省略しない。
- 最小の実装は、読み取ったsourceを既存の共通validator / 保存判定へ通してから重複扱いを確定すること。ファイル取得・hash計算を再実行する必要はない。receipt schemaを広げる方式を選ぶ場合だけ、その必要性と互換性を説明する。
- 回帰に「旧receipt＋旧v1＋同ID/revisionの新v2が保存済み」を1件加え、v1拒否を確認する。receiptはRecipe内容の正本ではない。

## 7. 検証の配置と打ち切り条件

| リスク | 主に検証する場所 | 重複させない範囲 |
|---|---|---|
| 数学・丸め・固定量・定性的な量・参照総量 | 純粋Dartの表形式テスト | Q01〜Q15を全画面・全人数のwidgetでも繰り返さない |
| Schema / ID / 単位 / 不正入力 | validatorテスト | 1種類の拒否規則ごとの代表入力。Schemaの全組合せ生成はしない |
| snapshot固定・改変拒否・保存失敗・backup | store/contextテスト | 全失敗パターンを実機で再現しない |
| 単体取込 / Inbox / active / 検索 / タグ | 既存controllerテストをv2へ追従 | 新機能と無関係な重複テストを別ファイルに作らない |
| 人数選択・再開・保存失敗の画面動作・TTS送信文 | widgetテスト | domain計算の全例をUIへ複製しない |
| 実音・OS復元・点灯・回転・操作可能性 | 範囲内の実機確認 | build合格で代替せず、代表フローにまとめる |

詳細計画第12章の受入項目は削らず、この表のいずれかで担保する。人数範囲の全値検証は、小さいdomainテスト内で回し、人数ごとにbuildや端末操作をしない。

対象テストは変更したまとまりごとに実行する。新規テスト名は作成した実ファイルを使い、存在しないコマンドを前提にしない。P6の最終確認はrepository直下で次の順序とする。

```powershell
dart format --output=none --set-exit-if-changed lib test
pwsh -File .\tool\flutterw.ps1 analyze
pwsh -File .\tool\flutterw.ps1 test
pwsh -File .\tool\flutterw.ps1 build apk --debug
```

変更ファイルのformat適用は最終チェック前に済ませる。無関係な既存format差分を混ぜない。wrapperは固定の`R:`を占有するため、Flutter / Gradleコマンドを同時に走らせない。`R:`が使用中なら所有者を確認し、他の実行の割当を解除しない。

再実行するのは、その検証に影響するsource・依存・環境を変えた場合、または失敗した場合だけ。テストだけ修正したならアプリbuildをやり直さない。docsの状態表だけを直したならformat / test / buildを繰り返さない。同じ入力・仮説の失敗を再試行せず、原因を絞ってから一度修正する。説明できない同一失敗が続く場合は、事実と次の診断1件を記録する。

全件通過後の追加coverage、benchmark、全ログ調査、別方式での再build、依存更新、release build、既存画面の全面デザインQAは通常不要。新しい失敗・変更・明示要求がある場合だけ追加する。

## 8. 実機と上流の最小引き継ぎ

実機が範囲内なら、適用するAndroid QA手順を読み、端末・インストール済み署名・対象APKを確認する。既存署名と異なるdebug APKをそのまま上書きしない。署名済みAPKが必要ならrepositoryの手順を使い、パスワードは外部対話PowerShellでユーザーが入力する。アンインストールで署名差を解消しない。

1回のまとまったQAで、基準→減量→増量、分数TTS実音、材料・本文一致、調理開始→工程移動→中断→プロセス再起動→保存人数で再開→完了を確認する。タイマー終了で工程が変わらないこと、Cooking mode終了時の点灯解除、端末の回転設定が起動前・中・後で不変なことも同じ機会に確認する。

人数ボタン・範囲端・再開表示は大文字サイズとTalkBackで操作可能か確認する。横向き確認は端末の自動回転設定を書き換えて実施しない。調理雑音下の音声コマンドは既存必須ケースの短い確認を1回行い、全コマンド総当たりや長時間の電池・発熱QAはPhase 6に残す。

上流Packageは詳細計画第9章の一覧を使う。別repoの編集が範囲内なら、そのrepoのAGENTS・dirty差分を先に確認してローカル準備まで行う。アプリと配布Schemaの最終hash確認は1回。ChatGPT Projectの実設定、Driveへの書込、公開・merge・Releaseはその操作を含む指示がある時だけ行う。未実施でもローカルで可能な作業は完了させる。

## 9. 完了・再開記録

工程ごとに会話へ「完了したP番号／変更範囲／合格した対象テスト／次の一手／未解決」を短く残す。中断時だけ、既存詳細計画へ必要最小限の到達点を追記する。全ログ用の新しい台帳や同じ計画の複製を増やさない。

最終報告は主要変更、主要ファイル、合格した自動検証、実機結果、上流切替の状態、未解決事項と次の最小操作を示す。受入未達を「Phase 1完了」と扱わない。rollbackは詳細計画第13章を使い、他者差分のreset、v1ファイル削除、端末初期化を行わない。

## 10. Solへ渡す開始文

> このrepositoryのPhase 1（Recipe / Feedback Schema v2・人数変更）を実装してください。`docs/plans/phase1-sol-execution-plan.md`を実行順と検証配分、`docs/plans/recipe-schema-v2-servings-implementation-plan.md`を仕様・受入期待値として使ってください。最初にAGENTSと現在のbranch/diffを確認し、既に完了した作業・合格済み検証を再利用してください。標準範囲はこのrepositoryのP1〜P6です。別repository、端末更新、外部Project切替は今回の会話で許可された範囲だけ実行し、対象外の残作業は具体的に引き継いでください。依存順に契約→共通計算→保存→UI→Feedback接続を完成させ、最終format・analyze・全unit/widget・debug buildまで進めてください。各段階は対象テストに絞り、合格済み検証は影響する変更がない限り繰り返さないでください。保存contextの消失、詳細再描画による人数リセット、旧Inbox receiptの検証前skipに注意してください。Kitchen mode、Drive Profile、評価・共有UIを追加せず、既存データとユーザー差分を保持してください。通常の実装判断は進め、既存仕様と承認済みv2計画の意味上の衝突やデータ破壊が避けられない場合だけ確認してください。完了時はローカル実装、自動検証、実機確認、上流切替を分けて簡潔に報告してください。

## 11. 2026-09-19 実装結果

- P1〜P4とアプリ内のP5を実装。Recipe / Feedback v2、人数別の有理数計算、RecipeText、CookingContext、v2保存領域、詳細人数選択、Cooking mode / TTS、保存SessionからのFeedback変換を接続した。
- v1 Schemaと旧保存ファイルは削除・移行せず、現行assetと保存先だけをv2へ切り替えた。旧Inbox receiptだけで検証を省略しない。
- `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、全74 unit/widget tests、Android debug APK buildが合格した。
- Pixel 10aは正式署名APKの`adb install -r`、v2サンプル取込、1人分・4人分表示、調理開始、工程移動、再起動後の「続きから」、1/4個を含むTTS再生状態、終了時の常時点灯解除まで確認した。
- `ai-prompt-library`のv2 Packageはローカルfeature branchへ出力し、Recipe / Feedback Schemaと連携仕様のSHA-256がアプリ側正本と一致した。ChatGPT Project実設定、v2 Inbox往復、push / merge / Releaseは未実施。
