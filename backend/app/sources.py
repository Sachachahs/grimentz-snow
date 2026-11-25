"""Sources de données réelles utilisées par l'application.

Toutes les URL ci-dessous ont été vérifiées sur le site officiel du Val d'Anniviers
(https://www.valdanniviers.ch, vers lequel redirige https://www.grimentz-zinal.ch).
Aucune donnée n'est inventée : si une source ne répond pas, l'interface affiche
« Donnée indisponible ».
"""
from dataclasses import dataclass
from typing import Optional

# --------------------------------------------------------------------------- #
# Site officiel / données de la station (infosnow, utilisé par la page "Info live")
# --------------------------------------------------------------------------- #
OFFICIAL_SITE = "https://www.valdanniviers.ch/fr/Z30511/domaine-rmgz"
OFFICIAL_INFOLIVE = "https://www.valdanniviers.ch/fr/Z15114/infolive"
# Calendrier et horaires officiels des remontées mécaniques de Grimentz-Zinal
OFFICIAL_HOURS_PAGE = "https://www.valdanniviers.ch/fr/Z15372/horaires-rmgz"
OFFICIAL_WEBCAMS_PAGE = "https://www.valdanniviers.ch/fr/Z21601/noswebcams"

INFOSNOW_RESORT_ID = 56  # Grimentz / Zinal (CMS.infosnow.snowResortId sur le site officiel)
INFOSNOW_API = "https://www.valdanniviers.ch/mycity/ajax/infosnow/objects/{resort}"
INFOSNOW_FACILITIES = "lifts,slopes,toboganning,touring,hiking,funparks,cross-country,restaurants,divers"
INFOSNOW_REPORTS = "snow,dangers"

# Identifiants des points de mesure de neige (CMS.infosnow sur le site officiel)
SNOW_POINT_STATION = 508  # En station
SNOW_POINT_BOTTOM = 509   # En bas du domaine skiable
SNOW_POINT_TOP = 510      # En haut du domaine skiable

# Carte interactive officielle (iframe de la page "Plan Grimentz-Zinal")
OFFICIAL_MAP_URL = "https://infosnow.ch/~apgmontagne/?id=169&lang=fr&tab=map-wi"
OFFICIAL_PISTE_MAP_PDF = (
    "https://static.mycity.travel/manage/uploads/9/76/859904/2/plan-de-pistes-rmgz-hiver-25-26.pdf"
)
OFFICIAL_PLAN_PAGE = "https://www.valdanniviers.ch/fr/Z15412/plan-grimentz-zinal"
SNOW_REPORT_MYSWITZERLAND = "https://snow.myswitzerland.com/snow_reports/grimentzzinalanniviers-140"

# Libellés officiels (repris de CMS.infosnow.activityNames du site officiel)
FACILITY_TYPE_NAMES = {
    1: "Téléski", 2: "Téléski", 3: "Télésiège", 4: "Télésiège", 5: "Télésiège",
    6: "Télésiège", 7: "Télésiège", 8: "Funiculaire", 9: "Télécabine", 10: "Téléphérique",
    13: "Piste bleue", 14: "Piste rouge", 15: "Piste noire", 16: "Piste jaune",
    17: "Piste bleu / rouge", 18: "Piste rouge / noire", 58: "Tapis",
}
SLOPE_COLORS = {13: "#2F7BFF", 14: "#E5383B", 15: "#101010", 16: "#E0A800",
                17: "#E5383B", 18: "#101010"}

# --------------------------------------------------------------------------- #
# Météo : MétéoSuisse uniquement (Open Government Data, « Source : MétéoSuisse »)
# https://opendatadocs.meteoswiss.ch
# --------------------------------------------------------------------------- #
METEOSWISS_URL = "https://www.meteosuisse.admin.ch/"
METEOSWISS_OGD_DOC = "https://opendatadocs.meteoswiss.ch/e-forecast-data/e4-local-forecast-data"

