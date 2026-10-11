# ロードマップ / ToDo

このファイルは、製品として到達したい状態と未達Outcomeを管理する。実行ログや固定された逐次手順ではない。

## Current-state contract

- Implementation baseline: `cf4f4b89942a500ab7d5fc7841163b37fe974f1d`
- Reconciled: 2026-10-11
- 現在の実装状態そのものは`main`のコード、tests、build結果が正本。
- このroadmapは、その状態を短く再開できるように要約する現在地・未達Outcomeの正本。
- Issue、PR、commit、Releaseは履歴・証拠であり、現在の再開地点を決める正本ではない。

Implementation baselineは「roadmapを最後に編集したcommit」ではなく、**Current statusとcheck状態を最後に照合した実装commit**を指す。roadmap自身の文書commitでmarkerを更新しない。

再開時は、baseline以降の差分を最初から全文再読しない。まず変更pathだけを確認する。

- baseline以降がroadmap、Issue整理、説明文など現在実装の意味を変えない文書変更だけなら、Current statusを再調査しない。
- application source、tests、schemas、build/runtime設定など現在実装の意味を変え得る差分がある場合だけ、その差分と影響testsを確認し、Current status / check状態を再同期する。
- 過去判断の理由が必要になった場合だけIssue / PR / commit履歴へ戻る。

roadmapとコードが矛盾する場合は、確認できたコード・testsの実状態を優先し、このroadmapを訂正する。古いroadmap記述に合わせて実装を戻さない。

## Current status

Flutter / Android版。公開済みの初期版0.1.0に加え、今回の反映対象にはRecipe/Feedback v2、人数変更、評価・改善、Kitchen基盤、Profile履歴、標準共有/コピー依頼、独立SIWC PoC、公開SIWCを使った本体のレシピ生成・Revision改善が含まれる。

本体200テスト、PoC21テストと静的解析・debug buildが合格。本体の正式署名APKとPoCをPixelへ更新し、本体起動を確認。端末の実料理/音声品質・Kitchen背景動作・Profile実運用は未確認。SIWCはforeground復帰待ち・nativeビルド経路・ストリーム受信を修正し、実機でOAuth・モデル一覧・完了回答の受信をユーザーが確認。正本Schema/Workflowを本文に添付する本体生成/Revision改善も実装し、共通Validator・材料/工程プレビュー・確認保存へ合流した。普通の会話文は保存せず、改善元ID/parent/next_revisionを照合し、activeと過去Versionを保持する。本体の正式署名APK更新済み。本体OAuth→生成→確認保存と改善の実機QAは次の未達Outcome。入力欄直下は音声入力と確定送信の2ボタンで、枠内編集の説明を配置した。外部SNS/バックエンド/iOSは今回追加しない。

## Execution notes

一般的なoutcome-first、Plan / Goalの使い分け、cohesive batching、machine-first Acceptance、user visual/manual QA handoffは上位のCodex global AGENTS / active execution policyを正本とし、このroadmapへ重複定義しない。

この製品固有の追加ルール:

- Phaseは製品領域と成熟度を整理する区分であり、厳密なblocking gateではない。
- 前段のmanual/device QA待ちでも、その結果へ依存しないmachine-readyなReady workは進めてよい。
- 前段の実使用結果によって設計・食品安全・UX判断が変わる場合は先回り実装しない。
- 実機でしか判定できない項目は未確認のまま残し、成功扱いしない。


## 次回更新の追加選定項目 / GitHub Issues

2026-10-05に作業リストへ反映。既存Phaseの依存順・未検証ゲートは維持し、この項目の公開版番号・公開日は未定とする。詳細設計・Acceptance・Issueの状態はGitHubの個別Issueを正本とする。

