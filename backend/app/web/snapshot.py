"""Instantané JSON des données de l'application pour la version mobile web.

Aucune donnée n'est calculée ici différemment de l'application PC : on reprend les mêmes objets
(prévision MétéoSuisse, relevés de la station, calendrier officiel, note) et les mêmes règles.
Une valeur absente reste `null` (affichée « Donnée indisponible » par l'interface web).
"""
from datetime import date, datetime, timedelta

from .. import sources
from ..services import infosnow, snow_series
from ..services import weather as wx
from ..services.symbols import describe_symbol

AVALANCHE_COLORS = {1: "#76C82B", 2: "#FFD60A", 3: "#FF9F0A", 4: "#FF6A1A", 5: "#C8141E"}
AVALANCHE_NAMES = {1: "Faible", 2: "Limité", 3: "Marqué", 4: "Fort", 5: "Très fort"}
JOURS = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]


def _iso(v):
    if isinstance(v, datetime):
        return v.isoformat(timespec="minutes")
    if isinstance(v, date):
        return v.isoformat()
    return v


def _num(v, digits=1):
    if v is None:
        return None
    try:
        return round(float(v), digits)
    except (TypeError, ValueError):
        return None


# --------------------------------------------------------------------------- météo
def _point(pw):
    c = pw.current or {}
    d = pw.daily or {}
    h = pw.hourly or {}
    today = date.today()
    days = []
    for k, day in enumerate(d.get("time", [])):
        if day < today or len(days) >= 7:
            continue
        snow = d["snowfall_sum"][k]
        pp = d["precipitation_probability_max"][k]
        gdir = d["wind_direction_10m_dominant"][k]
        sun = d["sunshine_duration"][k]
        days.append({
            "date": _iso(day), "code": d["weather_code"][k], "desc": describe_symbol(d["weather_code"][k]),
            "tmin": _num(d["temperature_2m_min"][k]), "tmax": _num(d["temperature_2m_max"][k]),
            "snow": _num(snow), "precip": _num(d["precipitation_sum"][k]),
            "q10": _num(d["precipitation_q10"][k]), "q90": _num(d["precipitation_q90"][k]),
            # même règle que l'application PC : probabilité affichée seulement s'il est prévu de la neige
            "risk": ((f"{pp:.0f} %" if pp is not None else None) if (snow or 0) > 0 else "faible"),
            "gust": _num(d["wind_gusts_10m_max"][k], 0), "gust_dir": _num(gdir, 0),
            "gust_dir_txt": wx.wind_dir(gdir) if gdir is not None else None,
            "sun_h": _num(sun / 3600 if sun is not None else None),
        })
    now = datetime.now().replace(minute=0, second=0, microsecond=0)
    hourly = []
    for i, t in enumerate(h.get("time", [])):
        if now - timedelta(hours=1) <= t <= now + timedelta(days=5):
            hourly.append({"t": _iso(t), "temp": _num(h["temperature_2m"][i]), "precip": _num(h["precipitation"][i]),
                           "snow": _num(h["snowfall"][i]), "code": h["weather_code"][i],
                           "q10": _num(h.get("temperature_q10", [None] * (i + 1))[i]),
                           "q90": _num(h.get("temperature_q90", [None] * (i + 1))[i])})
    wd = c.get("wind_direction_10m")
    return {
        "key": pw.key, "name": pw.name, "elevation": int(pw.elevation),
        "current": {
            "time": _iso(c.get("time")), "temp": _num(c.get("temperature_2m")), "code": c.get("weather_code"),
            "desc": wx.describe(c.get("precipitation"), c.get("snowfall"), c.get("sunshine_min")),
            "wind": _num(c.get("wind_speed_10m"), 0), "wind_dir": wx.wind_dir(wd) if wd is not None else None,
            "gust": _num(c.get("wind_gusts_10m"), 0), "precip": _num(c.get("precipitation")),
            "snowfall": _num(c.get("snowfall")), "sun_min": _num(c.get("sunshine_min"), 0),
            "prob": _num(c.get("precipitation_probability"), 0), "freezing": _num(c.get("freezing_level_height"), 0),
        },
        "days": days, "hourly": hourly,
    }


