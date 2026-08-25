# eigo-note-iOS

英語メモノート（サービス名 `phremo`）の iOS アプリ。iPhone / iPad の Universal app として
1ターゲットで作る（iPad は別アプリではない）。Apple Silicon Mac でもそのまま動く。

## このリポジトリの位置づけ

サーバー（API・DBスキーマ・Web画面）は別リポジトリにある。

| | リポジトリ | ローカル |
|---|---|---|
| サーバー + Web | [nakatayoshihiro/eigo-note](https://github.com/nakatayoshihiro/eigo-note) | `英語メモノート/app/` |
| iOS（ここ） | nakatayoshihiro/eigo-note-iOS | `英語メモノート/ios/` |

このアプリ自身はデータを持たず、上のサーバーの API を叩く。
**API を変更するときは必ず両方のリポジトリを同時に見ること。**

## 接続先

| 環境 | ベースURL |
|---|---|
| 本番 | https://phremo.com |
| dev | https://eigo-note-dev.nakata-dev.workers.dev |

## 開発環境

- Xcode 26.6 / iOS SDK 26.5 / Swift 6.3
- Minimum Deployment: iOS 18.0
- Interface: SwiftUI

## リポジトリに入れないもの

署名まわり（`.p12` / `.p8` / プロビジョニングプロファイル）と App Store の提出物は
リポジトリ外に置く。

- `英語メモノート/ios-signing/` — 証明書・鍵
- `英語メモノート/ios-store/` — スクリーンショット・審査メモ
