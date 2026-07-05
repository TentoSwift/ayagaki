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

FIXTURES = {
  "4-15 ブロック1": ([[],[1],[1],[]],
    ["ナミ","上1","上1","②③④ナミ"]),
  "4-15 ブロック2": ([[],[1],[1],[1,2],[1,2],[1,2,3],[]],
    ["ナミ","上1","上1","上2","上2","上3","②〜⑦ナミ"]),
  "4-15 ブロック3": ([[],[1],[1],[1,2],[1,2],[1,2,3],[1,2,3],[1,2,3,4],[1,2,3,4],[]],
    ["ナミ","上1","上1","上2","上2","上3","上3","上4","上4","②〜⑩ナミ"]),
  "4-15 ブロック4": ([[],[1],[1],[2],[2],[3],[3],[1,2,3,4],[1,2,3,4],[]],
    ["ナミ","上1","上1","下上下4","下上下4","下2上下3","下2上下3","2.3.4.5.6 上4","上4","②〜⑩ナミ"]),
}

ID = mcp([("create_design", {"name":"記号回帰テスト","tama":60,"rows":10})])[0]["id"]
failed = 0
try:
    for name, (slices, expected) in FIXTURES.items():
        rows = len(slices)
        grid = [[0]*13 for _ in range(rows)]
        for r, slots in enumerate(slices):
            for s in slots: grid[r][2*s-1] = 1
        res = mcp([("update_design", {"id":ID,"rows":rows}),
                   ("set_cells", {"id":ID,"cells":{"L":grid,"R":grid}}),
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
