/// Backend and auth endpoints for EAGLE STUDY.
///
/// Defaults point to the hosted Render API and Neon Auth project, and can be
/// overridden at build time with `--dart-define=API_BASE_URL=...` or
/// `--dart-define=NEON_AUTH_BASE_URL=...`.
class ApiConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://stopwatch-4dul.onrender.com',
  );

  static const neonAuthBaseUrl = String.fromEnvironment(
    'NEON_AUTH_BASE_URL',
    defaultValue:
        'https://ep-dry-brook-biypy8ou.neonauth.c-5.ap-southeast-1.aws.neon.tech/neondb/auth',
  );
}
