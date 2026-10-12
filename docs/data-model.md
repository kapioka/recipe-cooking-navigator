# データモデル

## 1. 基本方針

Recipe Cooking Navigatorでは、次の概念を分離する。

```text
Recipe
 └─ Recipe Revision
      ├─ Cook Session 1
      │    └─ Evaluation
      ├─ Cook Session 2
      │    └─ Evaluation
      └─ Cook Session 3
           └─ Evaluation
```

レシピそのもの、実際に作った記録、感想・評価を同じオブジェクトへ上書きしない。

## 2. Versionの区別

### Schema version

データ形式の互換性を表す。

例: `schema_version: "2.0.0"`

フィールド構造や意味が変わるときに更新する。

### Recipe revision

個別レシピの改良履歴を表す。

例: `revision: 1`, `revision: 2`

味付けや手順を改善してもSchema自体が同じならSchema versionは変更しない。

## 3. Recipe document

ChatGPTからアプリへ渡すトップレベル文書。

```json
{
  "schema_version": "2.0.0",
  "type": "recipe",
  "recipe": {}
}
```

ChatGPTとアプリの間は、途中で人間が読むためのMarkdownや説明文を混在させず、Schemaに適合するJSONを正本とする。

## 4. Recipe identity / lineage

Recipeは安定した`id`を持つ。

修正版は同じ`id`を維持し、`revision`を増やす。

新しい別料理として保存する場合は新しい`id`を使う。

`parent_revision`は、そのRevisionを生成するときにベースとしたRevisionを表す。

例:

```text
Revision 1
   ↓
Revision 2
   ├─ Revision 3
   └─ Revision 4
```

Revision 4がRevision 2をベースに再調整された場合、`parent_revision: 2`とする。

## 5. App-side active / latest state

`latest`と`active`はRecipe JSONそのものではなく、アプリのローカル保存状態として管理する。

- `latest_revision`: 最後に取り込まれた最も新しいRevision
- `active_revision`: 次回通常表示・調理に使うRevision

両者は一致しなくてもよい。

例:

```text
Revision 4 = latest
Revision 3 = active
```

ユーザーは過去Revisionを`active`へ戻せる。新しいRevisionを取り込んでも、過去Revisionは削除しない。

Schema v2の端末内領域ではRecipe documentとは別の`recipe-version-state-v2.json`に、Recipe IDごとの明示的な`active_revision`だけを保存する。明示状態がないRecipeは`latest_revision`をeffective activeとして扱う。旧v1領域は移行・削除せず保持する。

ユーザーが一度activeを明示したRecipeへ新しいRevisionを取り込んだ場合、その選択を勝手に変更しない。新しいRevisionは`latest`として履歴へ追加し、ユーザーが確認してactiveへ切り替えられる候補とする。active切替ではRecipe document、過去Revision、Cook Session、既存の調理途中位置を書き換えない。保存先に存在しないRecipe ID / revisionはactiveに設定しない。

### アーカイブと明示的な完全削除

アーカイブはRecipe ID単位の端末内表示状態を`recipe-archive-v1.json`へ保存する。通常一覧・検索から隠すだけで、全Revision、latest / active、タグ、事前準備、Cook Session、Evaluationは保持する。復元すると元のactive Revisionで一覧へ戻る。Recipe / Feedback Schemaにはアーカイブ状態を加えない。

アーカイブ画面からユーザーが確認して完全削除した場合だけ、対象Recipe IDの全Revision、active状態、タグ、事前準備、調理途中位置、Cook SessionとEvaluationを端末から削除する。他のRecipe IDのデータは保持する。関連データを読み取れない場合は削除を開始しない。途中失敗時はRecipe本体とアーカイブ状態を残し、再試行できるようにする。これは通常のRevision追加・active切替で履歴を保持する原則への、明示的な完全削除操作に限った例外である。Inbox元ファイルは変更しないため、削除前にユーザーへDrive側の元ファイルを除く案内を出す。

## 6. Quantity

Schema v2では計測可能量を正の有理数、計測不能量を定性的な型として分離する。表示文字列は計算結果から生成し、Recipe原本や保存contextの正本にしない。

