# -*- coding: utf-8 -*-
"""二枚高麗組（60玉）の綾書：糸交換の数字・丸数字・⬆ を目の色から導く規則。

------------------------------------------------------------------
【糸の動きのモデル】
 半面の畝は中央から w=0..6。偶数 w が＼（糸交換の目）、奇数 w が／（綾の目）。
 定規の目盛 n（位置）と畝 w の対応:
       n = 1            -> w=0（中心）
       n = 3, 4, 5      -> w=2
       n = 7, 8, 9      -> w=4
       n = 11, 12, 13   -> w=6
       n = 2, 6, 10     -> 綾の目 w=1,3,5（番号は振らない）
 1 本の糸は 1 段に 1 目盛ずつ外へ進む。段 r で位置 n にいる糸を
 「糸番号 t = r - n + 1」で呼ぶ（t = その糸が位置 1 にいる段）。
 糸 t が通る＼の目は
       (w, k) = (w,  t + 2w)          w = 0, 2, 4, 6
 すなわち **目 (w,k) を通る糸は t = k - 2w**、
 その糸が位置 n にいるのは段 r = t + n - 1。

【● 印】
 糸 t について、通る＼の目の色 c0, c2, c4, c6 を中央から外へ並べ、
   白→柄 に変わった目  … ● ＋ 素の数字（下段の柄糸を上段へ上げる）
   柄→白 に戻った目    … ● ＋ 丸数字（上げた糸を下段へ戻す）
 c(-2)（w=0 の手前）は常に白とみなす。

【数字を書く段（どの目盛を使うか）】
 1 つの ● は 3 段のうちどの段に書いてもよい（＝目盛 2w-1, 2w, 2w+1 のどれでもよい）。
 本文「入れかえは手取りの綾に隠れている部分で行うので3段先まで入れかえられる」。
 本の書き方は次の貪欲法でほぼ再現できる:
   同じ畝 w の ● を k の小さい順に見て、まだ組に入っていない一番小さい k を k0 とし、
   k0 <= k <= k0+2 の ● をひとつの組にして **段 r = k0** にまとめて書く。
   組の中の目 k の数字は   n = 2w + 1 - (k - k0)
   （w=2 なら 5,4,3 / w=4 なら 9,8,7 / w=6 なら 13,12,11。丸を付けるかは ● の種類）
 例外の扱い:
   * ● が 3 個連続している並びは必ず 1 組にする（その先頭は別の組に巻き込まない）。
   * k が飛んでいる ● を同じ組に入れるのは、種類（素/丸）が同じときだけ
     （例 1-18b 右の「③⑤」= 目 k=6 と k=8、k=7 には ● がない）。
   * k0 がブロックの段数を超える組は、書ける一番遅い段まで引き上げる。
 この段の選び方には本当に自由度があり、本もときどき 1〜2 段早く書いている。

【⬆（中心の入れかえ）】
 ⬆ は中心 (w=0) の ● に対応するが、**反対の半面の中心の目**を見る。
 左右の半面は定規が半段ずれており、自分の目 (0,r) の «すぐ下» にある
 反対半面の中心の目が柄のとき、その段に ⬆ が付く。実装上は
       右半面の段 r の ⬆  <=>  左半面の (0, k=r)   が柄
       左半面の段 r の ⬆  <=>  右半面の (0, k=r+1) が柄
------------------------------------------------------------------
"""
import kd

WOF = {1: 0, 3: 2, 4: 2, 5: 2, 7: 4, 8: 4, 9: 4, 11: 6, 12: 6, 13: 6}


def marks(G, kmax=None, pre=None):
    """目の色の表 G[k-1][w] から ● の一覧を作る。
    返り値 {(w,k): 'P'（素の数字）/ 'C'（丸数字）}, および履歴不明フラグ集合。"""
    kmax = kmax or len(G)
    m, unknown = {}, set()
    for w in (0, 2, 4, 6):
        for k in range(1, kmax + 1):
            cur = G[k - 1][w]
            if cur is None:
                continue
            if w == 0:
                prev, unk = 0, False
            elif k - 4 >= 1:
                prev, unk = G[k - 5][w - 2], False
            elif pre is not None and pre[4 - k] is not None:
                prev, unk = pre[4 - k][w - 2], False   # 前のブロックの格子から補う
            else:
                prev, unk = 0, True        # ブロックの外（手前は白と仮定）
            if prev is None:
                continue
            if prev == 0 and cur == 1:
                m[(w, k)] = 'P'
            elif prev == 1 and cur == 0:
                m[(w, k)] = 'C'
            if unk and (w, k) in m:
                unknown.add((w, k))
    return m, unknown


