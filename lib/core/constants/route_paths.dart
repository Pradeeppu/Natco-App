/// Route paths, in one place.
///
/// Declared as constants so a typo is a compile error rather than a
/// silently-broken deep link, and so the router, the navigation shell and the
/// tests all refer to the same strings.
library;

abstract final class RoutePaths {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String unauthorized = '/unauthorized';

  static const String dashboard = '/dashboard';

  static const String schools = '/schools';
  static const String schoolNew = '/schools/new';
  static const String schoolDetail = '/schools/:schoolId';

  static const String students = '/students';
  static const String studentNew = '/students/new';
  static const String studentImport = '/students/import';
  static const String studentDetail = '/students/:studentId';

  static const String users = '/users';
  static const String userNew = '/users/new';
  static const String userDetail = '/users/:userId';

  static const String assessments = '/assessments';
  static const String assessmentNew = '/assessments/new';
  static const String assessmentDetail = '/assessments/:assessmentId';
  static const String answerKey = '/assessments/:assessmentId/answer-key';

  static const String assessmentSession = '/assessment-session/:sessionId';

  static const String omrCapture = '/omr/capture';
  static const String omrReview = '/omr/review/:omrId';
  static const String omrValidationQueue = '/omr/validation';
  static const String omrValidationDetail = '/omr/validation/:omrId';

  static const String results = '/results';
  static const String studentResult = '/results/:studentId';

  static const String analytics = '/analytics';
  static const String reports = '/reports';
  static const String sync = '/sync';

  static const String settings = '/settings';
  static const String calibration = '/settings/calibration';

  /// Builds a concrete path from a parameterised one.
  ///
  /// `RoutePaths.of(RoutePaths.schoolDetail, {'schoolId': 's1'})`
  /// gives `/schools/s1`.
  static String of(String template, Map<String, String> params) {
    var path = template;
    for (final MapEntry<String, String> entry in params.entries) {
      path = path.replaceAll(':${entry.key}', Uri.encodeComponent(entry.value));
    }
    return path;
  }
}
