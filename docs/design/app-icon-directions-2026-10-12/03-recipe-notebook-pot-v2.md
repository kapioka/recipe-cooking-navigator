# 3案目の表紙を鍋へ変更 — v2

ユーザーの依頼: 3案目の本の中のお茶碗・スプーンを、2案目の鍋をもとにした自然なピクトグラムへ変更。

成果物: [03-recipe-notebook-pot-v2.png](03-recipe-notebook-pot-v2.png)

本の形・配色・背景・しおりを保ち、表紙の記号を変更した。鍋は蓋を本体に収め、丸みのある両手鍋の形を簡略化。元の3案は保持する。画像を目視確認し、鍋への置換と本の構成の維持を確認した。本番launcherへの適用はまだ行っていない。

内蔵image_genで編集。入力1は03-recipe-notebook.png（編集対象）、入力2は02-cozy-pot.png（鍋の形の参照）。

## 編集プロンプト

Use case: precise-object-edit.
Asset type: revised launcher icon concept for Recipe Cooking Navigator.
Input image 1 is the EDIT TARGET: the sage-green recipe notebook on cream background. Input image 2 is a SUBJECT REFERENCE ONLY: the cozy cream casserole pot with terracotta lid.
Primary request: keep the notebook icon from image 1 and replace ONLY the bowl, spoon and existing steam emblem printed on its cover with a natural-looking, simplified pictogram of the casserole pot from image 2.
Preserve image 1's book shape, orientation, placement, size, sage-green cover, deep-green edge outlines, cream paper pages, warm apricot ribbon bookmark, subtle paper texture, cream background and square composition. Do not redesign the book.
The new cover emblem should be a clean flat pictogram printed onto the same angled cover plane, NOT a separate 3D object standing on the book. Show a low rounded cream enamel cooking pot, two short balanced loop handles, a gently domed terracotta lid seated naturally on the rim and a small simple knob. The pot should have believable everyday kitchenware proportions: wider than tall, restrained curves, handles connected to the body. Use a consistent deep forest-green outline matching the book. Simplify the reference into just a few broad shapes with a quiet warm terracotta accent on the lid. Add two small, thin, gently rising curved steam strokes above the pot; these must read as wisps of steam, NOT flames, leaves or oversized decorative waves. Omit visible vegetables, food, shiny highlights and detailed shading. Keep the pictogram centered on the book cover and fit it within the space of the former emblem with comfortable breathing room.
Mood: warm natural home cooking, understated and refined, friendly to adults, crisp and readable at small launcher sizes.
Change ONLY the cover emblem. Remove the original bowl and spoon entirely. No text, letters, watermarks, extra objects, badges, borders, phone mockups or background changes. Preserve the existing opaque background.