def _weather(w):
    if w is None:
        return None
    e = w.obs.evo or {}
    return {
        "run": _iso(w.run), "fetched_at": w.fetched_at, "stale": bool(getattr(w.meta, "stale", False)),
        "points": [_point(w.village), _point(w.summit)],
        "evolene": {
            "time": _iso(w.obs.evo_time), "temp": _num(e.get("tre200s0")), "chill": _num(e.get("xchills0")),
            "hum": _num(e.get("ure200s0"), 0), "wind": _num(e.get("fu3010z0"), 0), "gust": _num(e.get("fu3010z1"), 0),
            "dir": wx.wind_dir(e.get("dkl010z0")) if e.get("dkl010z0") is not None else None,
        } if e else None,
    }


# --------------------------------------------------------------------------- neige
def _snow(w, r, fresh_snow, db):
    out = {"measures": [], "fresh": [], "last": None, "quality": None, "making": None, "avalanche": None,
           "fresh_days": {}, "history": [], "note": None}
    # enneigement actuel : Grimentz (MétéoSuisse 1512 m), bas et haut du domaine (station)
    h, hd = (w.obs.snow_height() if w else (None, None))
    out["measures"].append({"name": "Grimentz · MétéoSuisse", "altitude": "1512 m", "cm": _num(h, 0),
                            "when": f"MétéoSuisse · relevé du {hd:%d.%m.%Y}" if hd else None})
    for name, sp in (("Bas du domaine", r.snow_bottom if r else None), ("Haut du domaine", r.snow_top if r else None)):
        out["measures"].append({
            "name": name, "altitude": None,
            "cm": _num(sp.height_cm, 0) if sp and sp.height_cm is not None else None,
            "when": f"Station · relevé du {infosnow.format_date(sp.modified_at, True)}" if sp else None})
    for hours in (24, 48, 72):
        v, src = fresh_snow(hours)
        out["fresh"].append({"h": hours, "cm": _num(v, 0), "src": src or None})
    last = w.obs.last_snowfall() if w else None
    if last:
        amount = next((row[2] for row in reversed(w.obs.gri) if row[0] == last), None)
        out["last"] = {"date": _iso(last), "label": f"{JOURS[last.weekday()]} {last:%d.%m.%Y}", "cm": _num(amount, 0)}
    if r:
        q = [sp.quality for sp in r.snow.values() if sp.quality]
        out["quality"] = q[0] if q else None
        making = [sp.snow_making for sp in r.snow.values() if sp.snow_making is not None]
        out["making"] = None if not making else ("Oui" if any(making) else "Non")
        lvl = r.avalanche_level
        out["avalanche"] = {
            "level": lvl, "name": AVALANCHE_NAMES.get(lvl), "color": AVALANCHE_COLORS.get(lvl),
            "updated": infosnow.format_date(r.avalanche_modified, True) if r.avalanche_modified else None,
            "source": "Station (Info live, valdanniviers.ch)"}
        top = r.snow_top
        if not (top and infosnow.is_recent(top.modified_at)):
            out["note"] = ("Les relevés officiels ne sont pas encore actualisés pour la saison : cumuls de neige "
                           "fraîche et dernière chute d'après MétéoSuisse (Grimentz).")
    # neige fraîche quotidienne : mesures (Grimentz 1512 m) + prévisions par point (365 j max pour le menu)
    if w:
        today = date.today()
        days_v = snow_series.fresh_days(w.obs.gri, w.village.daily, today, past_days=365)
        days_s = snow_series.fresh_days([], w.summit.daily, today, past_days=1)
        out["fresh_days"] = {
            "village": [{"d": _iso(x.day), "m": _num(x.measured), "p": _num(x.precip), "f": _num(x.forecast),
                         "fp": _num(x.forecast_precip), "fut": x.is_future} for x in days_v],
            "summit": [{"d": _iso(x.day), "f": _num(x.forecast), "fp": _num(x.forecast_precip)} for x in days_s],
            "cumul_village": {str(hh): snow_series.forecast_cumul(w.village.hourly, datetime.now(), hh)
                              for hh in (24, 48, 168)},
            "cumul_summit": {str(hh): snow_series.forecast_cumul(w.summit.hourly, datetime.now(), hh)
                             for hh in (24, 48, 168)},
        }
    # historique : relevés officiels (un point par jour) + hauteur MétéoSuisse
    series = []
    for key, name, color in ((sources.SNOW_POINT_TOP, "Haut du domaine", "#398BEB"),
                             (sources.SNOW_POINT_STATION, "En station", "#35C6D9")):
        per_day = {}
        try:
            for row in db.snow_history(key, days=400):
                per_day[datetime.fromisoformat(row[0].replace(" ", "T")).date()] = row[1]
        except Exception:
            pass
        series.append({"key": str(key), "name": name, "color": color, "gap": 3,
                       "points": [[_iso(d), _num(v, 0)] for d, v in sorted(per_day.items())]})
    if w:
        series.append({"key": "meteoswiss", "name": "MétéoSuisse Grimentz 1512 m", "color": "#FFBE36", "gap": 1.5,
                       "points": [[_iso(d), _num(hs, 0)] for d, _, _, hs in w.obs.gri]})
    out["history"] = series
    return out


