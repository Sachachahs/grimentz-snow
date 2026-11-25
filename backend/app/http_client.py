"""Client HTTP avec cache disque.

- Évite les requêtes inutiles : une réponse reste valable pendant `ttl` secondes.
- En cas d'erreur réseau, renvoie la dernière réponse en cache (marquée « stale »).
"""
import hashlib
import re
import json
import logging
import threading
import time
from dataclasses import dataclass
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .config import APP_DISPLAY_NAME, APP_VERSION

log = logging.getLogger(__name__)

USER_AGENT = f"{APP_DISPLAY_NAME.replace(' ', '')}/{APP_VERSION} (application personnelle de suivi d'enneigement)"


@dataclass
class FetchMeta:
    fetched_at: float          # horodatage de la récupération réelle
    from_cache: bool           # servi depuis le cache (sans requête)
    stale: bool = False        # cache périmé servi suite à une erreur réseau
    error: str = ""            # message d'erreur éventuel
    source_time: Optional[float] = None  # date de publication côté serveur (en-tête Last-Modified)


class FetchError(Exception):
    pass


class HttpClient:
    def __init__(self, cache_dir: Path, timeout: float = 20.0):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.timeout = timeout
        self._local = threading.local()

    # Une session par thread (requests.Session n'est pas garanti thread-safe)
    @property
    def session(self) -> requests.Session:
        s = getattr(self._local, "session", None)
        if s is None:
            s = requests.Session()
            s.headers.update({"User-Agent": USER_AGENT, "Accept-Language": "fr-CH,fr;q=0.9"})
            # Les serveurs coupent parfois une connexion (ex. MétéoSuisse : « connexion fermée par l'hôte
            # distant ») : on réessaie automatiquement, avec une courte attente croissante.
            retry = Retry(total=4, connect=4, read=2, status=3, backoff_factor=0.6,
                          status_forcelist=(429, 500, 502, 503, 504), allowed_methods=("GET", "HEAD"),
                          raise_on_status=False)
            adapter = HTTPAdapter(max_retries=retry, pool_maxsize=8)
            s.mount("https://", adapter)
            s.mount("http://", adapter)
            self._local.session = s
        return s

    def _key(self, method: str, url: str, params) -> str:
        raw = method + " " + url + " " + json.dumps(params or {}, sort_keys=True)
        return hashlib.sha1(raw.encode("utf-8")).hexdigest()

    # ------------------------------------------------------------------ JSON
    def get_json(self, url, params=None, ttl=600, force=False, method="GET", headers=None):
        key = self._key(method, url, params)
        path = self.cache_dir / f"{key}.json"
        cached = None
        if path.exists():
            try:
                cached = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                cached = None
        if cached and not force and time.time() - cached["fetched_at"] < ttl:
            return cached["data"], FetchMeta(cached["fetched_at"], True)
        try:
            resp = self.session.request(method, url, params=params, headers=headers, timeout=self.timeout)
            resp.raise_for_status()
            data = resp.json()
            now = time.time()
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps({"fetched_at": now, "url": url, "data": data}), encoding="utf-8")
            tmp.replace(path)
            return data, FetchMeta(now, False)
        except Exception as exc:
            msg = _describe(exc)
            log.warning("Échec %s %s : %s", method, url, msg)
            if cached:
                return cached["data"], FetchMeta(cached["fetched_at"], True, stale=True, error=msg)
            raise FetchError(msg) from exc

    # ------------------------------------------------------- accès bruts
    def head(self, url) -> requests.Response:
        # « identity » : sans compression, le serveur indique la taille réelle (Content-Length)
        return self.session.head(url, timeout=self.timeout, allow_redirects=True,
                                 headers={"Accept-Encoding": "identity"})

    def get_range(self, url, start: int, end: int) -> bytes:
        """Lit les octets [start, end] (inclus) d'un fichier distant (requête HTTP Range)."""
        resp = self.session.get(url, headers={"Range": f"bytes={max(0, start)}-{end}"}, timeout=self.timeout)
        if resp.status_code == 416:
            return b""
        resp.raise_for_status()
        if resp.status_code != 206 and start > 0:
            raise FetchError("Le serveur ne gère pas les lectures partielles")
        return resp.content

    def get_text(self, url, encoding="latin-1") -> str:
        resp = self.session.get(url, timeout=self.timeout)
        resp.raise_for_status()
        return resp.content.decode(encoding, errors="replace")

    # ----------------------------------------------------------------- bytes
    def get_bytes(self, url, ttl=180, force=False):
        """Image avec cache disque. Requête conditionnelle (If-Modified-Since) : si l'image n'a pas
        changé sur le serveur, rien n'est re-téléchargé (réponse 304)."""
        key = self._key("GET", url, None)
        path = self.cache_dir / f"{key}.bin"
        meta_path = self.cache_dir / f"{key}.meta"
        meta = {}
        if path.exists() and meta_path.exists():
            try:
                raw = meta_path.read_text()
                meta = json.loads(raw) if raw.startswith("{") else {"fetched_at": float(raw)}
            except Exception:
                meta = {}
        fetched_at, last_mod = meta.get("fetched_at"), meta.get("last_modified")
        src_time = meta.get("capture_time") or _http_time(last_mod)
        if fetched_at and src_time and not force and time.time() - fetched_at < ttl:
            return path.read_bytes(), FetchMeta(fetched_at, True, source_time=src_time)
        try:
            headers = {"Cache-Control": "no-cache"}
            if last_mod and path.exists():
                headers["If-Modified-Since"] = last_mod
            resp = self.session.get(url, timeout=self.timeout, headers=headers)
            now = time.time()
            if resp.status_code == 304 and path.exists():
                data = path.read_bytes()
                src_time = src_time or image_capture_time(data)
                meta_path.write_text(json.dumps({"fetched_at": now, "last_modified": last_mod,
                                                 "capture_time": src_time}))
                return data, FetchMeta(now, False, source_time=src_time)
            resp.raise_for_status()
            ctype = resp.headers.get("Content-Type", "")
            is_image = "image" in ctype or resp.content.startswith((b"\xff\xd8", b"\x89PNG"))
            if not is_image:
                raise FetchError(f"Réponse inattendue ({ctype or 'type inconnu'})")
            last_mod = resp.headers.get("Last-Modified")
            capture = image_capture_time(resp.content) or _http_time(last_mod)
            path.write_bytes(resp.content)
            meta_path.write_text(json.dumps({"fetched_at": now, "last_modified": last_mod,
                                             "capture_time": capture}))
            return resp.content, FetchMeta(now, False, source_time=capture)
        except Exception as exc:
            msg = _describe(exc)
            log.warning("Échec image %s : %s", url, msg)
            if fetched_at and path.exists():
                return path.read_bytes(), FetchMeta(fetched_at, True, stale=True, error=msg, source_time=src_time)
            raise FetchError(msg) from exc


