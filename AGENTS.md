# AGENTS.md

このファイルは、Codexなどのコーディングエージェントが`kapioka/recipe-cooking-navigator`で安全かつ一貫して作業するためのリポジトリ共通指示です。

## 1. Project goal

Recipe Cooking Navigatorは、ChatGPTなどが生成した構造化レシピをスマートフォンへ取り込み、調理前の全体把握、調理中のナビゲーション、音声操作・読み上げ、調理後の評価、Recipe Revisionの改善循環を支援するローカル主体のアプリです。

当面の実装対象はAndroidです。Android版が完成・安定した後に、Mac購入を含めてiPhone版へ進むか判断します。ただし、OS非依存で済むRecipe / Feedback / Version / EvaluationロジックへAndroid固有仕様を直接埋め込まないでください。

## 2. Source of Truth

Source of Truthは用途ごとに分ける。Issue、PR、commit、Releaseの履歴を「現在状態」の正本として扱わない。

### 製品仕様・意味の正本

実装前に、今回のタスクに関係する範囲だけ次を参照する。

優先順位:

1. ユーザーの今回の明示指示
2. `AGENTS.md`
3. `docs/product-spec.md`
4. `docs/data-model.md`
5. `docs/chatgpt-integration.md`
6. `docs/platform-strategy.md`
7. `docs/roadmap.md`
8. `schemas/*.schema.json`
9. `examples/`
10. `README.md`

Schemaの構造・意味については`schemas/*.schema.json`を正本とする。文書とSchemaが食い違う場合は、勝手にどちらかへ合わせず不一致を報告する。

### 現在の実装状態の正本

現在何が実装済みか、次に何を進められるかを判断するときは次を優先する。

1. 現在のworking branch / `main`のソース、既存tests、build結果
2. `docs/roadmap.md`のCurrent-state contractと現在のcheck状態
3. 現在進行中のPRがある場合はその差分
4. Issue、過去PR、commit、Releaseは判断理由や過去証拠が必要な場合だけ参照する

`docs/roadmap.md`の`Last reconciled main`と現在の`main` HEADが一致する場合、現在地確認のために古いIssueや完了済みPRを読み直さない。

一致しない場合もrepository全体や全履歴を読み直さず、marker以降のcommit / diffと関係するtestsだけを確認し、roadmapの現在状態を先に再同期してから次の作業を選ぶ。

### Resume fast path

新しいCodex sessionや「続きをして」から再開するときは原則として次だけを見る。

1. 適用範囲の`AGENTS.md`
2. `git status`、現在branch、`main` HEAD
3. `docs/roadmap.md`のCurrent-state contractと今回関係する未達Outcome
4. そのOutcomeに関係するコード、tests、仕様
5. 過去判断の理由が不足する場合だけIssue / PR / commit履歴

「古いIssueの最初の未完了項目」から機械的に再開しない。

## 3. Current implementation status

実装状態は変動するため、このファイルへ細かな進捗や「次の実装単位」を重複して固定しない。現在状態は前節のResume fast pathと`docs/roadmap.md`で確認する。

実装技術はFlutter。当面はAndroidを実装し、OS非依存のドメインロジックとAndroid固有連携を分離する。iOS UIやiOS固有機能は明示的な将来タスクまで追加しない。

リポジトリ直下で使用する基本コマンド:

- format確認: `dart format --output=none --set-exit-if-changed lib test`
- static analysis / lint: `pwsh -File .\\tool\\flutterw.ps1 analyze`
- unit / widget tests: `pwsh -File .\\tool\\flutterw.ps1 test`
- Android debug build: `pwsh -File .\\tool\\flutterw.ps1 build apk --debug`

Windowsでは親パス`E:\\作ってみた`の非ASCII文字をAndroid Gradle Pluginが拒否するため、Flutterコマンドは`tool/flutterw.ps1`を介して実行する。wrapperは実行中だけ同じrepositoryをASCIIドライブへ割り当て、終了時に解除する。ソースは複製しない。

新しい検証ツールやコマンドを追加する場合は、実際に導入・実行できることを確認してからこのファイルへ追記する。

## 4. Core product invariants

次は明示的な仕様変更タスクでない限り維持してください。

