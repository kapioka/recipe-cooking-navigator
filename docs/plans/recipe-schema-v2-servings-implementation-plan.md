# Recipe / Feedback Schema v2・人数変更 実装計画

作成日: 2026-09-11  
状態: **P1〜P6・実機確認・Project設定切替済み。新規生成Recipeの取込確認待ち。**  
計画の対象: Android / Flutter。別モデルがこの文書を読み、契約確定から実装・検証まで進めるための仕様。

現状は[ロードマップ](../roadmap.md)と[実装結果](phase1-sol-execution-plan.md#11-2026-09-19-実装結果)を参照する。以下の調査状態・権限・「未変更」は2026-09-11の計画作成時点の記録であり、現在の実装状態を示さない。

## 1. 依頼、完了条件、今回の権限

ユーザーは「基準3人分から2人分・4人分へ、基準1人分から2人分・3人分へ、＋／－で分量を変更したい」と希望している。2026-09-11に、既存レシピは2件だけで破棄・後日再作成でもよいため、旧形式への対応コストを優先せず、Schemaから見直した実装計画を残すよう依頼した。実装は別モデルへ引き継ぐ。

この計画作成タスクで許可された変更は本書と発見用リンクだけ。端末データの削除、アプリ実装、外部リポジトリの変更、ChatGPT Project設定変更、push / merge / Releaseは行っていない。

後続の「この計画を実装」の完成条件は、P1〜P6を終え、新形式Recipeの取り込み、人数選択、材料・手順・TTSの一貫した表示、中断・再開・完了時の人数保持までを動かすこと。P7は実機検証と上流Package切替の実施状況を明示する。未実装の評価画面・Feedback共有を本機能へ抱き込まないが、Feedback v2のSchema・例・検証と、将来の生成に必要な調理記録は今回の実装範囲とする。

本計画の完了後は、`docs/roadmap.md`のPhase 2以降で、時計・独立タイマー・常時点灯・RecipeをまとめるKitchen toolへ進化させる。Kitchen mode、共通タイマー基盤、background通知、複数タイマー、ホーム再設計は本計画の実装範囲外。Schema v2担当モデルは、現在のRecipe Stepタイマーの回帰を保つために必要な変更だけを行い、先行してKitchen timerのarchitectureを作らない。

## 2. 調査時点の根拠と再開時の確認

### 確認済みのローカル状態

- アプリrepository: `E:\作ってみた\recipe-cooking-navigator`、基点commit `52384ba2e72b144deb0db61c4c852bb69dfd3395`。
- 計画作業branch: `codex/plan-schema-v2-servings`。
- 着手時に追跡ファイルの変更なし。既存untracked `design-qa.md`は本タスク外。変更・削除・一括stageしない。
- 上流Packageのローカルrepository: `E:\作ってみた\ai-prompt-library`、確認時commit `e68ca0211e943ded9c01ca9ead48fc8f9d07c2d7`、追跡差分なし。remoteの最新状態はこの調査では照合していない。
- 実装済み: Recipe v1の取り込み、Inbox、検索・タグ、Revision/active管理、Cooking mode、TTS、タイマー、途中位置・最小完了履歴。
- 未実装: Evaluation入力、Feedback生成・共有、過去版からの改善依頼UI。`docs/roadmap.md`のPhase 2と現行コードで確認した。
- 配布用Instructionsの実在場所: `ai-prompt-library/prompts/food-drink/recipe-cooking-navigator/`。実際のChatGPT Projectへ登録されているファイルは未確認。

### 実装モデルが最初に行うこと

1. 現在の`AGENTS.md`、Git branch/statusを確認し、本書作成後の変更を保護する。mainへ直接実装しない。
2. 上記基点以降の差分のうち、本書のChange Mapに重なるものだけ確認する。現在のSchemaと本書の「変更提案」を混同しない。
3. 本書の決定表を実装の標準案として採用する。新しい根拠で変更が必要なら、その理由・影響・期待値を本書へ先に追記する。過去の会話だけを根拠に別方式へ戻さない。
4. P1でSchema・完全な例・意味検証を先に一致させる。現時点の文書とv1の不一致は、下記の明示的な仕様変更として更新する。

正本の順序はrepositoryのAGENTSに従う。**実装後は`schemas/*-v2.schema.json`が構造の正本、`docs/data-model.md`が計算・参照の意味、`docs/product-spec.md`と`docs/cooking-mode-ui.md`が挙動の正本**になる。本書は実装順・受入条件・決定理由を保持し、重複する別の現行仕様にしない。

## 3. 決定表

| 論点 | 採用する設計 | 理由・境界 |
|---|---|---|
| 形式 | Recipe / Feedbackとも`schema_version: "2.0.0"` | v1の追加フィールド禁止・表示値正本を破る変更だから |
| 旧レシピ | v1読込・自動変換・両対応は実装しない | ユーザーが2件の再作成を許容。v1ファイルをv2として推測しない |
| 基準人数 | `recipe.servings`を維持 | `base_servings`をRecipeに重複追加しない |
| 人数範囲 | 整数1〜12のうち、Recipe指定範囲内 | 小規模家庭調理向けの製品上限。安全性の保証値ではない |
| 人数変更不可 | 許容範囲のmin=max=基準人数 | 複雑な換算式を導入せず表現できる |
| 分量の正本 | Recipe直下の`amounts`に、使い分ける分量を一度ずつ定義 | 材料総量・下準備・Stepへの数量重複を除く |
| 材料総量 | `amounts`から算出 | ChatGPTに総量と各使用量を二重入力させない |
| 計算値 | 正の有理数（分子・分母） | 1/3等の個数・大さじを損失なく扱う |
| 自動計算 | 各分量で`linear`または`fixed`を明示。定性的な量は別型 | 食材名から勝手に例外判定しない |
| 丸め | 数学的な値を丸めて変更しない。小数の表示だけ近似可 | 卵を切り上げるなどの調理内容変更を自動で行わない |
| 文章内分量 | 型付き参照を含む`RecipeText` | 自由文から数量を探して置換しない |
| 選択人数 | 調理前のローカルstate。開始時に調理contextへ固定 | Recipe/Revisionを人数操作で書き換えない |
| 再開 | 保存されたrevision・人数・計算結果で再開 | active版や詳細画面の新選択人数を使わない |
| 時間・火加減 | 人数倍率では変更しない | タイマー推奨値とユーザーによる手動調整を維持 |
| Feedback | 改善元の原本と、実際の調理元・選択人数・提示量を区別 | 提示量を「実際に使った量」と断定しない |

前の会話で候補に挙げた`rounded + increment`は採用しない。丸め方式の存在だけでは適切な味や工程を保証できず、総量と使い分けた量の食い違いを生むため。Schemaが保証できるのは構造と、実装した意味検証までであり、AIの料理上の判断の正しさや食品安全を保証するものではない。

## 4. Recipe v2の契約

### 4.1 トップレベルと維持する項目

ファイルは`schemas/recipe-v2.schema.json`、draft 2020-12、`type: "recipe"`。オブジェクトは原則`additionalProperties: false`。未知の型・単位・参照は拒否する。

外枠`schema_version / type / recipe`を維持する。Recipeの`id / revision / parent_revision / title / servings / total_time_minutes / estimated_difficulty / ingredients / overview / utensils / preparation / stages / adjustments`も責務を維持する。数量・文章の型変更は以下に従う。

- `servings`: integer 1..12。常に原本の基準人数。
- 新規必須`serving_adjustment`: `{min_servings, max_servings, note}`。両人数はinteger 1..12、`min <= servings <= max`を意味検証する。`note`は空でない文字列で、器具容量・分けて作る必要・変更非推奨の理由などを説明する。ここに材料の変動分量を埋め込まない。
- 選択値をRecipeへ保存しない。倍率も重複保存せず`target_servings / recipe.servings`で決まる。
- `total_time_minutes`、想定難易度、器具数は基準条件の値として扱う。
- Revision識別、過去版保持、active/latest、タグのローカル管理、食品安全の優先順位は維持する。

### 4.2 材料と分量を分離する

`ingredients[]`は`{id, name, note?}`とし、旧`quantity`を削除する。材料IDは一意、名前は空白だけを禁止する。noteの型は4.5のRecipeText。

新規必須`amounts[]`に、**その料理で用意する物理的な分量の区分**を定義する。全体で1..256件。

```json
{
  "id": "oil-frying",
  "ingredient_id": "oil",
  "label": "炒め用",
  "quantity": {
    "kind": "measured",
    "value": {"numerator": 1, "denominator": 1},
    "unit": "tsp",
    "scaling": "linear"
  }
}
```

- 必須: `id / ingredient_id / label / quantity`。`label`は「全量」「炒め用」「仕上げ用」等の空でない短い文字列（最大40文字）。任意`note: RecipeText`。
- amount IDはRecipe全体で一意。ingredient IDは既存材料を参照する。
- 同じ材料を炒め用と仕上げ用に分けるなら別amountにする。各amountに基準量を持たせる。
- 下準備で切った玉ねぎを後で炒める場合は、同じamountを再参照する。別量を追加しない。
- 合わせ調味料も、構成材料の同じamount IDを下準備と投入Stepから参照する。中間生成物専用の複雑なグラフは導入しない。
- すべての材料に最低1件のamountが必要。すべてのamountは下準備またはStepから最低1回参照されること。

`preparation[].ingredient_uses`と`steps[].ingredient_uses`は廃止し、どちらも必須`amount_ids: string[]`へ置換する。空配列は材料不要の工程に限って許容する。配列内重複は禁止。数量や単位を再び持たせない。

参照の意味は「この画面で必要な材料分量」であり、消費イベントではない。**下準備と全Stepの参照量を足して総量を計算しない。** 同じ量を二度投入するような手順の意味上の誤りは、参照整合性だけでは検出できない。生成指示と例のレビューで確認する。

### 4.3 quantityの型

`quantity`は`oneOf`で次の2型だけを受け付ける。旧`display`、null数値、自由な単位文字列、`rounded`、独自換算式は禁止。

| 型 | 必須フィールド | 意味 |
|---|---|---|
| measured | `kind="measured"`, `value`, `unit`, `scaling` | 基準人数での計測可能な量 |
| qualitative | `kind="qualitative"`, `text`, `adjustment_note` | 「適量」「少々」等。計算しない |

measuredの追加任意フィールドは`adjustment_note: string`だけ。`scaling="fixed"`なら空でないadjustment_noteを必須にする（例: 使用する器具条件で一定量を用いる理由）。`linear`では省略可。

- `value`: `{numerator, denominator}`。両方integer、分子1..1,000,000、分母1..1,000。分母0、負、null、小数の分子/分母は拒否する。これらはデータ処理上の上限であり、料理上の上限ではない。
- `1/2個`は分子1・分母2、`1.5大さじ`は3・2、`200g`は200・1。
- 入力の既約分数化は必須にしない。内部計算で約分する。原本を書き換えない。
- `linear`: value × target_servings ÷ servings。
- `fixed`: target_servingsにかかわらず基準value。単位や食材名から自動選択しない。
- `qualitative.text`: 空でない1..40文字、例「適量」。`adjustment_note`: 空でない1..300文字、例「仕上がりを確認しながら調整する」。数値入り自由文を計算対象にしない。
- 卵も自動切り上げしない。1個が2/3個になる場合は分数表示し、必要ならamount.noteに「溶いてから使う」等の手順を生成する。それが不適切な料理なら、生成側が人数範囲を狭くする。
- 塩・油はすべてmanualという共通ルールにしない。レシピの用途ごとにlinear / fixed / qualitativeを明示する。

単位コードと日本語表示は固定し、Dartの1つの対応表で管理する。

| unit | 画面 | TTS |
|---|---|---|
| g / kg | g / kg | グラム / キログラム |
| ml / l | ml / L | ミリリットル / リットル |
| tsp / tbsp | 小さじ / 大さじ（値の前） | 小さじ / 大さじ |
| piece / slice / clove | 個 / 枚 / 片 | 個 / 枚 / 片 |
| stalk / sheet / pack / bunch | 本 / 枚 / パック / 束 | 本 / 枚 / パック / 束 |

cupは容量規格が曖昧なので初版では受け付けず、生成時にmlへ明示する。tsp / tbspは本アプリでは日本の5ml / 15mlを意味するが、初版で単位間の自動換算はしない。同じingredientのmeasured amountsは同一unitでなければ拒否する。肉重量と個数の換算や密度換算も行わない。

### 4.4 材料一覧の総量

各ingredientに属するmeasured amountsの計算結果を有理数で合計する。同じamountの参照回数には依存しない。UI順序はingredients配列順、内訳はamounts配列順。

- measuredのみ: 合計を表示。複数amountなら内訳を表示可能にする。
- qualitativeのみ: `炒め用：適量／仕上げ用：少々`のように区分別に表示する。同じ文言でも別amountを消さない。
- measured + qualitative: `合計 小さじ2 ＋ 仕上げ用：適量`のように併記。文字列を数値化・加算しない。
- fixedを含む場合: 該当内訳に「人数によらず同量」と理由を表示する。
- 総量と各amountの**正確な値**は常に一致する。小数の近似表示同士の加算では最下位桁に差が出得るため、「約」と内訳で区別する。

### 4.5 手順文中の分量を参照にする

`RecipeText`は1..64個のsegment配列。segmentは次の`oneOf`。それぞれ未知フィールド禁止。

```json
[
  {"type": "text", "text": "フライパンに"},
  {"type": "amount_ref", "amount_id": "oil-frying"},
  {"type": "text", "text": "を入れる。"}
]
```

- text: `{type:"text", text:string}`。空文字不可、1segment最大2,000文字。
- amount_ref: `{type:"amount_ref", amount_id:string}`。**材料名＋そのamountの現在分量**を出力する。文字列テンプレート、任意式、Markdown/HTMLの解釈はしない。
- 表示例: 「フライパンにサラダ油 小さじ1と1/2を入れる。」
- 人数で変わる材料分量をtextに直書きしない。「厚さ1cm」「2分」「温度」等は人数比例対象ではなくtextに書ける。数字の一律禁止・正規表現による置換は行わない。
- Schemaがtextの料理的意味まで検証できるとは主張しない。生成チェックとP1の例レビューで変動分量の直書きを検出する。
- preparation.text、およびStepのinstruction/heat/done_when/parallel_tasks内のamount_refは、その所有オブジェクトのamount_idsにも含まれていなければ拒否。next_previewは次工程を参照できるのでローカルamount_idsへの包含を要求せず、Recipe内の存在だけ確認する。その他のRecipeTextフィールドもRecipe内の参照先存在を確認する。
- amount.note内の参照展開で別のnoteを再帰展開しない。amount_refは名前と量だけを出すため、循環する文章評価を生まない。

次のフィールドをstringからRecipeTextへ置換する。任意性はv1を継承する。

| 場所 | v2の型 |
|---|---|
| `preparation[].text` | RecipeText |
| `stages[].steps[].instruction`, `done_when`, `heat?`, `next_preview?` | RecipeText |
| `overview[]`, `steps[].parallel_tasks[]` | 各要素がRecipeText |
| `ingredients[].note?`, `amounts[].note?`, `utensils[].reuse_note?` | RecipeText |
| `adjustments[].condition`, `adjustments[].action` | RecipeText |
| `storage_note?`, `lunchbox_note?` | RecipeText |

Recipe/stage/stepのtitle、材料名・器具名、label、estimated_difficulty.reason、revision_summaryは通常の文字列を維持する。変動分量を書かず、revision_summaryは「しょうゆを減らした」等で説明する。serving_adjustment.note、quantity.adjustment_noteも変動分量を埋め込まない案内文とする。

UIで従来表示していたフィールドはすべてrendererへ通す。現在UIにない任意フィールドのために新しい独立画面は作らないが、ドメインrendererは全RecipeTextフィールドを処理できること。調理に必須の変更条件は、未表示のadjustmentsだけに置かず、Stepまたはserving_adjustment.noteにも含める。

### 4.6 意味検証とエラー

構造検証の後、保存前に以下を検証する。単一ファイル取込・Inbox・保存データ読込で同じvalidatorを使う。

1. 人数範囲、parent_revision < revision、既存のID一意性・器具参照。
2. amount ID一意性、ingredient参照、各材料にamountが存在すること。
3. 同じ材料のmeasured単位一致。linear/fixedの違いは許容する。
4. preparation/stepのamount_ids重複・欠損、未使用amount、RecipeText参照の欠損と4.5の包含条件。
5. 計算結果が正であり、サポート人数内で計算できること。許容人数は最大12通りなのでP1テストでは全通り列挙できる。
6. インポート前後で原本を書き換えない。同ID/revisionで異内容なら従来どおり拒否する。

エラーは`schemaViolation`等既存カテゴリを活用し、「工程Xの材料参照がありません」「材料Xの単位が一致しません」等の理由とJSON pathを返す。内部スタックや端末pathを表示しない。v1は「旧形式です。対応する指示文でレシピを作り直してください」と専用案内する。

## 5. 計算・表示・読み上げの実装契約

### 5.1 ドメインAPI

実装ファイル候補（新規）は`lib/domain/recipe_amount.dart`、`recipe_scaling.dart`、`recipe_text.dart`、`cooking_context.dart`。同等責務の小さな構成なら統合可。画面ごとに換算処理を作らない。

- `RecipeDocument`: validatedな型付きRecipeを保持。amount/ingredientの索引を作る。既存の名前検索・Revision参照APIを維持する。
- `resolveCookingContext(recipe, targetServings)`: 範囲検証後、Recipe identity、人数、すべてのresolved amountsを含むimmutable contextを返す。
- `resolveIngredientTotals(context)`: 4.4の集計。
- `renderRecipeText(text, context)`: 同じ意味の`displayText`と`speechText`を返す。
- `amountsFor(stepOrPreparation, context)`: amount_ids順に名前・分量・noteを返す。
- 計算はDartのみ。Android APIやWidgetへ依存しない。依存ライブラリの追加は不要。BigIntによる小さな有理数型で四則演算の必要範囲（乗除・加算・約分）だけ実装する。

計算は必ず基準値から行う。＋→＋→－で前の計算値を再倍率計算しない。元の人数へ戻したら正確に基準量へ戻る。

### 5.2 フォーマッタ

- 整数なら小数部を出さない。
- g/kg/ml/lは小数最大2桁、half-upで**表示だけ**丸め、0以外の桁を落とした場合は「約」を付ける。正の値が0.00になる場合は分数表示に切り替え、0とは表示しない。
- tsp/tbsp/個数系は約分済み分数・帯分数を使う。例: `大さじ1と1/2`、`2/3個`。`1個弱`等の曖昧な調理表現へ変換しない。
- 小数を表示した場合の正確な分数は分量の詳細/アクセシビリティ説明から確認できるようにする。計算・保存・Feedbackには表示小数を使わない。
- TTSでは`2/3個`を「3分の2個」、`1と1/2`を「1と2分の1」と読む。数字や単位以外の自然な発音の実機確認も必要。
- qualitativeはtextとadjustment_noteを表示する。Step TTSにも必要な調整案内を含める。
- fixedは人数変更時に同量である旨を明示する。基準人数の通常表示を不必要に長くしない。
- Step TTSはタイトル→本文→使用材料→火加減→時間の目安→完了判断を基準にする。本文内のamount_refと材料一覧で数量の読み上げが重なることは初版では許容し、同じ値であることを優先する。

## 6. UIと状態遷移

### 調理前

レシピ詳細の現在の人数Chip付近に＋／－を配置し、選択人数・基準人数・リセットを表示する。既存Theme/コンポーネントに合わせる。範囲端では該当ボタンを無効化する。min=maxなら変更不可の理由を表示する。

初期値はそのactive revisionのservings。±は1人ずつ。人数を変えると、材料総量、下準備、全体工程、amount_refを含む説明を同じcontextで同時更新する。時間は「目安○分（基準○人分）」として表示する。

人数変更時は「材料を○人分に換算しています。加熱時間・火加減・器具は自動調整されません。」とRecipe固有のserving_adjustment.noteを表示する。許容範囲は生成側の条件であり、設備容量や火の通りの保証ではない。

詳細画面を開き直した際は基準人数へ戻す。選択値を全Recipe共通の設定にしない。active revisionが切り替わった場合も、新revisionの基準人数へ戻す。タグ更新や同じrevisionの再描画では選択値を失わない。

### 開始・再開・終了

| 操作 | 使用する条件 | 保存/画面の結果 |
|---|---|---|
| 初回の調理開始 | 現在の詳細revision＋選択人数 | contextを先に保存し、成功後にCooking画面へ入る |
| 続きから | 進行状態のrevision＋保存人数＋保存量 | 詳細画面の選択値を無視して復元する |
| 最初から | 現在の詳細revision＋選択人数 | 既存の再開始確認に人数も表示。承認後に新contextを保存する |
| 前/次/工程ジャンプ | 既存contextを固定 | Stepとupdated_atだけ更新する |
| 中断/アプリ終了 | 既存contextを固定 | 再開に必要な状態を保持する |
| 完了 | 既存contextを履歴へコピー | Session保存成功後だけprogressを削除する |
| 保存エラー | 保存済み状態を保持 | 開始/移動/完了を成功表示しない |

Cooking modeでは「○人分で調理中」を常時確認でき、人数の編集は提供しない。材料シート、Step本文、工程一覧、TTSが同じcontextを使う。音声で人数を変えるコマンドは追加しない。

再開カードは「Version X・○人分・工程Y」を表示する。違うrevisionの再開時、詳細画面の現在選択とは別であることが分かる文言にする。既存のタップ/スワイプ領域をバッジで壊さない。大文字サイズ・TalkBack・横向きでも人数操作と材料詳細が使えること。

タイマーのユーザー起動・終了後の手動Step移動・常時点灯解除・端末回転設定を変更しない原則はそのまま検証する。

## 7. ローカル保存とv1からの切替

### 7.1 互換対応を作らない切替

端末の旧データを実際に消す必要はない。**新しい保存ファイル名でv2の空ライブラリを開始し、旧ファイルを読み込まず残す**。既存2件はユーザーが新形式で再作成する。旧形式の内容を推測変換したり、schema_versionだけ書き換えたりしない。

| 用途 | v2の保存先 | envelopeのstorage_version |
|---|---|---|
| Recipe原本 | `recipes-v2.json` | 2 |
| 進行状態/最小Session | `cooking-v2.json` | 2 |
| active選択 | `recipe-version-state-v2.json` | 1（構造は変更しない） |
| タグ | `recipe-tags-v2.json` | 1（構造は変更しない） |
| Inbox接続/取込記録 | 既存`recipe-inbox-v1.json`を継続 | 1 |

ファイル名のv2はこの切替のデータ領域、storage_versionは各保存形式、schema_versionは外部契約、revisionはレシピ履歴であり、それぞれ独立している。全クラスのversion定数を機械的に2へ置換しない。

- 旧v1のRecipe/調理履歴/タグ/activeファイルとそのbackup類は触らない。uninstallや`pm clear`を通常手順にしない。
- 新ファイルが壊れている場合に空状態で上書きしたり旧v1へfallbackしたりしない。新領域のbackupでの復旧かエラーにする。
- 旧データが存在するときだけ「旧形式のレシピは表示していません。新しい指示文で再作成してください」とホームで案内する。初版はデータ復旧・削除UIを追加しない。
- Inboxのフォルダ権限は保持する。古い取込記録があっても、新ライブラリに対応Recipe/revisionがなければ再検証する既存挙動を維持する。
- Inboxに残るv1はファイルごとに拒否し、v2ファイルの取り込みは継続する。Driveのファイルをアプリが削除・上書きしない。
- 再作成する2件は新Recipe ID / revision 1を推奨し、廃棄したv1 revisionをparentとして捏造しない。
- アプリ版番号更新は実装時の現在値から判断する。署名鍵・application IDを変更しない。

### 7.2 CookingContext

progressに以下を保存する。既存のRecipe IDごとに進行状態1件という制約を維持する。

- 既存の`recipe_id / revision / step_id / started_at / updated_at`。
- `recipe_snapshot`: 調理開始時のRecipe v2全文。raw原本をそのまま固定する。
- `cooking_context`: `{target_servings, scaling_algorithm, resolved_amounts}`。
- `scaling_algorithm`: 初版固定文字列`"servings-v2.0"`。
- `resolved_amounts[]`: 原本amounts順、全amountをちょうど1回含む。`{amount_id, quantity}`。
- resolved quantityはmeasuredなら`{kind, value:{numerator,denominator}, unit}`、qualitativeなら`{kind, text, adjustment_note}`。valueは約分し、BigIntを10進数字文字列でシリアライズする（原本の数値上限とは区別）。分子/分母の文字列は`^[1-9][0-9]{0,31}$`とする。scaling方式は原本から追跡できる。

この一覧は**アプリが調理時に提示した量**であり、秤で測った実使用量ではない。表示文字列や翻訳結果を正本として保存しない。

savePositionを、開始用`startCooking(recipe, context)`と移動用`updatePosition(recipeId, revision, stepId)`相当へ分離する。現行savePositionはMapを作り直すため、そのままでは新フィールドが工程移動時に消える。移動時に別revisionのcontextを流用できないよう検証する。

読み込み時は原本をv2検証し、identity、Step、人数範囲、algorithm、amount IDs/単位/型/値を照合する。現行algorithmなら原本から再計算して保存値と厳密一致を確認する。欠損・未知algorithmを基準人数へ補完しない。復元できない場合はエラーとし、明示的な「最初から」でのみ新contextを作る。

CookingEntryでは、ライブラリ内の該当revisionの存在と保存snapshotとの内容一致も確認する。欠落・異内容なら「続きから」を無効にし、保存snapshotをライブラリへ無断で再importしない。完了済みSessionからの将来Feedback生成は保存snapshotだけで読めるようにし、現在のactive版に依存させない。

型の取り違えを防ぐため、保存contextの例を示す（基準2人、linear肉200gを3人へ変更した場合の1amount抜粋。実際は全amountを含める）。

```json
{
  "target_servings": 3,
  "scaling_algorithm": "servings-v2.0",
  "resolved_amounts": [
    {
      "amount_id": "pork-all",
      "quantity": {
        "kind": "measured",
        "value": {"numerator": "300", "denominator": "1"},
        "unit": "g"
      }
    }
  ]
}
```

完了Sessionにもsnapshotとcontextを同じ内容でコピーする。completed_atは保存成功の完了時刻。Evaluationはまだ存在しないので、架空の難易度・調理時間・感想を埋めない。既存の逐次書込、temp/backup/recovery、保存失敗時の進行状態保持を維持する。

## 8. Feedback v2の先行設計

ファイルは`schemas/feedback-v2.schema.json`。既存のevaluation（味偏差-2..+2など）とrevision_requestの目的は維持する。Recipe v2をローカル`$ref`で参照し、ネットワーク取得せず検証できるようSchemaを登録する。

`cookingContext`と`resolvedQuantity`のJSON定義はFeedback v2の`$defs`に一度置く。第7章のローカルcontextのparse/serializeも同じDart型を使用する。Recipeの基準quantity（整数の分子/分母とscalingを持つ）と、計算後のresolved quantity（数字文字列の分子/分母）を混同しない。3つ目の配布Schemaを作らず、Project sourceは引き続きSchema2点と連携仕様1点に収める。

| 変更箇所 | 契約 |
|---|---|
| `schema_version` | `"2.0.0"` |
| `recipe_snapshot` | ユーザーが選んだ**改善元**Recipe v2の全文 |
| `cook_session.recipe_snapshot`（追加必須） | 実際の調理元Recipe v2全文。外側の改善元と異なるrevisionでもよい |
| `cook_session.cooking_context`（追加必須） | 7.2と同じtarget_servings、algorithm、提示量の記録 |
| `cook_session.recipe_id / recipe_revision` | 実際の調理元と一致。外側snapshotへの無条件一致は要求しない |
| `revision_request.next_revision`（追加必須） | アプリに存在する同IDの最大revision＋1を生成時に計算した整数 |

外側と内側のsnapshotは同じRecipe IDでなければ拒否する。外側がrev2、実調理がrev4なら、評価はrev4・その調理人数への評価、改善元はrev2と明示的に解釈できる。両者が同じ場合も省略せず同じ原本を入れる。重複は独立した役割を明示し、履歴参照なしで読めることを優先したもの。

新Revisionは外側snapshotのrevisionをparent_revisionにし、next_revisionをrevisionにする。next_revisionは両snapshotのrevisionより大きいことを検証する。オフラインで2件の改善依頼を同時生成すれば番号衝突はなお起こり得るため、既存の同ID/revision異内容拒否を維持する。予約機構・自動上書き・アプリ内での自動採番変更は導入しない。

基準人数は外側snapshotのservingsを維持するのが既定。調理時に2→4人分へ変えたからといって、改善Recipeのservingsを4へ変えない。ユーザーが基準人数自体の変更を明示した場合だけ再設計する。linearは倍率を考慮して改善できるが、fixed/qualitativeや実際の変更を一律で逆比例換算しない。

実際に使った量や味見で足した量は、ユーザーが記録した`changes_made`等で伝える。cooking_contextの提示量を実使用量とみなさない。

今回の実装では、Schema・例・Feedback意味validatorと、保存Sessionからidentity/snapshot/contextを取り出す純粋な変換部分まで用意する。まだない評価値を生成して公開UIからFeedbackを送れるようにしない。Evaluation画面、Session選択、revision_request入力、OS共有は既存Phase 2で実装する。

## 9. ChatGPT側の変更と配布順

変更先はローカル`E:\作ってみた\ai-prompt-library\prompts\food-drink\recipe-cooking-navigator\`。この計画作成では読取だけを行った。後続実装がこのrepositoryまで含む場合は、そのrepositoryの指示・差分・branchも確認する。

| ファイル | 変更 |
|---|---|
| `project-instructions.md` | v2、基準人数、許容範囲、amountの単一定義、RecipeText、Feedback文脈を反映 |
| `recipe-v2.schema.json`（新規） | アプリrepositoryのSchemaをそのまま配布コピー |
| `feedback-v2.schema.json`（新規） | 同上 |
| `chatgpt-integration.md` | アプリrepositoryの同名仕様へ追従 |
| `README.md` | v2対応版、必要3ファイル、旧アプリ非互換、更新手順、版番号を更新 |
| `cooking-profile.md` | 今回は変更しない。個人Profileをコピー/公開しない |

Instructionsへ反映する意味上の要件:

1. 人数はまず基準servingsとして確定し、measured量はその人数の量だけを書く。アプリ選択値をRecipeへ先回りして混ぜない。
2. 同じ材料の別用途は別amount、下準備と投入の同じ量は同じamountを参照する。総量を別途書かない。
3. measuredとqualitativeを使い分け、塩等を名前だけで一律例外扱いしない。各linear/fixed判断に料理上の根拠を持つ。
4. 材料分量はRecipeTextのamount_refへ、切る厚さ・加熱条件は通常textへ書く。
5. 支持できる人数範囲だけ指定する。全レシピを一律1〜12にしない。不確かなものは基準人数のみとする。量変更時に必要な器具・分割調理等の注意を明示する。
6. 分数値を勝手に「1個」に切り上げない。扱いづらい場合は量り方を示すか、対応範囲を制限する。
7. Feedbackの改善元と実調理元、基準人数と選択人数、提示量と実変更、parent_revisionとnext_revisionを区別する。
8. 旧v1はversion文字列を付け替えるだけで修復しない。今回の2件は新形式で再作成してよい。
9. Schema検証に加え、全参照、amountの用途、文章内直書き、Step単独実行性を出力前に1回確認する。調理安全性はSchema検証だけで合格したとみなさない。

再利用Instructionsを実際に編集する段階では、適用対象のPrompt guidanceを確認する。今回確認した`personal-context/agents/prompts/prompt-registry.yaml`にはこのPackageの個別登録はなく、temporary/model-independentな引き継ぎ文を新たなglobal promptとして登録する必要はない。モデル名・固有の推論手順を本書やRecipe契約へ埋め込まない。

配布順は「v2アプリの検証→v2 Packageの整合確認→対象アプリ更新→ChatGPT ProjectのInstructionsとsource3点を同時に切替→新規Recipe生成・取込確認」。旧アプリはv2を読めない。新旧Schemaを同一Projectで混在させない。Projectから旧sourceを外しても、個人cooking-profileを削除しない。

両repositoryのローカル準備は分けて管理できるが、公開push/merge/Release、既存Project設定の実変更は明示された範囲で行う。公開前はいつものsecret checkと各repositoryの公開手順を使う。配布コピーはSchema原本とSHA-256一致を確認する。今回、外部Packageの変更・公開・Project切替は一切行っていない。

## 10. Change Map

| Path / component | 役割 | 変更内容と理由 | 検証 |
|---|---|---|---|
| `schemas/recipe-v2.schema.json`（新規） | 正本 | 第4章のv2構造 | 完全例＋不正例、Dart validator |
| `schemas/feedback-v2.schema.json`（新規） | 正本 | 第8章、Recipe参照 | ローカルref解決＋意味検証 |
| `schemas/*-v1.schema.json` | 旧公開契約 | 履歴資料として残す。現行asset/入口から外す | v2アプリでv1を拒否 |
| `examples/recipe-example.json`, `feedback-example.json` | 現行例 | v2へ置換 | Schema＋意味validator |
| `examples/recipe-v2-split-example.json`（新規） | 分量配分例 | 同材料の別用途、下準備/Stepの再参照 | 総量と参照テスト |
| `lib/domain/recipe_document.dart` | consumer | 型付きamount/text、既存検索用名前等を保持 | parse/原本不変 |
| `lib/domain/recipe_validator.dart` | validator | v2のみ、参照/単位/人数検証 | 拒否ケース |
| `lib/domain/recipe_amount.dart`, `recipe_scaling.dart`, `recipe_text.dart`, `cooking_context.dart`（候補新規） | 共通計算 | 第5・7章の小さな責務 | 純粋Dart tests |
| `lib/domain/feedback_validator.dart`（新規） | 将来consumer | Feedback構造とsnapshot/context意味検証 | 異revision例も含める |
| `lib/data/cooking_store.dart` | 保存 | context固定、開始/移動分離、Sessionへコピー | 再起動/失敗/recovery |
| `lib/data/recipe_document_store.dart` | 保存 | v2 envelopeのみ | 競合拒否、backup、v1無変更 |
| `lib/main.dart`, `pubspec.yaml` | 初期化/asset | v2Schema・新保存先、旧領域の案内 | asset読込、更新起動 |
| `lib/application/recipe_library_controller.dart` | 取込/検索 | 型変更追従、legacy案内の状態 | Inbox/単体取込、検索、active |
| `lib/ui/recipe_detail_screen.dart` | 人数選択 | stateful選択、総量/RecipeText、再描画条件 | widgetテスト |
| `lib/ui/cooking_entry.dart` | 開始/再開 | 選択context、保存context、人数付き確認 | restart/resumeテスト |
| `lib/ui/cooking_screen.dart` | consumer | 本文/シート/TTS/context保存 | widget＋実機 |
| `lib/ui/home_screen.dart`, `recipe_version_history_screen.dart` | consumer | 基準人数と途中人数を混同しない、型追従 | 既存表示回帰 |
| `test/*` | 検証 | fixtureをv2へ更新、下記受入ケース追加 | format/analyze/test |
| `docs/product-spec.md`, `data-model.md`, `chatgpt-integration.md`, `cooking-mode-ui.md` | 現行仕様 | v1の表示値正本/数量再掲/文章例/再開を更新 | 参照・用語・例の照合 |
| `docs/roadmap.md`, `README.md` | 入口 | v2・互換性・実施済み/未実施状態 | linkと完了状態確認 |
| 上流Package（第9章） | 配布/生成 | 原本同期＋Instructions改訂 | hash一致、生成Recipe検証 |
| Android音声/タイマー/Inboxネイティブ、署名、Profile | 原則非対象 | domain変更だけで対応。新たな必要性があればChange Mapへ理由を追記 | diff範囲 |

未実装のphase2評価UI、SNS、バックアップ製品機能、単位自動換算、任意スケーリング式、栄養計算、複数料理、iOS、新規バックエンドは追加しない。

## 11. 実装順序と各段階の出口

### P1 — 契約・例を先に固定

- v2の2Schemaと完全な正常例（標準、分割材料、qualitative/fixed）を作る。
- v1から変更する仕様をdocsへ反映し、Schemaと説明の食い違いを解消する。
- 構造と参照・単位・人数の意味validatorを先に作り、Dartで実際に通ることを確認する。JSON SchemaのoneOf/ローカルref対応を未検証の前提にしない。
- Feedbackの旧refが残っていないことを確認する。
- 出口: 例が全数合格、不正fixtureは狙った理由で拒否。型・フィールド名・期待値が確定。

### P2 — 計算・文章の共通処理

- 有理数計算、量解決、総量、RecipeText、画面/TTSフォーマッタを実装する。
- 基準人数の表示も同じresolverを通す。rawのdisplay相当へ逃げる旧ルートを残さない。
- 出口: 第12章の計算/参照ケースが合格。原本不変が確認できる。

### P3 — 保存と起動切替

- 新保存領域、start/update/complete、contextの厳密復元を実装する。
- v1を読まないこと、Inbox権限・旧ファイルを保持することを検証する。
- 出口: 工程移動・失敗・再起動・完了で人数/原本/提示量が失われない。

### P4 — UI接続

- 詳細人数選択、材料・下準備、CookingEntry、Cooking画面・TTSを同一contextへ接続する。
- 中断・再開・active切替、大文字サイズ・アクセシビリティを確認する。
- 出口: 選択→調理→中断→再開→完了のwidgetフローが成立。

### P5 — Feedback契約と上流Package

- 保存SessionからFeedbackに必要なsnapshot/contextを取り出せることを検証する。
- まだないEvaluation UIを完成扱いにしない。
- 上流Packageのローカル更新が実装範囲なら第9章を実行し、原本コピーを一致させる。対象外なら必要ファイルと残作業を具体的に引き継ぐ。
- 出口: Feedbackの完全な例と生成契約が一致し、調理条件が解釈できる。

### P6 — 統合回帰

- formatter、analyze、全unit/widget、Android debug buildを順番に実行する。
- wrapperが同じR:ドライブを使うためFlutter/Gradle検証を並列起動しない。
- 既存の取込・検索・タグ・Revision・タイマー・音声の回帰を確認する。
- 出口: 全必須検証合格、差分がChange Map内、docsの状態が実績と一致。

### P7 — 実機・配布の引き継ぎ

- 実機QAが実装依頼に含まれる場合、現在のAndroid QA skillを使い、対象端末と署名を確認して検証する。署名不一致をuninstallで解消しない。
- 正式署名APKが必要な場合はrepositoryのrelease-signing手順と外部対話PowerShellでのパスワード入力方針に従う。チャットにパスワードを書かせない。
- 対象アプリ版とPackage/Projectの切替を対応付けて記録する。
- 完了報告を「実装済み」「自動検証済み」「実機確認済み」「上流/公開の残作業」に分ける。公開自体は今回の機能実装の自動完了条件にしない。

## 12. 受入テスト（実装時の期待値）

### 数量・テキスト

| ID | 入力/操作 | 期待値 |
|---|---|---|
| Q01 | 基準3人、linear肉300g、選択2/4 | 200g / 400g |
| Q02 | 基準1人、linear100g、選択2/3 | 200g / 300g |
| Q03 | 基準3人、linear200g、選択4 | 正確値800/3g、表示「約266.67g」。戻すと200g |
| Q04 | 基準3人、linear卵1個、選択2 | 2/3個。自動的に1個へ変えない。TTS「3分の2個」 |
| Q05 | 基準2人、linear大さじ1、選択3 | 大さじ1と1/2 |
| Q06 | fixed小さじ1、人数変更 | 1のまま。固定理由を表示 |
| Q07 | qualitative少々、人数変更 | 「少々」と調整案内。数値を捏造しない |
| Q08 | 同材料30g＋70g、基準2→3 | 内訳45g＋105g、総量150g |
| Q09 | 同amountをprepと2Stepで参照 | 総量は1回分。全表示/TTSは同じ量 |
| Q10 | 1材料にmeasured＋qualitative | 数値合計と定性的な区分を併記 |
| Q11 | textに「厚さ1cm」、amount_refに材料量 | 人数変更で厚さ1cmは不変、材料量だけ変わる |
| Q12 | ＋、＋、－、リセットを反復 | 累積誤差なし。raw原本はdeep equality一致 |
| Q13 | 正の値が表示丸めで0になる | 0表示にせず分数表示 |
| Q14 | 人数min=max=基準値 | ＋/－無効、理由あり、基準調理可能 |
| Q15 | 総量は正確な1g、内訳1/3g×3 | 正確値合計1g、内訳の約0.33gとの表示差を許容・明示 |

### 拒否・保存・UI

- v1、未知version、未知quantity kind/unit/scaling、旧display/ingredient_usesを拒否。
- 分母0、負値、浮動小数の分子、null、範囲外整数を拒否。
- 人数範囲の逆転、基準人数範囲外、選択人数0/13/小数を拒否。
- amount/ingredient/stepの重複ID、存在しないID、未参照amount、同一材料の単位混在を拒否。
- RecipeTextの壊れた型、未知segment、存在しないamount参照、本文参照がamount_idsにない場合を拒否。
- fixedの理由欠落とqualitativeの調整案内欠落を拒否。
- 3人分で開始して4人分を選択した詳細から再開しても、開始時の3人分が復元される。
- rev1・4人分の途中でrev2をactiveにしても、続きからはrev1・4人分。「最初から」の承認後だけrev2・新選択人数になる。
- 開始前保存失敗はCooking画面に入らず、移動時保存失敗は現在Stepを維持、完了時保存失敗はSession追加/進行削除を成功表示しない。
- progressの人数欠落・異常snapshot・量改変・algorithm不明を、基準人数へ補完せず拒否。
- 保存progressの参照revisionがライブラリにない、またはsnapshotと内容が異なる場合は再開不可。完了済みSessionのsnapshotはactive切替後も保持される。
- 再起動、primary破損時の有効backup復元、全候補破損時の書込禁止を確認する。
- v1のRecipe/タグ/active/調理ファイルとbackup類をbytes比較し、新版初回起動後も変化しない。
- 旧Inbox receipt＋v1ファイルは拒否、receipt＋v2ファイルで対象Recipeが新領域にない場合は再検証・取込、混在時も正常v2は取り込める。
- 同Recipe/revisionの重複・競合拒否、過去Revisionの保持、active/latest、名前/材料/タグ検索を維持する。
- UI本文、材料シート、下準備、全体工程、next_preview、TTSが同じcontextの量を使う。
- ±/リセットをTalkBackから操作できる。範囲端の無効状態と選択人数が分かる。文字拡大でも主要操作を隠さない。
- タイマー時間の自動倍率変更なし。手動開始・手動調整・終了後Step不変、Cooking終了時の常時点灯解除を確認。

### Feedback

- 基準2人→4人調理: recipe_snapshotは2人原本、contextは4人と提示量。原本の分量を4人分へ書き換えない。
- 改善元rev2・実調理rev4・次rev5: それぞれ区別され、生成Recipeのparent=2、revision=5。
- 別Recipe IDのSession混入、context量改変、next_revisionが過去番号、snapshotとSession identity不一致を拒否。
- qualitativeを実使用量の数値へ変換しない。未入力Evaluationを架空の標準点で埋めない。
- すべてのRecipe/Feedback例をネットワークなしで検証する。

### 実在する検証コマンド

repository直下で順番に実行する。

```powershell
dart format --output=none --set-exit-if-changed lib test
pwsh -File .\tool\flutterw.ps1 analyze
pwsh -File .\tool\flutterw.ps1 test
pwsh -File .\tool\flutterw.ps1 build apk --debug
```

新しいテストファイル単体を指定する場合も同じwrapperを使う。新Schema例の検証は新規Dart testへ組み込み、未導入のCLIを前提にしない。実機では基準・減量・増量の画面確認、TTS実音、雑音下の既存音声コマンド、再起動復元、起動前/中/終了後の`accelerometer_rotation`と`user_rotation`不変を記録する。実機未実施をbuild成功で代替したと報告しない。

## 13. ロールバックと完了記録

- 計画作成時: 新規計画書と入口リンクだけの変更。アプリは従来動作のまま。
- 実装コード: feature branchで扱い、既存ユーザー差分に混ぜない。強制reset/checkoutで戻さない。
- 端末: 旧v1ファイルを保持しても、APKのダウングレードが可能とは限らない。必要ならv1互換コードをより大きいversionCodeで再ビルドする。アンインストールをロールバック手順にしない。
- 新v2データ作成後に旧版へ戻る場合、旧版からv2データは見えない。新データが消えたわけではないことを明示する。
- 上流: アプリと対応するInstructions/Schemaの組を戻す。個人ProfileとDriveファイルは別管理。

実装終了時は本書のP1〜P7に実施結果、ソースcommit、テスト結果、実機/上流の未実施事項を追記し、docs/roadmapの対応項目を実績に合わせて更新する。本書の作成だけでv2実装を完了扱いにしない。

## 14. 別モデルへ渡す開始文

> `docs/plans/recipe-schema-v2-servings-implementation-plan.md`に従って、Recipe/Feedback v2と人数変更を実装してください。最初に現在のAGENTS・Git状態と計画作成後の関連差分を確認してください。P1で契約・例・validatorを固定し、P2〜P6を依存順に実装・検証してください。既存2件のv1レシピは再作成してよいため、v1読込・推測migrationは不要です。第7章の新保存領域への切替を採用してください。Recipe原本、材料分量参照、CookingContext、再開、TTS、将来Feedbackの条件を一致させてください。未実装の評価UI・共有機能は追加せず、Schemaと保存contextを整備してください。外部Packageのローカル変更・実機更新が今回の依頼範囲に含まれるかを会話から判断し、未実施分は対象ファイルと次の操作を明示してください。push、merge、Release、端末全消去を暗黙に行わないでください。
