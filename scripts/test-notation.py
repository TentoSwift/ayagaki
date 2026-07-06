#!/usr/bin/env python3
"""綾書記号の回帰テスト。書籍 4-15「四角」の4例（docs/notation-reference.md）と
stdio MCP 経由で突き合わせる。要: /Applications/Ayagaki.app"""
import json, subprocess, sys

BIN = "/Applications/Ayagaki.app/Contents/MacOS/Ayagaki"

def mcp(requests):
    lines = [json.dumps({"jsonrpc":"2.0","id":0,"method":"initialize",
        "params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}})]
    for i, (name, args) in enumerate(requests, 1):
        lines.append(json.dumps({"jsonrpc":"2.0","id":i,"method":"tools/call",
                                 "params":{"name":name,"arguments":args}}))
    out = subprocess.run([BIN,"--mcp"], input="\n".join(lines)+"\n",
                         capture_output=True, text=True).stdout.strip().split("\n")
    return [json.loads(json.loads(l)["result"]["content"][0]["text"]) for l in out[1:]]

# (塗り, ⬆の段(0始まり・左半面), 中央の色の段(右半面d=0→左に上ル), 期待値)。⬆は書籍 4-15 の左列に忠実
# 戻しの丸数字はひとつ段を飛ばした先に表示（ユーザー確認 2026-07-06）
FIXTURES = {
  "4-15 ブロック1": ([[],[1],[1],[],[]], [0,1], [],
    ["ナミ⬆","上1⬆","上1","ナミ","②③④ナミ"]),
  "4-15 ブロック2": ([[],[1],[1],[1,2],[1,2],[1,2,3],[],[]], [0,1,2,3,4], [],
    ["ナミ⬆","上1⬆","上1⬆","上2⬆","上2⬆","上3","ナミ","②〜⑦ナミ"]),
  "4-15 ブロック3": ([[],[1],[1],[1,2],[1,2],[1,2,3],[1,2,3],[1,2,3,4],[1,2,3,4],[],[]], [0,1,2,3,4,5,6,7], [],
    ["ナミ⬆","上1⬆","上1⬆","上2⬆","上2⬆","上3⬆","上3⬆","上4⬆","上4","ナミ","②〜⑩ナミ"]),
  "4-15 ブロック4": ([[],[1],[1],[2],[2],[3],[3],[1,2,3,4],[1,2,3,4],[],[]], [0,1,6,7], [],
    ["ナミ⬆","上1⬆","上1","下上下4","下上下4","下2上下3","下2上下3⬆","2.3.4.5.6 上4⬆","上4","ナミ","②〜⑩ナミ"]),
  # 戻しは交換した糸と同数（ユーザー確認 2026-07-06）
  "⬆なし 上1×1段": ([[],[1],[],[]], [], [],
    ["ナミ","上1","ナミ","②ナミ"]),
  "⬆なし 上2×2段": ([[],[1,2],[1,2],[],[]], [], [],
    ["ナミ","上2","上2","ナミ","②③ナミ"]),
  # 中央⬆の戻しは各段の2段先に③（毎回同じ番号。ユーザー確認 2026-07-06）
  "中央⬆はそれぞれ2段先で③で戻す": ([[],[],[],[],[],[],[]], [1,2,3], [1,2,3],
    ["ナミ","ナミ⬆","ナミ⬆","③ナミ⬆","③ナミ","③ナミ","ナミ"]),
  "中央⬆と模様の混在": ([[],[1],[],[1],[],[]], [1,2,3], [1,2,3],
    ["ナミ","上1⬆","ナミ⬆","③上1⬆","③ナミ","②③ナミ"]),
  "飛びの戻しは同数": ([[],[1],[1],[1],[1,2,3,4],[],[]], [], [],
    ["ナミ","上1","上1","上1","2.3 上4","ナミ","②〜⑤ナミ"]),
  # 飛びの数字は+2で戻す（糸交換の2 → ④。ユーザー確認 2026-07-06）
  "飛びの戻しは番号+2": ([[],[1],[1],[1],[1],[1],[1,2,3],[],[]], [], [],
    ["ナミ","上1","上1","上1","上1","上1","2.3.4.5 上3","ナミ","②〜⑦ナミ"]),
  # 戻しの段の直後から次の模様が始まる場合は模様の記号の前に付く
  "戻しが次の模様と重なる": ([[],[1],[],[1,2],[1,2],[],[]], [], [],
    ["ナミ","上1","ナミ","②上2","上2","ナミ","②③ナミ"]),
}

ID = mcp([("create_design", {"name":"記号回帰テスト","tama":60,"rows":10})])[0]["id"]
failed = 0
try:
    for name, (slices, arrowRows, centerRows, expected) in FIXTURES.items():
        rows = len(slices)
        grid = [[0]*13 for _ in range(rows)]
        for r, slots in enumerate(slices):
            for s in slots: grid[r][2*s-1] = 1
        gridR = [row[:] for row in grid]
        for r in centerRows: gridR[r][0] = 1  # 右の d=0 の色 → 左半面に中央上ル
        carr = [0]*(rows*2)  # C 配列: index 2r=右半面・2r+1=左半面
        for r in arrowRows: carr[2*r+1] = 1
        res = mcp([("update_design", {"id":ID,"rows":rows}),
                   ("set_cells", {"id":ID,"cells":{"L":grid,"R":gridR,"C":carr}}),
                   ("get_notation", {"id":ID})])
        got = [None]*rows
        for g in res[2]["notation"]:
            span = g["rows"].split("〜")
            for r in range(int(span[0])-1, int(span[-1])): got[r] = g["left"]
        for r in range(rows):
            if got[r] != expected[r]:
                print(f"✗ {name} 段{r+1}: 生成={got[r]!r} 期待={expected[r]!r}")
                failed += 1
        print(f"{'✓' if all(got[r]==expected[r] for r in range(rows)) else '✗'} {name}")
finally:
    mcp([("delete_design", {"id":ID})])

sys.exit(1 if failed else 0)
