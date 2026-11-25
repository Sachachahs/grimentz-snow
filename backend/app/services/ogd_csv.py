"""Lecture ciblée des fichiers CSV MétéoSuisse (prévisions locales) par requêtes HTTP Range.

Chaque fichier contient TOUS les points de Suisse (~5600) et pèse jusqu'à ~33 Mo. Pour ne pas
télécharger des centaines de Mo à chaque actualisation, on ne lit que les lignes utiles :

* fichiers « temps-majeur » (lignes triées par date puis par point) : on repère la ligne du point
  dans le premier bloc horaire, puis on saute de bloc en bloc (la taille d'un bloc varie très peu)
  en lisant une petite fenêtre autour de la position estimée ;
* fichiers « point-majeur » (triés par identifiant de point puis par date) : recherche dichotomique
  sur l'identifiant, puis lecture des lignes contiguës du point.

La disposition est détectée automatiquement. En cas d'incohérence, on lit le fichier en entier.
Format des lignes : point_id;point_type_id;AAAAMMJJHHMM;valeur
"""
from typing import Callable, Dict, List, Optional, Tuple

FetchRange = Callable[[str, int, int], bytes]
Target = Tuple[int, int]                      # (point_id, point_type_id)
Rows = Dict[Target, List[Tuple[str, str]]]    # cible -> [(date UTC, valeur)]

HEAD_BYTES = 262_144


def _lines_with_offsets(text: str, base: int, skip_first_partial: bool):
    """Renvoie [(offset_absolu, ligne)] pour les lignes complètes du morceau."""
    out = []
    pos = 0
    if skip_first_partial:
        nl = text.find("\n")
        if nl < 0:
            return out
        pos = nl + 1
    while True:
        nl = text.find("\n", pos)
        if nl < 0:
            break
        out.append((base + pos, text[pos:nl].rstrip("\r")))
        pos = nl + 1
    return out


def _parse(line: str):
    parts = line.split(";")
    if len(parts) < 4:
        return None
    try:
        return int(parts[0]), int(parts[1]), parts[2], parts[3]
    except ValueError:
        return None


def read_rows(fetch: FetchRange, url: str, size: int, targets: List[Target],
              horizon: Optional[str] = None) -> Rows:
    head = fetch(url, 0, min(size, HEAD_BYTES) - 1).decode("latin-1")
    lines = _lines_with_offsets(head, 0, False)
    data = [(off, _parse(l)) for off, l in lines[1:]]
    data = [(off, p) for off, p in data if p]
    if len(data) < 2:
        return _read_full(fetch, url, size, targets, horizon)
    point_major = data[0][1][:2] == data[1][1][:2]
    try:
        if point_major:
            res = _point_major(fetch, url, size, targets, horizon, header_end=lines[1][0])
        else:
            res = _time_major(fetch, url, size, targets, horizon, data)
        if all(res.get(t) for t in targets):
            return res
    except Exception:
        pass
    return _read_full(fetch, url, size, targets, horizon)


# ---------------------------------------------------------------- temps-majeur
def _time_major(fetch, url, size, targets, horizon, head_data) -> Rows:
    first_date = head_data[0][1][2]
    block_len = next((off for off, p in head_data if p[2] != first_date), None)
    if block_len is None:
        raise ValueError("bloc horaire plus grand que la lecture initiale")
    block_len -= head_data[0][0]
    out: Rows = {}
    for t in targets:
        hits = [(off, p) for off, p in head_data if (p[0], p[1]) == t]
        if not hits:
            raise ValueError(f"point {t} absent du premier bloc")
        out[t] = _chain(fetch, url, size, t, horizon, hits, block_len)
    return out


