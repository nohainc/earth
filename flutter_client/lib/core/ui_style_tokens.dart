import 'package:flutter/material.dart';
import 'ui_style.dart';

/// Central UI tokens loaded from the Dart development style map.
///
/// Values remain string-based and are converted at the renderer boundary.
class UiStyleTokens {
  UiStyleTokens._(this._root);

  final Map<String, dynamic> _root;
  static UiStyleTokens? _instance;

  static UiStyleTokens get current => _instance ??= UiStyleTokens._({});

  static Future<UiStyleTokens> load() async {
    return _setFromRoot(uiStyle);
  }

  static UiStyleTokens _setFromRoot(Map<String, dynamic> root) {
    final tokens = UiStyleTokens._(root);
    _instance = tokens;
    return tokens;
  }

  static Future<UiStyleTokens> reload() => load();

  dynamic get _ui => _root['ui'];

  String value(String path, [String fallback = '']) {
    dynamic current = _ui;
    for (final part in path.split('.')) {
      if (current is! Map || !current.containsKey(part)) return fallback;
      current = current[part];
    }
    return current?.toString() ?? fallback;
  }

  double number(String path, [double fallback = 0]) =>
      double.tryParse(value(path)) ?? fallback;

  int integer(String path, [int fallback = 0]) =>
      int.tryParse(value(path)) ?? fallback;

  Color color(String path, [Color fallback = Colors.transparent]) {
    final raw = value(path);
    final normalized = raw.startsWith('0x') ? raw.substring(2) : raw;
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }
}
