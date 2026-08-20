import 'dart:html' as html;

String? getInitialDeepLinkSection() {
  try {
    final hash = html.window.location.hash.replaceAll('#', '').trim();
    if (hash.isNotEmpty) {
      return hash;
    }
    final uri = Uri.parse(html.window.location.href);
    final sec = uri.queryParameters['section'];
    if (sec != null && sec.isNotEmpty) {
      return sec;
    }
  } catch (_) {}
  return null;
}

void updateDeepLinkSection(String section) {
  try {
    final currentHash = html.window.location.hash.replaceAll('#', '').trim();
    if (currentHash != section) {
      html.window.history.pushState(null, '', '#$section');
    }
  } catch (_) {}
}

void listenToDeepLinkChanges(void Function(String section) onSectionChange) {
  try {
    html.window.onHashChange.listen((_) {
      final hash = html.window.location.hash.replaceAll('#', '').trim();
      if (hash.isNotEmpty) {
        onSectionChange(hash);
      }
    });
  } catch (_) {}
}
