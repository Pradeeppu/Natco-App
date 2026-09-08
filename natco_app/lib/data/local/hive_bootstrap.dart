/// Local storage initialisation.
///
/// Runs before anything reads a box, and before the first frame, because the
/// session restore that decides the first screen depends on it.
library;

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:natco_app/core/services/logger.dart';

/// Initialises Hive against the app's documents directory.
///
/// A failure here is logged and swallowed rather than fatal. The app can still
/// run — the user simply has to sign in, and offline persistence is
/// unavailable until the next launch. Crashing on a storage problem would
/// leave a field user with an app that will not open at all.
Future<void> initialiseLocalStorage({required AppLogger logger}) async {
  try {
    await Hive.initFlutter('natco');
  } catch (error, stackTrace) {
    logger.error(
      'local_storage_init_failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