- [ ] [#7 Android共有でChatGPTのレシピ生成・改善結果を取り込む](https://github.com/kapioka/recipe-cooking-navigator/issues/7) — 2026-10-11実装・全195テスト・debug APK build・公開Schema整合・正式署名APKのPixel更新済み。ChatGPTとの往復を含むユーザー端末QAは未完了。共有/コピー方式を正本とし、詳細は[チェックポイント](plans/issues-7-8-checkpoint.md)、[後日のQA](plans/issue7-device-qa.md)。
  - 食材・人数・調理器具・味の方向性・時間を入力し、「ChatGPTでレシピを作る」から依頼する。
  - 公開AI入口 `ai/AGENTS.md` のURL、ユーザー条件、仕様取得失敗時は推測生成しない指示を含む短い依頼文を自動生成する。
  - ChatGPT側が必要な最新Schema / Workflow / 連携仕様を参照する。アプリ側の仕様全文取得・ETag・キャッシュは基本経路に含めない。
  - JSONの貼り付け・Android共有・ファイルを既存Parser / Schema Validation / Preview・確認へ合流し、正常なRecipeだけを保存する。既存の手動取込・Drive Inbox経路は維持する。
  - root開発用 `AGENTS.md` と一般利用者AI向け `ai/AGENTS.md` の役割を分ける。OpenAI APIキー・独自サーバーを必須にしない。
  - Android標準共有または依頼文コピー＋公開ChatGPT URLの起動を使う。事前入力や自動投稿は保証しない。
  - ローカルのRecipe / Feedback v2と公開mainのv1参照に差があるため、AI入口公開前に対応アプリ・公開Schema・生成Workflowの版をそろえる。公開されていないSchemaへ案内しない。

- [ ] [#8 Sign in with ChatGPTでアプリ内生成・再作成](https://github.com/kapioka/recipe-cooking-navigator/issues/8) — 2026-10-11公式仕様調査、独立Flutter/Android PoCの認証・テキスト推論・音声修正/確定導線を実装。本体200/PoC21テスト合格。実機PoCの認証・モデル・完了回答を確認し、本体の生成/改善・形式検証・プレビュー保存も実装。署名APKをPixelへ更新。本体での認証・生成・改善の実機QAは未完了。[調査と後日のQA](plans/issue8-siwc-research-and-qa.md)。

ちかベルの[#16](https://github.com/kapioka/chikabell/issues/16)と共通の操作方式で進める。共通化するのは「条件入力 → AI入口URL付き依頼 → ChatGPTで検索／生成 → 戻して検証・確認・保存」という体験であり、地点とRecipeのデータ形式は各アプリの正本に従う。

次期作業の確認時は、ロードマップに加えてGitHubのopen Issueと対象Issueの最新本文を読む。PR一覧だけでは未着手の作業を把握できない。個別IssueのAcceptanceを満たすまで完了にせず、実装・自動検証・端末での往復確認・公開を分けて記録する。2026-10-11の実装・機械検証の到達点は上記チェックポイントを参照する。

## 1. Product direction — Recipe appからKitchen toolへ

2026-09-11に、次の進化順を採用した。

1. Recipe / Feedback Schema v2と人数変更を先に完成させる。
2. その安定したRecipe基盤の上に、時計・独立タイマー・画面常時点灯をまとめた`Kitchen mode`を設計する。
3. 独立タイマーを画面やRecipeから切り離して信頼できる共通機能にする。
4. Recipe詳細とCooking modeをKitchen modeへ統合し、時計とタイマーを常に確認できるようにする。
5. 実際のキッチン利用で安定させた後、Feedback、Cooking Profile、共有、バックアップ、iPhoneを進める。

目指す製品像は、レシピを使う日だけ開くアプリではなく、調理中に置いておけるAndroidキッチンツールである。

- Recipeを開かなくても、現在時刻とタイマーを使える。
- Recipeを見ている間も、現在時刻と動作中タイマーを確認できる。
- Recipeの推奨時間から始めたタイマーと、単独で作成したタイマーを同じ仕組みで扱う。
- Kitchen mode中は画面を点灯状態に保ち、明示的な終了・ライフサイクル終了時には解除する。
- タイマー終了だけでRecipeの工程を自動的に進めない。

Recipeは引き続き中核機能だが、時計やタイマーをRecipe documentへ混ぜない。Recipe / Feedback / Cook Session / Kitchen Session / Timer runtimeの責務を分離する。

## 2. Roadmap overview

| 順序 | Phase | 状態 | ユーザーが得るもの | 次へ進む条件 |
|---:|---|---|---|---|
| 0 | 公開済みRecipe基盤 | 完了 | Recipe取込から調理完了まで | `v0.1.0`公開・実機確認済み |
| 1 | Schema v2・人数変更 | **Project切替済み／新規生成Recipeの取込確認待ち** | 人数に応じた一貫した材料分量 | v2生成→取込→調理→再開の成立 |
| 2 | Kitchen mode設計 | **3枚目を採用／設計整理済み** | 時計・タイマー・Recipeが共存する確定UI | 画面構成・状態遷移・受入条件の合意 |
| 3 | Kitchen tool基盤 | **実装・自動検証済み／画面・実機確認はユーザー担当** | 時計と単独タイマーだけでも使える常時表示画面 | 基本フローの自動・実機確認 |
| 4 | 共通タイマーの信頼性 | **通知・保存復元を実装／画面ロック等の実機確認待ち** | 画面移動やbackgroundでも失いにくいタイマー | 通知・復元・複数タイマー確認 |
| 5 | Recipeとの統合 | **主要導線を実装／実調理と旧タイマー移行確認待ち** | 時計・タイマーを見ながらRecipeを調理 | 全調理フローと既存機能の回帰合格 |
| 6 | Kitchen実利用安定化 | **実利用検査は全機能実装後へ延期** | 日常の調理で継続利用できる品質 | 実料理・電池・操作性・通知の評価完了 |
| 7 | Feedback / Revision loop | **主要導線を実装・自動検証／実往復は全機能実装後へ延期** | 調理結果を次回Recipeへ反映 | Feedback往復と任意Revision改善の成立 |
| 8 | Drive Feedback / Cooking Profile | **明示登録・候補承認、Drive評価蓄積・履歴読取・追記を実装／Work・実機未確認** | 調理履歴から自分の好みを安全に育てる | Evidence蓄積→候補化→承認→Profile更新の成立 |
| 9 | 共有・バックアップ | Phase 8後 | 外部共有と端末移行 | 権限・復元・プライバシー確認 |
| 10 | iPhone decision gate | Android安定後 | iOSへ進むか判断できるEvidence | 費用・需要・実装残量の判断 |

Phase番号は依存順を示す。公開版番号やリリース日は各Phaseの実装開始時に決め、ロードマップだけで固定しない。

## 3. Current status

### Phase 1実装状況

- [x] [Recipe / Feedback Schema v2・人数変更 実装計画](plans/recipe-schema-v2-servings-implementation-plan.md)を作成。
- [x] 既存2件のv1 Recipeは移行せず、新形式で再作成してよいと決定。
- [x] Schema v2をKitchen tool化より先に実装すると決定。
- [x] Recipeの上位にKitchen modeを置く製品方向を決定。
- [x] DriveへFeedbackを蓄積し、複数回のEvidenceからCooking Profileの更新候補を作る方針を決定。
- [x] しきい値到達は自動確定ではなく提案条件とし、ユーザー承認後だけProfileへ反映すると決定。
- [x] P1〜P4、アプリ内のFeedback v2接続、P6の自動検証を完了。
- [x] 配布用ChatGPT Project Packageのv2ローカル出力を準備する（2026-09-20にProject設定切替を確認。新規生成Recipeの往復は未確認）。
- [x] Pixel 10aで人数変更・中断・再開・分数TTSを確認する（1人分・4人分、TTS再生状態、再起動後の続きからを確認済み）。

### 公開・検証済み

- Flutter / Android初期版を実装済み。
- Recipeファイル取込、Schema v1検証、ローカル保存、一覧、検索、タグ、詳細、Revision履歴、active選択を実装済み。
- Google Drive Recipe Inboxの手動一括取込と、単一ファイル取込の独立したバックアップ導線を実装済み。
- Cooking mode、工程移動、材料表示、音声操作、TTS、タイマー、画面常時点灯、中断・再開、最小Cook Sessionを実装済み。
- 2026-09-06に自動テスト26件、format、analysis、debug build、Pixel 10aで主要フローを確認。
- 2026-09-08に専用署名APKをPixel 10aで確認し、`v0.1.0`をGitHub Releaseへ公開済み。
- 2026-09-20に同じ専用署名のv2対応APKをPixel 10aへデータ保持更新し、v2単一ファイル取込、1人分・4人分換算、中断・再開、工程移動、分数TTS、常時点灯解除を確認。

### 既知の未検証

- TalkBackによる全調理フロー。
- 換気扇・水道・調理音のある環境での実発話認識。
- TTS再生音を音声認識が誤検知しないこと。
- 長時間の画面点灯による電池・発熱・表示への影響。

これらはSchema v2の実装を止めず、Phase 6の実利用安定化でKitchen mode全体として確認する。Schema v2で触れる表示・TTS・再開については、Phase 1内でも変更分の回帰確認を行う。

## 4. Cross-phase invariants

明示的な仕様変更がない限り、全Phaseで次を維持する。

- 当面はAndroid / Flutterだけを実装する。
- Recipe / Feedback / Version / Cook Session / Kitchen timerのOS非依存ロジックをAndroid APIから分離する。
- 専用バックエンド、ユーザーアカウント、リアルタイムクラウド同期を前提にしない。
- 不正・未知Schemaを推測補完せずfail-closedで扱う。
- Recipe revision、Schema version、active/latest、Cook Sessionを混同しない。
- Feedbackは追記型のEvidenceとして保持し、Profile更新時も元Feedbackを上書き・削除しない。
- 単発評価や点数のしきい値到達だけで、恒久Preferenceを自動確定しない。
- アレルギー、医療・宗教上の制約は調理履歴から推測せず、ユーザーの明示入力だけを確定情報にする。
- 人数変更、タイマー操作、調理位置によってRecipe原本を上書きしない。
- タイマーはユーザー操作で開始し、終了しても工程を自動移動しない。
- 画面常時点灯はユーザーが入った実行モードの間だけ有効にし、終了時に解除する。
- 端末の`accelerometer_rotation`と`user_rotation`を書き換えない。
- 食品安全を効率や自動化より優先する。
- 外部SNS投稿やRecipe公開先のホスティング・URL管理をアプリの責任にしない。

Phase 2でKitchen modeの仕様を確定するまでは、現在の「Cooking mode中だけ画面常時点灯」を変えない。Kitchen mode実装後は「Kitchen modeがforegroundで有効な間」に適用範囲を広げ、通常のRecipe閲覧やアプリ全体へ無条件で適用しない。

アプリ名`Recipe Cooking Navigator`はPhase 6まで維持する。Kitchen toolとしての実利用結果を確認してから、名称変更の価値と移行コストを判断する。

## 5. Phase 0 — Released Recipe foundation（完了）

初期公開版`0.1.0`の完了点は、ChatGPTが生成したRecipeを取り込み、調理前確認を行い、1工程ずつ調理し、明示操作で調理完了を記録するところまで。

### Data / import / local state

- [x] Recipe / Feedback Schema v1とサンプルを定義。
- [x] Recipe ID、revision、parent_revision、latest、activeを分離。
- [x] 不正JSON、未知Schema、参照不整合、同一revision競合を拒否。
- [x] 保存済みRevisionを上書きせず保持。
- [x] ファイル取込とGoogle Drive Inbox取込を同じ検証・保存処理へ合流。
- [x] InboxのDrive文書ID・SHA-256取込記録、権限失効、処理上限、混在ファイルを処理。
- [x] Inboxファイルを削除・移動・変更しない。

### Library / pre-cook

- [x] Recipe一覧、詳細、材料、全体工程、器具、事前準備、想定時間・難易度を表示。
- [x] 料理名・食材名・最大5個のユーザータグを検索。
- [x] Version履歴表示とactive切替。

### Cooking / voice / device

- [x] 1工程表示、左右タップ・スワイプ、工程一覧、進行位置保存。
- [x] 工程の材料・分量、火加減、完了判断、次工程予告、並行作業を表示。
- [x] ユーザー起動タイマー、時間追加・リセット、終了後の工程維持。
- [x] Cooking mode中の画面常時点灯と終了時解除。
- [x] 音声操作ON/OFF、工程移動、材料・全体工程・調理画面、タイマー、読み上げを実装。
- [x] Recipe ID・revision・Step IDで「続きから」「最初から」を実装。
- [x] 調理完了時に最小Cook Sessionを保存。

元のPhase 0/1で未完了だった事前準備チェック、Recipe取込確認、Android Sharesheet受信はPhase 5へ移して扱う。Phase 0を再オープンして機能を追加しない。

## 6. Phase 1 — Recipe / Feedback Schema v2・人数変更（新規生成Recipeの取込確認待ち）

実装の詳細、Change Map、受入テスト、ロールバック、別モデルへ渡す開始文は[Schema v2実装計画](plans/recipe-schema-v2-servings-implementation-plan.md)を正本とする。

### 目的

基準人数から選択人数へ材料量を安全に解決し、材料一覧、下準備、工程、TTS、中断・再開、将来Feedbackで同じ量を扱う。Kitchen modeの基盤や共通タイマーはこのPhaseへ含めない。

### 実装順

- [x] P1: Recipe / Feedback v2 Schema、完全な例、意味validator、関連仕様を一致させる。
- [x] P2: 有理数、分量参照、総量、RecipeText、画面/TTSの共通rendererを実装する。
- [x] P3: v2保存領域と、人数・Recipe snapshot・解決済み分量を固定するCookingContextを実装する。
- [x] P4: Recipe詳細の人数選択とCooking modeへ接続する。
- [x] P5: Feedback v2契約とChatGPT Project Packageを更新する。（アプリ側契約・変換、ローカルv2出力、Project設定切替を確認。生成Recipeの往復は下記Completion gateで別途確認する）
- [x] P6: format、analysis、unit/widget tests、Android debug buildを合格させる。
- [x] P7: Pixel 10aで減量・増量・中断・再開・分数TTSを確認し、配布切替状態を記録する。

### Completion gate

- [ ] v2 Recipeを新規生成し、単一ファイルとInboxの両方から取り込める。（単一ファイルは実機合格、v2 Inboxは未確認）
- [x] 対応範囲内で増減でき、材料総量と各工程量が一致する。
- [x] qualitative / fixed量を数値として捏造せず、端数表示とTTSが同じ計算結果を使う。
- [x] 人数を変更して開始・中断・再起動・再開しても、開始時のrevisionと人数が保持される。
- [x] Recipeの推奨タイマー時間は人数倍率で自動変更されない。
- [x] 旧v1 Recipe・保存ファイルは変更されず、新領域で開始できる。
- [ ] ChatGPT側のv2 Instructions / Schema / 連携仕様がアプリと一致し、生成したRecipeで往復確認できる。
- [x] 未実装のEvaluation / Feedback共有UIやKitchen modeを完成扱いにしない。

Phase 1の受入合格後にだけPhase 2へ進む。人数変更の不具合をKitchen UIの作り替えと同時に診断しない。

2026-09-20追記: ユーザーがProject設定の切替完了と先行作業を指示したため、Phase 2の視覚案作成を先行した。ProjectのInstructionsはv2、情報源は`recipe-v2.schema.json`、`feedback-v2.schema.json`、`chatgpt-integration(2).md`の登録をブラウザで確認した。ローカル配布3ファイルはアプリ側正本とSHA-256一致。登録済み情報源の内容全体の一致と新規生成Recipeの取込は未確認であり、Phase 1全体を完了扱いにしない。ユーザー回答では切替後の新規Recipe取込は未実施。アプリのKitchen mode実装にはまだ着手していない。

## 7. Phase 2 — Kitchen mode製品仕様・画面構成

2026-09-20にユーザーが提示順の3枚目を採用。[Kitchen mode設計](kitchen-mode-design.md)へ基本画面・閲覧・調理・終了の画像と状態、データ責務、受入条件を整理した。配置はユーザー選択済み、細部の動作は既存invariantに沿った設計既定値。Phase 1の未確認を残し、アプリ実装はまだ開始していない。

### 目的

Recipe中心の既存画面を壊さず、時計・単独タイマー・Recipeを一つの調理用画面で使う体験を確定する。大きなUI変更なので、実装前に既存画面を基準に視覚案と状態遷移を決める。

### 決めること

- [x] Kitchen modeの開始・終了・foreground/background・異常復帰の状態遷移。
- [x] 現在時刻、動作中タイマー、Recipeへの導線の優先順位（選択案に合わせタイマー一覧を優先）。
- [x] 縦向き・横向き、スマートフォン・タブレット、大文字表示の基本構成。
- [x] 時計とタイマーを常時確認できる固定領域と、Recipe本文の可読領域。
- [x] タイマー終了時の画面・音・振動・通知の役割。
- [x] 画面点灯の開始条件、明示的な終了、電池制限時の説明。
- [x] Recipeなし、Recipe閲覧、調理中、タイマー完了の主要フロー。
- [x] 通知権限、画面ロック、background時の説明。
- [x] 既存の左右タップ・スワイプ・固定操作デッキと、新しい常設領域の競合回避。
- [x] Kitchen mode中に別Recipeを開く・調理を中断する場合の扱い。

### Design gate

- [x] 現行調理画面の既存視覚目標とコードの配色・操作配置を参照し、3つの視覚案を作る（2026-09-20、調理本文・時計・タイマーの優先順位を比較）。
- [x] 提示した3案から1案を実装目標として選ぶ（3枚目）。
- [x] 選択案の時計、タイマー、Recipeなし、Recipe閲覧、Cooking mode、タイマー終了状態を揃える。
- [x] `docs/product-spec.md`、`docs/data-model.md`、`docs/cooking-mode-ui.md`を更新する。AGENTSの現行点灯invariantは維持し、Phase 3着手時に移行条件と共に変更する。
- [x] 自動テスト可能な状態遷移と、実機でしか確認できない項目を分ける。

Completion: 選択済み画面目標、状態遷移、データ責務、受入条件が揃い、実装モデルが主要配置を判断し直さずPhase 3へ入れる。

## 8. Phase 3 — Kitchen tool基盤

2026-09-21: ユーザーの「画面確認を省いて先行する」指示により実装。再開点は[Phase 3実行計画](plans/kitchen-phase3-execution-plan.md)。自動テスト91件、対象lib/testのanalysis、変更Dartのformat、debug buildは合格。画面表示・操作・実機回帰は未実施で、下記Completion gateの実動作確認はユーザー担当とする。

### 目的

Recipeを開かなくても、現在時刻と単独タイマーだけで使える最小のKitchen modeを成立させる。

### Domain / state

- [ ] `KitchenSession`をRecipe/Cook Sessionと分離して定義する。
- [ ] タイマーをWidget内の一時変数から、画面外の共通controller / storeへ移す。
- [x] Timer ID、名前、作成元、設定時間、期限、状態を持つOS非依存モデルを作る。
- [x] 作成元はstandaloneとrecipe stepを表現できるが、Recipe参照は任意にする。
- [x] 内部保存は複数タイマーを扱える配列にし、初期UIの表示件数へデータ形式を結合しない（Phase 3はプロセス内store）。
- [x] 表示文字列や1秒ごとの残時間を正本にせず、期限から残時間を算出する。

### UI / lifecycle

- [x] Kitchen modeの入口と明示的な終了を追加する。
- [x] 現在時刻を大きく表示する。
- [x] Recipeなしで時間設定、開始、停止、リセットできる。
- [x] Kitchen mode内の画面移動で時計と動作中タイマーを失わない所有構造を実装する（操作確認は未実施）。
- [x] Kitchen modeがforegroundの間だけ画面常時点灯を保持する実装を追加する。
- [x] 終了、Activity lifecycle、例外時に常時点灯を解除する実装を追加する（Android実動作は未確認）。
- [x] 既存Recipe一覧・取込・詳細をKitchen modeから開く導線を実装する。

### Completion gate

- [ ] Recipeが0件でもKitchen modeを開始し、時計と単独タイマーを使える。
- [ ] タイマー動作中にRecipe一覧・詳細を移動しても同じ期限が維持される。
- [ ] Kitchen mode終了後に画面常時点灯が残らない。
- [ ] 通常のRecipe閲覧だけでは無条件に常時点灯にならない。
- [ ] Recipe SchemaやRecipe原本へTimer runtimeを書き込まない。

## 9. Phase 4 — 共通タイマーの信頼性

2026-09-27: Android終了通知、権限案内、正確なアラーム、通知タップ復帰、Kitchen終了後のタイマー継続を実装。自動テスト、正式署名APKのPixel 10a更新、background通知・音・振動設定・通知タップ復帰まで確認。画面ロック中の追加QAはユーザー指示で中断し、Phase 6に残す。

### 目的

Kitchen timerとして期待される終了通知と復元を、表示中のWidgetに依存せず成立させる。

### 機能

- [x] 複数の名前付きタイマーを作成・同時実行する実装を追加する（画面確認はユーザー担当）。
- [x] 各タイマーを個別に開始、停止、再開、延長、終了できる。
- [x] 現在時刻・期限・残時間を端末時刻変更やresume時に再評価する。
- [x] アプリ再起動後にKitchenを明示的に開くと実行中タイマーを復元し、期限超過を完了として扱う（自動テスト合格、実機未確認）。
- [x] background / 画面ロック中のAndroid通知、音、振動を実装する（画面ロック実機QAは未完了）。
- [x] 通知権限拒否、音量0、通知チャネル無効、電池制限時の挙動を説明する。
- [x] 通知操作から対象タイマーまたはKitchen modeへ戻れる。
- [x] 同時終了、終了音とTTSの競合、重複通知を処理する。
- [x] 端末再起動後は自動再始動せず、確認後に停止状態で復元する。名前・設定時間は保持する。

### Completion gate

- [x] 複数タイマーが互いを上書きしない。
- [ ] 画面遷移、background、process再生成後も期限と完了通知が一貫する。
- [ ] 停止・削除済みタイマーの通知が後から発火しない。
- [x] 通知できない条件を黙って成功扱いにしない。
- [x] タイマー終了でRecipe工程が移動しない。

## 10. Phase 5 — Recipe / Cooking modeをKitchen modeへ統合

2026-09-27: Kitchen内のRecipe詳細からCooking modeを開始可能にし、工程推奨時間を共通Kitchen timerへ接続。単一ファイルとAndroid共有のRecipe取込に保存前確認を追加。事前準備チェックはRevision別のローカル保存へ分離。通常ホームからの旧Cooking timerは回帰用に残し、共通所有者への全導線移行後に除去する。

### 目的

時計とタイマーを見ながら、Schema v2のRecipeを確認・調理できる一続きのキッチン体験にする。

### Integration

- [x] v2 Recipe取込時の確認画面を設計・実装する（単一ファイル導線）。
- [x] Android Sharesheetの`SEND`と`content://`の`VIEW`からv2 Recipeを受信し、単一ファイルと同じ検証・保存前確認を通す（Pixel 10aでDownloadsのJSON共有先への表示、v2のキャンセルと取込成功、旧形式の拒否、「アプリで開く」経由の動作をユーザーが確認）。
- [x] 事前準備のチェック状態をRecipe revision別のローカルUI stateとして保存・表示する（自動検証済み、実機の表示・操作確認は未実施）。
- [x] Recipe一覧、詳細、Cooking modeで現在時刻と動作中タイマーへ常に到達できる（Kitchen内導線）。
- [x] Recipe Stepの`timer_seconds`を共通タイマーの初期値として渡す。
- [x] Recipe由来タイマーへ料理名・Step名を表示し、元Recipeを閉じても継続する。
- [x] 単独タイマーを動かしたままRecipeを開き、Recipeタイマーも追加できる。
- [x] Recipe由来タイマーの終了でもStepを自動完了・自動移動しない。
- [x] Schema v2の選択人数・CookingContextとTimer runtimeを独立して復元する。
- [x] 材料、工程一覧、TTS、音声操作から同じ共通タイマーを操作する（Kitchen内導線）。
- [ ] 現行`CookingScreen`内の独立タイマー状態を、移行確認後に重複なく除去する。
- [x] 調理中断・完了でTTSや音声認識を止めても、継続を選んだKitchen timerは失わない。

### Completion gate

- [ ] 時計＋単独タイマー＋Recipeタイマー＋Schema v2人数変更を同じ実調理フローで使える。
- [ ] Recipeを切り替えても実行中タイマーの所有元と表示が分かる。
- [ ] Cooking modeの工程操作、画面スクロール、タイマー操作が競合しない。
- [ ] 常時点灯、音声認識、TTS、通知の開始・終了責務が重複しない。
- [ ] Phase 0/1の取込、検索、タグ、Revision、再開、分量表示が回帰しない。

## 11. Phase 6 — Kitchen実利用安定化

### 実料理QA

- [ ] Recipeなしで時計・タイマーだけを継続利用する。
- [ ] 複数の待ち時間がある料理で、単独・Recipeタイマーを同時使用する。
- [ ] 両手が汚れる料理で音声操作とタイマー確認を行う。
- [ ] 換気扇、水道、炒め音、終了音、TTSが重なる環境で確認する。
- [ ] 長いRecipe、人数変更、複数Revision、中断・再起動・再開を通す。

### Device / UX QA

- [ ] Pixel 10aで縦向き・横向き、文字拡大、TalkBackを確認する。
- [ ] 主要画面サイズと、利用可能ならAndroidタブレットを確認する。
- [ ] 長時間点灯時の電池消費、発熱、OLEDへの配慮、暗所での眩しさを評価する。
- [ ] foreground/background、画面ロック、電話・音声割込み、通知権限変更を確認する。
- [ ] `accelerometer_rotation`と`user_rotation`が起動前・利用中・終了後で不変であることを確認する。
- [ ] timer終了、TTS、音声認識、通知音の音量・優先順位を調整する。
- [ ] Schema不適合、保存破損、通知不可などのエラーUXを確認する。

### Product decision gate

- [ ] 既定ホームをRecipe一覧のままにするか、Kitchen dashboardへ変えるかを利用記録から判断する。
- [ ] `Recipe Cooking Navigator`の名称を維持するか、Kitchen toolを表す名称へ変えるか判断する。
- [ ] 日常利用で時計・タイマー・Recipeのどれが主な入口になったかを記録する。
- [ ] Android版に継続利用価値があることを確認する。

このPhaseの結果が悪い場合、機能追加で覆い隠さず、Kitchen modeの情報量、画面点灯、タイマー信頼性、Recipe統合を修正する。

## 12. Phase 7 — Feedback / Revision loop

Feedback v2契約はPhase 1で確定する。ここではユーザーが実際に評価・共有できる製品フローを実装する。

2026-09-27: 完了済みCook Sessionへ任意の評価を追記し、実調理元と改善元のRevisionを分けたFeedback v2をSchema検証してからAndroid共有画面へ渡す実装を追加。既存の評価なしsessionと`cooking-v2.json`の`storage_version: 2`は維持する。自動testとdebug buildを通し、実機の評価入力・ChatGPT受信は未確認。

2026-09-28: ユーザー指示によりPhase 6の実利用検査とPhase 7の実往復確認は、全機能実装後にまとめて行う。Version履歴から任意の過去Versionを改善元として評価画面へ進む導線を追加し、調理記録を切り替えてもその選択を保持する。Feedbackからの複数回のRevision再取込、保存・再読込、active/latest分離は自動検証する。

- [x] 実調理時間、実難易度1〜5、総合評価1〜5を入力。
- [x] 味の偏り-2〜+2、困ったこと、実際の変更点、一言メモ、次回希望を入力。
- [x] 選択したCook Sessionと、改善元に選んだRecipe Revisionを区別する。
- [x] 基準人数、実際に選択した人数、提示量をFeedbackへ含める。
- [x] Feedback JSONを生成し、SharesheetからChatGPTへ共有する（自動検証済み。実機の共有先受信は未確認）。
- [x] 過去Revisionを選び、そのsnapshotを基準に再調整する（生成されたFeedbackの契約を自動検証済み）。
- [x] Version履歴から選んだ改善元を評価画面に引き継ぎ、Cook Sessionを切り替えてもactiveを変更せず維持する（widget test済み）。
- [x] 新Revisionを再importし、parent_revision、latest、activeを正しく扱う（Feedbackからの往復と端末保存・再読込を自動検証済み。ChatGPTでの生成・実機取込は未確認）。
- [ ] 良かった部分を保ちながら複数回改善できることを実料理で確認する。
- [x] 単発評価を恒久Preferenceへ自動昇格させない。

Completion: `Recipe生成 → 取込 → 人数選択 → Kitchen modeで調理 → 評価 → Feedback共有 → 改善Recipe取込 → 過去版復帰`が成立する。

## 13. Phase 8 — Drive Feedback蓄積 / Cooking Profile

Phase 7で生成できるようになったFeedbackを、Google Drive内の通常のユーザー可視フォルダへ蓄積する。Feedbackを変更しないEvidence、Cooking ProfileをEvidenceから導いた現在の確定状態として分離する。専用バックエンドやリアルタイム同期は導入しない。

### Drive folder contract

```text
Recipe Cooking Navigator/
├─ Inbox/                       # Workからアプリへ渡すRecipe JSON
├─ Feedback/                    # 未変更のFeedback v2を含むEvidence envelope
│  └─ YYYY/
└─ Profile/
   ├─ cooking-profile.json      # 配布用・互換用snapshot（派生物）
   ├─ preference-candidates.json
   └─ History/profile-<IDのSHA-256>/ # immutable更新履歴（正本）
```

- [x] Google Driveの非表示なアプリデータ領域ではなく、ユーザー可視の通常フォルダを使用するadapterを実装（providerでの操作・Workからの可視性は実機未確認）。
- [x] 現在の`Inbox`選択権限を壊さず、アプリ用ルートフォルダを別設定で追加選択・再接続する実装を追加（実機未確認）。
- [ ] `Inbox`、`Feedback`、`Profile`の用途をファイル種別とSchemaで検証し、異なるdocumentを混在処理しない。
- [x] Driveを利用できない場合も、端末内保存と既存のSharesheet共有を利用できる状態にする（自動検証済み）。
- [x] 保存用Evidenceに一意な`feedback_id`、Cook Session、Recipe ID / revision、作成日時を保持し、同一Feedbackを重複集計しない。
- [x] Feedback Evidenceは取込・集計後も上書き、移動、削除せず、破損・未知Schema・ID競合を個別に拒否する（Dart・channel契約を自動検証、provider実機は未確認）。

### Data responsibility

- [x] `Feedback`、`CookingProfile`、`PreferenceCandidate`を別document / domain modelとして定義する。
- [x] Profile Schemaに`profile_schema_version`、`profile_id`、`revision`、`updated_at`、確定Preference、明示的な制約を定義する（Drive配置・制約入力は未実装）。
- [x] Candidate Schemaに判定規則version、対象dimension、適用scope、方向、score、根拠Feedback ID、異なるCook Session ID、異なるRecipe ID、状態を持たせる。
- [x] Candidate状態は`proposed`、`accepted`、`rejected`を区別する。
- [ ] Preferenceのscopeを`recipe`、料理カテゴリ・タグ、`global`で区別し、限定的なEvidenceを全料理へ一般化しない。
- [x] Profileの確定統計をFeedbackと重複保存せず、再集計可能な派生値とユーザー確定値を区別する。
- [x] Profile更新時は更新元・更新後・操作をimmutable Historyへ保持し、同じrevision番号の分岐も上書きせず停止する（自動検証済み、provider実機未確認）。

### Initial scoring contract

初期値は実利用後に規則versionを上げて調整できるようにし、過去の判定を無言で再解釈しない。

- [x] 同じCook Session内の同じ味dimensionは最大1件のEvidenceとして数え、コメント・偏差・変更点の重複加点を防ぐ。
- [ ] 明示的な`next_time_intent`で方向が判定できる場合は`+2`、味の偏差または成功した実変更から方向が判定できる場合は`+1`を基本値とする。
- [x] 反対方向のEvidenceは同じ規則で減算し、総合評価だけから味の方向を推測しない。
- [x] 初期の提案条件は、正味scoreが`4`以上、提案方向を支持する異なるCook Sessionが`3`件以上、異なるRecipeが`2`件以上とする。
- [ ] 同一Recipe周辺だけのEvidenceはRecipeまたはカテゴリscopeに留め、global候補には複数カテゴリのEvidenceを要求する。
- [x] ユーザーが「普段から薄味が好き」等を明示した場合は、集計しきい値を待たず確認済みPreferenceとして端末内へ登録できる（1.1 Schema、旧store移行、UI確認を自動検証済み）。
- [x] アレルギー、医療・宗教上の制約、食品安全判断を自動推論・点数化しない。

### Approval / update flow

- [x] しきい値到達時はProfileを自動更新せず、根拠件数、対象scope、提案内容をユーザーへ表示する。
- [x] ユーザーが承認した場合だけHistoryへ更新を追記しProfile revisionを増やし、Candidateを`accepted`へ変更する（自動検証済み）。
- [ ] `cooking-profile.json`をHistoryから互換用に再生成する。
- [x] 却下時はCandidateを`rejected`として保持し、同じ支持Sessionだけで再提案しない。新しい反復Sessionが加わった場合だけ再候補化する。
- [ ] ChatGPT WorkはFeedbackの要約と更新案の説明を担当できるが、score、重複除外、しきい値判定は同じ入力から同じ結果になるアプリのドメインロジックを正本とする。
- [ ] Workまたはアプリが更新する場合は、読み取ったProfile revisionを更新元として照合し、競合時は自動上書きせず再読込を要求する。
- [x] アプリは最後にSchema・ドメイン検証を通過したDrive Profileを接続元とともに端末へキャッシュし、Driveが利用できない間は読み取り専用で確認できる（自動検証済み、実機未確認）。

### Implementation order

- [x] P1: Profile / Candidate / Evidence Schema、Drive folder契約、点数規則version、完全なdocument例を追加する。
- [x] P2: Feedback重複排除、category / global scope判定、score集計、候補状態遷移をOS非依存ドメインとして実装する。recipe scopeの条件は未決。
- [x] P3: Driveのアプリ用ルート接続、Feedback追記・再取込、Profile取得・検証・読取専用端末キャッシュを実装する（Dart・channel契約を自動検証、Androidコンパイル、実機は未確認）。
- [x] P4: Candidateの根拠表示、承認・却下、端末内Profile revision更新・履歴UIを実装する（Drive更新はP3に残る）。
- [ ] P5: ChatGPT WorkがProfileをRecipe生成へ利用し、承認済み更新だけを書き戻す運用契約を整合させる。
- [ ] P6: unit / widget tests、Drive権限失効・競合・破損・offline、Pixel 10a実機フローを確認する。

### Completion gate

- [ ] 3件以上のFeedbackをDriveへ重複なく蓄積し、元ファイルを変更せず再集計できる。
- [ ] しきい値未満ではCandidateを提案せず、しきい値到達後も承認前にProfileが変わらない。
- [ ] 承認後だけProfile revisionが増え、根拠Feedbackと過去Profileを追跡できる。
- [ ] 反対Evidence、同一Session内の重複情報、同一Feedback再読込でscoreが不正に増えない。
- [ ] recipe / category / global scopeを越えて好みを一般化しない。
- [ ] 却下したCandidateを同じEvidenceだけで再提案しない。
- [ ] Driveがoffline、権限失効、Profile競合、ファイル破損の場合に既存Profileを失わずfail-closedになる。
- [ ] ChatGPT Workが承認済みProfileを参照したRecipeを作成でき、未承認Candidateを確定Preferenceとして扱わない。

Completion: `評価 → FeedbackをDriveへ追記 → 決定的に集計 → Preference候補を提示 → ユーザー承認 → Profile revision更新 → 次回Recipe生成へ反映`が、元Feedbackと過去Profileを失わず成立する。

### 2026-10-04実装チェックポイント

- 端末内Evidence保存、候補集計、承認・却下、revision照合、過去Profile保持を実装。評価画面の「好みの記録に残す」とホームの「料理の好み」を接続した。
- Android SAFによるアプリ用ルート選択とFeedback追記を追加。既存ファイル比較、読戻し、権限失効・部分成功の表示を実装した。Drive providerでの操作・クラウド同期は未確認。
- 規則1.0.0では自由文を解析せず、確認済み方向2点・偏差1点を使う。成功した実変更の自動分類は未実装。recipe scopeは共通の「Recipe 2件」条件と両立しないため、自動提案をまだ有効にしない。
- Drive Profileの明示取得・検証・読取専用キャッシュを追加した。欠落・破損・offline・同revisionの内容違い・巻戻りでは既存キャッシュを保持し、端末内承認履歴と混合しない。
- Drive Evidenceの明示読込を追加。正常ファイルの追加、同一内容の再取込スキップ、破損・未対応・ID競合の個別拒否を実装し、候補の再集計だけでProfileを変更しない。
- 明示Preference登録、storage v2の操作履歴、旧原文保持のmigration、Profile 1.1を実装した。Drive履歴のSchema・連結・digest・操作再生を検証し、分岐・欠落時にはキャッシュを保持する読取経路を追加した。承認した明示登録・候補変更の履歴追記、旧snapshotからの開始、確認待ち送信の永続化・同ID再送も実装した。単純上書きを競合制御として扱わない。
- Phase 8の完了判定とWork運用・Pixel実機確認は未完了。実機確認の延期は前段Phaseの受入済みを意味しない。
- 最終機械検証: formatはCLI込み80ファイル差分なし、`analyze lib test tool/validate_profile_history.dart`はNo issues found、全189テスト合格、Work CLI 6 smoke合格、Android debug build成功。APK・主要ファイル・後日の実機手順は[検証チェックポイント](plans/phase8-validation-checkpoint-2026-10-04.md)に記録した。
- Astraの限定レビューを踏まえ、[明示登録とProfile書戻しの設計](plans/phase8-profile-explicit-and-write-design.md)を作成。ユーザー承認によりDrive履歴を正本に変更した。アプリの書戻しは実装した。Work接続・競合解決UIと互換snapshot再生成は未実装。

## 14. Phase 9 — External sharing / portability / backup

### SNS・外部共有

- [ ] 完成写真、料理名、アプリ利用表示、総合評価、実難易度、公開用の一言を選択。
- [ ] ユーザー自身が用意した任意Recipe URLを入力。
- [ ] 投稿前プレビューで公開内容を確認・編集。
- [ ] OS Sharesheetへ画像と投稿文を渡す。
- [ ] ChatGPT用JSONとSNS用文章を別成果物として扱う。

### Recipe / backup

- [ ] 単一Recipeのポータブルexport/import形式を決定。
- [ ] 全Recipe、Revision、Cook Session、Evaluation、active状態のbackup形式を設計。
- [ ] Kitchen timer履歴をbackupへ含める価値を実利用から判断。実行中Timerを安易に端末間復元しない。
- [ ] 破損・中断・部分復元をfail-closedで扱う。
- [ ] Android端末間でexport/importを確認。

### 公開プロフィール

- [ ] Phase 8の内部用Cooking Profileと公開可能なプロフィールを分離。
- [ ] 公開項目をユーザーが選択し、内部Preferenceを自動公開しない。
- [ ] Cook SessionやRecipe履歴から算出できる統計を手入力で重複保持しない。
- [ ] カード・投稿文の共有前プレビューを行う。

専用クラウド同期は必須にしない。保存先、公開設定、アクセス権、外部URLの有効性・生存期間はユーザーと外部サービスの責任とする。

## 15. Phase 10 — iPhone decision gate

AndroidのKitchen tool、Feedback loop、Cooking Profileが日常利用で安定してから判断する。

### 判断事項

- [ ] iPhone対応の需要と、Android版の継続利用価値。
- [ ] Mac購入、Apple Developer Program、公開費用の妥当性。
- [ ] iPhone実機を用意するか、TestFlight協力者で検証するか。
- [ ] 共通DartドメインとAndroid固有実装の分離状況。
- [ ] Kitchen timer通知、常時点灯、音声認識、TTS、Share SheetのiOS実装量。

### 進む場合

- [ ] macOS / Xcode環境、iOS target、署名・配布を準備。
- [ ] Recipe v2 / Feedback v2、保存、Revision、Kitchen modeを移植。
- [ ] iOS通知・タイマー、idle timer、音声認識、TTS、Share Sheetを実装。
- [ ] AndroidとのRecipe / Feedback / backup互換性を検証。
- [ ] Simulator後にiPhone実機 / TestFlightで調理フローを確認。

## 16. Later candidates — 実利用Evidenceがある場合だけ

- [ ] 最近使った時間、繰り返しタイマー。Kitchenの固定10分・1分・10秒追加ボタンはユーザー選択の画面設計として実装済み。
- [ ] 音声による「5分タイマー」等の時間指定。誤認識時は必ず確認可能にする。
- [ ] ストップウォッチ。
- [ ] 調理ロック、片手モード、テーマ、低輝度表示。
- [ ] 材料チェック、工程内メモ・ハイライト、明示的な工程完了。
- [ ] 物理ボタンによる工程送り。
- [ ] 複数料理の並行調理支援。複数タイマーとは別の製品機能として扱う。
- [ ] Cooking Profileのカテゴリ細分化、時系列重み、季節・体調等の文脈を使う高度な嗜好分析。
- [ ] Recipe revision差分表示。

## 17. Non-goals until justified

- 専用バックエンド。
- ユーザーアカウント。
- アプリ内SNS、フォロー、コメント、ランキング。
- サブスクリプション。
- Recipeホスティング、公開URL発行・監視。
- リアルタイムクラウド同期。
- 買い物リスト、栄養管理、スーパー在庫・価格取得。
- カメラ常時監視。
- 複雑なAgent構成、大規模推薦基盤。
- 時計やTimer runtimeをRecipe Schemaへ格納すること。

## 18. Development / completion rule

- 各Phaseは、前段のCompletion gateを満たしてから開始する。
- 複数Phaseを同じ変更へ混ぜない。前段の不具合を後段のUI変更と同時に診断しない。
- 大きなUI変更は、実装前に既存画面を参照した視覚目標と主要状態を確定する。
- Schema、外部Package、アプリconsumer、保存、UI、docsの正本と派生物をChange Mapで固定する。
- 現在使える検証コマンドだけを用い、format、analysis、unit/widget tests、debug buildを変更リスクに応じて実行する。
- Android実機依存の通知、常時点灯、音声、TTS、回転設定はbuild成功だけで完了扱いにしない。
- 実装済み、自動検証済み、実機検証済み、公開済み、未実施を分けて報告する。
- mainへのmerge、push、tag、Releaseはrepository policyとユーザーの明示承認に従う。

価値の評価では、機能数より次の摩擦が減ったかを見る。

- 調理中に現在時刻を確認するため別の時計を見る必要。
- タイマーを使うためRecipeを開く必要。
- 画面移動や再起動でタイマーを失う不安。
- 複数タイマーの区別がつかない問題。
- 分量確認、スクロール、工程の見落とし。
- 手が汚れて操作できない問題。
- 画面消灯による中断。
- 改善後に以前のRecipeへ戻れない問題。
- 調理結果が次回へ残らない問題。


2026-10-04 Phase 8追加: Work向けのread-only検証入口`tool/validate_profile_history.dart`を追加。正常な全観測履歴だけProfile JSONを出力し、分岐・欠落・改変・未知Schemaでは出力しない。Workの実際のDrive取得・承認済みwriterと配布snapshot再生成は引き続き未実装。