def _chain(fetch, url, size, target, horizon, hits, block_len):
    rows = [(p[2], p[3]) for _, p in hits]
    pos = [off for off, _ in hits]
    last_date = rows[-1][0]
    prefix = f"{target[0]};{target[1]};"
    while True:
        step = pos[-1] - pos[-2] if len(pos) >= 2 else block_len
        est = pos[-1] + step
        if est >= size:
            break
        found = None
        win = 4096
        for _ in range(4):
            a, b = max(0, est - win), min(size - 1, est + win)
            chunk = fetch(url, a, b).decode("latin-1")
            best = None
            for off, line in _lines_with_offsets(chunk, a, a > 0):
                if line.startswith(prefix):
                    p = _parse(line)
                    if p and p[2] > last_date and (best is None or p[2] < best[1][2]):
                        best = (off, p)
            if best:
                found = best
                break
            win *= 4
        if not found:
            break
        off, p = found
        if horizon and p[2] > horizon:
            break
        rows.append((p[2], p[3]))
        pos.append(off)
        last_date = p[2]
    return rows


# --------------------------------------------------------------- point-majeur
def _first_point_at(fetch, url, size, offset):
    chunk = fetch(url, offset, min(size - 1, offset + 2047)).decode("latin-1")
    for _, line in _lines_with_offsets(chunk, offset, offset > 0):
        p = _parse(line)
        if p:
            return p[0], p[1]
    return None


# Ordres de tri rencontrés dans les fichiers MétéoSuisse : (type, id) ou (id, type)
_SORT_KEYS = (lambda pid, typ: (typ, pid), lambda pid, typ: (pid, typ))


def _detect_sort_key(fetch, url, size, header_end):
    probes = []
    for i in range(17):
        off = header_end + (size - header_end - 1) * i // 16
        pt = _first_point_at(fetch, url, size, off)
        if pt:
            probes.append(pt)
    for key in _SORT_KEYS:
        seq = [key(*pt) for pt in probes]
        if all(a <= b for a, b in zip(seq, seq[1:])):
            return key
    raise ValueError("ordre de tri inconnu")


def _point_major(fetch, url, size, targets, horizon, header_end) -> Rows:
    key = _detect_sort_key(fetch, url, size, header_end)
    out: Rows = {}
    for t in targets:
        goal = key(*t)
        lo, hi = header_end, size
        while hi - lo > 65_536:
            mid = (lo + hi) // 2
            pt = _first_point_at(fetch, url, size, mid)
            if pt is None or key(*pt) >= goal:
                hi = mid
            else:
                lo = mid
        rows, pos, seen = [], lo, False
        at_line_start = lo == header_end
        while pos < size:
            end = min(size - 1, pos + 131_071)
            chunk = fetch(url, pos, end).decode("latin-1")
            lines = _lines_with_offsets(chunk, pos, not at_line_start)
            at_line_start = True
            if not lines:
                break
            stop = False
            for _, line in lines:
                p = _parse(line)
                if not p:
                    continue
                k = key(p[0], p[1])
                if k == goal:
                    seen = True
                    if not (horizon and p[2] > horizon):
                        rows.append((p[2], p[3]))
                elif k > goal:
                    stop = True
                    break
            if stop or end >= size - 1:
                break
            last_off, last_line = lines[-1]
            pos = last_off + len(last_line.encode("latin-1")) + 1
        if not seen:
            raise ValueError(f"point {t} introuvable")
        out[t] = rows
    return out


# ------------------------------------------------------------------- secours
def _read_full(fetch, url, size, targets, horizon) -> Rows:
    return parse_text(fetch(url, 0, size - 1).decode("latin-1"), targets, horizon)


def parse_text(text: str, targets: List[Target], horizon: Optional[str] = None) -> Rows:
    """Extrait les lignes des points d'un fichier CSV complet."""
    prefixes = {f"{t[0]};{t[1]};": t for t in targets}
    out: Rows = {t: [] for t in targets}
    for line in text.splitlines():
        for pre, t in prefixes.items():
            if line.startswith(pre):
                p = _parse(line)
                if p and not (horizon and p[2] > horizon):
                    out[t].append((p[2], p[3]))
    return out
