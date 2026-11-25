"""Données officielles de la station (enneigement, remontées, pistes, avalanches).

Source : endpoint infosnow utilisé par la page « Info live » du site officiel
https://www.valdanniviers.ch (objet 56 = Grimentz / Zinal).
"""
import html
import logging
import re
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from .. import sources
from ..http_client import FetchError, FetchMeta, HttpClient

log = logging.getLogger(__name__)

OPEN, PREPARING, CLOSED = 1, 2, 3
STATE_LABELS = {OPEN: "Ouvert", PREPARING: "En préparation", CLOSED: "Fermé"}

AVALANCHE_LEVELS = {1: "1 – Faible", 2: "2 – Limité", 3: "3 – Marqué", 4: "4 – Fort", 5: "5 – Très fort"}

WEATHER_CLOSURE_WORDS = ("vent", "météo", "meteo", "tempête", "tempete", "visibilit", "avalanche",
                         "intempérie", "intemperie", "brouillard", "orage", "conditions")


@dataclass
class SnowPoint:
    id: int
    label: str
    height_cm: Optional[float]
    new_cm: Optional[float]
    last_snow: Optional[str]
    snow_making: Optional[bool]
    modified_at: Optional[str]
    quality: Optional[str] = None


@dataclass
class Facility:
    id: int
    name: str
    kind: str                # "lift" ou "slope"
    type_id: int
    type_label: str
    state: int               # OPEN / PREPARING / CLOSED
    condition: str           # libellé officiel (fr)
    sector: str              # "Grimentz", "Zinal" ou "Domaine"
    length_m: Optional[float] = None
    height_valley: Optional[int] = None
    height_mountain: Optional[int] = None
    valley: Optional[tuple] = None    # (lat, lon)
    mountain: Optional[tuple] = None  # (lat, lon)
    remarks: str = ""
    hours: str = ""
    modified_at: Optional[str] = None
    number: str = ""                  # numéro officiel de la piste (« initial »), ex. « 14a »

    @property
    def state_label(self):
        return STATE_LABELS.get(self.state, "Fermé")


@dataclass
class ResortData:
    fetched_at: float
    meta: FetchMeta
    snow: dict = field(default_factory=dict)           # id -> SnowPoint
    lifts: list = field(default_factory=list)
    slopes: list = field(default_factory=list)
    lifts_total: Optional[int] = None
    lifts_open: Optional[int] = None
    slopes_total: Optional[int] = None
    slopes_open: Optional[int] = None
    slopes_km_total: Optional[float] = None
    slopes_km_open: Optional[float] = None
    avalanche_level: Optional[int] = None
    avalanche_modified: Optional[str] = None
    official_modified_at: Optional[str] = None
    weather_closures: list = field(default_factory=list)
    hours: list = field(default_factory=list)
    schedule: Optional[object] = None                   # calendrier officiel (services.schedule.Schedule)

    # ------------------------------------------------------------- helpers
    @property
    def snow_top(self) -> Optional[SnowPoint]:
        return self.snow.get(sources.SNOW_POINT_TOP)

    @property
    def snow_bottom(self) -> Optional[SnowPoint]:
        return self.snow.get(sources.SNOW_POINT_BOTTOM)

    @property
    def snow_station(self) -> Optional[SnowPoint]:
        return self.snow.get(sources.SNOW_POINT_STATION)

    @property
    def open_pct(self) -> Optional[float]:
        if self.slopes_km_total:
            return 100.0 * (self.slopes_km_open or 0) / self.slopes_km_total
        if self.slopes_total:
            return 100.0 * (self.slopes_open or 0) / self.slopes_total
        return None

    def sector_stats(self, sector: str) -> dict:
        lifts = [f for f in self.lifts if f.sector == sector]
        slopes = [f for f in self.slopes if f.sector == sector]
        return {
            "lifts_total": len(lifts), "lifts_open": sum(f.state == OPEN for f in lifts),
            "slopes_total": len(slopes), "slopes_open": sum(f.state == OPEN for f in slopes),
        }


