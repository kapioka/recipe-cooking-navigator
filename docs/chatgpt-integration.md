# ChatGPT連携仕様

## 1. 目的

ChatGPTはレシピ内容の生成・改善を担当し、Recipe Cooking Navigatorは表示・進行・記録・Version管理・共有を担当する。

両者の責務を分離し、アプリが自由文を解析して意味を推測することを避ける。

## 2. Machine-to-machine first

ChatGPTとアプリの往復データは、途中で人間が読むことを前提にしない。

- ChatGPT → App: Recipe JSON
- App → ChatGPT: 調理結果を使う改善はFeedback JSON、評価なしの調整・再作成と単体共有は選択VersionのRecipe JSON

人間向けMarkdown、説明文、補足文章を機械payloadへ混在させない。回答の取り込みではJSON全体を基本とし、明確な外側の`json`コードフェンス1つだけはtransport wrapperとして除去してから同じValidatorへ渡す。前後の説明文・複数候補・自由文からの推測抽出は拒否する。

ユーザー向けUIでは`JSON`を前面に出さず、「ChatGPTレシピを取り込む」「ChatGPTで改善」等の表現を使う。

## 3. ChatGPT → App

ChatGPTは`type: "recipe"`のRecipe JSONだけを生成する。

アプリ側は受信後にRecipe Schema v2で構造と参照・人数・単位を検証する。v1は推測変換せず、新しい指示文による再作成を案内する。

### Android MVP受信フロー

1. ChatGPTでRecipe JSONを生成
2. Android Sharesheetまたはファイル経由でRecipe Cooking Navigatorへ渡す
3. アプリがJSONとしてparse
4. `schema_version`と`type`を確認
5. JSON Schema検証
6. 合格した内容をプレビューし、ユーザーが確認した場合のみ保存
7. 同一Recipe IDがあれば新Revisionとして追加
8. 新Recipeまたは追加Versionをレシピ詳細へ表示

不正JSONや未知Schemaは推測補完しない。

### Issue #7: 標準共有・コピーによる生成/改善

ホームの「ChatGPTでレシピを作る」で食材・人数・時間・器具・味・追加希望を入力し、送信文を確認する。アプリは公開`ai/AGENTS.md`のURLと対応Schema版、取得失敗時の停止条件だけを付け、仕様全文を取得・キャッシュしない。

「ChatGPTへ共有」はAndroidの標準ACTION_SENDを開く。「依頼文をコピーしてChatGPTを開く」はClipboardへの明示コピー後に公開`https://chatgpt.com/`を開く。起動できなくてもコピーを保持し手動起動を案内する。非公開deep link、事前入力の保証、自動投稿は使わない。Profile・全Recipe履歴は渡さない。

改善は既存の評価画面でCook Session・改善元Version・目標を明示選択し、「選択した評価でChatGPTに改善を依頼」から検証済みFeedbackだけを依頼文へ添付する。従来の「Feedbackを共有」は従来どおりJSONのみを送る。

回答はホームの「レシピを貼り付け」、共有受信、ファイル選択から同じRecipeValidatorとprepare/confirmへ合流する。キャンセル・不正入力では保存しない。2026-10-11にv2 Schema・例・Router・Workflow・連携仕様をmainへ整合反映した。送信は標準で無効にし、`tool/validate-public-ai.ps1`で公開内容と対応アプリの一致を確認した場合だけ、`tool/build-release.ps1 -PublicAiV2Ready`から`--dart-define=RCN_PUBLIC_AI_V2_READY=true`で有効化する。このフラグは公開済みとの自動判定ではない。端末QA・一般公開・main mergeは別ゲート。

### iOS将来対応

iPhone版でも同一Recipe Schemaを使い、iOS固有の受け渡し方式だけをplatform layerで実装する。Recipe document自体はAndroid/iOSで変更しない。

## 4. App → ChatGPT

調理後にユーザーが改善を希望する場合、アプリは`type: "recipe_feedback"`のFeedback JSONを生成する。

Feedback JSONには最低限次を含める。

- 改善対象としてユーザーが選択したRecipe Revisionのsnapshot
- Cook Session
- Evaluation
- 次回希望
- Revision依頼条件
- 実際に調理したRecipe snapshot、選択人数、アプリが提示した正確な分量

