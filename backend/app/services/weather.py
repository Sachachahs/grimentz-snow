"""Météo 100 % MétéoSuisse (Open Government Data – « Source : MétéoSuisse »).

* Prévisions locales officielles (les mêmes que l'app MétéoSuisse), run horaire, ~9 jours :
    - Grimentz (code postal 3961, point 396126, 1577 m)
    - Corne de Sorebois (point d'intérêt 1122, 2895 m) pour l'altitude
* Mesures :
    - station pluviométrique MétéoSuisse « Grimentz » (GRI, 1512 m) : neige fraîche,
      hauteur de neige, précipitations (valeurs journalières)
    - station automatique « Evolène / Villa » (EVO, 1825 m, vallée voisine) : valeurs 10 min
* Pictogrammes officiels MétéoSuisse.

La neige prévue (cm) n'est pas publiée par MétéoSuisse dans ces données : elle est ESTIMÉE à partir
des précipitations prévues et de la température prévue (1 mm d'eau ≈ 1 cm de neige fraîche).
"""
import calendar
import json
import logging
import math
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional

from .. import sources
from ..http_client import FetchError, FetchMeta, HttpClient
from . import ogd_csv

log = logging.getLogger(__name__)

HOURLY_PARAMS = ["tre200h0", "rre150h0", "fu3010h0", "fu3010h1", "dkl010h0", "sre000h0", "zprfr0hs",
                 "jww003i0", "rp0003i0", "treq10h0", "treq90h0", "rreq10h0", "rreq90h0"]
DAILY_PARAMS = ["jp2000d0", "tre200pn", "tre200px", "rka150p0", "rreq10p0", "rreq90p0"]
ALL_PARAMS = HOURLY_PARAMS + DAILY_PARAMS
POINTS = [sources.POINT_VILLAGE, sources.POINT_SUMMIT]

DIRS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]


def wind_dir(deg) -> str:
    if deg is None:
        return "—"
    return DIRS[int((float(deg) % 360) / 22.5 + 0.5) % 16]


def snow_from(precip_mm, temp_c) -> float:
    """Estimation de la neige fraîche (cm) : 1 mm ≈ 1 cm sous 0,5 °C, moitié entre 0,5 et 1,5 °C."""
    if not precip_mm or temp_c is None:
        return 0.0
    if temp_c <= 0.5:
        return precip_mm * 1.0
    if temp_c <= 1.5:
        return precip_mm * 0.5
    return 0.0


def describe(precip_mm, snow_cm, sun_min=None) -> str:
    """Résumé textuel déduit des valeurs MétéoSuisse (le pictogramme officiel est affiché à côté)."""
    if snow_cm and snow_cm >= 0.1:
        return "Neige"
    if precip_mm and precip_mm >= 0.1:
        return "Pluie"
    if sun_min is not None:
        if sun_min >= 40:
            return "Ensoleillé"
        if sun_min >= 10:
            return "Éclaircies"
    return "Sec"


def utc_to_local(stamp: str) -> datetime:
    """'AAAAMMJJHHMM' (UTC) -> datetime locale (fuseau du PC, Europe/Zurich)."""
    ts = calendar.timegm(time.strptime(stamp, "%Y%m%d%H%M"))
    return datetime.fromtimestamp(ts)


def daylight_seconds(day: date, lat: float) -> float:
    """Durée astronomique du jour (formule de la déclinaison solaire)."""
    n = day.timetuple().tm_yday
    decl = math.radians(23.44) * math.sin(math.radians(360 / 365 * (n - 81)))
    x = -math.tan(math.radians(lat)) * math.tan(decl)
    x = max(-1.0, min(1.0, x))
    return 2 * math.degrees(math.acos(x)) / 15 * 3600


def _num(v):
    try:
        f = float(v)
        return None if f in (32767, -32767, 99999) else f
    except (TypeError, ValueError):
        return None