```json
{
  "kind": "measured",
  "value": {"numerator": 1, "denominator": 2},
  "unit": "piece",
  "scaling": "linear"
}
```

人数によらず同量にする場合は`scaling: "fixed"`と理由を明示する。機械値にしない場合:

```json
{
  "kind": "qualitative",
  "text": "少々",
  "adjustment_note": "味見をして必要な場合だけ加える。"
}
```

`linear`は基準値 × 選択人数 ÷ 基準人数で解決する。卵等も自動で切り上げず、分数を維持する。g / kg / ml / Lの小数丸めは表示だけに適用し、計算・保存・Feedbackへ戻さない。

## 7. IngredientとAmount参照

材料の名称は`ingredients`、用途別の物理量はRecipe直下の`amounts`に一度だけ定義する。同じ材料を炒め用・仕上げ用に分ける場合は別amountとし、下準備と投入で同じ量を示す場合は同じamountを再参照する。

事前準備と各工程は`amount_ids`を持つ。総量はamount定義を一度ずつ合計し、参照回数を足さない。文章内で人数により変動する量は`RecipeText`の`amount_ref`として参照し、自由文の数字を置換しない。

## 8. Overview

`overview`は調理開始前に見る全体工程。

詳細手順のコピーではなく、料理全体の流れを短く表現する。

## 9. Preparation

加熱開始前に済ませられる作業を独立タスクとして保持する。

チェック状態そのものはRecipe JSONへ書き戻さず、Cook SessionまたはローカルUI stateとして扱える。

Android初版のチェック状態は`preparation-checklist-v1.json`へRecipe IDとrevisionごとに保存する。Recipe原本、CookingContext、Cook Sessionには追加しない。明示的にチェックをリセットでき、次回調理前には再確認する。破損した保存とbackupを空のチェック状態として上書きしない。

## 10. Stage / Step

Recipeは複数のStageを持てる。

StepはCooking modeで1画面に表示できる実行単位とする。

主要情報:

- `id`
- `title`
- `instruction`
- `amount_ids`
- `heat`
- `timer_seconds`
- `done_when`
- `utensil_ids`
- `parallel_tasks`
- `next_preview`

`heat`や`timer_seconds`は不要な工程では省略できる。

## 11. Timer state

Recipe JSONの`timer_seconds`は推奨時間を表す。実際のタイマー開始・停止・残時間はRecipe本体へ保存しない。

タイマーはユーザーがボタンまたは音声で開始する。Step表示だけでは自動開始しない。

## 12. Voice interaction state

音声認識や読み上げのON/OFF、現在認識中かどうか等はアプリのUI / runtime stateでありRecipe JSONには含めない。

Recipe側は読み上げ可能な構造化情報を保持し、アプリ側が現在Stepから読み上げ文を組み立てる。

## 13. Utensil

器具はRecipe直下で定義し、StepからID参照する。

`reuse_note`で使い回しの流れを説明できる。

器具再利用は食品安全より優先しない。

## 14. Estimated difficulty

AIがレシピ作成時に予測した難易度。

```json
{
  "score": 2,
  "reason": "フライパン1つで完結し、加熱判断が単純"
}
```

1〜5で保存する。

ユーザーが調理後に付ける実難易度とは別物。

## 15. Cook Session

1回の実調理を表す。

同じRecipe revisionを複数回作った場合も、Cook Sessionは毎回追加する。

主な項目:

- session ID
- Recipe ID / revision
- 実調理時間
- 実難易度
- 困ったこと
- レシピから実際に変更したこと

### 調理途中のローカル進行状態との分離

調理位置の再開用に、完了後の評価とは別の`CookingProgress`を端末内で保持する。内部保存形式の設計項目であり、Recipe / Feedback JSON Schemaへの追加ではない。