# Prévisions locales (les mêmes que l'app MétéoSuisse), un fichier CSV par paramètre et par run horaire :
#   {base}/{AAAAMMJJ}-ch/vnut12.lssw.{AAAAMMJJHH00}.{parametre}.csv   (heures en UTC)
LOCAL_FORECAST_BASE = "https://data.geo.admin.ch/ch.meteoschweiz.ogd-local-forecasting"
# Pictogrammes officiels MétéoSuisse
WEATHER_SYMBOL_URL = "https://www.meteoswiss.admin.ch/static/resources/weather-symbols/{code}.svg"

# Mesures
# Station pluviométrique manuelle MétéoSuisse « Grimentz » (GRI, 1512 m) : précipitations,
# neige fraîche et hauteur de neige journalières.
GRI_DAILY_URL = "https://data.geo.admin.ch/ch.meteoschweiz.ogd-nime/gri/ogd-nime_gri_d_recent.csv"
# Station automatique SwissMetNet « Evolène / Villa » (EVO, 1825 m, vallée voisine) : valeurs 10 min.
EVO_NOW_URL = "https://data.geo.admin.ch/ch.meteoschweiz.ogd-smn/evo/ogd-smn_evo_t_now.csv"


@dataclass(frozen=True)
class ForecastPoint:
    key: str
    name: str
    point_id: int
    point_type: int     # 1 = station, 2 = code postal, 3 = point d'intérêt en montagne
    elevation: int
    lat: float
    lon: float


# Points de prévision officiels (fichier ogd-local-forecasting_meta_point.csv)
POINT_VILLAGE = ForecastPoint("village", "Grimentz", 396126, 2, 1577, 46.179247, 7.575481)
POINT_SUMMIT = ForecastPoint("summit", "Corne de Sorebois", 1122, 3, 2895, 46.150797, 7.586592)


# --------------------------------------------------------------------------- #
# Webcams officielles (page "Nos webcams" du site officiel)
# --------------------------------------------------------------------------- #
TRINUM = "https://www.trinum.com/ibox/FTPCam/"


@dataclass(frozen=True)
class Webcam:
    name: str
    altitude: int
    url: str        # image standard (600 px de haut) : galerie + actualisation automatique
    hd_url: str     # image « mega » pleine résolution : chargée seulement en plein écran
    sector: str


# Webcams officielles de la station (page « Nos webcams » de valdanniviers.ch).
# Le site les affiche via un proxy qui réduit les images (api.mycity.travel/proxy/webcam/334…337) ;
# on utilise directement les originaux du fournisseur (trinum), identifiés par leurs proportions
# identiques : 334 = Sorebois, 335 = Orzival (grand-plan), 336 = Espace Weisshorn (telepherique),
# 337 = Col du Pouce. Bendolla est une webcam supplémentaire de la station chez le même fournisseur.
WEBCAMS = [
    Webcam("Espace Weisshorn", 2700, TRINUM + "grimentz-zinal_telepherique.jpg",
           TRINUM + "mega_grimentz-zinal_telepherique.jpg", "Liaison Grimentz – Zinal"),
    Webcam("Sorebois", 2440, TRINUM + "grimentz-zinal_sorebois.jpg",
           TRINUM + "mega_grimentz-zinal_sorebois.jpg", "Zinal"),
    Webcam("Bendolla", 2130, TRINUM + "grimentz-zinal_bendolla.jpg",
           TRINUM + "mega_grimentz-zinal_bendolla.jpg", "Grimentz"),
    Webcam("Col du Pouce", 2812, TRINUM + "grimentz-zinal_col-du-pouce.jpg",
           TRINUM + "mega_grimentz-zinal_col-du-pouce.jpg", "Grimentz"),
    Webcam("Buvette Orzival", 2600, TRINUM + "grimentz-zinal_grand-plan.jpg",
           TRINUM + "mega_grimentz-zinal_grand-plan.jpg", "Grimentz"),
    Webcam("Barrage de Moiry", 2250, TRINUM + "val-d-anniviers_barrage-de-moiry.jpg",
           TRINUM + "mega_val-d-anniviers_barrage-de-moiry.jpg", "Val de Moiry"),
    Webcam("Cabane de Tracuit", 3256, TRINUM + "val-d-anniviers_cabane-de-tracuit.jpg",
           TRINUM + "mega_val-d-anniviers_cabane-de-tracuit.jpg", "Haute montagne (Zinal)"),
]
