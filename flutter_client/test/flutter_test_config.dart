import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test configuration executed by the Flutter test runner before all tests.
/// Configures a tolerant golden comparator to accommodate cross-platform OS
/// font rasterization and anti-aliasing deltas between Linux CI (GitHub Actions)
/// and macOS.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (goldenFileComparator is LocalFileComparator) {
    final defaultComparator = goldenFileComparator as LocalFileComparator;
    final baseUri = defaultComparator.basedir;
    final testFileUri = baseUri.path.endsWith('/')
        ? Uri.parse('${baseUri}dummy_test.dart')
        : Uri.parse('$baseUri/dummy_test.dart');

    final isCI = Platform.environment['CI'] == 'true' ||
        Platform.environment['GITHUB_ACTIONS'] == 'true' ||
        !Platform.isMacOS;
    final envTolerance = double.tryParse(Platform.environment['GOLDEN_TOLERANCE'] ?? '');
    final tolerance = envTolerance ?? (isCI ? 0.25 : 0.08);

    goldenFileComparator = TolerantGoldenComparator(
      testFileUri,
      // Flutter on macOS and Linux CI differ in FreeType vs CoreText
      // text, antialiasing, and shadow rasterization.
      tolerance: tolerance,
    );
  }
  await testMain();
}

class TolerantGoldenComparator extends LocalFileComparator {
  final double tolerance;

  TolerantGoldenComparator(super.testFile, {this.tolerance = 0.03});

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed || result.diffPercent <= tolerance) {
      return true;
    }

    final String error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}
