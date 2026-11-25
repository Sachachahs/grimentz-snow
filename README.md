# Grimentz Snow – application mobile (Android / iOS)

Une vraie application mobile **Flutter** (compilée en natif), indépendante de ton PC : neige, météo MétéoSuisse,
webcams, domaine skiable et danger d'avalanche de Grimentz-Zinal, utilisable partout où il y a Internet.

L'application PC (`GrimentzSnowTracker`) n'est pas modifiée : ce projet est un dossier séparé.

---

## 1. Architecture

```
 Sources officielles                    Backend en ligne (gratuit)                 Téléphone
 ───────────────────                    ──────────────────────────                 ─────────
 MétéoSuisse (prévisions + mesures) ─┐
 Station / Info live (infosnow) ─────┼─► GitHub Actions, toutes les 15 min ──► data.json ──► App Flutter
 Calendrier officiel des remontées ──┘   (code Python de l'app PC, sans Qt)     (≈ 70 Ko)     (cache hors ligne)
 Webcams (trinum) ──────────────────────────────────────────────────────────────────────────► (direct)
```

**Choix retenu : option C** (le code Python existant tourne dans un backend en ligne).

| | Option A : l'app va tout chercher | **Option C : backend Python en ligne** |
|---|---|---|
| Prévisions MétéoSuisse | fichiers nationaux de ~30 Mo, lus par milliers de petites requêtes (~10 Mo par actualisation) : lent et coûteux en 4G | lus une seule fois par le serveur, le téléphone télécharge ~70 Ko |
| Réutilisation | tout réécrire en Dart (MétéoSuisse, infosnow, horaires, note, historique…) | le code Python de l'app PC est réutilisé tel quel |
| Correction si un site change | nouvelle version de l'app à installer | corriger le backend suffit, l'app ne change pas |
| Historique des relevés officiels | perdu à chaque réinstallation | conservé par le serveur |
| Notifications push | impossible sans serveur | le serveur détecte déjà les événements (`events.json`) |
| Coût | 0 | 0 (GitHub Actions, dépôt public) |

Le PC n'est jamais utilisé : le backend tourne sur les serveurs de GitHub, l'app lit les données publiées sur
`https://raw.githubusercontent.com/<ton-compte>/<dépôt>/data/data.json`.

### Contraintes liées aux sources

- **MétéoSuisse** : données ouvertes officielles (Open Government Data), utilisation libre avec mention « Source : MétéoSuisse ».
- **Station (Info live)** : ce n'est pas une API publique documentée (c'est celle qu'utilise la page Info live de
  valdanniviers.ch). Le backend l'interroge toutes les 15 min, comme l'app PC. Si le site change, l'app affiche
  « Donnée indisponible » et le backend garde la dernière version publiée, datée et marquée comme ancienne.
- **Webcams** : images officielles du fournisseur trinum, téléchargées directement par le téléphone.
- **Aucune donnée inventée** : une valeur absente est affichée « Donnée indisponible ». Hors connexion, l'app affiche
  les dernières données enregistrées avec leur date, jamais comme si elles étaient actuelles.
- Les heures affichées sont en **heure suisse**, où que tu sois.

---

## 2. Mise en ligne (une seule fois, ~10 minutes, sans rien installer)

1. Crée un compte gratuit sur <https://github.com> (si tu n'en as pas).
2. Crée un dépôt : bouton **New** → nom `grimentz-snow` → **Public** → **Create repository**.
3. Sur la page du dépôt vide : **uploading an existing file** → glisse **tout le contenu** du dossier
   `GrimentzSnowMobile` (dossiers `.github`, `backend`, `mobile` et ce fichier) → **Commit changes**.
4. Onglet **Actions** : deux tâches démarrent automatiquement.
   - **Données (backend)** : ~2 min, crée la branche `data` avec `data.json`. Ensuite elle se relance seule toutes les 15 min.
   - **Application (APK Android)** : ~10 min, compile l'application.
5. Quand les deux sont vertes : page du dépôt → **Releases** → **latest** → télécharge **GrimentzSnow.apk**.

> Si une tâche est rouge, ouvre-la pour voir l'erreur (ou demande à Claude de la corriger).

## 3. Installation sur le téléphone Android

1. Sur le téléphone, ouvre la page **Releases** du dépôt (`https://github.com/<ton-compte>/grimentz-snow/releases/latest`).
2. Touche **GrimentzSnow.apk** pour le télécharger, puis ouvre-le.
3. Android demande d'autoriser l'installation depuis le navigateur : **Paramètres → Autoriser cette source**, puis **Installer**.
4. L'icône **Grimentz Snow** apparaît sur l'écran d'accueil.

