# アプリアイコン3案 — 2026-10-12

2026-10-12、本人が3案目の修正版 [本と鍋のアイコン](03-recipe-notebook-pot-v2.png) を明示採用した。以下の3案比較と提案は選定前の記録。以後の実装は修正版を基準にする。

採用後、通常5密度のlauncherとadaptive背景・透明前景に組み込み、Pixel 10aの本番版へ更新済み。[実装・検証記録](../../plans/recipe-creation-visual-implementation-2026-10-12.md)を参照。以下の「組み込まない」は候補生成時点の範囲を表す。

本人の「主婦女性ウケしそうな感じ」という依頼と、選択済みのクリーム色＋深いグリーンの画面方向をもとにした比較用の候補。内蔵image_genで各案を個別に生成した。暖かな陶器・キッチン用品・生活雑貨の雰囲気を使い、文字やキャラクター顔を入れず、料理アプリとしての分かりやすさを優先した。

| 案 | ファイル | 意図 |
|---|---|---|
| 1 お皿とハーブ | [01-plate-herbs.png](01-plate-herbs.png) | 自然なカフェ・器のやさしさ |
| 2 ほっとするお鍋 | [02-cozy-pot.png](02-cozy-pot.png) | 毎日の家庭料理が一目で伝わる |
| 3 わたしのレシピ帳 | [03-recipe-notebook.png](03-recipe-notebook.png) | 自分のレシピを集めるアプリとして伝える |

提案は2。鍋と湯気のまとまりが料理アプリの目的を伝えやすく、クリーム色とセージの画面にも合うと判断した。「女性に好まれる」ことを検証した結果ではなく、本人が比較して選ぶデザイン提案である。

生成画像は正方形の候補アート。今回は本番launcher resourceへ組み込まない。採用案が決まったら、Androidの丸／角丸maskで切れない位置・余白に調整し、通常・adaptive・monochrome resourceを作る。機能コードの本番更新とアイコン候補の作成は別の完了状態として扱う。

## 生成プロンプト

### 1 お皿とハーブ

Create ONE polished square Android launcher app icon for Recipe Cooking Navigator, a personal home-cooking recipe app. Concept 1: a welcoming ceramic dinner plate, top-down, slightly softly scalloped cream plate with one simple sage-green herb sprig and a small muted apricot food accent, paired with a bold deep-green fork tucked just beside the plate, composition reads instantly as home cooking. Intended audience: adult Japanese women managing everyday household meals, tasteful natural cafe style, warm and reassuring rather than childish. Full-bleed warm cream background #F7F5EE, deep forest green #365848, sage #A5B69A, a restrained warm apricot accent. Beautiful flat illustrated brand mark with subtle ceramic dimensionality, strong confident silhouette, generous empty space, few broad shapes, crisp clean edges, no tiny detail. One icon occupies the center 60 percent of a 1024x1024 square; all recognizable elements stay inside central circular safe area, ample margin for Android circular or rounded-square masks. Fill the ENTIRE canvas with background, do not draw a rounded-square tile, outer frame, surrounding mockup, phone, text, letters, labels, badges, watermarks, or UI. No photography, gradients, glossy 3D, flowers, human faces. Render the actual icon artwork only.

### 2 ほっとするお鍋

Create ONE polished square Android launcher app icon for Recipe Cooking Navigator, a personal home-cooking recipe app. Concept 2: a single cozy rounded enamel casserole pot with a cream body, terracotta lid and two tiny side handles, two broad deep-green curved steam strokes rising above. The lid is tilted slightly so a very small sage-green vegetable hint suggests freshly cooked meals. Intended audience: adult Japanese women managing everyday household meals, warm elegant Scandinavian kitchenware / natural cafe mood, endearing without cartoon faces. Full-bleed pale sage background #DCE6D9, warm cream #F7F5EE, deep forest green #365848 and restrained terracotta #C8876E. Beautiful flat illustrated brand mark with very subtle ceramic dimensionality, bold confident silhouette, crisp edges, very few broad shapes; legible at tiny launcher sizes. Single icon centered inside central 60 percent of a 1024x1024 square, ample margin for Android circular / rounded-square masks. Fill entire canvas with background; NO pre-rounded tile, border, surrounding mockup, phone, text, letters, labels, badges, watermark, gradients, glossy 3D, flowers or faces. Render the actual icon artwork only.

### 3 わたしのレシピ帳

Create ONE polished square Android launcher app icon for Recipe Cooking Navigator, a personal home-cooking recipe app. Concept 3: a closed sage-green recipe notebook with gently rounded corners in a simple slightly angled front view. Its cover contains ONE bold cream bowl-and-spoon symbol with a small rising steam stroke; a single muted apricot ribbon bookmark peeks from the lower edge. Immediately recognizable as a personal collection of cooking recipes, friendly and refined. Intended audience: adult Japanese women managing everyday household meals, natural cafe / home-lifestyle stationery, tasteful and calm without childishness. Full-bleed warm cream background #F7F5EE, sage-green book #8EAB89, deep forest-green outlines #365848, one restrained muted apricot accent. Beautiful flat illustrated brand mark, very subtle paper depth, crisp clean edges, balanced negative space, a few broad shapes, readable at 48 pixels. Single icon occupies central 60 percent of a 1024x1024 square, all distinctive elements inside central circular safe area with ample margin for Android masks. Fill entire canvas with background; NO pre-rounded tile, frame, scene, phone, mockup, text, letters, labels, badges, watermark, excessive linework, gradients, glossy 3D, flowers or human faces. Render actual icon artwork only.