- Recipe ID、固定したrevision、現在のStep ID、更新時刻を保持する
- 調理開始時のRecipe v2全文を`recipe_snapshot`として固定する
- 選択人数、`servings-v2.0`、全amountの正確な解決量を`cooking_context`として固定する
- 画面上の工程番号は、そのrevisionのStep順序から算出する
- 初期版はRecipe IDごとに再開対象を1件保持する。同時に複数料理を管理する設計へ広げない
- 位置変更時はStepと更新時刻だけを変更し、snapshot・人数・解決量を維持する
- 起動時には参照先revision・Step・snapshot・再計算したcontextとの一致を検証する
- Recipe importやactive切替は、既存の進行状態が参照するrevisionを書き換えない
- 現在位置は閲覧・操作位置であり、工程の作業完了状態やEvaluationではない
- 「最初から」は進行状態だけを更新し、過去のCook SessionやRecipeを削除しない
- 調理完了時はCook Session保存の成功を確認してから進行中表示を終了する
- タイマーの実行状態・復元は別責務とし、Stepの位置だけから開始・完了を推定しない

UI上の再開・欠損時の扱いは[cooking-mode-ui.md](cooking-mode-ui.md)を参照する。

## 16. Evaluation

Cook Sessionに対するユーザー評価。

Android初版では、完了済みCook Sessionに任意の`assessment`を追記して保持する。`cooking-v2.json`の`storage_version: 2`を維持し、評価のない既存Sessionもそのまま読み込む。評価には実調理時間・実難易度・困ったこと・実変更と、総合評価・味の偏り・一言メモ・次回希望を分けて保存する。Recipe原本、調理途中の位置、選択人数と解決済み分量を書き換えない。

### Overall

1〜5の総合満足度。

### Taste deviation

各味覚軸は「強度」ではなく「理想との差」を -2〜+2 で保存する。

```text
-2 かなり弱い
-1 少し弱い
 0 ちょうどよい
+1 少し強い
+2 かなり強い
```

対象例:

- sweetness
- saltiness
- umami
- spiciness
- acidity
- richness
- aroma
- texture

## 17. 一言メモ

短い自由記述を、自分の記録とChatGPT改善材料として保存できるようにする。

SNS共有時にそのまま公開するとは限らない。共有文は別途ユーザーが確認・編集できるようにする。

## 18. Next-time intent

「次回どうしたいか」は評価コメントと分離する。

例:

- 甘味を少し下げる
- 旨味を一段強くする
- 合わせ調味料を加熱前に完成させる

ChatGPTによるRevision生成時の直接的な修正要求として利用する。

## 19. Preference profileとの分離

一回のCook Sessionで得た評価を、恒久的なユーザー嗜好へ自動昇格しない。

将来Preference Profileを実装する場合も、複数の独立したCook Sessionから継続的に確認された傾向と、個別料理だけの評価を分離する。

## 20. Feedback document

アプリからChatGPTへ戻すトップレベル文書。

```json
{
  "schema_version": "2.0.0",
  "type": "recipe_feedback",
  "recipe_snapshot": {},
  "cook_session": {},
  "evaluation": {},
  "revision_request": {}
}
```

外側の`recipe_snapshot`には改善対象として選んだRecipe v2を含める。`cook_session.recipe_snapshot`と`cook_session.cooking_context`には実際に調理した原本、人数、提示量を含める。改善元と実調理元は同じRecipe IDの異なるrevisionでもよい。

これにより、ChatGPT側が過去会話や外部保存状態を前提とせず、Feedback document単独で修正できる。

任意の過去Revisionから改善要求を作成できるため、Feedbackは常に選択されたRevisionのsnapshotを含める。提示量を実使用量とは断定せず、実際の変更は`changes_made`等へ記録する。`revision_request.next_revision`は改善元・実調理元の両revisionより大きくする。

## 21. Portable recipe / backup data

将来のレシピ書き出しやバックアップでは、内部データモデルを特定クラウドサービスへ依存させない。

- 単一Recipe共有: Recipe documentまたは将来定義するポータブルRecipe container
- 全体バックアップ: Recipe、Revision履歴、Cook Session、Evaluation、active状態を含むバックアップ形式を別途定義

バックアップ形式とRecipe Schemaを同一視しない。

## 22. External URL

