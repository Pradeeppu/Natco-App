/// Build environments.
///
/// Selected at build time with `--dart-define=NATCO_ENV=<name>`; nothing about
/// the environment is baked into source (requirement section 54).
library;

enum AppEnvironment {
  /// Local development against a development Firebase project.
  dev('dev'),

  /// Pre-production verification against a staging Firebase project.
  staging('staging'),

  /// Production.
  prod('prod'),

  /// No backend at all: in-memory services and seeded demo data.
  ///
  /// This exists so the whole application — routing, roles, screens — can be
  /// run and tested without a Firebase project, and so the widget tests
  /// exercise the same wiring the app uses (docs/53 seed data).
  demo('demo');

  const AppEnvironment(this.name);

  final String name;

  /// Resolves the environment from a `--dart-define` value.
  ///
  /// An unknown value is a build misconfiguration, and defaulting it to
  /// production would be the most dangerous possible guess — so it falls back
  /// to [AppEnvironment.demo], which cannot touch real data.
  static AppEnvironment fromName(String? value) => switch (value?.trim()) {
    'dev' => AppEnvironment.dev,
    'staging' => AppEnvironment.staging,
    'prod' => AppEnvironment.prod,
    'demo' => AppEnvironment.demo,
    _ => AppEnvironment.demo,
  };

  bool get usesFirebase => this != AppEnvironment.demo;

  bool get isProduction => this == AppEnvironment.prod;
}
