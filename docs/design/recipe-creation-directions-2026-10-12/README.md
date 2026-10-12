# レシピを作る — 3案比較と採用

2026-10-12、ユーザーの「やさしい感じ」「見た目の要素のグループ感」「メイン画面のイメージから離れすぎない」という依頼で作成。内蔵image_genで3回独立生成し、表示順と番号を対応させた。

| 表示順 | 画像 | 方向 |
|---|---|---|
| 1 | [01-soft-conditions.png](01-soft-conditions.png) | 白い条件カード・人数と時間を横に並べる |
| 2 | [02-recipe-notes.png](02-recipe-notes.png) | 余白と区切り線でまとめるレシピノート |
| 3 | [03-sage-group.png](03-sage-group.png) | セージ色で基本条件をまとめる |

ユーザーが3案目を明示採用した。実装の基準は03-sage-group.png。本と鍋の採用アイコンは ../app-icon-directions-2026-10-12/03-recipe-notebook-pot-v2.png。

採用案をFlutterへ反映し、Pixel 10aの本番版へ更新済み。[実装・検証記録](../../plans/recipe-creation-visual-implementation-2026-10-12.md)に変更範囲、端末更新、本人による最小確認をまとめた。

参照はメイン画面の01-natural-cafe-no-photo.pngと採用アイコン。参照画像を目視で確認し、3つのImage Genへ両方の実ファイルを添えた。作成画面のコード・製品仕様を確認し、接続済み、食材入力済み、こだわり閉、未生成の同じ状態で比較。基本条件、任意条件、別の作成方法、下部の主ボタンという既存の操作を保つ。Recipe / Feedback Schemaや生成処理の変更は対象外。幅390×高さ844の画面を想定し、生成画像は同じ縦横比の853×1844。

## 生成プロンプト

### 表示順1

Use case: ui-mockup. Create ONE realistic, production-quality mobile Android app screen for Recipe Cooking Navigator, focused on the existing recipe creation conditions form.
Reference image 1: the approved natural cream/deep-green main-screen design, a STYLE AND BRAND CONTINUITY reference. Reference image 2: the newly approved sage recipe-book/cooking-pot app icon, a BRAND reference. Both are moodboard references, not edit targets. Do not copy the home-screen recipe list. Design the creation form described below.
Target dimensions: 390 x 844 portrait logical viewport; output app content only, with this natural aspect ratio. No device bezel, phone, notch, status bar, clock, signal/battery, home indicator, browser chrome, external canvas, rounded device mask, presentation caption or mockup shadow. Exactly one screen and one design, not a collage.
Audience: Japanese adults preparing everyday home meals, especially women who want a calm, welcoming, easy-to-read recipe app. Stay very close to the main-screen family: warm ivory #F7F5EE, deep green #365848, pale sage #DCE6D9, warm white fields, dark neutral readable text, tiny optional muted terracotta accent from the selected icon. Restrained and mature, not cute cartoons or pink stereotypes.
Current product contract from lib/ui/ai_recipe_request_screen.dart: back navigation and title at top, a three-stage indicator below, compact ChatGPT connection state above input conditions, food ingredients plus numeric servings and time, optional preferences collapsed, alternative methods collapsed, a fixed full-width create action at bottom. Preserve this workflow and main button placement. Group existing inputs visually; do not introduce a wizard, new modes, preset choices, stepper +/- buttons, chat UI, new AI options, unrelated navigation tabs, illustrations of meals, stock food photos or nutrition/shopping/social features.
Show the SAME state as all comparison mocks: ChatGPT connected, conditions entered, optional preferences collapsed, keyboard closed, no errors, not yet generating.
Exact Japanese visible UI copy:
Header: "レシピを作る" and back chevron.
Small stage track: "条件" (current), "作成中", "内容確認".
Quiet connection row: "ChatGPT 接続済み" and "変更".
Short welcome line: "使いたい食材から、今日のひと皿を。"
Main group heading: "基本の条件".
Ingredient label: "食材"; editable input content: "なす、豚肉、玉ねぎ".
Servings label: "人数"; numeric input value: "2", unit "人分".
Time label: "調理時間"; numeric input value: "30", unit "分".
Secondary collapsible group: "こだわりを追加（任意）", secondary hint "器具・味つけ・その他の希望", downward chevron. Do not expose all optional fields in this initial mock. Voice input exists inside this optional group, do not add an extra standalone microphone action outside it.
A very quiet collapsed row below: "別の方法で作る", downward chevron.
Fixed footer helper: "入力した条件をChatGPTへ送ります".
Single primary CTA: "この条件でレシピを作る" in white on deep green. No competing large action. Footer is cream, no opaque dark giant nav block.
Readable Japanese Noto Sans-like rounded sans, logical body 14–16 px, labels 14–16, title 22, strong clear hierarchy, comfortable line height, generous whitespace. Inputs should look editable with ordinary touch targets. Use spacing, alignment, headings and subtle tint to group elements before borders and minimal elevation. No nested decorative cards. Do not advertise hidden features. Keep all core content and bottom CTA comfortably inside 844 height with no clipping or tiny print. Small simple library-style line icons can distinguish food/person/time; any book-pot mark must be very small, never a giant hero illustration.
Today is 2026-10-12 Asia/Tokyo. Do not put dates on this form.

