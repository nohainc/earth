import 'dart:convert';
import 'package:nanomarkup/nanomarkup.dart' as nm;

/// Utility for serializing and deserializing payloads using Nano Markup.
class NanoMarkupHelper {
  /// Encodes a Dart Map, List, or primitive to a Nano Markup formatted string.
  static String encode(dynamic data) {
    if (data == null) return 'null';
    try {
      return nm.encode(data);
    } catch (_) {
      return jsonEncode(data);
    }
  }

  /// Decodes a Nano Markup string (or legacy JSON string) to dynamic / Map<String, dynamic>.
  static dynamic decode(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;

    // If it starts with JSON syntax, try jsonDecode first
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        // Fall through to nanomarkup
      }
    }

    try {
      final result = nm.decode(trimmed);
      return result;
    } catch (_) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        return trimmed;
      }
    }
  }
}
