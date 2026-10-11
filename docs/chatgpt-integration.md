# ChatGPT連携仕様

## 1. 目的

ChatGPTはレシピ内容の生成・改善を担当し、Recipe Cooking Navigatorは表示・進行・記録・Version管理・共有を担当する。

両者の責務を分離し、アプリが自由文を解析して意味を推測することを避ける。

## 2. Machine-to-machine first

ChatGPTとアプリの往復データは、途中で人間が読むことを前提にしない。

- ChatGPT → App: Recipe JSON
- App → ChatGPT: Feedback JSON

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

回答はホームの「レシピを貼り付け」、共有受信、ファイル選択から同じRecipeValidatorとprepare/confirmへ合流する。キャンセル・不正入力では保存しない。公開mainは2026-10-11時点でv1、手元consumerはv2のため送信は標準で無効。v2 Schema・例・Router・Workflow・連携仕様の整合公開と確認後だけ`--dart-define=RCN_PUBLIC_AI_V2_READY=true`で有効化する。このフラグは公開済みとの自動判定ではない。端末QA・一般公開・main mergeは別ゲート。

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