SNS共有で使用する任意のレシピURLは、Recipeの正本データではない。

アプリはURLを生成・ホスト・検証・維持しない。必要なら共有画面の一時入力または共有用メタデータとして扱う。

## 23. Platform independence

Recipe / Feedback Schemaと主要ドメインモデルはAndroid/iOS共通とする。

OS固有の次の情報をRecipe JSONへ混ぜない。

- Android `content://` URI
- iOS file bookmark / security-scoped URL
- 端末ローカルパス
- OS固有の共有先識別子
- 音声認識セッションID

## 24. Invariants

- Recipe IDとRevisionを混同しない
- Schema versionとRecipe revisionを混同しない
- latestとactiveを混同しない
- 親Revisionを常に最新Revisionと仮定しない
- AI想定難易度とユーザー実難易度を混同しない
- 個別Evaluationを恒久Preferenceとみなさない
- Ingredient総量とStep使用量を混同しない
- Feedback作成時に選択した元Recipe snapshotを欠落させない
- 不明Schemaを推測で取り込まない
- OS固有データを共有Schemaの正本へ混ぜない

## 25. Local Recipe Metadata / User Tags

ユーザーがアプリ内でレシピを整理する情報は、ChatGPTが生成するRecipe documentと分離し、端末内の`RecipeLocalMetadata`として管理する。

初期対象はユーザータグとする。

```text
RecipeLocalMetadata
 ├─ recipe_id
 └─ tags（最大5個）
```

- `recipe_id`でRecipeへ紐づける
- 特定Revisionへは紐づけず、同じRecipe IDの全Revisionで共有する
- タグの追加、編集、削除はRecipe revisionを増やさない
- Recipe JSON / Feedback JSONのSchemaへは含めない
- Recipe importで上書きしない
- Feedbackや外部共有へ自動的に含めない
- 空文字と正規化後の重複を保存しない

タグの表示文字列はユーザー入力を基本とする。検索用には別途、前後空白の除去、Unicode NFKC相当の全角・半角正規化、英字の小文字化を行った比較値を使用できる。

ホーム検索では、通常表示に使うRevision（`active_revision`があればactive、未設定なら`latest_revision`）の料理名と食材名、およびRecipe IDに紐づくタグを検索対象とする。いずれかが検索語と部分一致すればRecipe単位で結果へ含める。

検索インデックスを将来追加する場合も、正本はRecipe Revisionと`RecipeLocalMetadata`に置き、インデックスを正本データとして扱わない。

### 任意のRecipe写真

写真はRecipe原本に含めず、Recipe IDをキーにするローカルメタデータとして扱う。各Revisionで共通の1枚とし、active / latestの切替では写真を切り替えない。`recipe-photos-v1/<SHA256(Recipe ID)>.png` に512×512の丸いPNGを保存し、元写真のURI・ファイル名・撮影情報は保持しない。取消・保存失敗では現在の写真を維持し、写真だけを明示変更・削除できる。アーカイブでは保持、Recipe完全削除で削除する。Recipe / Feedback JSON、Drive同期、Android自動バックアップ・端末移行の対象外とする。

## 26. Google Drive Recipe Inbox local state

Google Drive Recipe Inboxの接続状態と取込記録は、Recipe / Feedback Schemaへ追加せず、Android固有adapterの端末内データとして管理する。初期構築ではスプレッドシートやSQLデータベースを使わず、既存の端末内JSON保存方針に合わせる。

```text
RecipeInboxState
 ├─ connection
 │   ├─ connection_id
 │   ├─ tree_uri
 │   └─ configured_at
 └─ receipts[]
     ├─ receipt_id
     ├─ connection_id
     ├─ source_document_id
     ├─ content_sha256
     ├─ recipe_id
     ├─ revision
     ├─ result
     └─ handled_at
```