Pour une mise à jour : refais la même chose, l'app est mise à jour sans perdre ses données.
`GrimentzSnow-debug.apk` est une version de diagnostic (plus lente), inutile en temps normal.

## 4. Utilisation

- **Barre du bas** : Accueil, Neige, Météo, Webcams, Domaine. **⋮ (en haut à droite)** : cartes et liens officiels,
  activité récente, état des données, détail de la note, réglages.
- **Tirer vers le bas** sur un écran ou bouton ⟳ : actualiser. L'app s'actualise aussi seule toutes les 10 min et à chaque retour dans l'app.
- **Graphiques** : touche ou glisse le doigt pour afficher les valeurs ; choix de la période (7 jours → 1 an) ; séries activables.
- **Météo** : touche un jour pour le détail, balaie pour passer au jour suivant.
- **Webcams** : touche une image pour le plein écran, glisse pour changer de webcam, pince ou double-touche pour zoomer.
- **Hors connexion** : un bandeau orange l'indique ; les dernières données et webcams enregistrées restent visibles avec leur date.

---

## 5. Compiler soi-même (optionnel)

Uniquement si tu veux compiler sur ton PC au lieu de GitHub.

1. Installer Flutter : <https://docs.flutter.dev/get-started/install/windows/mobile> (avec Android Studio).
2. Dans le dossier `mobile` :
   ```
   flutter create --org ch.grimentzsnow --project-name grimentz_snow --platforms=android,ios .
   python tool/setup_platforms.py
   flutter pub get
   flutter run --dart-define=DATA_URL=https://raw.githubusercontent.com/<ton-compte>/grimentz-snow/data/data.json
   ```
3. APK : `flutter build apk --release --dart-define=DATA_URL=...` → `build/app/outputs/flutter-apk/app-release.apk`.

L'adresse des données peut aussi être changée dans l'app : **⋮ → Source des données → Modifier**.

## 6. Version iOS

Le code est le même (Flutter). Contraintes d'Apple :
- la compilation demande un **Mac** avec Xcode (ou un service cloud macOS) ;
- l'installation sur un iPhone demande un **compte développeur Apple** (99 $/an) ou, gratuitement, un Mac avec Xcode
  (l'app expire alors après 7 jours).

Vérification sans Mac : **Actions → Application (APK Android) → Run workflow → cocher « Compiler aussi la version iOS »**
(compilation non signée, pour vérifier que tout compile).

Avec un Mac : dans `mobile`, mêmes commandes qu'au §5 puis `open ios/Runner.xcworkspace`, choisir ton équipe de
signature dans Xcode et lancer sur l'iPhone.

## 7. Notifications push (prochaine étape)

Le backend détecte déjà les événements et les publie dans `events.json` (visibles dans l'app : ⋮ → Activité récente) :
nouvelle chute de neige importante, changement du danger d'avalanche, ouverture de la station, forte chute de neige prévue.

Pour les recevoir en notification : créer un projet Firebase (gratuit), ajouter `firebase_messaging` à l'app et
une étape d'envoi dans `.github/workflows/data.yml` (les seuils sont dans `backend/events.py`).

---

## 8. Structure du projet

```
GrimentzSnowMobile/
├─ .github/workflows/
│  ├─ data.yml           backend : collecte toutes les 15 min → branche « data »
│  └─ build-app.yml      compilation des APK (et iOS en option) → Release « latest »
├─ backend/
│  ├─ build_data.py      point d'entrée du backend
│  ├─ events.py          détection des événements (futures notifications)
│  ├─ requirements.txt
│  └─ app/               copie sans Qt du code de l'application PC (sources, services, snapshot)
└─ mobile/               application Flutter
   ├─ lib/
   │  ├─ main.dart       navigation (barre du bas), cycle de vie
   │  ├─ data/           téléchargement, cache hors ligne, webcams
   │  ├─ pages/          Accueil, Neige, Météo, Webcams, Domaine, Plus
   │  ├─ widgets/        cartes, graphiques tactiles, pictogrammes météo et avalanche
   │  └─ util/           formatage, heure suisse, lecture JSON sûre
   ├─ assets/icon/       icône de l'application
   ├─ tool/setup_platforms.py   réglages Android / iOS après « flutter create »
   └─ test/
```

### Mettre à jour le backend après une modification de l'app PC

Le dossier `backend/app` est une copie des fichiers sans Qt de l'app PC (`sources.py`, `config.py`, `http_client.py`,
`database.py`, `services/*.py`, `web/snapshot.py`). Après une correction dans l'app PC, recopier le fichier concerné
puis l'envoyer sur GitHub : le backend utilise la nouvelle version au passage suivant.
Exception : `backend/app/web/snapshot.py` contient quelques champs en plus (adresses et heures des webcams, liens
officiels, horodatage) : ne pas l'écraser avec la version du PC.
