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

    # ⬆: 中心の入れかえは**反対の半面**の中心の目を見る
    #     右半面の段 r ⇔ 左半面の (0,k=r) が柄 ／ 左半面の段 r ⇔ 右半面の (0,k=r+1) が柄
    rise = mcp([("paint", {"id": d["id"], "ops": [
                    {"side": "R", "rowFrom": 3, "rowTo": 3, "posFrom": 1, "posTo": 1, "color": 1}]}),
                ("get_notation", {"id": d["id"]})])[1]["notation"]
    gotR, gotL = {}, {}
    for g in rise:
        span = g["rows"].split("〜")
        for r in range(int(span[0]), int(span[-1]) + 1):
            gotR[r], gotL[r] = g["right"], g["left"]
    ok = True
    for r, side, got, want in ((2, "左", gotL, "上1下2⬆"), (3, "左", gotL, "上1下2"),
                               (3, "右", gotR, "上1下2"), (4, "右", gotR, "上1下2")):
        if got[r] != want:
            print(f"✗ ⬆ {side}半面 段{r}: 生成={got[r]!r} 期待={want!r}")
            failed += 1
            ok = False
    if ok:
        print("✓ ⬆: 右半面 (0,k=3) の色 → 左半面 段2 に ⬆（反対の半面・半段ずれ）")
finally:
    mcp([("delete_design", {"id": d["id"]})])


# ---------------------------------------------------------------------------
# 書籍 1-14 / 1-17 / 1-18 の格子（docs/korai-fixtures）を投入して、
# 糸交換の数字・丸数字・⬆ を Python 実装（scripts/korai_rule.py）と突き合わせる。
# **期待値は korai_rule.py の出力**（Swift は忠実な移植なので全段一致するはず）。
# 書籍そのものとの一致率は参考表示（docs/korai-fixtures/rule_check.md の数字と同程度）。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kd, korai_rule

def to_grid(G, kmax):
    """fixture の 7 列（畝 w）を 13 列（畝 w → 列 2w）に展開。null（読めない目）は白とみなす"""
    out = [[0] * COLS for _ in range(kmax)]
    if G is None:
        return out
    for k in range(min(kmax, len(G))):
        for w in range(WALES):
            out[k][2 * w] = 1 if G[k][w] == 1 else 0
    return out


print()
print("== 書籍 1-14 / 1-17 / 1-18 の格子との突き合わせ ==")
py_total = py_ok = 0
bk_total = bk_ok = 0
bk_aya = bk_num = bk_up = 0
for pg, bk in kd.BLOCKS:
    fx = kd.load(pg, bk)
    kmax = fx["kMax"]
    grids, zero = {}, [[0] * COLS for _ in range(kmax)]
    for key in ("R", "L"):
        grids[key] = to_grid(fx.get(key), kmax) if fx.get(key) else zero
    # Python 実装の期待値（前のブロックの格子は使わない = アプリと同じ条件）
    GR = [[grids["R"][k][2 * w] for w in range(WALES)] for k in range(kmax)]
    GL = [[grids["L"][k][2 * w] for w in range(WALES)] for k in range(kmax)]
    exp = korai_rule.notation(GR, GL, kmax)

    dd = mcp([("create_design", {"name": "高麗組 %s %s" % (pg, bk), "tama": 60,
                                 "rows": kmax, "braidType": "korai"})])[0]
    try:
        res = mcp([("set_cells", {"id": dd["id"], "cells": {"L": grids["L"], "R": grids["R"]}}),
                   ("get_notation", {"id": dd["id"]})])
        got = {"L": [None] * kmax, "R": [None] * kmax}
        for g in res[1]["notation"]:
            span = g["rows"].split("〜")
            for r in range(int(span[0]) - 1, int(span[-1])):
                got["L"][r], got["R"][r] = g["left"], g["right"]
    finally:
        mcp([("delete_design", {"id": dd["id"]})])

    for key in ("R", "L"):
        if fx.get(key) is None:
            continue
        # (1) Python 実装との完全一致（全 kMax 段）
        for e in exp[key]:
            r = e["row"]
            p = kd.parse(got[key][r - 1])
            mine = sorted([(n, 0) for n in p["plain"]] + [(n, 1) for n in p["circ"]])
            want = sorted([(n, 1 if c else 0) for n, c in e["tokens"]])
            py_total += 1
            if mine == want and p["up"] == e["up"]:
                py_ok += 1
            else:
                print("✗ %s %s %s 段%d: 生成 %r / Python %r" %
                      (pg, bk, key, r, got[key][r - 1],
                       korai_rule.fmt(e["tokens"], e["up"])))
                failed += 1
        # (2) 書籍との一致（参考。ブロックの段数まで）
        book = fx.get("notation" + key)
        if not book:
            continue
        for r, bs in enumerate(book, 1):
            b, p = kd.parse(bs), kd.parse(got[key][r - 1])
            bk_total += 1
            same_aya = (p["aya"] == b["aya"])
            same_num = (sorted(p["plain"]) == sorted(b["plain"])
                        and sorted(p["circ"]) == sorted(b["circ"]))
            same_up = (p["up"] == b["up"])
            bk_aya += same_aya
            bk_num += same_num
            bk_up += same_up
            bk_ok += (same_aya and same_num and same_up)

print("Python 実装（korai_rule.py）との一致: %d/%d 段" % (py_ok, py_total))
print("書籍との一致（参考）: 全体 %d/%d・綾名 %d/%d・数字 %d/%d・⬆ %d/%d"
      % (bk_ok, bk_total, bk_aya, bk_total, bk_num, bk_total, bk_up, bk_total))

print("NG あり" if failed else "すべて一致")
sys.exit(1 if failed else 0)
