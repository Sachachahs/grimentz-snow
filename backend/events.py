"""Détection des changements notables entre deux instantanés : base des futures notifications push.

Chaque événement est un petit dictionnaire {id, type, title, body, at}. Ils sont ajoutés à events.json
(les 100 derniers sont conservés). Une future étape « push » (Firebase Cloud Messaging, par ex.) n'aura qu'à
envoyer les nouveaux événements : la détection est déjà faite ici, au même endroit que la collecte.
"""
import json
from datetime import datetime
from pathlib import Path

HEAVY_FORECAST_CM = 20      # neige prévue sur 48 h (Corne de Sorebois) considérée comme forte
FRESH_SNOW_CM = 10          # neige fraîche 24 h considérée comme importante


def _get(d, *path):
    for p in path:
        if d is None:
            return None
        d = d[p] if isinstance(d, list) and isinstance(p, int) and len(d) > p else (d.get(p) if isinstance(d, dict) else None)
    return d


def _fresh24(s):
    for f in _get(s, "snow", "fresh") or []:
        if f.get("h") == 24:
            return f.get("cm")
    return None


def _event(kind, title, body):
    now = datetime.now().isoformat(timespec="minutes")
    return {"id": f"{kind}-{now}", "type": kind, "title": title, "body": body, "at": now}


def diff(prev, cur):
    if not prev or not cur:
        return []
    out = []
    a0, a1 = _get(prev, "snow", "avalanche", "level"), _get(cur, "snow", "avalanche", "level")
    if a1 and a0 != a1:
        name = _get(cur, "snow", "avalanche", "name") or ""
        out.append(_event("avalanche", "Danger d'avalanche modifié",
                          f"Niveau {a1} ({name})" + (f", auparavant {a0}" if a0 else "")))
    o0, o1 = _get(prev, "domain", "lifts", "open") or 0, _get(cur, "domain", "lifts", "open") or 0
    if o0 == 0 and o1 > 0:
        total = _get(cur, "domain", "lifts", "total")
        out.append(_event("opening", "La station est ouverte", f"{o1} / {total} remontées ouvertes"))
    f0, f1 = _fresh24(prev), _fresh24(cur)
    if f1 is not None and f1 >= FRESH_SNOW_CM and (f0 is None or f1 > f0):
        out.append(_event("fresh_snow", "Nouvelle chute de neige", f"{f1:.0f} cm de neige fraîche en 24 h"))
    h0 = _get(prev, "snow", "fresh_days", "cumul_summit", "48")
    h1 = _get(cur, "snow", "fresh_days", "cumul_summit", "48")
    if h1 is not None and h1 >= HEAVY_FORECAST_CM and (h0 is None or h0 < HEAVY_FORECAST_CM):
        out.append(_event("heavy_forecast", "Forte chute de neige prévue",
                          f"≈ {h1:.0f} cm prévus en 48 h à 2895 m (estimation MétéoSuisse)"))
    return out


def append(path: Path, new):
    try:
        old = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        old = []
    Path(path).write_text(json.dumps((old + new)[-100:], ensure_ascii=False, indent=1), encoding="utf-8")