_XMP_DATE = re.compile(rb"<exif:DateTimeOriginal>(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)")
_EXIF_DATE = re.compile(rb"(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)")


def image_capture_time(data: bytes) -> Optional[float]:
    """Heure de prise de vue lue dans les métadonnées de la photo (XMP/EXIF DateTimeOriginal),
    exprimée en heure locale de la caméra (Suisse = fuseau du PC)."""
    head = data[:131072]
    m = _XMP_DATE.search(head) or _EXIF_DATE.search(head)
    if not m:
        return None
    try:
        y, mo, d, h, mi, s = (int(x) for x in m.groups())
        return time.mktime((y, mo, d, h, mi, s, 0, 0, -1))
    except (ValueError, OverflowError):
        return None


def _http_time(value) -> Optional[float]:
    if not value:
        return None
    try:
        return parsedate_to_datetime(value).timestamp()
    except (TypeError, ValueError):
        return None


def _describe(exc: Exception) -> str:
    if isinstance(exc, requests.exceptions.ConnectionError):
        return "Pas de connexion au serveur"
    if isinstance(exc, requests.exceptions.Timeout):
        return "Délai d'attente dépassé"
    if isinstance(exc, requests.exceptions.HTTPError) and exc.response is not None:
        return f"Erreur HTTP {exc.response.status_code}"
    if isinstance(exc, ValueError):
        return "Réponse illisible"
    return str(exc) or exc.__class__.__name__