Direction name: やわらかな条件カード.
Art direction: make this feel like the same warm rounded-card main screen. The visual center is ONE broad warm-white rounded 24px group for the three basic conditions. Put heading and ingredient field at top within it; pair the servings and time fields side by side below, aligned neatly, as two inputs within one group rather than separate cards. Standard thin light-beige outlined fields with 14px corners, very faint subtle shadow only on the outer basic group. Clearly prioritize ingredients, with a roomy multiline ingredient input; show values 2 and 30 clearly. Place the optional-preferences collapse row on a single pale-sage rounded horizontal surface below the basic group, with no nested cards. Keep the alternative-method row bare and understated. Use quiet deep-green section headings and cozy generous spacing. The composition should feel soft, stable, familiar to the cream/green home screen. Primary button is rounded 24px, tall about56px and spans usable width near bottom.

### 表示順2

Use case: ui-mockup. Create ONE realistic, production-quality mobile Android app screen for Recipe Cooking Navigator, focused on the existing recipe creation conditions form.
Reference image 1: the approved natural cream/deep-green main-screen design, a STYLE AND BRAND CONTINUITY reference. Reference image 2: the newly approved sage recipe-book/cooking-pot app icon, a BRAND reference. Both are moodboard references, not edit targets. Do not copy the home-screen recipe list. Design the creation form described below.
Target dimensions: 390 x 844 portrait logical viewport; output app content only, with this natural aspect ratio. No device bezel, phone, notch, status bar, clock, signal/battery, home indicator, browser chrome, external canvas, rounded device mask, presentation caption or mockup shadow. Exactly one screen and one design, not a collage.
Audience: Japanese adults preparing everyday home meals, especially women who want a calm, welcoming, easy-to-read recipe app. Stay very close to the main-screen family: warm ivory #F7F5EE, deep green #365848, pale sage #DCE6D9, warm white fields, dark neutral readable text, tiny optional muted terracotta accent from the selected icon. Restrained and mature, not cute cartoons or pink stereotypes.
Current product contract from lib/ui/ai_recipe_request_screen.dart: back navigation and title at top, a three-stage indicator below, compact ChatGPT connection state above input conditions, food ingredients plus numeric servings and time, optional preferences collapsed, alternative methods collapsed, a fixed full-width create action at bottom. Preserve this workflow and main button placement. Group existing inputs visually; do not introduce a wizard, new modes, preset choices, stepper +/- buttons, chat UI, new AI options, unrelated navigation tabs, illustrations of meals, stock food photos or nutrition/shopping/social features.
Show the SAME state as all comparison mocks: ChatGPT connected, conditions entered, optional preferences collapsed, keyboard closed, no errors, not yet generating.
Exact Japanese visible UI copy:
Header: "レシピを作る" and back chevron.
Small stage track: "条件" (current), "作成中", "内容確認".
Quiet connection row: "ChatGPT 接続済み" and "変更".
Short welcome line: "使いたい食材から、今日のひと皿を。"
Main group heading: "基本の条件".
Ingredient label: "食材"; editable input content: "なす、豚肉、玉ねぎ".
Servings label: "人数"; numeric input value: "2", unit "人分".
Time label: "調理時間"; numeric input value: "30", unit "分".
Secondary collapsible group: "こだわりを追加（任意）", secondary hint "器具・味つけ・その他の希望", downward chevron. Do not expose all optional fields in this initial mock. Voice input exists inside this optional group, do not add an extra standalone microphone action outside it.
A very quiet collapsed row below: "別の方法で作る", downward chevron.
Fixed footer helper: "入力した条件をChatGPTへ送ります".
Single primary CTA: "この条件でレシピを作る" in white on deep green. No competing large action. Footer is cream, no opaque dark giant nav block.
Readable Japanese Noto Sans-like rounded sans, logical body 14–16 px, labels 14–16, title 22, strong clear hierarchy, comfortable line height, generous whitespace. Inputs should look editable with ordinary touch targets. Use spacing, alignment, headings and subtle tint to group elements before borders and minimal elevation. No nested decorative cards. Do not advertise hidden features. Keep all core content and bottom CTA comfortably inside 844 height with no clipping or tiny print. Small simple library-style line icons can distinguish food/person/time; any book-pot mark must be very small, never a giant hero illustration.
Today is 2026-10-12 Asia/Tokyo. Do not put dates on this form.