- ChatGPT -> AppはRecipe JSONのみを機械受け渡しに使う。
- App -> ChatGPTはFeedback JSONのみを機械受け渡しに使う。
- 機械受け渡しJSONへ人間向けMarkdownや説明文を混ぜない。
- UIでは`JSON`を主要なユーザー向け名称として使わず、`ChatGPTレシピを取り込む`等の理解しやすい表現を優先する。
- 不正JSON、必須項目欠落、未対応Schemaを推測補完しない。fail-closedを基本とする。
- Schema versionと個別Recipe revisionを混同しない。
- Recipe revisionを上書き削除せず履歴として保持する。
- `latest`と`active`は別概念として扱う。
- 過去Revisionを`active`へ戻せる設計を維持する。
- 過去Revisionをベースに再度ChatGPTへ改善依頼できる。
- `parent_revision`でどのRevisionから派生したかを保持する。
- Cook Session、Evaluation、一言メモをRecipe本体へ上書きしない。
- AI想定難易度とユーザー実難易度を分離する。
- 味評価は本人の理想を0とする`-2..+2`の偏差として扱う。
- 一度のEvaluationだけで恒久的なPreference Profileを断定しない。
- タイマーはユーザー起動とし、終了しても自動で次Stepへ進めない。
- Cooking mode中のみ必要に応じて画面常時点灯を有効化し、終了時に解除する。
- アプリの起動、foreground復帰、利用、終了によって端末の画面回転設定を変更しない。Androidでは起動前、起動中、終了後の`accelerometer_rotation`と`user_rotation`が同一であることを必須とする。
- 音声操作と現在StepのTTS読み上げはAndroid MVPの必須機能である。
- 調理効率より食品安全を優先する。

## 5. Platform boundaries

### Android now

当面はAndroidのみ実装・検証します。

Android固有コードとして隔離してよい例:

- Sharesheet受信 / 送信
- Android URI / permission
- ファイル選択
- 画面常時点灯API
- Android音声認識
- Android TTS
- Android通知 / タイマー連携

### iOS later

現時点では次を実装しません。

- iOS UI
- IPA配布
- App Store対応
- Apple Developer Program前提の処理
- iOS固有CI

ただし、Recipe / Feedback / Version / Cook Session / Evaluationなどのドメインロジックは将来iOSでも再利用できる境界を維持してください。

## 6. MVP scope

Android MVPは`docs/roadmap.md`のPhase 1〜2を中心に進めます。

特に重要:

- ホームはレシピ一覧を基本とする。
- `ChatGPTレシピを取り込む`導線を分かりやすく配置する。
- 調理前に材料、全体工程、器具、事前準備を確認できる。
- Cooking modeでは1Stepごとに、そのStepで使う材料名と分量を再掲する。
- 火加減、完了判断、次工程予告を必要に応じて表示する。
- 音声で`次`、`戻る`、`材料`、`全体工程`、`調理画面`、`タイマー開始`、`タイマー停止`、`残り時間`、`読んで/もう一度`を扱えることを目標とする。
- TTSでは現在Stepを読み上げられること。
- 調理後にCook Session / Evaluation / 一言メモを保存できる。
- Feedback JSONを生成し、ユーザー操作でChatGPTへ共有できる。

## 7. Explicit non-goals

実利用で必要性が確認されるまで、次を追加しないでください。

- 専用バックエンド
- ユーザーアカウント
- アプリ内SNS
- フォロー / コメント / ランキング
- サブスクリプション
- 専用レシピホスティング
- 公開URL発行
- URLの有効性 / 生存確認
- URL永続性保証
- リアルタイムクラウド同期
- 買い物リスト
- 栄養管理
- スーパー在庫 / 価格取得
- カメラ常時監視
- 複雑なAgent構成
- 大規模推薦基盤
- OpenAI API直接統合

将来のバックアップは、専用クラウド同期より先にファイルexport / importを検討します。保存先、公開設定、アクセス権、URL維持はユーザーと外部サービスの責任です。

## 8. External sharing boundary

外部SNS向け共有素材の生成は予定していますが、Recipe Cooking Navigator自体はSNSサービスやホスティングサービスになりません。

アプリが将来生成してよいもの:

- 任意の料理写真
- 料理名
- Recipe Cooking Navigatorを使ったことの表示
- 総合評価
- 実難易度
- 味評価 / 好み
- ユーザーが公開用に選択・編集した一言
- ユーザー自身が入力した任意のRecipe URL
- SNS投稿前プレビュー

アプリが引き受けないもの:

- Recipeファイルのホスティング
- 公開URLの生成
- 保存先が公開可能かの自動判定
- 公開設定の管理
- URLの生存確認
- URLの永続性保証

## 9. Change discipline

タスク開始時に、今回のDesired end stateと変更範囲を短く確定してください。

### Outcome-first execution

将来改善では、細かな実装順を先に固定するより、今回達成するDesired end state、成功条件、守る境界、停止条件を先に明確にする。

