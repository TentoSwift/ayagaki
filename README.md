# 綾書エディタ — 二枚安田組

組紐（高台・二枚安田組）の綾書（あやがき）をブラウザ上で設計できるエディタです。

**▶ 使う： https://tentoswift.github.io/ayagaki/**

## 機能

- 綾書グリッド（60玉＝片面15目 / 68玉＝片面17目、段数可変）をタップ・ドラッグで塗って模様を設計
- 塗った模様から段ごとの交換記号（ナミn／上n）を自動生成
- 仕上がりプレビュー（2リピート表示）
- ブラウザへの自動保存、名前を付けて保存、JSON 書き出し / 読み込み、印刷・PDF 出力

## 記号の読み方

- **ナミn** … n目そのまま組む
- **上n** … 色糸をn目交換して表に浮かせる

※記号体系は簡易版です。お手持ちの綾書資料と突き合わせて読み替えてください。

## ネイティブアプリ（macOS / iOS / iPadOS）

`apple/` に SwiftUI 製のネイティブアプリがあります（iOS 16+ / macOS 13+）。

- デザインは Core Data + CloudKit（`NSPersistentCloudKitContainer`）で保存し、iCloud で端末間同期
- Web 版と同じ JSON 形式の書き出し / 読み込みに対応（Web ↔ アプリでデザインを行き来できる）
- PDF 手順書の書き出し
- **MCP サーバ内蔵（macOS 版）**: `127.0.0.1:53536/mcp` で待機し、Claude などの MCP クライアントから
  デザインの作成・塗り・交換記号の取得ができる
  （登録例: `claude mcp add --transport http ayagaki http://127.0.0.1:53536/mcp`）

```bash
cd apple
xcodegen generate   # Ayagaki.xcodeproj を生成
# スキーム: Ayagaki-iOS / Ayagaki-macOS
```

## 開発（Web 版）

単一の `index.html`（依存ライブラリなし）。ローカルで開くだけで動きます。