- `tree_uri`と`source_document_id`はAndroid DocumentsProviderが返すopaqueな値として扱い、Recipe JSON、Feedback JSON、共有物へ含めない
- `receipt_id`は端末内の取込記録を識別するIDであり、Recipe IDやrevisionの代わりにしない
- `content_sha256`は同じDrive文書が変更されていないことを高速に判定するための補助情報とする
- Recipe重複・競合判定の正本は、parseとSchema検証を通過したRecipe documentのRecipe ID、revision、内容比較とする
- `result`の初期値は`imported`または`already_exists`とし、拒否したファイルはreceiptへ追加しない
- receiptは対象Recipeの端末内保存に成功した後だけ追加する。receipt保存に失敗した場合も既存RecipeやInboxファイルを削除・上書きしない
- 同じ`source_document_id`でも内容SHA-256が変化した場合は再検証する。新Revisionなら追加し、同一Recipe ID・revisionの内容違いなら拒否する
- receiptが一致しても対応するRecipe IDとrevisionが端末内に存在しない場合は、receiptを古い記録として対象ファイルを再検証する
- フォルダ接続とreceiptのread-modify-writeは直列化し、並行操作で一方の更新を失わない
- フォルダの再選択で`connection_id`が変わっても、Recipe保存側の重複・競合規則を維持する

Inboxは取込元の追跡情報であり、Recipeの正本、backup、同期状態、処理queueではない。

## 27. KitchenSession / KitchenTimer（基盤・Phase 4保存復元を実装）

[Kitchen mode設計](kitchen-mode-design.md)の画面・状態遷移を支えるローカル状態。Recipe / Feedbackの共有Schema、Cook Session、CookingContextへTimer runtimeを追加しない。

| 所有者 | 保持する情報 | 境界 |
|---|---|---|
| KitchenSession | session_id、開始時刻、有効・suspended・終了状態、表示中の画面 | 画面点灯の要求元。Cook Sessionとは別。プロセス起動だけで有効状態へ復帰しない |
| KitchenTimer | timer_id、名前、作成元、設定時間、状態、期限、pause時の残時間、作成・更新時刻 | Widgetの破棄やRecipe切替で失わない |
| Timer notification adapter | timer_id、通知世代、配信・確認状態、OS側登録ID | Android依存情報を隔離し、取消済み世代の通知を拒否する |
| Clock adapter | 壁時計、単調時計、端末起動の識別情報 | 端末時刻変更と再起動を区別。OS実装はadapterに閉じる |

Timerの作成元はstandaloneまたはrecipe_step。recipe_stepだけにRecipe ID・revision・Step IDと表示用料理名・工程名を持たせる。Recipe原本や選択人数をTimerへ複製せず、Recipeを閉じてもTimerの識別と表示を維持する。

- Phase 3はプロセス内の不変timers配列を`KitchenTimerStore`が保持し、`KitchenController`が開始・foreground・終了の所有者となる。ID重複のある置換は拒否し、子画面へ所有権を渡さない。初期UIの1件制限と配列形式を結合しない。永続化するPhase 4ではversion付き形式へ拡張する。
- 状態はready、running、paused、finished、cancelledを区別する。finishedの確認日時は終了状態とは別に持ち、消音だけで行を消さない。
- 設定時間・残時間は整数の時間単位で扱う。UIの分秒文字列や毎秒tickを保存の正本にしない。
- 同一起動中は単調時計の期限を使う。復元用の壁時計期限・起動識別情報も持ち、端末再起動後は自動再始動せず要確認として保持する。具体的な保存フィールド・versionはPhase 3/4で使用APIと共に確定する。
- 開始・一時停止・再開・延長・取消・終了確認の更新を直列化する。状態保存に成功した後でUI成功を示す。
- 通知予約の失敗はTimer保存成功とは別に表示する。保存状態と通知予約は再照合できるようにし、片方だけ成功した状態を黙って成功扱いにしない。
- 再生成時の期限超過はfinishedへ一度だけ遷移する。同じtimer_id・通知世代で重複通知しない。
- 破損・未知versionは既存データとbackupを保持して拒否する。v1/v2 Recipe・Inbox権限・CookingContextの保存領域を変更しない。