Android MVPではSharesheetからChatGPTへ共有する。MVPではOpenAI APIを直接呼ばない。
共有時は検証済みFeedback v2をJSON文字列として`ACTION_SEND`のテキストに載せる。説明文やMarkdownをpayloadへ足さず、共有先への送信はユーザーが選ぶ。

### 4.1 評価なしのレシピ共有・相談・調整

調理記録・評価を必要とせず、選択Versionの検証済みRecipe v2 JSONをそのままコピーまたは共有する。Recipeの基準人数と分量を維持し、画面の人数換算値やCook Session、Evaluation、一言メモ、Preference、他Recipeの履歴を混ぜない。共有だけで保存データを更新しない。

「ChatGPTで調整」では同じRecipe JSONに、ユーザーが確認できる選択Version・任意の変更希望・新Revisionの番号指定を含む依頼文を添える。JSON自体へ説明や独自フィールドを足さない。新Revision番号はアプリが知る同Recipeの最大revision + 1、parent_revisionは選択Versionとする。過去Versionをベースにする場合も、選択版 + 1と決めつけない。

変更希望が空欄なら、まず相談用のレシピとして受け取り、ユーザーが変更内容を指定するまで新Revisionを生成しない。希望があれば、無関係な味付け・良好部分を維持し、完成Recipe JSONだけを返す。調理実績・評価・恒久的な好みを推測しない。Recipe単体をrecipe_feedbackと誤認せず、評価を仮入力してFeedbackを作らない。

この依頼文は、利用中のChatGPT Project等へ用意された対応Schemaと連携仕様を使う経路であり、公開`ai/AGENTS.md`を取得する経路へ依存しない。対応仕様を取得・解釈できない場合は不足を説明し、準拠したRecipe JSONを推測生成しない。Recipe単体のコピー・共有は、AI連携の公開状態に依存しない。

## 5. 任意Versionからの再改善

改善元は常に最新Versionとは限らない。

例:

```text
Version 2 ← 好み
  ├─ Version 3 ← 最新だが好みではない
  └─ Version 4 ← Version 2を再調整
```

ユーザーがVersion 2を選んで「このバージョンをChatGPTで調整」を実行した場合、Feedback JSONにはVersion 2のsnapshotを入れる。

AndroidではVersion履歴の各Versionから「このVersionをChatGPTで調整」で評価画面を開き、そのVersionを改善元として初期選択する。評価対象のCook Sessionを切り替えても、明示的に選んだ改善元Versionは維持する。active Versionはこの操作では変更しない。

ChatGPTは新Revisionを作成し、`parent_revision`に改善元Revisionを設定する。

## 6. Recipe生成時のChatGPT責務

ChatGPT Project側では次を保証する。

- 基準人数と、料理上対応できる人数範囲を指定する
- 材料名と用途別amountを分離し、同じ物理量を一度だけ定義する
- measured量を正の有理数とし、`linear` / `fixed`を明示する。定性的な量を数値化しない
- 人数で変わる量をRecipeTextの`{"type":"amount_ref","amount_id":"..."}`で参照し、自由文へ重複記載しない
- 全体工程を詳細Stepとは別に生成する
- 事前準備を独立タスクとして生成する
- 各Stepの`amount_ids`で、そのStepに必要な材料と分量を再掲できるようにする
- 火加減、時間、完了判断を必要に応じて生成する
- 器具の使い回しを安全性の範囲で考慮する
- 安全な並行作業だけを生成する
- 次工程予告を必要に応じて生成する
- AI想定難易度1〜5と理由を付ける
- Schemaに存在しない独自フィールドを勝手に追加しない
- 出力payloadに人間向け前置き・後書き・Markdownを混ぜない

### 計量しやすい単位の選択（新規生成・Revision生成共通）

