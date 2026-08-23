import 'dart:async';
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
    goldenFileComparator = TolerantGoldenComparator(
      testFileUri,
      tolerance: 0.05, // 5% tolerance absorbs Linux/macOS font rasterization without false positives
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