- 対象と完成条件が明確なbounded taskは、通常の実装指示で直接進めてよい。
- `/plan`または同等の計画フェーズは、方式選択・migration・互換性・高リスク判断など、実装前の設計判断で結果が大きく変わる場合だけ使う。
- `/goal`または同等の持続Goalは、複数checkpointにまたがる1つのObjectiveを完了状態まで追跡する価値がある場合だけ使う。
- Plan / Goal / Loopを形式として毎回要求しない。必要性がなければ追加しない。
- Desired end stateと制約の範囲内で、実装順、work package、必要なtests、依存解決はCodexが現在のrepositoryから判断してよい。
- roadmapのPhase番号を厳密な実行順とは扱わない。依存関係がなく安全に進められるReady workは、前Phaseのmanual QA待ちだけを理由に停止しない。
- 実機、実料理、TalkBack、実音声環境、バッテリーなどでしか確認できない事項は、コードと機械検証が完了している場合は`User device/manual acceptance: pending`として残し、独立したReady workを続ける。
- 未確認の実機挙動を「正常」「検証済み」とは扱わない。


- 関係する既存仕様・コードを先に読む。
- 現在のタスクを満たす最小変更を優先する。
- `docs/roadmap.md`の将来項目を「ついでに」実装しない。
- 不要なarchitecture、dependency、service、abstractionを先回りして増やさない。
- 既存Schemaを実装都合だけで変更しない。
- Schema変更が必要なら、理由、互換性、migration、examples、関連docsへの影響を先に示す。
- ユーザーデータを破壊的に上書き・削除しない。
- 認証情報、APIキー、個人情報をrepositoryへcommitしない。
- 無関係なformat変更やリファクタを同じ変更へ混ぜない。

## 10. Git / branch policy

- `main`へ直接実装変更を入れない。
- feature branchで作業する。
- force pushや履歴破壊をしない。
- mainへのmergeはユーザーの明示承認がある場合だけ行う。
- 既存Draft PRが同じlogical operationを扱っている場合は、不要な重複PRを作らない。
- 変更前に対象ファイルの最新状態を確認し、競合がある場合は最新内容を再取得して差分を評価する。

## 11. Validation

変更リスクに応じて、実在する検証手段だけを使ってください。

実装技術決定前:

- JSON Schemaとexamplesの整合
- 文書間の責務・用語整合
- 参照pathの存在確認

実装開始後:

- formatter
- static analysis / lint
- unit tests
- 必要なwidget / UI tests
- build

通常Acceptanceはmachine-verifiableな証拠を優先する。実機でしか確認できない項目は、今回の変更自体にGUI操作が不可欠でない限り各work packageの進行条件にせず、manual/device acceptance backlogへ集約する。

同じsource / artifactに対して必須checkが合格済みで、新しい変更・失敗・懸念がない場合は同じ検証を反復しない。

フレームワーク導入後は、実際に使用するコマンドをこのファイルへ追記してください。

最低限の回帰ケース:

1. 正常なRecipeをimportできる。
2. 壊れたJSONを拒否する。
3. 未対応Schema versionを拒否する。
4. 同一Recipeの複数Revisionを失わず保持する。
5. `latest`と`active`を別々に扱える。
6. 過去Revisionをactiveへ戻せる。
7. 選択RevisionからFeedbackを生成できる。
8. タイマー終了で自動Step遷移しない。
9. Cooking mode終了時に画面常時点灯を解除する。
10. 音声操作 / TTS追加後は調理雑音下での誤認識リスクを実機確認する。
11. アプリ起動前、起動中、終了後で端末の自動回転設定と固定回転方向が変化しない。

## 12. Stop / ask conditions

次の場合は推測で大きな実装を進めず、未決事項として報告してください。

- 実装技術の選択がタスク成果を大きく左右するが指定がない。
- Schemaと製品仕様が意味上競合している。
- データmigrationなしでは既存データを壊す。
- 新しいバックエンド、アカウント、課金、外部契約が必要になる。
- iOS対応のためだけにAndroid MVPを大きく複雑化する必要がある。
- 食品安全と効率化要求が競合し、安全な選択肢を一意に決められない。

小さな不足で安全に進められる場合は合理的な仮定を置き、完了報告で明示してください。

## 13. Completion report

各Codexタスクの完了時は、少なくとも次を簡潔に報告してください。

- 実装した内容
- 変更した主要ファイル
- 実行した検証 / テストと結果
- 仕様上の仮定
- 未解決事項
- User device/manual acceptance pending
- 次に進める最小タスク

完了条件を満たした後は、将来機能を追加して作業範囲を広げないでください。