時計はAndroid `SystemClock.elapsedRealtime()`を基準とし、Kitchen起動時・foreground復帰時に同期する。表示中は単調Stopwatchで補間する。壁時計は現在時刻の表示にだけ使い、タイマー期限はDart Durationで保持する。

2026-09-21にPhase 4の保存/復元を追加した。保存先はapplication support directory内の`kitchen-timers-v1.json`。`storage_version: 1`、Android `BOOT_COUNT`由来の`boot_id`、`timers`配列を持つ。個別timerはID・名前・作成元・設定時間・状態・期限・pause残時間・通知世代・作成/更新/確認日時を持ち、時間値は整数microseconds。壁時計期限による推定再開はせず、同じboot_idなら単調時計をそのまま使う。

保存更新はcontroller transactionで直列化し、fileへのcommit成功後に公開状態へ反映する。表示tickだけではfileを書かない。`.tmp`へflush後に置換し、前回commitを`.bak`へ保持する。primary破損・未知versionはbackupで黙って置換せず読み込み/保存を拒否する。primary欠落時だけbackupから復元する。初回保存中断でtmpだけが残る場合も空データで上書きしない。

boot_idが異なる場合、ユーザーの明示確認まで保存原本を保ち、確認後はrunning/pausedをcancelledへ変更し単調時刻を現在起動へ付け替える。名前・作成元・設定時間は保持し、手動リセット/開始を必要とする。通常のprocess再生成でKitchen・音声・点灯を自動起動しない。通知adapterは未実装で、background通知・音・振動の実機受入は別途残る。

## 28. Feedback Evidence / Cooking Profile（Phase 8のローカル基盤）

2026-10-04時点で、評価の明示記録、候補の決定的集計、ユーザーによる承認・却下、端末内Profile履歴、AndroidからDriveへのEvidence追記・再取込、Drive Profileの取得・検証・読取専用キャッシュを実装した。明示Preference登録とDrive履歴の読取・再生検証を追加した。承認した変更のDrive履歴追記・確認待ち送信の再確認も実装した。制約の直接入力は未実装。

正本Schemaと完全なdocument例:

| document | Schema | 例 |
|---|---|---|
| Feedback Evidence | `schemas/feedback-evidence-v1.schema.json` | `examples/feedback-evidence-example.json` |
| Cooking Profile (旧) | `schemas/cooking-profile-v1.schema.json` | `examples/cooking-profile-example.json` |
| Cooking Profile (明示登録) | `schemas/cooking-profile-v1.1.schema.json` | `examples/cooking-profile-explicit-example.json` |
| Preference Operation | `schemas/preference-operation-v1.schema.json` | History例の`operation` |
| Profile History | `schemas/profile-history-v1.schema.json` | `examples/profile-history-explicit-example.json`（2 documentの系列） |
| Preference Candidates | `schemas/preference-candidates-v1.schema.json` | `examples/preference-candidates-example.json` |

Evidenceは未変更のFeedback v2を`feedback`へ格納する保存用envelope。`feedback_id`、UTC作成日時、ユーザー指定カテゴリ、確認済み方向`confirmed_intents`を付ける。Feedback v2の機械受け渡し契約は変更しない。IDは端末間で衝突しにくいUUIDを使用し、同じ評価内容・カテゴリ・確認済み方向の再保存では既存IDを再利用する。同じIDの異なる内容や、同じSession IDの異なるRecipe参照は拒否する。

規則version `1.0.0`では、味の偏差が正なら減らす方向`-1`、負なら増やす方向`+1`へ1点。ユーザーが構造化入力で確認した次回方向は2点とし、偏差と重複加点しない。自由文の`next_time_intent`、変更の説明、総合評価、制約は解析・推論しない。同一Session・dimensionは最大2点で、方向が矛盾する記録（中立と方向の混在を含む）は集計から除外する。反対方向は減算する。

候補条件は正味score 4以上、提案方向を支持する異なるSession 3件以上、Recipe 2件以上。globalは支持Evidenceに異なるカテゴリ2件以上も要求する。カテゴリ未指定をglobalへ一般化しない。根拠Feedback IDには減算に使った記録も含め、Session・Recipeの件数は支持側を表示する。却下・承認の後は同じ支持Sessionだけで再提案せず、新しい支持Sessionが加わった場合に再判定する。

