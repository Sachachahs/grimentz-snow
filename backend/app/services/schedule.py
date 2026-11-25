"""Calendrier d'ouverture officiel de Grimentz-Zinal (page « Horaires » de valdanniviers.ch).

La page publie, pour la saison d'hiver, des lignes du type :
  « Ouverture anticipée | … ouverts les week-ends à partir du 28 novembre 2026* (sous réserve …) »
  « Secteur de Sorebois | … 7/7 jours dès le samedi 05 décembre 2026 »
  « Ouverture 7/7 jours des deux secteurs | Du vendredi 18 décembre 2026 au dimanche 11 avril 2027 »
et les heures (ouverture, dernière montée, dernière descente). On en déduit, pour un jour donné, les secteurs
dont l'ouverture est prévue. Rien n'est inventé : si la page ne peut pas être lue, le calendrier est vide.
"""
import html as htmllib
import json
import logging
import re
import time
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import List, Optional

from .. import sources

log = logging.getLogger(__name__)

MOIS = {"janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7,
        "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12}
DATE_RE = re.compile(r"(\d{1,2})(?:er)?\s+(" + "|".join(MOIS) + r")\s+(\d{4})", re.I)
SECTORS = ("Bendolla", "Sorebois")


@dataclass
class Rule:
    label: str
    text: str
    start: date
    end: Optional[date]
    weekends_only: bool
    sectors: tuple
    conditional: bool          # « sous réserve de conditions d'enneigement »


@dataclass
class Schedule:
    season: str = ""                       # ex. « Hiver 2026-2027 »
    rules: List[Rule] = field(default_factory=list)
    open_time: str = ""                    # « 09h00 »
    last_up: str = ""                      # « 16h00 »
    last_down: str = ""                    # « 16h30 »
    rows: list = field(default_factory=list)   # (libellé, texte) tels que publiés
    source_url: str = ""

    @property
    def season_end(self) -> Optional[date]:
        ends = [r.end for r in self.rules if r.end]
        return max(ends) if ends else None

    def plan(self, d: date):
        """(secteurs prévus ouverts, sous_réserve) pour le jour d ; secteurs vide = fermé selon le calendrier."""
        end_cap = self.season_end
        sectors: set = set()
        conditional, firm = False, False
        for r in self.rules:
            end = r.end or end_cap
            if d < r.start or (end and d > end):
                continue
            if r.weekends_only and d.weekday() < 5:
                continue
            sectors.update(r.sectors)
            if r.conditional:
                conditional = True
            else:
                firm = True
        return tuple(s for s in SECTORS if s in sectors), conditional and not firm

    def hours_text(self) -> str:
        if self.open_time and self.last_down:
            return f"{self.open_time} – {self.last_down}"
        return self.open_time or ""

    def next_opening(self, today: date, horizon_days=200):
        for k in range(horizon_days):
            d = date.fromordinal(today.toordinal() + k)
            sectors, cond = self.plan(d)
            if sectors:
                return d, sectors, cond
        return None


def _clean(fragment: str) -> str:
    fragment = re.sub(r'<span class="table-mobile-only">.*?</span>', " ", fragment, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", fragment)
    return re.sub(r"\s+", " ", htmllib.unescape(text)).strip()


def _dates(text: str) -> List[date]:
    out = []
    for d, m, y in DATE_RE.findall(text):
        try:
            out.append(date(int(y), MOIS[m.lower()], int(d)))
        except ValueError:
            pass
    return out


def parse(page: str, url: str = "") -> Schedule:
    sch = Schedule(source_url=url)
    m = re.search(r"<span>\s*(Hiver\s+\d{4}\s*-\s*\d{4})\s*</span>", page, re.I)
    if not m:
        return sch
    sch.season = m.group(1)
    rest = page[m.end():]
    stop = re.search(r'data-block="subtitle"|data-block=\'subtitle\'|data-block=\\"subtitle', rest)
    section = rest[:stop.start()] if stop else rest[:20000]
    for th, body in re.findall(r"<tr>\s*<th>(.*?)</th>(.*?)</tr>", section, re.S):
        label, text = _clean(th), _clean(body)
        if not label and not text:
            continue
        sch.rows.append((label, text))
        low = (label + " " + text).lower()
        if "ouverture des installations" in low:
            sch.open_time = text.replace("dès", "").strip()
            continue
        if "dernière montée" in low:
            sch.last_up = text
            continue
        if "dernière descente" in low:
            sch.last_down = text
            continue
        ds = _dates(text)
        if not ds:
            continue
        sectors: tuple
        if "deux secteurs" in low or ("bendolla" in low and "sorebois" in low):
            sectors = SECTORS
        elif "sorebois" in low:
            sectors = ("Sorebois",)
        elif "bendolla" in low:
            sectors = ("Bendolla",)
        else:
            sectors = SECTORS
        end = ds[1] if len(ds) >= 2 and re.search(r"\bau\b", text.lower()) else None
        sch.rules.append(Rule(label, text, ds[0], end, "week-end" in low or "weekend" in low, sectors,
                              "sous réserve" in low))
    return sch


def fetch_schedule(client, ttl: int = 6 * 3600) -> Optional[Schedule]:
    """Lit la page officielle (au plus toutes les 6 h ; repli sur la dernière version lue)."""
    url = sources.OFFICIAL_HOURS_PAGE
    path = Path(client.cache_dir) / "schedule_rmgz.json"
    cached = None
    if path.exists():
        try:
            cached = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            cached = None
    if cached and time.time() - cached.get("fetched_at", 0) < ttl:
        page = cached["html"]
    else:
        try:
            page = client.get_text(url, encoding="utf-8")
            path.write_text(json.dumps({"fetched_at": time.time(), "html": page}), encoding="utf-8")
        except Exception as exc:
            log.warning("Horaires officiels indisponibles : %s", exc)
            if not cached:
                return None
            page = cached["html"]
    sch = parse(page, url)
    return sch if sch.rules or sch.open_time else None
