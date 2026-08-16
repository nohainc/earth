import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/nano_markup_helper.dart';

void main() {
  group('NanoMarkupHelper', () {
    test('encodes and decodes Nano Markup', () {
      final input = {
        'founder': 'H-001',
        'city': 'CITY-001',
        'active': 'true',
      };

      final encoded = NanoMarkupHelper.encode(input);
      expect(encoded.isNotEmpty, isTrue);

      final decoded = NanoMarkupHelper.decode(encoded);
      expect(decoded, isA<Map>());
      expect(decoded['founder'], equals('H-001'));
      expect(decoded['city'], equals('CITY-001'));
    });

    test('gracefully decodes fallback JSON strings', () {
      const jsonString = '{"title":"Tax Charter","rate":500}';
      final decoded = NanoMarkupHelper.decode(jsonString);

      expect(decoded, isA<Map>());
      expect(decoded['title'], equals('Tax Charter'));
      expect(decoded['rate'], equals(500));
    });
  });
}