# ---------------------------------------------------------------------------
def fetch_resort(client: HttpClient, force: bool = False, ttl: int = 300) -> ResortData:
    url = sources.INFOSNOW_API.format(resort=sources.INFOSNOW_RESORT_ID)
    headers = {"Content-Type": "application/json", "Referer": sources.OFFICIAL_INFOLIVE,
               "X-Requested-With": "XMLHttpRequest"}
    params = {"facilities": sources.INFOSNOW_FACILITIES, "reports": sources.INFOSNOW_REPORTS}
    try:
        data, meta = client.get_json(url, params=params, ttl=ttl, force=force, method="POST", headers=headers)
        failed = meta.stale
    except FetchError:
        failed, data, meta = True, None, None
    if failed:
        # Le site peut exiger un cookie de session : on visite la page officielle puis on réessaie une fois.
        try:
            client.session.get(sources.OFFICIAL_INFOLIVE, timeout=client.timeout)
        except Exception:
            pass
        try:
            data, meta = client.get_json(url, params=params, ttl=ttl, force=True, method="POST", headers=headers)
        except FetchError:
            if data is None:
                raise
    res = parse_resort(data, meta)
    try:
        from . import schedule
        res.schedule = schedule.fetch_schedule(client)
    except Exception as exc:
        log.warning("Calendrier d'ouverture illisible : %s", exc)
    return res


def parse_resort(data: dict, meta: FetchMeta) -> ResortData:
    res = ResortData(fetched_at=meta.fetched_at, meta=meta)
    reports = (data or {}).get("reports") or {}
    facilities = (data or {}).get("facilities") or {}
    modified = []

    # --- Neige -----------------------------------------------------------
    for item in ((reports.get("snow") or {}).get("items") or []):
        tr = item.get("translation") or {}
        sp = SnowPoint(
            id=item.get("id"),
            label=tr.get("fr") or item.get("name") or "Point de mesure",
            height_cm=_num(item.get("snowHeight")),
            new_cm=_num(item.get("snowHeightNew")),
            last_snow=item.get("lastSnow"),
            snow_making=item.get("snowMaking"),
            modified_at=item.get("modifiedAt"),
            quality=_quality(item),
        )
        res.snow[sp.id] = sp
        if sp.modified_at:
            modified.append(sp.modified_at)

    # --- Avalanches ------------------------------------------------------
    for d in ((reports.get("dangers") or {}).get("items") or []):
        if d.get("type") == "avalanche" and d.get("state"):
            level = int(d["state"])
            if 1 <= level <= 5:
                res.avalanche_level = max(level, res.avalanche_level or 0)
                res.avalanche_modified = d.get("modifiedAt") or res.avalanche_modified

    # --- Remontées -------------------------------------------------------
    lifts = facilities.get("lifts") or {}
    for item in lifts.get("items") or []:
        res.lifts.append(_facility(item, "lift"))
    res.lifts_total = lifts.get("count", len(res.lifts)) if lifts else None
    if lifts:
        res.lifts_open = sum(f.state == OPEN for f in res.lifts)

    # --- Pistes ----------------------------------------------------------
    slopes = facilities.get("slopes") or {}
    for item in slopes.get("items") or []:
        if item.get("type") in (13, 14, 15, 16, 17, 18):
            res.slopes.append(_facility(item, "slope"))
    if slopes:
        res.slopes_total = len(res.slopes)
        res.slopes_open = sum(f.state == OPEN for f in res.slopes)
        if slopes.get("length"):
            res.slopes_km_total = slopes["length"] / 1000.0
            res.slopes_km_open = (slopes.get("length_open") or 0) / 1000.0

    for f in res.lifts + res.slopes:
        if f.modified_at:
            modified.append(f.modified_at)
        txt = (f.remarks + " " + f.condition).lower()
        if f.state != OPEN and any(w in txt for w in WEATHER_CLOSURE_WORDS):
            res.weather_closures.append(f"{f.name} : {f.remarks or f.condition}")
        if f.hours:
            res.hours.append(f"{f.name} : {f.hours}")

    res.official_modified_at = max(modified) if modified else None
    return res