- ユーザーが計量方法を指定した場合は、その指定を優先する。指定がなければ、日本の家庭用計量スプーンで量りやすい単位を選ぶ。
- 醤油・みりん・酒・酢・油・ソース類、および少量の砂糖・塩・顆粒だし・香辛料・粉類は、原則として大さじ・小さじを優先する。Schemaの `unit` は大さじを `tbsp`、小さじを `tsp` とし、日本語の単位名をJSONの `unit` に入れない。
- 大さじ1は15ml、小さじ1は5mlの体積として扱う。粉類はすり切りを基準とする。gからの換算には材料・製品ごとの重量根拠が必要であり、「大さじ1 = 15g」等の一律換算や、根拠のない密度の推測をしない。換算根拠がない既存の重量指定はgのまま保つ。
- 基準人数では、可能な範囲で整数・1/2・1/4など量りやすい杯数を選び、端数は既存の有理数で表す。例: 大さじ1と1/2は `value: {"numerator": 3, "denominator": 2}, unit: "tbsp"`。表記を簡単にするためだけに、指定量・味の設計・食品安全に必要な比率を勝手に丸めない。
- 肉・野菜・バター等はg・個・枚など、大量の水・だし汁や計量カップで量る方が扱いやすい量はml・Lを使う（Schemaでは `ml`・`l`）。重量管理が必要な調理や、スプーンでは正確に量りにくい微量もg等を維持する。すべての材料をスプーンへ統一しない。
- 「少々」「適量」は本当に定性的な量に限り、既存の `qualitative` 契約を使う。数値指定が必要な塩分や調味料を、計量の手間を省くために曖昧化しない。
- 材料一覧・事前準備・各Stepでは同じ `amount` と `amount_ref` を使い、別単位の換算値を自由文へ重複記載しない。人数変更後の量はアプリの既存の有理数計算に委ね、基準人数の杯数を工程文へ固定しない。
- 構造例や改善元snapshotの単位を新しい生成の既定値とはみなさない。Revisionでも上記方針を使うが、単位の都合だけで元の物理量や良好な味を変えない。

### 6.1 下準備の具体性（新規生成・改善共通）

加熱前に必要な下処理は、材料一覧や調理Stepの中だけに書かず、`preparation`へ独立したチェック項目として含める。各項目は対象の`amount_ids`と`amount_ref`を使い、下準備画面だけで作業できる内容にする。

- 肉は部位・形状と料理に合う切り方、大きさをcmで示す。「一口大」「食べやすく」だけで済ませず、例えば「大きい豚こま肉は約3cm幅に切る」「鶏もも肉は約3cm角に切る」と書く。厚みが加熱判断に関わる場合は厚みも示す。すでに切られた肉やひき肉には不要な切断を指示せず、必要なら「切らずに使う」と書く。
- 玉ねぎ等の野菜は、料理に合う切り方の名前（薄切り、半月切り、いちょう切り、短冊切り、千切り、乱切り、みじん切り等）と寸法を組み合わせる。薄切り・半月切り等は厚さ約何mm、千切り・短冊切り等は幅・長さ、乱切り・角切り等は約何cm、みじん切りは粒の大きさを示す。必要なら皮・芯の除去や繊維に沿う／断つ方向も書く。切り方や寸法は料理ごとに決め、全食材を同じ大きさにしない。
- 生姜・にんにくをチューブで使う場合は、チューブであることを材料名に明記し、重さgと絞り出す長さ約何cmを下準備に併記する。生の食材を使う場合は、すりおろし・みじん切り等の必要な下処理を示し、チューブへ無条件に置き換えない。
- チューブの重量は`amounts.quantity`の`measured` / `g`を正本とし、下準備では`amount_ref`で参照する。長さは根拠のある目安を使い、通常の`text`に「約4cm・基準2人分」のように短く添える。cm用の別amountは作らない。
- 製品差や人数変更時の量り方は、作業文に繰り返さず`adjustments`へ一度だけ置く。例: `condition`「チューブの長さ」、`action`「長さは製品で異なる目安。人数を変えたら表示gで量る。」。換算式や出典の解説を下準備へ入れない。切る寸法は人数で変えない。
- 出力前に、使う食材の下処理とチューブ量が下準備から抜けていないか確認する。改善Recipeでも同じ基準を適用し、問題と無関係な味付けや良好な工程は維持する。

