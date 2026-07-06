# CLAUDE.md — 綾書エディタ（Ayagaki）

組紐（高台・二枚安田組）の綾書を設計するアプリ。Web 版 + macOS/iOS/iPadOS ネイティブ + MCP サーバ内蔵。
題材はユーザー所有の組紐書籍（4-4〜4-15、60玉/68玉二枚安田組）。**書籍との一致が正**。

## 構成

```
index.html              Web 版（単一ファイル・依存なし）。GitHub Pages: https://tentoswift.github.io/ayagaki/
apple/                  ネイティブアプリ（XcodeGen 管理）
  project.yml           ターゲット: Ayagaki-iOS (iOS16+) / Ayagaki-macOS (macOS13+)
  Shared/               ソース共有。BraidModel.swift が仕様の中心
  Shared/MCP/           MCP サーバ（HTTP + stdio）
docs/notation-reference.md  書籍 4-15「四角」の転記（正解データ）と手取り機構（4-4〜4-8）の要約
scripts/test-notation.py    記号生成の回帰テスト（4-15 全4例と突き合わせ）
```

## ビルド・デプロイ（macOS）

```bash
cd apple && xcodegen generate   # 初回・project.yml 変更時
xcodebuild build -project Ayagaki.xcodeproj -scheme Ayagaki-macOS -configuration Release \
  -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates -derivedDataPath macbuild
# /Applications へ設置（アプリ終了→差し替え→起動）
pkill -f "Ayagaki.app/Contents/MacOS/Ayagaki"; rm -rf /Applications/Ayagaki.app
ditto macbuild/Build/Products/Release/Ayagaki.app /Applications/Ayagaki.app
open /Applications/Ayagaki.app
# 回帰テスト（要 /Applications/Ayagaki.app）
python3 scripts/test-notation.py
```

- チームID LV3H7Q68W6、バンドルID com.tento.ayagaki、iCloud コンテナ iCloud.com.tento.ayagaki
- デザインは Core Data + NSPersistentCloudKitContainer で **iCloud 同期**（同じ Apple ID の Mac/iOS 間で共有される）
- ⚠️ シミュレータで `CODE_SIGNING_ALLOWED=NO` にすると CloudKit 初期化がクラッシュ（署名ありでビルドする）

## MCP（Claude / Codex からデザイン操作）

- 登録（stdio・アプリ起動不要）: `claude mcp add ayagaki -- /Applications/Ayagaki.app/Contents/MacOS/Ayagaki --mcp`
  / Codex: `codex mcp add ayagaki -- /Applications/Ayagaki.app/Contents/MacOS/Ayagaki --mcp`
- アプリ起動中は HTTP も可: `http://127.0.0.1:53536/mcp`
- ツール10個: list/get/create/update_design, paint, set_cells, get_notation, export_pdf, clear_cells, delete_design
- ⚠️ stdio で viewContext（main キュー + dispatchMain）に保存するとデッドロック → 専用バックグラウンドコンテキスト + DesignStore の performAndWait で解決済み。⚠️ SwiftUI ImageRenderer はヘッドレスで永久ハング → PDF は PDFSheetRenderer（CoreGraphics 直描き）

## 仕様（書籍と照合済みの規則）

- グリッド: 片面13目（60玉）/15目（68玉）× 段数。目盛りは **1=中央 … 13/15=外端**（綾書定規 4-10/4-11）
- 右半面は d=0 が中央線上・1目(c)下がる配置で左右が隙間なく連続（書籍 4-14 の左右1段ずれ）
- 記号 = [糸交換の数字] + [綾名] + [⬆]：
  - **綾名**: 1目おきの「入れかえの目」（d=1,3,5…、60玉=6目）だけを読む。上n＝上n下(6-n) の手取り（合計は常に6、4-6 に明記）。中央からの浮きは「上n」略記、内側は「下上下4」形式（3区間以上は1省略）
  - **戻し**: 交換した糸と同数を丸数字で戻す（ユーザー確認 2026-07-06）。ブロック内で交換した対＝入れかわっていた目（スロットi→対i+2）＋飛びの数字＋中央の連続⬆（1段=1対 → ①〜ⓚ）。手取りの⬆のみ（中央の色なし）のブロックは書籍 4-15 の一括の戻し「②〜(M+2)」。数字は片面の目数で頭打ち、3個以下は並記・4個以上は範囲形式
  - **飛び**: 入れかえの目が一度に2目以上増える段に「2.3…M 」を前置
  - **⬆（中央で上ル）**: C 配列が唯一の情報源（index 2r=右半面・2r+1=左半面）。中央の2列（d=0）に色を置くと自動で**反対側の半面**に⬆。連続 k 段の⬆が終わった段に ①〜ⓚ の戻し（置いた段に数字は出さない）。ナミ⬆の段は数えに中立。手動は記号表の左右セルをタップ
- 変更したら必ず `python3 scripts/test-notation.py` で 4-15 と一致することを確認

## 残タスク・未解決

- ⬆の完全自動導出と糸番号リスト（「3,5,7,9 上ル」等）: 糸1本ずつの経路追跡（二枚安田の組成シミュレーション）が必要。4-15 が答え合わせデータ
- 部分的な戻し（模様が全消えせず狭まる場合）の丸数字は未対応（現状は全消え段のみ）
- 色違い（柄1→柄2）の塗り替えは糸交換の数字に出ない（スロットが boolean のため）

## 進め方の約束

- 決定は「書籍のページ写真 → ユーザー確認 → 実装 → 4-15 回帰テスト」の順
- Web（index.html）とアプリ（Shared/BraidModel.swift ほか）の**両方**に同じ変更を入れる
- デプロイ: push で GitHub Pages（Web）、/Applications へ ditto（アプリ）