# ---------------------------------------------------------------------------
def _facility(item: dict, kind: str) -> Facility:
    type_id = item.get("type") or 0
    cond = ((item.get("condition") or {}).get("translation") or {}).get("fr", "")
    valley, mountain = _coords(item)
    f = Facility(
        id=item.get("id"), name=item.get("name", "?"), kind=kind, type_id=type_id,
        type_label=sources.FACILITY_TYPE_NAMES.get(type_id, "Installation"),
        state=_state(item.get("state")), condition=cond,
        sector="Domaine",
        length_m=_num(item.get("length")),
        height_valley=item.get("heightValley"), height_mountain=item.get("heightMountain"),
        valley=valley, mountain=mountain,
        remarks=_clean_html(((item.get("stateRemarks") or {}).get("fr")) or ""),
        hours=_hours(item),
        modified_at=item.get("modifiedAt"),
        number=str(item.get("initial") or ""),
    )
    f.sector = _sector(f)
    return f


def _state(raw) -> int:
    # Correspondance officielle (getAvailableState sur le site) : 1 ouvert, 2 en préparation, sinon fermé
    return {1: OPEN, 2: PREPARING}.get(raw, CLOSED)


_COORD_RE = re.compile(r"Talstation\s+([\d.]+)\s*N\s*/\s*([\d.]+)\s*E.*?Bergstation\s+([\d.]+)\s*N\s*/\s*([\d.]+)\s*E",
                       re.S)


def _coords(item):
    desc = " ".join(str(v) for v in (item.get("description") or {}).values())
    m = _COORD_RE.search(desc)
    if m:
        a, b, c, d = map(float, m.groups())
        return (a, b), (c, d)
    c = item.get("coords") or {}
    if c.get("latitude") and c.get("longitude"):
        return (float(c["latitude"]), float(c["longitude"])), None
    return None, None


def _sector(f: Facility) -> str:
    name = f.name.lower()
    if "bendolla" in name or name.startswith("grimentz") or "orzival" in name:
        return "Grimentz"
    if "sorebois" in name or "zinal" in name:
        return "Zinal"
    if f.valley:
        # Bendolla (Grimentz) est au nord de 46.16°, Sorebois (Zinal) au sud
        return "Grimentz" if f.valley[0] >= 46.16 else "Zinal"
    # Les pistes n'ont pas de coordonnées dans le flux officiel, mais un numéro : sur le plan des pistes,
    # 01–26 sont les pistes de Grimentz (Forêt, Marenda, Tsarva, Lona, Becs…) et 30 et plus celles de Zinal
    # (Chamois, Chiesso, Durand, Tsarmettaz…).
    m = re.match(r"\s*(\d+)", f.number or "")
    if m:
        return "Grimentz" if int(m.group(1)) < 30 else "Zinal"
    return "Domaine"


def _hours(item: dict) -> str:
    for key, val in item.items():
        k = key.lower()
        if ("opening" in k or "operating" in k or "hours" in k) and val:
            if isinstance(val, dict):
                val = val.get("fr") or " ".join(str(v) for v in val.values())
            return _clean_html(str(val))
    return ""


def _quality(item: dict) -> Optional[str]:
    for key in ("snowCondition", "snowQuality", "quality", "condition"):
        v = item.get(key)
        if isinstance(v, dict):
            v = (v.get("translation") or {}).get("fr") or v.get("fr")
        if v:
            return str(v)
    return None


def _clean_html(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def _num(v):
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def format_date(iso: Optional[str], with_time=False) -> str:
    if not iso:
        return "Donnée indisponible"
    try:
        dt = datetime.fromisoformat(iso.replace(" ", "T"))
        return dt.strftime("%d.%m.%Y %H:%M" if with_time else "%d.%m.%Y")
    except ValueError:
        return iso


def is_recent(iso: Optional[str], days: int = 21) -> bool:
    """Vrai si le relevé officiel date de moins de `days` jours (sinon : hors saison)."""
    if not iso:
        return False
    try:
        dt = datetime.fromisoformat(iso.replace(" ", "T"))
        return (time.time() - dt.timestamp()) < days * 86400
    except ValueError:
        return False
