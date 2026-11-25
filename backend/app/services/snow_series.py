"""Préparation des données des graphiques de neige (sans Qt, donc testable).

Règle commune : une donnée absente reste `None` et n'est jamais remplacée par 0 ;
une période sans mesure n'est jamais reliée par une courbe.
"""
import math
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import List, Optional, Sequence, Tuple

MOIS = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
MOIS_LONG = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre",
             "novembre", "décembre"]
JOURS_COURTS = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]
JOURS_LONGS = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]


# --------------------------------------------------------------------------- neige fraîche quotidienne
@dataclass
class FreshDay:
    day: date
    measured: Optional[float] = None        # neige fraîche mesurée (cm) ; None = pas de mesure
    precip: Optional[float] = None          # précipitations mesurées (mm)
    forecast: Optional[float] = None        # neige estimée par la prévision (cm) ; None = pas de prévision
    forecast_precip: Optional[float] = None  # précipitations prévues (mm)
    is_future: bool = False                 # jour >= aujourd'hui (zone « prévisions »)


def fresh_days(gri: Sequence[tuple], daily: dict, today: date, past_days: int = 45,
               future_days: int = 7) -> List[FreshDay]:
    """Un élément par jour, de `today - past_days + 1` à `today + future_days - 1`.

    `gri` : [(date, précip mm, neige fraîche cm, hauteur cm)] (station MétéoSuisse de Grimentz) ;
    `daily` : prévision journalière du point d'altitude (clés time, snowfall_sum, precipitation_sum)."""
    by_day = {r[0]: r for r in gri}
    times = daily.get("time", []) if daily else []
    snow = daily.get("snowfall_sum", []) if daily else []
    prec = daily.get("precipitation_sum", []) if daily else []
    fc = {t: (snow[i] if i < len(snow) else None, prec[i] if i < len(prec) else None) for i, t in enumerate(times)}
    out = []
    start = today - timedelta(days=past_days - 1)
    for k in range(past_days + future_days - 1):
        d = start + timedelta(days=k)
        row = by_day.get(d)
        fd = FreshDay(d, is_future=d >= today)
        if row is not None and d <= today:
            fd.precip, fd.measured = row[1], row[2]
        if d >= today and d in fc:
            fd.forecast, fd.forecast_precip = fc[d]
        out.append(fd)
    return out


def forecast_cumul(hourly: dict, now: datetime, hours: int, min_coverage: float = 0.9) -> Optional[float]:
    """Cumul de neige estimé par la prévision sur les `hours` prochaines heures.

    Seules les heures dont les précipitations sont connues comptent ; si la prévision ne couvre pas au
    moins `min_coverage` de la période, le cumul est indisponible (None) plutôt que sous-estimé."""
    times = hourly.get("time", []) if hourly else []
    snow = hourly.get("snowfall", [])
    prec = hourly.get("precipitation", [])
    end = now + timedelta(hours=hours)
    idx = [i for i, t in enumerate(times) if now <= t < end
           and i < len(prec) and prec[i] is not None and i < len(snow) and snow[i] is not None]
    if len(idx) < hours * min_coverage:
        return None
    return round(sum(snow[i] for i in idx), 1)


# --------------------------------------------------------------------------- historique (courbes)
def segments(points: Sequence[Tuple[datetime, Optional[float]]], max_gap: timedelta) -> List[list]:
    """Découpe une série en tronçons continus : coupure sur une valeur absente ou un trou > max_gap."""
    segs: list = []
    cur: list = []
    prev = None
    for t, v in sorted(points, key=lambda p: p[0]):
        if v is None:
            if cur:
                segs.append(cur)
            cur, prev = [], None
            continue
        if prev is not None and t - prev > max_gap:
            segs.append(cur)
            cur = []
        cur.append((t, v))
        prev = t
    if cur:
        segs.append(cur)
    return segs


def nearest(points: Sequence[Tuple[datetime, float]], t: datetime, tolerance: timedelta):
    """Point réel le plus proche de `t` (à `tolerance` près), sinon None."""
    best, bd = None, None
    for p in points:
        d = abs(p[0] - t)
        if d <= tolerance and (bd is None or d < bd):
            best, bd = p, d
    return best


# --------------------------------------------------------------------------- axes
def nice_step(span: float, target: int = 4) -> float:
    raw = span / max(1, target)
    if raw <= 0:
        return 1.0
    mag = 10 ** math.floor(math.log10(raw))
    for m in (1, 2, 5, 10):           # pas « ronds » en cm (pas de 2.5)
        if raw <= m * mag + 1e-12:
            return m * mag
    return 10 * mag


def y_scale(max_value: Optional[float], min_top: float = 5.0, target: int = 5) -> Tuple[float, float]:
    """(sommet de l'axe, pas des graduations) adaptés à la valeur maximale, axe partant de 0."""
    v = max_value or 0
    m = max(min_top, v)
    step = nice_step(m, target)
    top = math.ceil(m / step) * step
    if top - v < step * 0.3:       # un peu d'air au-dessus de la plus haute valeur (étiquettes)
        top += step
    return float(top), float(step)


def date_ticks(start: date, end: date, width_px: float, min_px: float = 64) -> Tuple[List[date], str]:
    """Graduations régulières de l'axe horizontal et leur nature ('day' ou 'month').

    Les pas en jours sont alignés sur `end` (aujourd'hui toujours gradué) ; au-delà, un repère par
    début de mois (tous les 1, 2, 3 ou 6 mois)."""
    days = max(1, (end - start).days)
    px_per_day = width_px / days
    for step in (1, 2, 3, 7, 14):
        if step * px_per_day >= min_px:
            ticks = []
            d = end
            while d >= start:
                ticks.append(d)
                d -= timedelta(days=step)
            return sorted(ticks), "day"
    for months in (1, 2, 3, 6, 12):
        if months * 30.4 * px_per_day >= min_px:
            ticks = []
            y, m = start.year, start.month
            while True:
                d = date(y, m, 1)
                if d > end:
                    break
                if d >= start and (m - 1) % months == 0:
                    ticks.append(d)
                m += 1
                if m > 12:
                    y, m = y + 1, 1
            return ticks, "month"
    return [start, end], "day"


def day_label(d: date, with_weekday: bool = False) -> str:
    base = f"{d.day} {MOIS[d.month - 1]}"
    return f"{JOURS_COURTS[d.weekday()]} {base}" if with_weekday else base


def month_label(d: date) -> str:
    return f"{MOIS[d.month - 1]} {d.year}" if d.month == 1 else MOIS[d.month - 1].capitalize()


def long_date(d: date) -> str:
    return f"{JOURS_LONGS[d.weekday()]} {d.day} {MOIS_LONG[d.month - 1]} {d.year}"


def fmt_cm(v: Optional[float]) -> str:
    if v is None:
        return "—"
    if abs(v) < 1 and v != 0:
        return f"{v:.1f} cm"
    return f"{v:.0f} cm"
