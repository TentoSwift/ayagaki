# -*- coding: utf-8 -*-
"""fixtures から 綾書トークンと格子色を取り出す共通部分。"""
import json, os, re

FX = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'docs', 'korai-fixtures')
BLOCKS = [('1-14','top'),('1-14','bottom'),
          ('1-17','a'),('1-17','b'),('1-17','c'),
          ('1-18','a'),('1-18','b'),('1-18','c'),('1-18','d')]

CIRC = '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮'
# 位置 n -> 畝 w
def wof(n):
    return {1:0,3:2,4:2,5:2,7:4,8:4,9:4,11:6,12:6,13:6}.get(n)

AYA = ('上1下2','上2下1','下2上1','下1上2','上下上','下上下','上3','下3','ナミ')

def parse(s):
    """綾書1段 -> dict(up=⬆有無, plain=[n...], circ=[n...], aya=名)"""
    t = re.sub(r'[（(].*?[)）]', '', s)
    up = '⬆' in t
    t = t.replace('⬆','').strip()
    aya = None
    for n in AYA:
        if t.endswith(n):
            aya = n; t = t[:len(t)-len(n)]; break
    else:
        for sh, full in (('上1','上1下2'),('上2','上2下1'),('下1','下1上2'),('下2','下2上1')):
            if t.endswith(sh):
                aya = full; t = t[:len(t)-len(sh)]; break
    plain, circ = [], []
    i = 0
    while i < len(t):
        ch = t[i]
        if ch in CIRC:
            circ.append(CIRC.index(ch)+1); i += 1
        elif ch in '0123456789':
            j = i
            while j < len(t) and t[j] in '0123456789': j += 1
            plain.append(int(t[i:j])); i = j
            if i < len(t) and t[i] in '.。': i += 1
        else:
            i += 1
    return dict(up=up, plain=plain, circ=circ, aya=aya, raw=s)

def load(page, block):
    return json.load(open(os.path.join(FX, '%s_%s.json' % (page, block))))

def sides(d):
    out = []
    for key in ('R','L'):
        if d.get(key) is None or d.get('notation'+key) is None:
            continue
        out.append((key, d[key], d['notation'+key], d.get('dots'+key) or [],
                    d.get(key+'values')))
    return out


# 同じページで上下に連続している格子（前のブロックの k = 自分の k + DELTA）
PREV = {('1-17','b'): ('a',16), ('1-17','c'): ('b',16),
        ('1-18','b'): ('a',13), ('1-18','c'): ('b',13), ('1-18','d'): ('c',13)}
PREV_SIDES = {('1-17','b'): 'RL', ('1-17','c'): '',   # c は段差 DELTA が確かめられない
              ('1-18','b'): 'R', ('1-18','c'): 'R', ('1-18','d'): 'R'}


def prefix(page, block, key):
    """目 (w, k) の一つ手前 (w-2, k-4) がブロックの外に出る k=1..4 のために、
    前のブロックの格子から k = 0, -1, -2, -3 の行を取り出す。"""
    if (page, block) not in PREV or key not in PREV_SIDES[(page, block)]:
        return None
    pb, dl = PREV[(page, block)]
    G = load(page, pb).get(key)
    if G is None:
        return None
    out = []
    for j in range(4):                  # j = 0,1,2,3  ->  k = 0,-1,-2,-3
        kk = dl - j
        out.append(G[kk-1] if 1 <= kk <= len(G) else None)
    return out