現在の「Recipe 2件以上」という共通条件ではrecipe scopeの自動候補は成立しない。scopeの保存形式は用意するが、初期UIの自動提案はcategory / globalのみ。recipe限定の自動候補条件は未決とし、しきい値を無断で緩めない。本人が明示した好みは、候補の集計条件とは独立してrecipe / category / globalへ登録できる。

端末内`preferences-v1.json`は現在`storage_version: 2`で、Evidence配列、Profile履歴、順序付き`operations`を保存する。候補承認・却下と明示登録を区別し、却下はrevisionを増やさない。読込時は候補をその時の根拠から再集計し、明示操作とともに初期状態からProfileを再現する。根拠欠落、重複operation ID、stale base、改変・欠落した操作は拒否する。操作の時刻はUTC、旧却下時刻だけは不明をnullとして保持する。

旧storage v1は厳格な検証後に読み、最初の更新時に旧原文を`.legacy-v1`へflushしてからv2へ移行する。旧原文と過去の1.0 Profileは変更しない。保全先に異なる原文があれば停止する。承認時刻は保存済みProfileの更新日時を使い、却下時刻は作らない。旧アプリによるv2読込は非互換であり、rollback時は保全原文の復元が必要。

Profile 1.1はPreferenceの`source_kind`を`feedback` / `explicit_user`で分ける。前者はrules version・根拠Feedback IDを保持し、後者は非空の`declaration`（2000文字以内）・確認時刻を保持する。初めて明示登録すると、旧Preferenceの由来を補った1.1の新revisionを追加する。架空のFeedbackやscoreを作らない。全料理、入力したカテゴリ、画面から選んだレシピを対象に、現在値と変更後を確認して登録する。自由文は本人の説明として保存するだけで解析しない。

同一プロセス内の保存操作を直列化し、`.tmp`へflushして置換、前回commitを`.bak`に残す。primary欠落時だけbackupを使用し、primary破損やtmpだけが残る状態を空記録で上書きしない。これはDrive上の複数writerの競合制御を代替しない。

Androidの別接続でGoogle Driveの`Recipe Cooking Navigator`ルートを選び、`Feedback/YYYY/feedback-<feedback_idのSHA-256>.json`へ保存する。1ファイル1 MB、ディレクトリ走査2000件を上限とする。同名既存ファイルは内容一致なら保存済み、内容違いなら停止する。新規書込後は読戻しを確認し、不完全なファイルも自動削除・上書きしない。保存先providerへの書込完了とクラウド同期は別に扱う。Inboxの接続・取込処理は変更しない。

Driveの正本は、ユーザー承認により`Profile/History/profile-<profile_idのSHA-256>/record-<record_idのSHA-256>.json`のimmutable履歴へ変更した。`Profile/cooking-profile.json`は配布用・互換用snapshotであり、履歴と並列の正本にしない。現在のadapterは履歴を読み、本人の承認後にimmutable recordを追記する。snapshot再生成は未実装。

Historyは1件の`bootstrap`と、そのrecord IDを`parent_id`でつなぐ`update`で構成する。bootstrapは明示移行したProfileの開始snapshotを保持し、過去の評価根拠を捏造しない。updateは更新元・更新後Profile、各SHA-256 digest、親record全体の`parent_digest`、承認された操作、候補の場合は未変更の根拠Evidenceを保持する。digestは再帰的にobjectキーを整列したJSONのUTF-8をSHA-256にした小文字hex。配列順は保持する。digestや操作documentだけでは外部writerの本人承認・署名を証明しない。

readerは全取得documentを検証し、1 Profile・1 bootstrap・単一の連結履歴であること、更新元内容、操作の再生結果を照合する。同ID同内容は重複観測として扱い、同ID別内容、複数開始記録、分岐、欠落、改変、未接続・循環は停止する。日時や最大revisionで勝者を選ばない。SAFの遅延表示によって世界で唯一の最新を保証する契約ではない。