Direction name: すっきりしたレシピノート.
Art direction: make the app feel like a calm cream recipe notebook, harmonizing with the approved recipe-book icon. Distinguish groups through typography, whitespace and thin horizontal sage rules, rather than floating card boxes. No notebook rings or decorative book illustration. Basic heading has a small sage vertical marker and a light divider, ingredient input is a generous warm-white text area with a clean fine underline. Stack the servings and time controls in separate full-width aligned rows below, label left, white editable numeric area plus units at right, separated by hairline rules. This stacked editorial form is visibly different from the paired controls in the card direction. Keep the whole page on the cream base surface with flat styling, airy margins, fewer outlines and no shadows. Optional preferences appear as a clearly grouped flat section with a small light-sage heading strip and hint, collapsible, separated from required conditions by substantial whitespace. Use dark forest-green typography and tiny muted terracotta accent only if useful. Maintain the usual fixed green primary CTA at bottom.

### 表示順3・採用

Use case: ui-mockup. Create ONE realistic, production-quality mobile Android app screen for Recipe Cooking Navigator, focused on the existing recipe creation conditions form.
Reference image 1: the approved natural cream/deep-green main-screen design, a STYLE AND BRAND CONTINUITY reference. Reference image 2: the newly approved sage recipe-book/cooking-pot app icon, a BRAND reference. Both are moodboard references, not edit targets. Do not copy the home-screen recipe list. Design the creation form described below.
Target dimensions: 390 x 844 portrait logical viewport; output app content only, with this natural aspect ratio. No device bezel, phone, notch, status bar, clock, signal/battery, home indicator, browser chrome, external canvas, rounded device mask, presentation caption or mockup shadow. Exactly one screen and one design, not a collage.
Audience: Japanese adults preparing everyday home meals, especially women who want a calm, welcoming, easy-to-read recipe app. Stay very close to the main-screen family: warm ivory #F7F5EE, deep green #365848, pale sage #DCE6D9, warm white fields, dark neutral readable text, tiny optional muted terracotta accent from the selected icon. Restrained and mature, not cute cartoons or pink stereotypes.
Current product contract from lib/ui/ai_recipe_request_screen.dart: back navigation and title at top, a three-stage indicator below, compact ChatGPT connection state above input conditions, food ingredients plus numeric servings and time, optional preferences collapsed, alternative methods collapsed, a fixed full-width create action at bottom. Preserve this workflow and main button placement. Group existing inputs visually; do not introduce a wizard, new modes, preset choices, stepper +/- buttons, chat UI, new AI options, unrelated navigation tabs, illustrations of meals, stock food photos or nutrition/shopping/social features.
Show the SAME state as all comparison mocks: ChatGPT connected, conditions entered, optional preferences collapsed, keyboard closed, no errors, not yet generating.
Exact Japanese visible UI copy:
Header: "レシピを作る" and back chevron.
Small stage track: "条件" (current), "作成中", "内容確認".
Quiet connection row: "ChatGPT 接続済み" and "変更".
Short welcome line: "使いたい食材から、今日のひと皿を。"
Main group heading: "基本の条件".
Ingredient label: "食材"; editable input content: "なす、豚肉、玉ねぎ".
Servings label: "人数"; numeric input value: "2", unit "人分".
Time label: "調理時間"; numeric input value: "30", unit "分".
Secondary collapsible group: "こだわりを追加（任意）", secondary hint "器具・味つけ・その他の希望", downward chevron. Do not expose all optional fields in this initial mock. Voice input exists inside this optional group, do not add an extra standalone microphone action outside it.
A very quiet collapsed row below: "別の方法で作る", downward chevron.
Fixed footer helper: "入力した条件をChatGPTへ送ります".
Single primary CTA: "この条件でレシピを作る" in white on deep green. No competing large action. Footer is cream, no opaque dark giant nav block.
Readable Japanese Noto Sans-like rounded sans, logical body 14–16 px, labels 14–16, title 22, strong clear hierarchy, comfortable line height, generous whitespace. Inputs should look editable with ordinary touch targets. Use spacing, alignment, headings and subtle tint to group elements before borders and minimal elevation. No nested decorative cards. Do not advertise hidden features. Keep all core content and bottom CTA comfortably inside 844 height with no clipping or tiny print. Small simple library-style line icons can distinguish food/person/time; any book-pot mark must be very small, never a giant hero illustration.
Today is 2026-10-12 Asia/Tokyo. Do not put dates on this form.

Direction name: セージのまとまり.
Art direction: emphasize a clear single pale-sage large rounded group spanning the basic conditions; sage acts as the welcoming continuous section background and is visibly more present than in the other directions. Heading at top of this group, then ingredient input as a wide warm-white rounded editable area; below it show two vertical compact full-width rows for servings and time, each with a small deep-green line icon, label left and a white rounded numeric editable capsule plus unit aligned right. These are ordinary fields on the SAME group surface, not multiple independent floating cards. Number values are larger 22px and easy to identify. No heavy borders or shadows; clean block hierarchy from sage background, warm-white inputs and cream page gutters. The optional collapse group is a separate flat warm-white horizontal group below with generous space, connecting cue from small simple chevron and sage heading text, not a big decorative card. Keep connection row and progress quieter than the form. Make the composition feel warm, clear and less clinical, using consistent 24px outer corners and soft precise spacing, with the fixed dark-green CTA anchored at bottom.
