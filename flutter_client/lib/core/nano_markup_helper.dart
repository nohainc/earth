import 'dart:convert';
import 'package:nanomarkup/nanomarkup.dart' as nm;

/// Utility for serializing and deserializing payloads using Nano Markup.
class NanoMarkupHelper {
  static dynamic _normalize(dynamic val) {
    if (val == null || val == 'null') return null;
    if (val is Map) {
      final map = <String, dynamic>{};
      for (final entry in val.entries) {
        map[entry.key.toString()] = _normalize(entry.value);
      }
      return map;
    }
    if (val is List) {
      return val.map((item) => _normalize(item)).toList();
    }
    return val;
  }

  static dynamic _toNanoTree(dynamic val) {
    if (val == null) return 'null';
    if (val is num || val is bool) return val.toString();
    if (val is String) return val;
    if (val is Map) {
      final map = <String, dynamic>{};
      for (final entry in val.entries) {
        map[entry.key.toString()] = _toNanoTree(entry.value);
      }
      return map;
    }
    if (val is List) {
      return val.map((item) => _toNanoTree(item)).toList();
    }
    return val.toString();
  }

  /// Encodes a Dart Map, List, or primitive to a Nano Markup formatted string.
  static String encode(dynamic data) {
    if (data == null) return 'null';
    try {
      final tree = _toNanoTree(data);
      return nm.encode(tree);
    } catch (_) {
      return jsonEncode(data);
    }
  }

  /// Decodes a Nano Markup string (or legacy JSON string) to dynamic or `Map<String, dynamic>`.
  static dynamic decode(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;

    // If it starts with JSON syntax, try jsonDecode first
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final decoded = jsonDecode(trimmed);
        return _normalize(decoded);
      } catch (_) {
        // Fall through to nanomarkup
      }
    }

    try {
      final result = nm.decode(trimmed);
      return _normalize(result);
    } catch (_) {
      try {
        final decoded = jsonDecode(trimmed);
        return _normalize(decoded);
      } catch (_) {
        return trimmed;
      }
    }
  }
}
