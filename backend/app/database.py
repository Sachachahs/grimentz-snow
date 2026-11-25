"""Historique local (SQLite) : relevés officiels de neige, état du domaine, note de conditions."""
import sqlite3
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS snow_reports (
    point_id INTEGER, label TEXT, snow_height REAL, snow_new REAL, last_snow TEXT,
    modified_at TEXT, recorded_at REAL, PRIMARY KEY (point_id, modified_at)
);
CREATE TABLE IF NOT EXISTS domain_snapshots (
    recorded_at REAL PRIMARY KEY, lifts_open INTEGER, lifts_total INTEGER,
    slopes_open INTEGER, slopes_total INTEGER, km_open REAL, km_total REAL
);
CREATE TABLE IF NOT EXISTS score_history (recorded_at REAL PRIMARY KEY, score INTEGER);
CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT);
"""


class Database:
    def __init__(self, path: Path):
        self.path = Path(path)
        self._lock = threading.Lock()
        self.conn = sqlite3.connect(str(self.path), check_same_thread=False)
        with self._lock:
            self.conn.executescript(SCHEMA)
            self.conn.commit()

    # ------------------------------------------------------------ neige
    def save_snow(self, resort):
        with self._lock:
            for sp in resort.snow.values():
                if not sp.modified_at:
                    continue
                self.conn.execute(
                    "INSERT OR IGNORE INTO snow_reports VALUES (?,?,?,?,?,?,?)",
                    (sp.id, sp.label, sp.height_cm, sp.new_cm, sp.last_snow, sp.modified_at, time.time()))
            self.conn.commit()

    def snow_history(self, point_id: int, days: int = 120):
        since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
        with self._lock:
            rows = self.conn.execute(
                "SELECT modified_at, snow_height, snow_new FROM snow_reports "
                "WHERE point_id=? AND modified_at>=? ORDER BY modified_at", (point_id, since)).fetchall()
        return rows

    def official_new_snow_sum(self, point_id: int, days: int):
        """Somme des neiges fraîches officielles (un relevé max. par jour) sur `days` jours.

        Renvoie None si l'historique local ne couvre pas chaque jour de la période
        (le chiffre serait alors trompeur)."""
        start = (datetime.now() - timedelta(days=days - 1)).date()
        with self._lock:
            rows = self.conn.execute(
                "SELECT substr(modified_at,1,10) d, MAX(snow_new) FROM snow_reports "
                "WHERE point_id=? AND substr(modified_at,1,10)>=? GROUP BY d", (point_id, start.isoformat())
            ).fetchall()
        if len(rows) < days:
            return None
        return sum(r[1] or 0 for r in rows)

    # ---------------------------------------------------------- domaine
    def save_domain(self, resort):
        with self._lock:
            self.conn.execute("INSERT OR REPLACE INTO domain_snapshots VALUES (?,?,?,?,?,?,?)",
                              (time.time(), resort.lifts_open, resort.lifts_total, resort.slopes_open,
                               resort.slopes_total, resort.slopes_km_open, resort.slopes_km_total))
            self.conn.commit()

    # ------------------------------------------------------------ score
    def save_score(self, score: int, min_interval=900):
        with self._lock:
            last = self.conn.execute("SELECT MAX(recorded_at) FROM score_history").fetchone()[0]
            if last and time.time() - last < min_interval:
                return
            self.conn.execute("INSERT INTO score_history VALUES (?,?)", (time.time(), score))
            self.conn.commit()

    def score_history(self, days=14):
        since = time.time() - days * 86400
        with self._lock:
            return self.conn.execute("SELECT recorded_at, score FROM score_history WHERE recorded_at>=? "
                                     "ORDER BY recorded_at", (since,)).fetchall()

    # --------------------------------------------------------------- kv
    def get(self, key, default=None):
        with self._lock:
            row = self.conn.execute("SELECT value FROM kv WHERE key=?", (key,)).fetchone()
        return row[0] if row else default

    def set(self, key, value):
        with self._lock:
            self.conn.execute("INSERT OR REPLACE INTO kv VALUES (?,?)", (key, str(value)))
            self.conn.commit()
