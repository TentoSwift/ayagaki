#!/usr/bin/env python3
"""二枚高麗組の綾名の回帰テスト。書籍 1-3「60玉二枚高麗組 手取り練習」の 42 段と
stdio MCP 経由で突き合わせる。

書籍の柄（右半面。左半面も同じ）を畝（wale）w の目 k で置く:
  段 1〜6   → w=1 の目 k=1..6
  段 7〜12  → w=1,3
  段 13〜18 → w=1,3,5
  段 19〜24 → w=3
  段 25〜30 → w=1,5
  段 31〜36 → w=3,5
  段 37〜42 → w=5
段 r の綾名は畝 w=1,3,5 の目を k=r で読む（データ上は L/R[k-1][2w]）。

要: /Applications/Ayagaki.app、または AYAGAKI_BIN で別のビルドを指定
（例: AYAGAKI_BIN=apple/macbuild/Build/Products/Release/Ayagaki.app/Contents/MacOS/Ayagaki）
"""
import json, os, subprocess, sys

BIN = os.environ.get("AYAGAKI_BIN", "/Applications/Ayagaki.app/Contents/MacOS/Ayagaki")

def mcp(requests):
    lines = [json.dumps({"jsonrpc":"2.0","id":0,"method":"initialize",
        "params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}})]
    for i, (name, args) in enumerate(requests, 1):
        lines.append(json.dumps({"jsonrpc":"2.0","id":i,"method":"tools/call",
                                 "params":{"name":name,"arguments":args}}))
    out = subprocess.run([BIN,"--mcp"], input="\n".join(lines)+"\n",
                         capture_output=True, text=True).stdout.strip().split("\n")
    return [json.loads(json.loads(l)["result"]["content"][0]["text"]) for l in out[1:]]

COLS = 13          # 60玉の片面の目数
WALES = 7          # 畝の本数 = (COLS+1)/2
ROWS = 42

# 段のブロック（1始まりの段範囲, 色を置く畝, 期待する綾名）— 書籍 1-3 の表
BLOCKS = [
    ((1, 6),   [1],     "上1下2"),
    ((7, 12),  [1, 3],  "上2下1"),
    ((13, 18), [1, 3, 5], "上3"),
    ((19, 24), [3],     "下上下"),
    ((25, 30), [1, 5],  "上下上"),
    ((31, 36), [3, 5],  "下1上2"),
    ((37, 42), [5],     "下2上1"),
]

grid = [[0] * COLS for _ in range(ROWS)]
expected = [None] * ROWS
for (a, b), wales, name in BLOCKS:
    for r in range(a, b + 1):
        for w in wales:
            grid[r - 1][2 * w] = 1   # 畝 w の目 k=r → L/R[r-1][2w]
        expected[r - 1] = name

failed = 0
d = mcp([("create_design",
          {"name": "高麗組 1-3 手取り練習", "tama": 60, "rows": ROWS, "braidType": "korai"})])[0]
try:
    if d.get("braidType") != "korai":
        print(f"✗ create_design の braidType={d.get('braidType')!r} 期待='korai'")
        failed += 1
    if d.get("walesPerSide") != WALES:
        print(f"✗ walesPerSide={d.get('walesPerSide')!r} 期待={WALES}")
        failed += 1

    res = mcp([("set_cells", {"id": d["id"], "cells": {"L": grid, "R": grid}}),
               ("get_notation", {"id": d["id"]})])
    notation = res[1]["notation"]
    if res[1].get("braidType") != "korai":
        print(f"✗ get_notation の braidType={res[1].get('braidType')!r} 期待='korai'")
        failed += 1

    gotL, gotR = [None] * ROWS, [None] * ROWS
    for g in notation:
        span = g["rows"].split("〜")
        for r in range(int(span[0]) - 1, int(span[-1])):
            gotL[r], gotR[r] = g["left"], g["right"]

    for (a, b), _, name in BLOCKS:
        ok = True
        for r in range(a, b + 1):
            for label, got in (("右", gotR), ("左", gotL)):
                if got[r - 1] != name:
                    print(f"✗ {label}半面 段{r}: 生成={got[r-1]!r} 期待={name!r}")
                    failed += 1
                    ok = False
        print(f"{'✓' if ok else '✗'} 段{a}〜{b}: {name}（左右とも）")

    # ⬆（暫定規則）: 中央の目（w=0, k=r）に色があるとその段に ⬆
    rise = mcp([("paint", {"id": d["id"], "ops": [
                    {"side": "R", "rowFrom": 3, "rowTo": 3, "posFrom": 1, "posTo": 1, "color": 1}]}),
                ("get_notation", {"id": d["id"]})])[1]["notation"]
    got3 = next(g["right"] for g in rise if g["rows"] == "3")
    if got3 == "上1下2⬆":
        print("✓ ⬆（暫定）: 中央の目の色でその段に ⬆ が付く")
    else:
        print(f"✗ ⬆（暫定）段3: 生成={got3!r} 期待='上1下2⬆'")
        failed += 1
finally:
    mcp([("delete_design", {"id": d["id"]})])

print("NG あり" if failed else "すべて一致")
sys.exit(1 if failed else 0)
