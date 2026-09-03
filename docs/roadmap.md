# ロードマップ

## Phase 0 — Specification

現在の段階。

- [x] 製品目的を定義
- [x] Recipe / Cook Session / Evaluationを分離
- [x] Recipe Schema v1を定義
- [x] Feedback Schema v1を定義
- [x] ChatGPT共有フローを定義
- [x] サンプルJSONを用意
- [ ] 実機での共有フローを検証
- [ ] MVP画面構成を確定

## Phase 1 — Android MVP

### Import / storage

- [ ] Android SharesheetからRecipe JSONを受信
- [ ] Schema validation
- [ ] ローカル保存
- [ ] レシピ一覧
- [ ] レシピ詳細

### Pre-cook view

- [ ] 材料一覧
- [ ] 全体工程
- [ ] 器具一覧 / 使い回しメモ
- [ ] 事前準備チェック

### Cooking mode

- [ ] 1工程表示
- [ ] 前へ / 次へ
- [ ] 工程ごとの材料・分量表示
- [ ] 火加減 / 完了判断
- [ ] 次工程予告
- [ ] タイマー
- [ ] Cooking mode中の画面常時点灯

## Phase 2 — Feedback loop

- [ ] Cook Session保存
- [ ] 実難易度1〜5
- [ ] 総合評価1〜5
- [ ] 味の偏り -2〜+2
- [ ] 実際の変更点
- [ ] 困ったこと
- [ ] 次回希望
- [ ] Feedback JSON生成
- [ ] SharesheetからChatGPTへ共有
- [ ] 修正版Recipeの再import
- [ ] Revision履歴表示

## Phase 3 — Usability improvements

実利用で必要性が確認されたものだけ追加する。

候補：

- 音声「次へ」「戻る」
- 音声タイマー
- 文字サイズ / 高コントラスト
- 片手操作向け大型ボタン
- Recipe revision差分表示
- ローカルバックアップ / export
- タブレット最適化

## Phase 4 — Optional intelligence

MVPとFeedback loopが安定してから評価する。

候補：

- 複数Cook Sessionからの嗜好傾向分析
- Preference Profile
- 複数料理の並行調理支援
- 買い物リスト
- 手持ち材料との照合
- OpenAI API等の直接統合

## Non-goals until justified

次は「将来必要そう」という理由だけでは追加しない。

- 専用バックエンド
- ユーザーアカウント
- SNS
- レシピランキング
- サブスクリプション
- カメラ常時監視
- 複雑なAgent構成
- 大規模推薦基盤

## Development rule

各Phaseは前段の利用上の問題を確認してから拡張する。

機能数ではなく、次の摩擦が減ったかを評価する。

- スクロールや戻り操作
- 次工程の見落とし
- 分量確認の迷い
- 調理器具の無駄
- 待ち時間の無駄
- 画面消灯による中断
- 次回へ改善内容が残らない問題
