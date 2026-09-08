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

Android固有APIを使う場合も、アプリは端末の画面回転設定を所有しない。`accelerometer_rotation`と`user_rotation`へ書き込まず、manifest、Activity、Flutter runtimeから端末の向きを永続的に変更しない。起動前、起動中、終了後で両設定が同一であることを各Android実機milestoneの受入条件にする。

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

Android MVPの実装技術はFlutterとする。

Androidのapplication IDは`com.kapioka.recipe_cooking_navigator`とする。

当面はAndroidだけを対象に実装する。将来iPhone版へ進む場合に主要ロジックを再利用できるよう、Recipe / Feedback / Version / Cook Session / EvaluationなどのOS非依存ロジックはDartのドメイン層へ置き、音声認識、TTS、ファイル、共有、画面常時点灯などのOS連携から分離する。

Flutterの採用はiOS実装の開始を意味しない。Android版の完成と実利用評価までは、iOS UI、iOS固有機能、iOS向けCIを追加しない。

選定理由:

1. Androidで先行開発できる
2. Recipe / Feedback / Version管理ロジックを将来iOSでも再利用しやすい
3. 音声認識、TTS、OS共有、ファイルI/O、画面常時点灯をplatform layer経由で扱える
4. 特定クラウドやバックエンドを必須にしない

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
