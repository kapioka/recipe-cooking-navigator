# プラットフォーム方針

## 1. 結論

当面はAndroid版だけを実装する。

Android版の完成・実利用評価後に、Mac購入を含めてiPhone版へ進むか判断する。

ただし、将来のiPhone対応を不必要に難しくしないよう、データ契約と主要ドメインモデルは最初からAndroid/iOS共通で設計する。

## 2. Android firstの理由

- 現在の実機検証環境がAndroid中心
- APKで開発版を直接検証しやすい
- 調理中の音声操作、TTS、画面常時点灯、共有フローを実生活で先に評価できる
- iOS用Mac/Xcode環境への投資前に、製品としての実用性を確認できる

## 3. iPhoneは最終到達点に含める

iPhone版は「Android版とは別製品」ではなく、同じRecipe Cooking Navigatorの別プラットフォームとして扱う。

共通にするもの:

- Recipe Schema
- Feedback Schema
- Recipe ID / Revision lineage
- latest / active Versionの意味
- Cook Session
- Evaluation
- 味評価 -2〜+2
- 一言メモ
- ChatGPT改善フロー
- 調理前情報構造
- Cooking modeのStep概念
- タイマーのユーザー起動原則
- 音声操作の意味
- TTS読み上げ対象
- SNS共有データ
- ポータブルRecipe / backupの意味

## 4. OS固有にしてよいもの

次はplatform layerへ隔離する。

### Android

- Sharesheet受信 / 送信
- Androidファイル選択
- 画面常時点灯API
- Android音声認識 / TTS
- 通知 / タイマー実装
- Android URI / permission

### iOS

- Share Sheet / Files連携
- iOSファイル選択
- idle timer制御
- Speech framework等の音声認識
- AVSpeechSynthesizer等のTTS
- iOS notification / timer
- security-scoped resource等のiOS固有ファイルアクセス

OS固有識別子やローカルURIをRecipe / Feedback Schemaへ混ぜない。

## 5. 実装技術

クロスプラットフォーム技術を優先候補とするが、現時点では最終決定しない。

候補例:

- Flutter
- その他、Android/iOS共通ロジックを保ちつつ音声・ファイル・共有のネイティブ連携が可能な構成

技術選定時の優先条件:

1. Androidで先行開発しやすい
2. Recipe / Feedback / Version管理ロジックをiOSでも再利用しやすい
3. 音声認識とTTSへ安定してアクセスできる
4. OS共有機能とファイルI/Oを扱える
5. 画面常時点灯を制御できる
6. 特定クラウドやバックエンドを必須にしない
7. 将来の保守負担が過大にならない

## 6. Android完成までiOSでやらないこと

- iOS UI実装
- IPA配布準備
- App Store申請
- Apple Developer Program加入を前提とした作業
- Mac購入
- iOS固有CI
- iOS実機購入を前提とした設計拡張

Android実装の都合だけで共通データ契約を壊さないことは継続する。

## 7. iPhone decision gate

Android版が次を満たした後に判断する。

- 日常の料理で継続利用できる
- Recipe import → 調理 → 評価 → ChatGPT改善 → 再importの循環が成立する
- 音声操作が実用レベル
- TTS読み上げが実用レベル
- Version履歴と過去Versionへの復帰が破綻しない
- 外部SNS共有とRecipe exportの責任境界が成立する
- データ消失リスクへ最低限のbackup/export方針がある

その時点で次を評価する。

- iPhone版の需要
- Mac購入費用と用途
- iOS固有実装の残量
- iPhone実機の入手またはTestFlight協力者
- App Store公開の必要性
- Apple Developer Program費用を負担する価値

## 8. iOSテスト方針

Mac/Xcodeを導入した場合、SimulatorでUI・データ・一般ロジックを確認できる。

ただし本アプリは音声認識、TTS、調理中の雑音環境、画面常時点灯、OS共有など実機依存が大きいため、最終公開前はiPhone実機で検証する。

自分でiPhoneを所有しない場合はTestFlight等による協力者テストを選択肢とする。

## 9. Portable dataの役割

Android先行であってもRecipeとFeedbackはOS非依存にする。

将来は次を目標にする。

```text
Androidで作成・保存したRecipe
        ↓
ポータブルRecipe / backup
        ↓
iPhone版で取り込み
```

これにより、iPhone版追加時にユーザーデータを作り直す必要をなくす。

## 10. Stop rule

Android版がまだ実用性を証明していない段階では、iOS対応のためだけに大規模な抽象化、CI、Mac環境、Apple向け公開作業を追加しない。

一方で、Android実装時にOS非依存で済むRecipe / Feedback / Version / EvaluationロジックへAndroid固有APIを直接埋め込まない。
