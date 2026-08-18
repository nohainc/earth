import 'navigation_deep_link_stub.dart'
    if (dart.library.html) 'navigation_deep_link_web.dart' as platform;

class NavigationDeepLink {
  static String? getInitialSection() => platform.getInitialDeepLinkSection();

  static void updateSection(String section) =>
      platform.updateDeepLinkSection(section);

  static void listen(void Function(String section) onSectionChange) =>
      platform.listenToDeepLinkChanges(onSectionChange);
}