# --------------------------------------------------------------------------- modèles
@dataclass
class PointWeather:
    key: str
    name: str
    elevation: float
    lat: float
    current: dict = field(default_factory=dict)
    hourly: dict = field(default_factory=dict)   # var -> list ; "time" -> list[datetime]
    daily: dict = field(default_factory=dict)    # var -> list ; "time" -> list[date]

    def hourly_between(self, start: datetime, end: datetime):
        return [i for i, t in enumerate(self.hourly.get("time", [])) if start <= t < end]

    def today_indices(self):
        start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        return self.hourly_between(start, start + timedelta(days=1))

    def daily_index(self, day):
        for i, d in enumerate(self.daily.get("time", [])):
            if d == day:
                return i
        return None

    def snowfall_last_hours(self, hours: int) -> Optional[float]:
        """Neige estimée par la prévision MétéoSuisse sur les dernières heures couvertes par le run."""
        end = datetime.now()
        idx = self.hourly_between(end - timedelta(hours=hours), end)
        if len(idx) < hours * 0.8:
            return None
        return round(sum(self.hourly["snowfall"][i] or 0 for i in idx), 1)


@dataclass
class Observations:
    evo: dict = field(default_factory=dict)        # dernière mesure 10 min d'Evolène
    evo_time: Optional[datetime] = None
    gri: List[tuple] = field(default_factory=list)  # [(date, précip mm, neige fraîche cm, hauteur cm)]

    def gri_recent(self) -> bool:
        return bool(self.gri) and (date.today() - self.gri[-1][0]).days <= 3

    def fresh_snow(self, days: int) -> Optional[float]:
        """Neige fraîche mesurée à Grimentz sur les `days` derniers relevés journaliers."""
        if not self.gri_recent():
            return None
        vals = [r[2] for r in self.gri[-days:]]
        if len(vals) < days or any(v is None for v in vals):
            return None
        return float(sum(vals))

    def snow_height(self):
        for r in reversed(self.gri):
            if r[3] is not None:
                return r[3], r[0]
        return None, None

    def last_snowfall(self) -> Optional[date]:
        for r in reversed(self.gri):
            if r[2] and r[2] > 0:
                return r[0]
        return None


@dataclass
class WeatherData:
    fetched_at: float
    meta: FetchMeta
    run: Optional[datetime]
    village: PointWeather
    summit: PointWeather
    obs: Observations
    icons: Dict[int, bytes] = field(default_factory=dict)

    def last_snowfall_date(self):
        return self.obs.last_snowfall()


# --------------------------------------------------------------------------- récupération
def _run_url(run: str, param: str) -> str:
    return f"{sources.LOCAL_FORECAST_BASE}/{run[:8]}-ch/vnut12.lssw.{run}.{param}.csv"


def find_latest_runs(client: HttpClient, max_back_hours=10, limit=3) -> list:
    """Runs publiés les plus récents (du plus récent au plus ancien), au plus `limit`."""
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    runs = []
    for h in range(max_back_hours):
        run = (now - timedelta(hours=h)).strftime("%Y%m%d%H00")
        try:
            if all(client.head(_run_url(run, p)).status_code == 200 for p in ("tre200h0", "jww003i0", "tre200px")):
                runs.append(run)
                if len(runs) >= limit:
                    break
        except Exception as exc:
            if runs:
                break
            raise FetchError(f"MétéoSuisse injoignable ({exc.__class__.__name__})") from exc
    return runs


def find_latest_run(client: HttpClient, max_back_hours=10) -> Optional[str]:
    runs = find_latest_runs(client, max_back_hours, limit=1)
    return runs[0] if runs else None


def _download_run(client: HttpClient, run: str) -> dict:
    """Lit, pour chaque paramètre, les lignes des deux points (≈ 10 Mo au lieu de ~500 Mo)."""
    horizon = (datetime.strptime(run, "%Y%m%d%H%M") + timedelta(days=8)).strftime("%Y%m%d%H%M")
    targets = [(p.point_id, p.point_type) for p in POINTS]

    sizes = {}

    def size_of(param):
        url = _run_url(run, param)
        resp = client.head(url)
        resp.raise_for_status()
        return param, int(resp.headers.get("Content-Length") or 0)

    def one(job):
        param, target = job
        url = _run_url(run, param)
        if sizes[param] and sizes[param] > 3_000_000:
            rows = ogd_csv.read_rows(client.get_range, url, sizes[param], [target], horizon)
        else:  # petit fichier (ou taille inconnue) : téléchargement complet, compressé par le serveur
            rows = ogd_csv.parse_text(client.get_text(url), [target], horizon)
        return param, f"{target[0]};{target[1]}", rows[target]

    # 4 connexions simultanées au plus : au-delà, le serveur MétéoSuisse coupe des connexions
    with ThreadPoolExecutor(max_workers=4) as ex:
        sizes.update(ex.map(size_of, ALL_PARAMS))
        jobs = [(p, t) for p in ALL_PARAMS for t in targets]
        results: dict = {p: {} for p in ALL_PARAMS}
        for param, key, rows in ex.map(one, jobs):
            results[param][key] = rows
    return {"run": run, "params": results}