# --------------------------------------------------------------------------- domaine
def _open_count(n_open, total, items):
    if not total:
        return None
    prep = sum(1 for f in items if f.state == infosnow.PREPARING)
    return {"open": n_open or 0, "total": total, "prep": prep, "closed": max(0, total - (n_open or 0) - prep)}


def _facility(f):
    alt = (f"{f.height_valley} → {f.height_mountain} m" if f.height_valley and f.height_mountain
           else (f"{f.height_valley} m" if f.height_valley else None))
    return {"name": f.name, "number": f.number or None, "type": f.type_label, "state": f.state,
            "state_label": f.state_label, "alt": alt, "remark": f.remarks or (f.condition.capitalize() if f.condition else None),
            "length_km": _num(f.length_m / 1000 if f.length_m else None),
            "color": sources.SLOPE_COLORS.get(f.type_id)}


def _domain(r):
    if r is None:
        return None
    prep_km = sum((f.length_m or 0) for f in r.slopes if f.state == infosnow.PREPARING) / 1000.0
    prep_n = sum(1 for f in r.slopes if f.state == infosnow.PREPARING)
    prep_pct = (100.0 * prep_km / r.slopes_km_total if r.slopes_km_total
                else (100.0 * prep_n / r.slopes_total if r.slopes_total else None))
    today = date.today()
    sch = r.schedule
    hours = sch.hours_text().replace(" – ", "–") if sch else ""
    week = []
    for k in range(7):
        d = today + timedelta(days=k)
        sectors, cond = sch.plan(d) if sch else ((), False)
        if k == 0 and r.lifts_open:
            state, kind = "Ouvert", "open"
        elif sectors:
            state, kind = " + ".join(sectors) + ("*" if cond else ""), ("cond" if cond else "open")
        else:
            state, kind = "Fermé", "closed"
        week.append({"date": _iso(d), "label": "Aujourd'hui" if k == 0 else JOURS[d.weekday()],
                     "state": state, "kind": kind, "hours": hours if kind != "closed" else ""})
    nxt = sch.next_opening(today) if sch else None
    stations = {}
    for key in ("Grimentz", "Zinal", "Domaine"):
        lifts = sorted((f for f in r.lifts if f.sector == key), key=lambda f: f.name)
        slopes = sorted((f for f in r.slopes if f.sector == key), key=lambda f: (f.type_id, f.name))
        if lifts or slopes:
            stations[key] = {"lifts": [_facility(f) for f in lifts], "slopes": [_facility(f) for f in slopes],
                             "lifts_count": _open_count(sum(f.state == infosnow.OPEN for f in lifts), len(lifts), lifts),
                             "slopes_count": _open_count(sum(f.state == infosnow.OPEN for f in slopes), len(slopes),
                                                         slopes)}
    return {
        "fetched_at": r.fetched_at, "stale": bool(getattr(r.meta, "stale", False)),
        "lifts": _open_count(r.lifts_open, r.lifts_total, r.lifts),
        "slopes": _open_count(r.slopes_open, r.slopes_total, r.slopes),
        "km_open": _num(r.slopes_km_open), "km_total": _num(r.slopes_km_total, 0), "km_prep": _num(prep_km),
        "pct_open": _num(r.open_pct, 0), "pct_prep": _num(prep_pct, 0),
        "week": week, "season": sch.season if sch else None, "last_up": sch.last_up if sch else None,
        "next_opening": ({"date": _iso(nxt[0]), "label": f"{JOURS[nxt[0].weekday()]} {nxt[0]:%d.%m}",
                          "sectors": list(nxt[1]), "cond": nxt[2]} if nxt else None),
        "stations": stations, "closures": list(r.weather_closures),
        "official_snow_date": infosnow.format_date(r.snow_top.modified_at if r.snow_top else None, True),
    }


