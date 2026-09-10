/// Loads the bundled OMR template asset.
///
/// A thin wrapper around `rootBundle` so the domain layer's own
/// `OmrTemplate.fromJsonString` stays free of any Flutter dependency — it is
/// also called directly from a plain `dart run` script (the golden-dataset
/// harness, `tool/omr_eval.dart`), which has no `rootBundle` to load from.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';

/// The one template this app ships (docs/07-omr-pipeline.md §1).
const String kNatcoV1TemplateAsset = 'assets/omr_templates/natco_v1.json';

final class OmrTemplateLoader {
  const OmrTemplateLoader();

  Future<OmrTemplate> load(String assetPath) async {
    final String source = await rootBundle.loadString(assetPath);
    return OmrTemplate.fromJsonString(source);
  }
}