def _load_observations(client: HttpClient) -> Observations:
    obs = Observations()
    try:
        text = client.get_text(sources.EVO_NOW_URL)
        lines = [l for l in text.splitlines() if l.strip()]
        hdr = lines[0].split(";")
        last = lines[-1].split(";")
        row = dict(zip(hdr, last))
        obs.evo = {k: _num(v) for k, v in row.items() if k not in ("station_abbr", "reference_timestamp")}
        obs.evo_time = datetime.fromtimestamp(
            calendar.timegm(time.strptime(row["reference_timestamp"], "%d.%m.%Y %H:%M")))
    except Exception as exc:
        log.warning("Mesures Evolène indisponibles : %s", exc)
    try:
        text = client.get_text(sources.GRI_DAILY_URL)
        lines = [l for l in text.splitlines() if l.strip()]
        hdr = lines[0].split(";")
        ix = {k: hdr.index(k) for k in ("reference_timestamp", "rre150d0", "hns000d0", "hto000d0") if k in hdr}
        for l in lines[1:]:
            p = l.split(";")
            d = datetime.strptime(p[ix["reference_timestamp"]][:10], "%d.%m.%Y").date()
            obs.gri.append((d, _num(p[ix["rre150d0"]]) if "rre150d0" in ix else None,
                            _num(p[ix["hns000d0"]]) if "hns000d0" in ix else None,
                            _num(p[ix["hto000d0"]]) if "hto000d0" in ix else None))
        obs.gri = obs.gri[-400:]   # ~1 an : période maximale du graphique historique
    except Exception as exc:
        log.warning("Mesures Grimentz indisponibles : %s", exc)
    return obs


def _icons(client: HttpClient, codes) -> Dict[int, bytes]:
    out = {}
    for c in sorted(codes):
        try:
            data, _ = client.get_bytes(sources.WEATHER_SYMBOL_URL.format(code=c), ttl=30 * 86400)
            out[c] = data
        except Exception:
            pass
    return out


def fetch_weather(client: HttpClient, force=False, cache_dir: Optional[Path] = None) -> WeatherData:
    cache_dir = Path(cache_dir or client.cache_dir)
    stale, error = False, ""
    try:
        runs = find_latest_runs(client)
        if not runs:
            raise FetchError("aucun run de prévision MétéoSuisse récent")
        raw, last_exc = None, None
        for run in runs:   # le plus récent d'abord ; s'il échoue, les runs précédents
            path = cache_dir / f"meteoswiss_run_{run}.json"
            if path.exists():  # un run publié ne change plus : inutile de le relire
                raw = json.loads(path.read_text(encoding="utf-8"))
                break
            try:
                raw = _download_run(client, run)
            except Exception as exc:
                last_exc = exc
                log.warning("Run MétéoSuisse %s illisible, essai du précédent", run, exc_info=True)
                continue
            path.write_text(json.dumps(raw), encoding="utf-8")
            for old in cache_dir.glob("meteoswiss_run_*.json"):
                if old != path:
                    old.unlink(missing_ok=True)
            break
        if raw is None:
            raise last_exc or FetchError("prévision MétéoSuisse illisible")
        fetched = time.time()
    except Exception as exc:  # repli sur le dernier run en cache
        log.warning("Prévision MétéoSuisse non actualisée, repli sur le dernier run en cache : %s", exc,
                    exc_info=True)
        cached = sorted(cache_dir.glob("meteoswiss_run_*.json"))
        if not cached:
            raise FetchError(str(exc) or "MétéoSuisse indisponible") from exc
        raw = json.loads(cached[-1].read_text(encoding="utf-8"))
        fetched, stale, error = cached[-1].stat().st_mtime, True, str(exc)
    obs = _load_observations(client)
    data = build(raw, obs, FetchMeta(fetched, False, stale=stale, error=error))
    codes = set()
    for p in (data.village, data.summit):
        codes.update(c for c in p.hourly.get("weather_code", []) if c)
        codes.update(c for c in p.daily.get("weather_code", []) if c)
    data.icons = _icons(client, codes)
    return data