# --------------------------------------------------------------------------- webcams / note
def _webcams(cam_meta):
    out = []
    now = datetime.now()
    for i, cam in enumerate(sources.WEBCAMS):
        meta = cam_meta.get(i)
        ts = getattr(meta, "source_time", None) if meta is not None and not isinstance(meta, str) else None
        if ts is not None and not isinstance(ts, datetime):
            try:
                ts = datetime.fromtimestamp(float(ts))
            except (TypeError, ValueError):
                ts = None
        if ts:
            age = (now - ts).total_seconds()
            state = "old_day" if ts.date() != now.date() else ("ok" if age <= 30 * 60 else "old")
            txt = f"Image de {ts:%H:%M}" + ("" if ts.date() == now.date() else f" le {ts:%d.%m}")
        else:
            state, txt = ("unknown" if meta is not None else "none"), ("Heure inconnue" if meta is not None else "")
        out.append({"i": i, "name": cam.name, "altitude": cam.altitude, "sector": cam.sector, "time": txt,
                    "state": state, "has_image": meta is not None and not isinstance(meta, str),
                    "hd_url": cam.hd_url, "url": cam.url, "ts": ts.timestamp() if ts else None})
    return out


def _score(s):
    if s is None:
        return None
    return {"score": s.score, "label": s.label, "color": s.color, "reasons": list(s.reasons),
            "factors": [{"name": f.name, "points": f.points, "max": f.max_points, "detail": f.detail}
                        for f in s.factors]}


def build_snapshot(weather, resort, score, fresh_snow, db, cam_meta) -> dict:
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "generated_ts": datetime.now().timestamp(),
        "station": {"name": "Grimentz-Zinal", "region": "Valais, Suisse",
                    "altitude": f"{int(sources.POINT_VILLAGE.elevation)} m"},
        "weather": _weather(weather),
        "snow": _snow(weather, resort, fresh_snow, db),
        "domain": _domain(resort),
        "score": _score(score),
        "webcams": _webcams(cam_meta),
        "links": {"infolive": sources.OFFICIAL_INFOLIVE, "map": sources.OFFICIAL_MAP_URL,
                  "hours": sources.OFFICIAL_HOURS_PAGE, "webcams": sources.OFFICIAL_WEBCAMS_PAGE,
                  "piste_map_pdf": sources.OFFICIAL_PISTE_MAP_PDF, "site": sources.OFFICIAL_SITE,
                  "meteoswiss": sources.METEOSWISS_URL},
    }
