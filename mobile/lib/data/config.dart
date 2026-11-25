/// Adresse des données publiées par le backend (GitHub Actions → branche « data »).
///
/// Fixée à la compilation par le workflow GitHub :
///   flutter build apk --dart-define=DATA_URL=https://raw.githubusercontent.com/<compte>/<dépôt>/data/data.json
/// Modifiable aussi dans l'application (Plus → Source des données).
const String kDefaultDataUrl = String.fromEnvironment('DATA_URL', defaultValue: '');

const String kAppName = 'Grimentz Snow';
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// Actualisation automatique tant que l'application est ouverte.
const Duration kAutoRefresh = Duration(minutes: 10);

/// Au-delà, les données sont signalées comme anciennes.
const Duration kStaleAfter = Duration(minutes: 90);

const String kUserAgent = 'GrimentzSnowMobile/$kAppVersion (application personnelle de suivi d\'enneigement)';
