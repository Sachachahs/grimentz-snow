"""Configuration de l'application (fichier JSON dans %LOCALAPPDATA%\\GrimentzSnowTracker)."""
import copy
import json
import logging
import os
import sys
from pathlib import Path

APP_NAME = "GrimentzSnowTracker"
APP_DISPLAY_NAME = "Grimentz Snow Tracker"
APP_VERSION = "1.0.0"

log = logging.getLogger(__name__)

DEFAULTS = {
    "refresh": {
        "weather_min": 20,      # Météo : 15 à 30 min
        "resort_min": 10,       # Enneigement / remontées : vérification toutes les 10 min
        "webcams_min": 3,       # Webcams : 1 à 5 min
    },
    "notifications": {
        "enabled": True,
        "snowing_now": True,
        "heavy_snow_forecast": True,
        "heavy_snow_threshold_cm": 20,
        "good_conditions": True,
        "good_conditions_threshold": 75,
        "domain_change": True,
        "domain_change_threshold_pct": 25,
    },
    "minimize_to_tray": True,
    "start_minimized": False,
    "web": {
        "enabled": True,        # version mobile sur le réseau local (lecture seule)
        "port": 8765,
    },
}


def app_data_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA")
    path = Path(base) / APP_NAME if base else Path.home() / ".local" / "share" / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def resource_path(relative: str) -> Path:
    """Chemin d'une ressource, compatible avec l'exécutable PyInstaller."""
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
    return base / relative


def _deep_merge(base: dict, override: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in (override or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


class Config:
    def __init__(self, path: Path | None = None):
        self.path = path or (app_data_dir() / "config.json")
        self.data = copy.deepcopy(DEFAULTS)
        self.load()

    def load(self):
        try:
            if self.path.exists():
                self.data = _deep_merge(DEFAULTS, json.loads(self.path.read_text(encoding="utf-8")))
        except Exception as exc:  # fichier corrompu => valeurs par défaut
            log.warning("Configuration illisible (%s), valeurs par défaut utilisées", exc)
            self.data = copy.deepcopy(DEFAULTS)

    def save(self):
        try:
            self.path.write_text(json.dumps(self.data, indent=2, ensure_ascii=False), encoding="utf-8")
        except Exception as exc:
            log.error("Impossible d'enregistrer la configuration : %s", exc)

    def get(self, dotted: str, default=None):
        node = self.data
        for part in dotted.split("."):
            if not isinstance(node, dict) or part not in node:
                return default
            node = node[part]
        return node

    def set(self, dotted: str, value):
        parts = dotted.split(".")
        node = self.data
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