# --------------------------------------------------------------------------- construction
def build(raw: dict, obs: Observations, meta: FetchMeta) -> WeatherData:
    params = raw["params"]
    points = []
    for fp in POINTS:
        key = f"{fp.point_id};{fp.point_type}"
        series = {p: {d: _num(v) for d, v in params.get(p, {}).get(key, [])} for p in ALL_PARAMS}
        pw = PointWeather(fp.key, fp.name, fp.elevation, fp.lat)
        stamps = sorted(series["tre200h0"])
        h = {"time": [utc_to_local(s) for s in stamps]}
        for name, p in (("temperature_2m", "tre200h0"), ("precipitation", "rre150h0"),
                        ("wind_speed_10m", "fu3010h0"), ("wind_gusts_10m", "fu3010h1"),
                        ("wind_direction_10m", "dkl010h0"), ("sunshine_min", "sre000h0"),
                        ("freezing_level_height", "zprfr0hs"), ("precipitation_probability", "rp0003i0"),
                        ("temperature_q10", "treq10h0"), ("temperature_q90", "treq90h0"),
                        ("precipitation_q10", "rreq10h0"), ("precipitation_q90", "rreq90h0")):
            h[name] = [series[p].get(s) for s in stamps]
        h["weather_code"] = [int(series["jww003i0"][s]) if series["jww003i0"].get(s) else None for s in stamps]
        h["snowfall"] = [round(snow_from(pr, t), 1) for pr, t in zip(h["precipitation"], h["temperature_2m"])]
        h["is_day"] = [(c < 100) if c else bool(sm) for c, sm in zip(h["weather_code"], h["sunshine_min"])]
        pw.hourly = h

        now = datetime.now()
        cur_i = max((i for i, t in enumerate(h["time"]) if t <= now), default=None)
        if cur_i is not None:
            pw.current = {k: h[k][cur_i] for k in h if k != "time"}
            pw.current["time"] = h["time"][cur_i]

        days = sorted({s[:8] for s in series["jp2000d0"]} | {s[:8] for s in series["tre200px"]})
        d = {"time": [datetime.strptime(x, "%Y%m%d").date() for x in days]}

        def daily_val(p, day):
            for s, v in series[p].items():
                if s[:8] == day:
                    return v
            return None

        d["weather_code"] = [int(v) if (v := daily_val("jp2000d0", x)) else None for x in days]
        d["temperature_2m_min"] = [daily_val("tre200pn", x) for x in days]
        d["temperature_2m_max"] = [daily_val("tre200px", x) for x in days]
        d["precipitation_sum"] = [daily_val("rka150p0", x) for x in days]
        d["precipitation_q10"] = [daily_val("rreq10p0", x) for x in days]
        d["precipitation_q90"] = [daily_val("rreq90p0", x) for x in days]
        for k in ("snowfall_sum", "wind_gusts_10m_max", "wind_direction_10m_dominant", "sunshine_duration",
                  "precipitation_probability_max", "daylight_duration"):
            d[k] = []
        for day in d["time"]:
            idx = [i for i, t in enumerate(h["time"]) if t.date() == day]
            full = len(idx) >= 20
            snow = sum(h["snowfall"][i] for i in idx) if idx else None
            d["snowfall_sum"].append(round(snow, 1) if snow is not None and full else None)
            gusts = [(h["wind_gusts_10m"][i], h["wind_direction_10m"][i]) for i in idx
                     if h["wind_gusts_10m"][i] is not None]
            g = max(gusts, default=None)
            d["wind_gusts_10m_max"].append(g[0] if g else None)
            d["wind_direction_10m_dominant"].append(g[1] if g else None)
            sun = [h["sunshine_min"][i] for i in idx if h["sunshine_min"][i] is not None]
            d["sunshine_duration"].append(sum(sun) * 60 if full and sun else None)
            pp = [h["precipitation_probability"][i] for i in idx if h["precipitation_probability"][i] is not None]
            d["precipitation_probability_max"].append(max(pp) if pp else None)
            d["daylight_duration"].append(daylight_seconds(day, fp.lat))
        pw.daily = d
        points.append(pw)

    run_dt = utc_to_local(raw["run"]) if raw.get("run") else None
    return WeatherData(meta.fetched_at, meta, run_dt, points[0], points[1], obs)
