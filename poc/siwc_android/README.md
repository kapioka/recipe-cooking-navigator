# Recipe SIWC Android PoC

独立した検証アプリ。既存Recipe Cooking Navigatorのデータにはアクセスしない。
公式SIWCの実機OAuth・テキスト推論は後日の確認待ち。

[契約・調査・機械検証と実機手順](../../docs/plans/issue8-siwc-research-and-qa.md)

repository rootで`tool/siwc-poc.ps1`を使う。debug APKだけを検証用にbuildする。
APIキー、既存Codex token、非公開ChatGPT backendは使用しない。
