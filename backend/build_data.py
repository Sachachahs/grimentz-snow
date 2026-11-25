"""Backend en ligne de l'application mobile Grimentz Snow.

Exécuté automatiquement par GitHub Actions (toutes les 15 min environ), jamais sur le PC de l'utilisateur.
Réutilise tel quel le code de l'application PC (dossier `app/`, copie sans Qt) :
prévisions locales MétéoSuisse, mesures MétéoSuisse, données officielles de la station (infosnow),
calendrier officiel des remontées, note de conditions, danger d'avalanche.

Produit dans le dossier de sortie (`--out`) :
- data.json      : l'instantané lu par l'application mobile (≈ 150 Ko) ;
- events.json    : changements notables depuis l'exécution précédente (base des futures notifications push) ;
- history.sqlite : historique des relevés officiels de la station (conservé d'une exécution à l'autre) ;
- status.json    : état de chaque source (succès / erreur), pour le diagnostic.

Règle de l'application : aucune donnée n'est inventée. Une source en erreur donne `null`
(affiché « Donnée indisponible » dans l'application) ou les dernières valeurs en cache, marquées comme anciennes.
"""
import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime
from pathlib import Path

os.environ.setdefault("TZ", "Europe/Zurich")
if hasattr(time, "tzset"):
    time.tzset()

sys.path.insert(0, str(Path(__file__).resolve().parent))

from app import sources  # noqa: E402
from app.database import Database  # noqa: E402
from app.http_client import HttpClient  # noqa: E402
from app.services import infosnow, weather  # noqa: E402
from app.services.score import compute_score  # noqa: E402
from app.web.snapshot import build_snapshot  # noqa: E402

import events  # noqa: E402

SCHEMA_VERSION = 1
log = logging.getLogger("backend")


def fresh_snow_fn(resort, wx, db):
    """Même règle que l'application PC (DataController.fresh_snow)."""
    def fresh_snow(hours):
        r = resort
        if r and r.snow_top and infosnow.is_recent(r.snow_top.modified_at, 3):
            if hours == 24 and r.snow_top.new_cm is not None:
                return r.snow_top.new_cm, "relevé officiel"
            v = db.official_new_snow_sum(sources.SNOW_POINT_TOP, hours // 24)
            if v is not None:
                return v, "officiel (historique local)"
        if wx:
            v = wx.obs.fresh_snow(hours // 24)
            if v is not None:
                return v, "mesure MétéoSuisse (Grimentz, 1512 m)"
        return None, ""
    return fresh_snow


def fetch_webcam_meta(client):
    """Heure de la dernière image de chaque webcam (l'application télécharge les images elle-même)."""
    meta = {}
    for i, cam in enumerate(sources.WEBCAMS):
        try:
            _, m = client.get_bytes(cam.url, ttl=60, force=True)
            meta[i] = m
        except Exception as exc:
            log.warning("Webcam %s : %s", cam.name, exc)
            meta[i] = str(exc)
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="out", help="dossier de sortie (branche « data »)")
    ap.add_argument("--cache", default=".cache", help="cache HTTP (runs MétéoSuisse déjà lus)")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    client = HttpClient(Path(args.cache))
    db = Database(out / "history.sqlite")
    status = {}

    previous = None
    if (out / "data.json").exists():
        try:
            previous = json.loads((out / "data.json").read_text(encoding="utf-8"))
        except Exception:
            previous = None

    wx = None
    try:
        wx = weather.fetch_weather(client, force=True)
        status["meteoswiss"] = {"ok": not wx.meta.stale, "error": wx.meta.error or None,
                                "run": wx.run.isoformat() if wx.run else None}
    except Exception as exc:
        log.exception("MétéoSuisse indisponible")
        status["meteoswiss"] = {"ok": False, "error": str(exc)}

    resort = None
    try:
        resort = infosnow.fetch_resort(client, force=True)
        db.save_snow(resort)
        stale = bool(getattr(resort.meta, "stale", False))
        if not getattr(resort.meta, "from_cache", False) and not stale:
            db.save_domain(resort)
        status["station"] = {"ok": not stale, "error": getattr(resort.meta, "error", "") or None,
                             "schedule": resort.schedule is not None}
    except Exception as exc:
        log.exception("Données de la station indisponibles")
        status["station"] = {"ok": False, "error": str(exc)}

    score = compute_score(resort, wx)
    cams = fetch_webcam_meta(client)
    status["webcams"] = {"ok": sum(1 for m in cams.values() if not isinstance(m, str)), "total": len(cams)}

    snap = build_snapshot(wx, resort, score, fresh_snow_fn(resort, wx, db), db, cams)
    snap["schema"] = SCHEMA_VERSION
    snap["sources_status"] = status
    # Si une source est en panne, on garde sa dernière version publiée plutôt que de tout effacer ;
    # elle reste datée (fetched_at) et marquée « stale » pour que l'application l'indique.
    if previous:
        if snap.get("weather") is None and previous.get("weather"):
            snap["weather"] = dict(previous["weather"], stale=True)
        if snap.get("domain") is None and previous.get("domain"):
            snap["domain"] = dict(previous["domain"], stale=True)

    new_events = events.diff(previous, snap)
    events.append(out / "events.json", new_events)

    tmp = out / "data.json.tmp"
    tmp.write_text(json.dumps(snap, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    tmp.replace(out / "data.json")
    (out / "status.json").write_text(json.dumps({"generated_at": snap["generated_at"], **status},
                                                ensure_ascii=False, indent=1), encoding="utf-8")
    db.conn.close()
    log.info("data.json écrit (%d octets), %d événement(s)", (out / "data.json").stat().st_size, len(new_events))
    # Échec seulement si TOUTES les sources sont tombées (pour être averti par GitHub)
    return 0 if (wx is not None or resort is not None) else 1


if __name__ == "__main__":
    sys.exit(main())