def tokens(G, rows, kmax=None, skip_unknown=True, pre=None):
    """段ごとの (数字, 丸か) の一覧を作る。 {r: [(n, circled), ...]}

    同じ畝の ● を k の小さい順に見て、まだ書いていない一番小さい ● の k を
    k0 とし、k0..k0+2 の窓に入る ● をすべて段 k0 にまとめて書く。
    窓の j 番目（j = k - k0）の数字は n = 2w+1-j。"""
    kmax = kmax or len(G)
    m, unk = marks(G, kmax, pre)
    if skip_unknown:
        m = {c: v for c, v in m.items() if c not in unk}
    out = {}
    for w in (2, 4, 6):
        ks = sorted(k for (ww, k) in m if ww == w)
        # 3 連続の ● は 1 組から外さない（先に切り出す）
        runs, i = [], 0
        while i < len(ks):
            j = i
            while j + 1 < len(ks) and ks[j + 1] == ks[j] + 1:
                j += 1
            runs.append(ks[i:j + 1])
            i = j + 1
        keep = set()
        for run in runs:
            if len(run) >= 3:
                for s2 in range(0, len(run), 3):
                    if len(run[s2:s2 + 3]) == 3:
                        keep.add(run[s2])          # ここから 3 個は固定の組
        used, i = set(), 0
        grps = []
        for k in ks:
            if k in used:
                continue
            grp = [k]
            used.add(k)
            for k2 in ks:
                if k2 in used or not (k < k2 <= k + 2):
                    continue
                if k2 in keep:                     # 3 連続の組の先頭は巻き込まない
                    break
                if k2 != grp[-1] + 1 and m[(w, k2)] != m[(w, grp[0])]:
                    break                          # 飛んだ先は同じ種類のときだけ同じ組
                grp.append(k2)
                used.add(k2)
                if len(grp) == 3:
                    break
            grps.append(grp)
        for grp in grps:
            k0 = grp[0]
            # 綾書はブロックの段数までしかないので、k0 が段数を超える組は
            # 書ける一番遅い段（= max(k)-2 以上, rows 以下）まで引き上げる
            if k0 > rows:
                k0 = rows
            if not (max(grp) - 2 <= k0 <= min(grp)) or k0 < 1:
                continue
            out.setdefault(k0, [])
            for k in grp:
                out[k0].append((2 * w + 1 - (k - k0), m[(w, k)] == 'C'))
    for r in out:
        out[r].sort()
    return out


def ups(Gself, Gother, side, rows):
    """段ごとの ⬆ の有無"""
    off = 0 if side == 'R' else 1
    out = {}
    for r in range(1, rows + 1):
        k = r + off
        out[r] = (1 <= k <= len(Gother)) and Gother[k - 1][0] == 1
    return out


def notation(GR, GL, rows, preR=None, preL=None):
    """右・左の目の色から綾書の「糸交換部分」を作る。"""
    res = {}
    for key, G, Go, pre in (('R', GR, GL, preR), ('L', GL, GR, preL)):
        if G is None:
            res[key] = None
            continue
        tk = tokens(G, rows, pre=pre)
        up = ups(G, Go, key, rows) if Go is not None else {r: False for r in range(1, rows + 1)}
        res[key] = [dict(row=r, tokens=tk.get(r, []), up=up[r]) for r in range(1, rows + 1)]
    return res


def fmt(tks, up):
    C = '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬'
    s = ''.join((C[n - 1] if c else '%d.' % n) for n, c in tks)
    return s + ('⬆' if up else '')


if __name__ == '__main__':
    for pg, bk in kd.BLOCKS:
        d = kd.load(pg, bk)
        pred = notation(d.get('R'), d.get('L'), d['rows'],
                        kd.prefix(pg, bk, 'R'), kd.prefix(pg, bk, 'L'))
        print('==', pg, bk)
        for key in ('R', 'L'):
            if pred[key] is None or d.get('notation' + key) is None:
                continue
            for e, s in zip(pred[key], d['notation' + key]):
                p = kd.parse(s)
                got = sorted([(n, 0) for n in p['plain']] + [(n, 1) for n in p['circ']])
                mark = ' ' if (got == e['tokens'] and p['up'] == e['up']) else 'X'
                print(' %s %s r=%2d  予測 %-14s 本 %-14s' %
                      (key, mark, e['row'], fmt(e['tokens'], e['up']),
                       fmt(got, p['up'])))
