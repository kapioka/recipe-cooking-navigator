# Phase 8 明示登録とProfile書戻しの設計

2026-10-04。Astraの限定read-onlyレビューとMainのAPI調査を踏まえた変更案。ユーザー承認により、immutable履歴をDriveの正本に変更する方針を採用した。既存の163テスト・Androidビルド済みチェックポイントは保持する。

## 先に進めるローカル実装

目的は、評価を3回蓄積しなくても、ユーザーが明示した好みを確認して登録できる状態。自動候補のしきい値やscopeは変更しない。

現Profile 1.0のPreferenceはFeedback IDを必須とし、storeは空Profileから候補承認だけで全履歴を再現している。架空Feedbackを作ると根拠が失われるため、別の由来を表現する。

- 新たにProfile `1.1.0` Schemaを追加する。旧1.0 Schemaは変更せず、新readerは両方を受け入れる。
- 1.1の由来は`feedback` / `explicit_user`。前者は規則versionと根拠Feedback IDを必須、後者はユーザーの明示文と確認日時を必須とし、Feedback IDやscoreを作らない。
- ProfileのID・revisionと過去snapshotを維持する。最初の明示登録時に現在のPreferenceの由来を補った1.1 Profileを新revisionとして追加する。過去の1.0 snapshotは変更しない。
- storage v2は候補承認／却下、明示登録を順序付き操作履歴として再生する。承認した変更だけがrevisionを増加させ、却下はProfileを変更しない。
- 旧storage v1は現在の厳格な検証を通した後に変換する。承認時刻は保存済みのProfile更新時刻を使い、存在しない却下日時は捏造しない。最初の更新時に旧原文を別ファイルへ保存して保持する。
- 同じscope・dimensionの既存値と変更後を確認できる画面を用意し、確認時に更新元revisionを照合する。
- rollbackは保存した旧原文とGit差分を使う。旧アプリがv2を読めるとは扱わず、未知形式は拒否する。

関連変更は新Schema・例、Dart Profile・操作履歴・store・cache、明示登録画面、mainのSchema接続、data-model / roadmap。Recipe / Feedbackの共有Schema、Inbox、健康や宗教の推論は変更しない。

Acceptanceは1.0/1.1 Schema、旧store移行・再読込、候補承認／却下／明示登録の混在再生、stale revision拒否、原本保持、破損・中断での拒否、画面での確認・取消、既存回帰、analysis・build。端末確認は後日。

## Drive書戻しの判断点

現契約は`Profile/cooking-profile.json`を確定Profileの正本とする。しかし使用中のSAF APIはexpected revision/digestを渡す更新を提供していない。renameでdocument IDが変わる場合があり、書込modeの動作もprovider依存と明記されている。そこから、単純な再読取・rename・lockfileで原子的な競合制御を保証できるとは判断できない。[DocumentsContract](https://developer.android.com/reference/android/provider/DocumentsContract)、[ContentResolver](https://developer.android.com/reference/android/content/ContentResolver)。

| 方式 | 成果・必要な変更 |
|---|---|
| 現在ファイルを正本に維持 | 現契約を保つ。保証できる条件付き更新手段が導入されるまで確定書戻しは保留する |
| immutable履歴を正本に変更（推奨案） | 更新元digestを持つrevision documentを追記し、分岐は両方残して競合表示する。`cooking-profile.json`を配布用の派生物へ変更し、アプリ・Workのreader契約を更新する |

推奨案のフォルダ案:

```text
Profile/
  History/<profile_id>/<operation_id>.json  # 未変更のProfile更新document
  cooking-profile.json                     # 再生成可能な互換用snapshot
```

更新documentにはoperation ID、更新元Profileとdigest、更新後Profileとdigest、承認した操作を含める。同じ操作の再送は同ID・同内容のみ。同じparentの異なる更新は両方保持し、勝者を日時で選ばない。readerは履歴を検証し、分岐・欠落・改変があれば最後の有効な状態を保持して更新を止める。

これは上書きによる消失を避ける契約変更であり、遅延したprovider表示から世界で唯一の最新を保証するものではない。snapshotだけを読んで確定する旧Work運用は対応が必要。ローカルProfileを異なるremote Profileへそのまま移植せず、検証済みremoteを更新元にした変更だけを扱う。

新OAuth・専用バックエンドや、競合保証を緩める単一writerの仮定は今回追加しない。履歴を正本とする契約へアプリ・Workのreaderを段階的に更新する。承認済み変更の追記だけを実装する中間段階も、Phase 8の確定書戻し完了とは扱わない。


## 実装到達点

明示登録・Profile 1.1・storage v2移行、immutable HistoryのSchema・ドメイン・Android読取と追記、承認前後の表示、remote head照合、確認待ち送信の永続化と同ID再確認まで実装した。開始記録は確認したlegacy Profileまたは新しい空Profile。確定したremoteのIDを保ち、選択した変更だけを適用する。candidate更新は根拠Evidenceを含めremoteの過去承認とともに再集計する。

物理名は`History/profile-<profile_idのSHA-256>/record-<record_idのSHA-256>.json`。既存のsnapshotは書き換えない。Workの実運用接続、snapshot再生成、分岐解決UIとPixelのprovider確認は残る。Phase 8全体の完了ではない。
