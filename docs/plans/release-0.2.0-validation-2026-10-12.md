# 0.2.0 統合・公開検証 — 2026-10-12

## 対象と正本

採用済みの画面・アイコン・料理写真・レシピ作成改善と、Issue #14 / Draft PR #15の最新版切替をまとめる。PR #15のheadは `251601c0fceb52c8a547a121abc633991503e93a`。公開main `8bc338da1cecfa38387d462b7f7ec592ab00cf2b` を基点に、新しいホームの見た目を保って対象2ファイルの変更を取り込んだ。

Issue #8のGitHub本文は初期調査時の記録。統合PR #13と現在の実装・端末結果を合わせて判断し、未実施項目を成功扱いしない。PoCを端末に再インストールせず、本体の正式署名APKで確認する。

## 機械検証

- formatter: 106ファイル、変更なし。
- 本体analyze: No issues found。
- 本体unit / widget tests: **244件成功**。
- 共通SIWC adapterを使うPoC tests: **23件成功**。PoCのテスト実行は別PoCアプリの配布・端末更新を意味しない。
- PoC analyze: No issues found。
- 最新版切替の追加テスト: 一覧・active保存の反映、過去Revision保持、調理途中データの完全一致、最新版での無効化と追加書込なし、保存失敗時の旧active・表示・保存済みRecipe維持。
- 既存SIWC tests: 音声・編集時の未送信、キャンセル後の回答破棄、改善元ID / parent / next_revision検証、保存失敗、権限不足、SSE完了、refresh直列化、更新後のscope減少、接続解除失敗時の端末token削除など。
- `tool/build-release.ps1 -PublicAiV2Ready`: 成功。公開AI v2契約7ファイルを照合、正式署名・zipalign・非debuggableを確認。

## 実機で確認した結果

Pixel 10a / Android 17。本体package `com.kapioka.recipe_cooking_navigator` をversionName 0.2.0 / versionCode 2へ `adb install -r` で更新した。既存APKとの署名証明書SHA-256一致を確認している。

1. 検証専用のRecipe IDでVersion 1・2を共有受信。内容確認後だけ保存できた。
2. Version 1の工程2で中断し、ホームの「最新版レシピに変更」でVersion 2へ切替。詳細に「使用中の版 2」、履歴2件、Version 1の途中位置を確認した。
3. 「続きから」でVersion 1 / 工程2へ戻れた。最新の通常表示と途中の調理Versionを混同しない。
4. 検証専用Version 1に調理完了記録を作り、履歴からそのVersionの評価・改善画面を開いた。実際の料理品質や安全性の評価を意味しない。
5. アプリ更新・cold start後、端末に保存したChatGPT接続を読み込み、公開モデル一覧を取得して改善画面が接続済みになった。
6. 本人が「塩分を少し控えめにしたい」と音声入力し、認識文が編集可能な欄へ入ったことを確認。送信前の条件画面と入力内容をUI hierarchyでも確認した。
7. GPT-6.1-Solへの送信は1回時間切れとなった。条件画面へ戻り、入力を保持し、未完了のRecipeを保存しなかった。モデルをGPT-6-Lunaへ変更した再試行では、Version 1を親とする第3版が内容確認へ返り、明示操作で保存できた。同一Recipe ID、parent_revision 1、revision 3を検証し、過去2版と使用中の第2版は維持した。この1回の結果からモデル全体の安定性や時間切れの原因を断定しない。
8. 保存後にアプリを終了して起動し直し、使用中の第2版と「新しい版があります」の表示が残った。端末そのものの再起動は行っていない。
9. 本人が同じChatGPTアカウントで接続し直し、「アプリに戻る」まで完了した。アプリの接続済み表示とモデル選択欄も確認した。

検証操作には専用Recipeを用い、本人の既存Recipe・評価・Profileを変更しない。UI hierarchy、APK、診断logはローカル検証資料として扱い、Gitに含めない。

## 実機確認を残す項目

認証キャンセル、期限切れ、利用枠上限、複数アカウント、同意拒否、通信断のすべてをこの端末で再現したとは扱わない。機械テストと実際のサービス・OSの結果を分ける。

調理雑音下の音声認識精度、TalkBack、長時間点灯、Kitchenの背景動作、Profile実運用、全画面の最終的な見た目は別の未確認項目。Issue #8を全完了として閉じない。
