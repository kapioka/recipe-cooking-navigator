# 最新版ソースと公開範囲 — 2026-10-31

## 今回の反映対象

- 開発版: `0.2.6 (8)`、package `com.kapioka.recipe_cooking_navigator`。
- ソースcommit: `f939b70d04ffb445b4ec6cd36322f39c24eeeac4`。
- ブランチ: `codex/restore-current-ui-and-sharing`。土台はmain `fadcd8a4fe57256998bde18a3f314615e642fae2`。
- 生成失敗時の明示的な形式修正、直近の拒否回答の端末内復元、未対応形式の更新案内、評価なしの選択Version再作成。
- 既存SSEを使う受信状況・経過時間表示、下準備からの点灯と共有チェックリスト。
- 既存UIを維持した選択Versionのコピー・共有、作業文とコツ・失敗対策の別表示。

旧`codex/issues-7-8-ai-integration`の未整理差分を最新版として再公開しない。復元元の識別と経緯は[インストール元の復元記録](installation-source-recovery-2026-10-25.md)を参照する。

今回はソースと残作業を作業ブランチ・Draft PRへ反映する。mainへのmerge、tag、新しいGitHub Release、APKアップロード、端末更新は含めない。配布中のReleaseは`v0.2.1`のまま。

## 検証

- formatter: 本体・tests・共有SIWC package・PoC testsの132ファイル、変更なし。
- 本体と独立PoCの静的解析: 指摘なし。
- 本体302テスト、独立PoC26テスト: すべて成功。
- 本体Android debug APK: build成功。
- 既存の正式署名APK: 署名有効、zipalign済み、debuggableではないこと、package、`0.2.6 (8)`を確認。今回、新しい正式署名APKは生成していない。
- 既存正式署名APKのSHA-256: `1958509d7f8da2c44fbd4cffd7891c9f34ab95359bee8e36214091b1eeff3428`。
- stagedの秘密情報検査: 指摘145件を確認。Flutter Key、公開認証endpoint、実行時変数、テスト内で生成する鍵などの誤検出。秘密値・鍵ファイルの公開なし。

## 残作業

User device/manual acceptance: pending。

1. 保存済みレシピの詳細・履歴からコピー/共有し、選択Versionの原本が渡ることを確認する。人数変更中も、原本の基準人数を渡す想定。
2. 過去Versionから「ChatGPTで調整」を実行し、新Versionを確認保存する。元Version・使用中Version・途中位置が残ることを確認する。
3. 生成中の回答待ち→受信中→形式確認、形式不正後の明示的な作り直し、再起動後の拒否回答復元を実際の往復で確認する。
4. 調理開始で下準備が開き、点灯・背景復帰・終了時解除が期待どおりか確認する。チェックと「続きから」の途中位置も確認する。
5. コツ欄を開かずに調理を進められること、実際の生成文が読みやすいことを確認する。実料理、音声品質、Kitchen通知・背景動作、Profile/Drive実運用の残件はroadmapの各領域で管理する。

不具合時はアプリの版番号、対象画面、選択Version、操作、表示されたエラーを記録する。秘密情報やレシピ履歴全体は送らない。

次の最小作業は、このDraft PRの差分確認と上記の対象を絞った実機確認。main統合・新Releaseはそれぞれの明示承認と配布条件を満たしてから行う。
