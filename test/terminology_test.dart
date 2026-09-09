/// Enforces the product's non-negotiable terminology.
///
/// Critical Rule 1 and requirement section 1: the monitoring role is
/// **Supervisor**, and the word "Coordinator" must not appear in the
/// application, its database roles, its UI or its schema.
///
/// This file is excluded from its own scan: it necessarily contains the term
/// it forbids.
///
/// A convention nobody checks is a convention that drifts, so this test reads
/// the source tree. Two scoping decisions keep it useful rather than noisy:
///
/// * **`lib/` and `firebase/` are scanned; `docs/` is not.** The docs discuss
///   this rule in prose, so scanning them for the word they define would
///   produce nothing but false positives. The product surface is what matters,
///   and the widget tests separately assert that the word never renders.
/// * **A line may opt out with [_optOutMarker].** Tests that assert the word's
///   absence necessarily contain it. An explicit marker makes each such line a
///   visible, reviewable decision instead of a silent exclusion. The marker
///   counts if it is on the line itself or within [_markerWindow] lines of it,
///   because `dart format` reflows a trailing comment onto its own line and a
///   check that broke on formatting would just get disabled.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The forbidden term, and the near-miss that reads the same way to a user.
const List<String> _forbiddenTerms = <String>[
  'coordinator',
  'co-ordinator',
]; // allow-coordinator-reference

/// A line carrying this marker is allowed to mention the term.
const String _optOutMarker = 'allow-coordinator-reference';

/// How far from the term the marker may sit and still apply.
const int _markerWindow = 2;

/// Directories that make up the shipped product and its schema.
const List<String> _scannedDirectories = <String>['lib', 'firebase', 'test'];

const List<String> _scannedExtensions = <String>['.dart', '.rules', '.json'];

List<File> _sourceFiles() {
  final List<File> files = <File>[];
  for (final String name in _scannedDirectories) {
    // Tests run with the package root as the working directory; `firebase/`
    // lives one level up, beside it.
    for (final String candidate in <String>[name, '../$name']) {
      final Directory directory = Directory(candidate);
      if (!directory.existsSync()) {
        continue;
      }
      files.addAll(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => _scannedExtensions.any(file.path.endsWith))
            .where(
              (File file) =>
                  !file.path.contains('/build/') &&
                  !file.path.contains('/.dart_tool/') &&
                  !file.path.endsWith('.g.dart') &&
                  !file.path.endsWith('.freezed.dart'),
            ),
      );
      break;
    }
  }
  return files;
}

/// Whether an opt-out marker sits on or near line [index].
bool _isMarkedNear(List<String> loweredLines, int index) {
  final int from = (index - _markerWindow).clamp(0, loweredLines.length - 1);
  final int to = (index + _markerWindow).clamp(0, loweredLines.length - 1);
  for (int i = from; i <= to; i++) {
    if (loweredLines[i].contains(_optOutMarker)) {
      return true;
    }
  }
  return false;
}

void main() {
  group('terminology', () {
    test('the forbidden term appears nowhere in the product', () {
      final List<String> offences = <String>[];

      for (final File file in _sourceFiles()) {
        // This file states and tests the rule, so it cannot obey it.
        if (file.uri.pathSegments.last == 'terminology_test.dart') {
          continue;
        }
        final List<String> lines = file.readAsLinesSync();
        final List<String> lowered = lines
            .map((String line) => line.toLowerCase())
            .toList(growable: false);
        for (int i = 0; i < lines.length; i++) {
          if (!_forbiddenTerms.any(lowered[i].contains)) {
            continue;
          }
          if (_isMarkedNear(lowered, i)) {
            continue;
          }
          offences.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }

      expect(
        offences,
        isEmpty,
        reason:
            'Use "Supervisor". If a line must mention the term (a test '
            'asserting its absence, say), append "$_optOutMarker" to it.\n'
            '${offences.join('\n')}',
      );
    });

    test('the scan actually reached the source tree', () {
      // Guards against the test above passing because it found no files. A
      // green check that checked nothing is worse than no check at all.
      final int scanned = _sourceFiles().length;
      expect(scanned, greaterThan(50), reason: 'only $scanned files scanned');
    });

    test('the opt-out marker applies within its window', () {
      // Proves the exclusion mechanism works, rather than assuming it.
      final List<String> lines = <String>[
        '// allow-coordinator-reference',
        'expect(role.wireName, isNot(theForbiddenName));',
        '',
        'somethingElse();',
      ];
      expect(_isMarkedNear(lines, 1), isTrue);
      expect(_isMarkedNear(lines, 3), isFalse);
    });
  });
}