History読取は100ファイル・20サブフォルダ・1ファイル1 MB・合計5 MB、ディレクトリ走査2000件が上限。1ファイルでも読取・検証に失敗すれば全履歴の更新を停止し、最後の有効な読取専用キャッシュを保持する。元ファイルを変更しない。履歴未移行のDriveだけ、旧snapshotを読取専用で検証できる。一度履歴を検証した接続元では、履歴が消えてもsnapshotへ戻らない。この状態と最終record ID・record全体のSHA-256はcache storage v3へ保存し、再起動後も保持する。旧cache v1/v2は読めるが、v3を検証した後はdigestなしへ戻さない。以前に検証したrecord IDが新しい取得履歴から消えた場合や、そのrecordの結果Profile・record全体のdigestが以前と異なる場合は更新を拒否する。好みの値が同じでも根拠の説明だけを変えた履歴を拒否する。

Schema・ドメイン検証を通ったProfileだけを接続元とともに`cooking-profile-cache-v1.json`へ保存する。Profile ID変更、revision巻戻り、更新日時巻戻り、同revision別内容・別record IDは拒否する。端末内の承認履歴と独立し、読込だけでローカル候補を承認・変更しない。接続先が変われば別接続のキャッシュを表示しない。

「Driveの評価を読み込む」は`Feedback/YYYY`の`.json`ファイルだけを読み、envelopeと内部Feedback v2の契約を検証して端末内Evidenceへ追加する。1回100ファイル、最大20年分、1ファイル1 MB、合計5 MBを上限とする。取得一覧の上限超過・権限失効は今回の一覧取得を停止し、ファイル単位の読込・parse・Schema・ID競合は該当ファイルだけ拒否する。元ファイルの削除・移動・上書き、ファイル名からのID推測、本文の補完をしない。UTF-8不正も拒否する。再読込は同じID・内容なら追加せず、同じCook Sessionの別Feedbackでも重複加点しない。Profileや承認履歴は自動更新しない。


### 承認したProfile変更のDrive追記

「Driveの好みの保存を始める」は確認した旧Drive Profileをbootstrapとして保持する。旧snapshotがない場合は新ID・revision 1の空Profileで開始する。既存の端末Profileを異なるDrive Profileへ丸ごと移植しない。直前のlegacy snapshotが確認画面の内容と違う場合や、別bootstrapが見える場合は停止する。旧snapshotを上書き・削除しない。

登録済みPreferenceの「Driveへ反映」はscope・現在値・変更後を確認してから実行する。接続元、確認したhead ID・内容、現在の端末登録値を照合する。明示登録は本人の説明と方向、候補承認は元のEvidenceを使ってremote履歴の過去承認を含め再集計する。remote headから新operationを生成し、Profile IDを保ってrevisionを増やす。同じ支持Sessionを重ねて再承認・二重適用しない。

`profile-write-v1.json`に接続元と送信recordを先にflushして保持する。送信結果が不明なら同じID・同じ内容で再確認し、新IDを発行し直さない。別の更新・別接続先への送信は確認待ち記録がある間停止する。providerへの追記後に全履歴を再読取・検証し、recordが見えることを確認してキャッシュを保存した後、送信記録を完了状態へ更新する。破損primaryやtmpだけの記録は初期化しない。

native adapterはハッシュ化したIDでfolder/fileを作成し、同名既存の同内容は保存済み、異内容は停止する。新規documentの名前・ID、書込後の内容を確認する。新規作成と送信前の再読取は原子的なCASではなく、同時更新が起きれば両方を保持して検出・停止する。遅延表示やクラウド同期を完了保証にしない。分岐・不完全ファイルの解決UI、Workのwriter、配布snapshot再生成は後続タスク。

親record全体のdigestを各updateへ保持し、headのrecord digestを端末に固定する。途中の古いEvidenceだけを書き換えた場合も、次recordのparent digestまたは検証済みhead digestで拒否する。このHistory Schemaは今回の未公開・未インストール実装で追加したもので、既存の端末Recipe / Feedback / Profile 1.0データの形式は変えない。