表記例（チューブにんにく）: `amount_ref`に続けて「を量る（約4cm・基準2人分）。」とし、画面では「にんにく（チューブ）2gを量る（約4cm・基準2人分）。」と表示する。この例の換算根拠はS&Bの[にんにく約10cm＝小さじ1](https://www.sbfoods.co.jp/customer/detail/00332.html)と[小さじ1＝5g](https://www.sbfoods.co.jp/customer/faq/quantity.html)。他製品や生姜へ一律適用しない。根拠の確認は生成側で行い、説明を作業文へ転記しない。

アプリは文章の料理上の十分性を機械判定せず、不足を推測補完したり、既存Recipeの取り込みを新たに拒否したりしない。保存済みRecipeを直す場合は新Revisionを生成し、元Revisionを保持する。

### 6.2 作業文とコツ・失敗対策を分ける（新規生成・改善共通）

- `preparation.text`と`steps.instruction`は、今する動作が分かる短い文にする。1項目1作業を基本に、連続する動作は1〜2文にまとめる。切り方・寸法・必要な分量は省かない。
- 火加減は`heat`、仕上がりは`done_when`へ短く分け、本文へ同じ説明を重ねない。加熱・衛生など、その場で守る必要のある安全な操作と判断は作業文・完了判断に残す。
- 失敗を防ぐコツ、理由、うまくいかなかった場合の対処は既存の`adjustments`へ分ける。`condition`に「肉を焼くとき」などの場面、`action`に対策を1〜2文で書く。必要なものに絞り、同じ注意を各工程へ繰り返さない。専用の独自フィールドは追加しない。
- 例: 作業文「肉を広げて焼き、裏返す。」／`heat`「中火」／`done_when`「肉の中心まで火が通る。」／コツの`condition`「肉が重なるとき」、`action`「2回に分けて焼くと、水っぽくなりにくい。」。
- 長い括弧書き、換算の解説、一般的な免責文で作業文を膨らませない。既存Revisionの文量が多い場合も、新Revisionではこの分離を適用する。

## 7. Revision生成時のChatGPT責務

Feedback JSONを受け取った場合、ChatGPTは元Recipe snapshotを基準にRevisionを作る。

原則:

1. ユーザーが明示した問題を優先する
2. `changes_made`で実際に有効だった変更を考慮する
3. `next_time_intent`を直接的な改善要求として扱う
4. 一言メモを補助Evidenceとして考慮する
5. 問題と直接関係しない良好な部分は不必要に変更しない
6. 食品安全上必要な変更は例外として優先する
7. Recipe IDは維持する
8. 新しいRecipe revisionを作る
9. `parent_revision`は改善元Revisionを指す
10. Schema versionはSchema変更時以外増やさない
11. 出力はRecipe JSONだけにする
12. 改善元snapshotと実調理snapshot、基準人数と選択人数、提示量と実変更を混同しない
13. 新Revision番号は`revision_request.next_revision`を使い、`parent_revision`は改善元を指す

## 8. 単発評価と嗜好の区別

Feedbackに、ある料理で「甘味 +1」と記録されていても、ユーザーが全料理で甘さ控えめを好むとは断定しない。

個別Cook Sessionから導けるのは、原則としてそのRecipe Revisionの改善だけ。

将来Preference Profileを使う場合は、複数回・複数料理のEvidenceを別途評価する。

## 9. 推奨Revision処理契約

```text
このFeedback documentに含まれる改善元Recipeと実調理評価を使い、
次回希望と実際に有効だった変更を優先してRecipeを改善する。

良かった部分を不必要に変更しない。
食品安全を損なう変更は採用しない。
Recipe IDを維持する。
新しいrevisionを作り、parent_revisionには改善元revisionを設定する。
出力は対応Recipe Schemaに適合するRecipe JSONだけにする。
```

実際のProject Instructionsは別リポジトリ`kapioka/ai-prompt-library`で公開する想定。

Recipe / Feedback Schemaの正本はこのリポジトリとする。

## 10. Error / fallback

### ChatGPT出力がSchema不適合

アプリは読み込まず、エラー理由を表示する。

MVPではアプリ側で自由文から自動修復しない。

ユーザーは元データをChatGPTへ戻し、Schema適合版の再出力を依頼できる。

### 未対応Schema version

読み込みを停止し、対応アプリ版が必要であることを表示する。

### Feedback共有先にChatGPTがない

OSの共有機能で他のテキスト受信アプリへ送れること自体は妨げない。特定アプリへの強制依存を作らない。

## 11. SNS共有との分離

ChatGPT連携用JSONとSNS投稿用文章は別の成果物とする。

SNS共有時はアプリが人間向け投稿文を生成し、ユーザーが確認・編集してからOSの共有機能へ渡す。

SNS投稿文へ含められる候補:

- 料理名
- アプリを使ったこと
- 総合評価
- 実難易度
- 味評価 / 好み
- 公開用一言メモ
- ユーザーが自分で取得・入力したレシピURL

アプリはそのURLを生成、ホスト、検証、維持しない。

## 12. Security / privacy

- APIキーをRecipe JSONへ含めない
- アカウントIDや認証情報をFeedbackへ含めない
- 端末ローカルパスを共有文書へ含めない
- Android/iOS固有のローカルURIを共有Schemaへ含めない
- Cook history全体を自動送信しない
- ユーザーが改善を依頼した対象Sessionに必要な情報だけ共有する
- 自分用一言メモをSNSへ自動公開しない

## 13. 将来のAPI連携

OpenAI API直接統合はAndroid MVP外。

将来導入する場合も、現在のRecipe / Feedback JSON契約を維持し、UIや保存モデルをAPI固有仕様へ直接結合しないことを優先する。

## 14. Google Drive Recipe Inbox

現在のAndroid実装では、`Work → Google Drive Inbox → アプリ`の一方向受信を提供する。

`Work`は、ChatGPT等で作成したRecipe JSONをGoogle Driveの`Recipe Cooking Navigator/Inbox`へ配置する上流側作業の総称とする。特定のAI API、会話履歴、GoogleアカウントIDをRecipe JSONへ追加しない。

受け渡し契約:

1. Work側は、1レシピにつき1つのRecipe JSONファイルをInbox直下へ配置する
2. ユーザーがアプリで`新しいレシピを確認`を実行する
3. アプリは各`.json`ファイルを独立してparse・Schema検証する
4. 正常な新規Recipe / Revisionを端末内へ保存し、同一内容はスキップ、同一Recipe ID・revisionの内容違いは拒否する
5. アプリは取込結果を表示し、Inbox内のファイル自体は変更しない

あるファイルが不正でも他の正常ファイルは処理する。不正データを推測補完せず、不正ファイルを取込済みとして記録しない。

Android側は、選択先がGoogle DriveのDocumentsProviderかつ`Inbox`フォルダであることを検証する。Inbox走査は30秒、100ファイル、1ファイル1 MB、合計5 MBを上限とし、上限超過や不正なSHA-256 metadataを個別ファイルの拒否として扱う。Inbox確認中も既存の単一ファイル取込を利用できる状態に保つ。

初期実装でアプリからInboxへRecipeや状態を書き戻さない。Evaluation、Feedback JSON生成、Feedback Outbox、Work側への返却は後続の実装単位とし、Recipe Inboxへ混在させない。

WorkやInboxが利用できない場合も、既存の`ChatGPTレシピを取り込む`単一ファイル取込をバックアップ導線として使用できるようにする。この経路はGoogle Drive接続やInbox取込記録へ依存せず、ユーザーが明示的にファイルを選択した場合だけ動作する。受信経路が異なってもRecipe JSON契約、Schema検証、重複・競合規則は変えない。

Google Driveは受け渡し経路であり、Recipeのホスティング、リアルタイム同期、バックアップの正本として扱わない。Androidのシステムフォルダ選択を利用し、Google Drive API、独自OAuth、スプレッドシート、SQLデータベースは導入しない。

## 15. Drive Feedback Evidence / Cooking Profile

Phase 8では、ユーザーが調理後の評価を「好みの記録に残す」で蓄積し、「料理の好み」画面から明示操作でDriveの`Recipe Cooking Navigator/Feedback/YYYY`へ追記できる。評価や一言メモを含むため、保存前に内容範囲を表示して確認する。Driveが使えない場合も端末内記録と個別FeedbackのSharesheet共有を利用できる。

Drive保存ファイルは`feedback-evidence-v1.schema.json`に適合するenvelopeであり、Recipe改善の機械受け渡しには内部の`feedback`（Feedback v2）を使う。envelope自体をFeedback v2と誤認しない。カテゴリ・確認済み方向はユーザー入力であり、Workが自由文から補完したり元ファイルを変更したりしない。Feedback IDによる重複判定と候補集計の規則は[データモデル](data-model.md#28-feedback-evidence--cooking-profilephase-8のローカル基盤)に従う。

アプリの「Driveの評価を読み込む」は明示操作でEvidenceを端末へ追加し、元ファイルを変えず候補を再集計する。不正・未対応・内容競合は個別に表示し、正常な他ファイルは処理する。同じEvidenceを読み直しても件数・scoreを重複加算しない。読込だけでProfileを承認・変更しない。

Workが将来Profileを読む場合はSchemaとtype/versionを検証し、Recipe生成へ使えるのはユーザー承認済みの`preferences`と明示的な`explicit_constraints`のみ。`preference_candidates`の`proposed`・`rejected`を確定した好みとして扱わず、限定scopeをglobalへ拡張しない。Profileは医療・アレルギー判断や食品安全の保証を代替しない。

現時点のアプリは候補の承認・却下と明示Preference登録の操作履歴を端末内に保存する。「Driveの好みを確認する」は`Profile/History`を正本として連結・digest・操作を検証し、読取専用キャッシュへ保持する。履歴未移行の接続元だけ旧`Profile/cooking-profile.json`も読める。一度履歴を検証した接続元ではsnapshotへ戻らない。読込だけで端末内の承認履歴を置き換えない。アプリのDrive履歴追記は承認済み変更だけを対象に実装した。分岐・更新元変更・送信不明時は停止または同じIDで再確認する。Workによる承認済み更新の書戻しとprovider実機確認は未実施。Recipe / FeedbackのProject Instructionsをこの段階で再変更する必要はない。


### Profile履歴を正本とするWork契約

2026-10-04のユーザー判断で、`Profile/cooking-profile.json`は配布用の派生snapshotへ変更した。WorkはHistoryの全取得記録を検証して得た単一headだけを確定Profileとして扱う。分岐・欠落・未知Schema・改変・読取失敗がある場合、日時や最大revisionから勝者を選ばず更新とProfileの新規利用を停止する。必要な契約は[data-model](data-model.md#28-feedback-evidence--cooking-profilephase-8のローカル基盤)と`profile-history-v1.schema.json`。

未承認Candidateを確定好みとしない。`explicit_user`は本人が指定した説明と方向であり、集計scoreや架空Feedbackを作らない。Recipe / Feedback v2の受け渡し形式は変更しない。History / Operationは保存契約であり、Recipe / Feedbackの代わりにアプリへ送らない。

アプリのHistory追記・移行・再送確認は実装した。Workの実運用reader・承認済みwriter接続と互換snapshot再生成は未実装。旧snapshotだけを読む既存運用を、新契約対応済みとは扱わない。Workの後続実装では、検証済みremote headをbaseにして本人が承認した操作のみ追記し、異なるローカルProfile IDを丸ごと移植しない。


### Work向けread-only検証入口

ローカルの`tool/validate_profile_history.dart`は、Historyディレクトリ全体または取得した全recordのJSON配列を入力として、アプリと同じSchema・ドメイン・連結検証を行う。成功時は唯一の観測headのProfile JSONだけをstdoutへ出す。失敗時はProfileを出さずexit 2、理由をstderrへ出す。元ファイルとDriveを変更しない。

```powershell
dart run --verbosity=error tool/validate_profile_history.dart examples/profile-history-explicit-example.json
# 実際のHistory全体を取得した場合:
dart run --verbosity=error tool/validate_profile_history.dart '<取得したHistoryフォルダ>'
```

ディレクトリ入力は最大20のProfileサブフォルダ、100 JSONファイル、1ファイル1 MB、合計5 MB。record配列は最大100件・5 MBで、各recordも1 MB以下。symlink、UTF-8不正、同名ID別内容、分岐、更新元欠落、改変、未知Schemaを拒否する。ローカルの部分コピーをDrive全体の取得済み証拠とは扱わない。この入口はWorkの実際のDrive取得や書込adapterではなく、その後の検証入口。

Workの運用ではexit 0と出力JSONのProfile Schema適合を確認し、成功したProfileのscopeと本人の明示制約だけをRecipe生成へ使う。Candidateや未確定の更新を好みへ加えない。recipe scopeは同Recipe、category scopeは対象が本人の指定カテゴリへ該当する場合だけ使い、globalへ拡大しない。適用される好み同士が矛盾する場合は、この段階でscopeの優先順位を捏造せず、その生成タスクで本人へ確認する。医療・宗教・食品安全の制約を味の方向から推測しない。
