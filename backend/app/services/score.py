"""Indicateur estimatif « Conditions de ski » (note sur 100).

Ce n'est PAS une mesure officielle : c'est une combinaison pondérée des données
disponibles. Si une donnée manque, son poids est retiré du calcul (et signalé).
"""
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from .infosnow import ResortData, is_recent

LEVELS = [
    (90, "Conditions exceptionnelles", "#7CF0B5"),
    (75, "Très bonnes conditions", "#4ADE80"),
    (60, "Bonnes conditions", "#A3E635"),
    (40, "Conditions moyennes", "#FBBF24"),
    (0, "Conditions difficiles", "#F87171"),
]


@dataclass
class Factor:
    name: str
    points: float
    max_points: float
    detail: str


@dataclass
class ScoreResult:
    score: Optional[int]
    label: str
    color: str
    factors: list = field(default_factory=list)
    reasons: list = field(default_factory=list)
    missing: list = field(default_factory=list)


def level_for(score: int):
    for threshold, label, color in LEVELS:
        if score >= threshold:
            return label, color
    return LEVELS[-1][1], LEVELS[-1][2]


def _lin(x, x0, x1):
    """0 en x0, 1 en x1 (borné)."""
    if x1 == x0:
        return 1.0
    return max(0.0, min(1.0, (x - x0) / (x1 - x0)))


def compute_score(resort: Optional[ResortData], weather) -> ScoreResult:
    factors, missing = [], []
    in_season = bool(resort and resort.snow_top and is_recent(resort.snow_top.modified_at))

    # 1) Neige fraîche (25 pts) — officielle si relevé récent, sinon modèle
    fresh, src = None, ""
    if in_season and resort.snow_top.new_cm is not None:
        fresh, src = resort.snow_top.new_cm, "relevé officiel"
    elif weather and weather.obs.fresh_snow(1) is not None:
        fresh, src = weather.obs.fresh_snow(1), "mesure MétéoSuisse Grimentz"
    if fresh is not None:
        factors.append(Factor("Neige fraîche", 25 * _lin(fresh, 0, 30), 25, f"{fresh:.0f} cm en 24 h ({src})"))
    else:
        missing.append("neige fraîche")

    # 2) Hauteur de neige (20 pts) — officielle uniquement
    if in_season and resort.snow_top.height_cm is not None:
        h = resort.snow_top.height_cm
        factors.append(Factor("Hauteur de neige", 20 * _lin(h, 20, 150), 20, f"{h:.0f} cm en haut du domaine"))
    else:
        missing.append("hauteur de neige officielle")

    if weather:
        cur = weather.summit.current
        # 3) Température en altitude (15 pts) : idéal entre -12 °C et -2 °C
        t = cur.get("temperature_2m")
        if t is not None:
            if -12 <= t <= -2:
                p = 1.0
            elif t > -2:
                p = 1 - _lin(t, -2, 6)
            else:
                p = _lin(t, -25, -12)
            factors.append(Factor("Température", 15 * p, 15, f"{t:.0f} °C à 2895 m (prévision MétéoSuisse)"))
        else:
            missing.append("température")
        # 4) Vent (15 pts) : rafales
        g = cur.get("wind_gusts_10m")
        if g is not None:
            factors.append(Factor("Vent", 15 * (1 - _lin(g, 20, 75)), 15, f"rafales {g:.0f} km/h en altitude"))
        else:
            missing.append("vent")
        # 5) Ensoleillement (10 pts) : durée d'ensoleillement prévue / durée du jour
        d = weather.summit.daily
        i = weather.summit.daily_index(datetime.now().date())
        sun_ratio = None
        if i is not None and d.get("sunshine_duration") and d.get("daylight_duration"):
            sd, dl = d["sunshine_duration"][i], d["daylight_duration"][i]
            if sd is not None and dl:
                sun_ratio = sd / dl
        if sun_ratio is not None:
            factors.append(Factor("Ensoleillement", 10 * _lin(sun_ratio, 0.1, 0.8), 10,
                                  f"{sd / 3600:.1f} h de soleil prévues aujourd'hui"))
        else:
            missing.append("ensoleillement")
    else:
        missing += ["température", "vent", "ensoleillement"]

    # 6) Pistes ouvertes (15 pts)
    pct = resort.open_pct if resort else None
    if pct is not None:
        factors.append(Factor("Pistes ouvertes", 15 * pct / 100, 15, f"{pct:.0f} % du domaine ouvert"))
    else:
        missing.append("pistes ouvertes")

    if not factors:
        return ScoreResult(None, "Donnée indisponible", "#8FA6C8", missing=missing)

    total = sum(f.points for f in factors)
    max_total = sum(f.max_points for f in factors)
    score = round(100 * total / max_total)

    reasons = []
    domain_closed = resort is not None and resort.lifts_total and resort.lifts_open == 0
    if domain_closed:
        score = min(score, 15)
        reasons.append("Domaine fermé : aucune remontée mécanique en service")
    # Raisons : les 2 points forts et les 2 points faibles
    ranked = sorted(factors, key=lambda f: f.points / f.max_points, reverse=True)
    for f in ranked[:2]:
        if f.points / f.max_points >= 0.6:
            reasons.append(f"✓ {f.name} : {f.detail}")
    for f in ranked[::-1][:2]:
        if f.points / f.max_points < 0.5:
            reasons.append(f"✗ {f.name} : {f.detail}")
    if missing:
        reasons.append("Non pris en compte (indisponible) : " + ", ".join(missing))

    label, color = level_for(score)
    return ScoreResult(score, label, color, factors, reasons, missing)
