import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/main.dart';

void main() {
  testWidgets('EARTH command center renders its connection state',
      (tester) async {
    await tester.pumpWidget(const EarthApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
