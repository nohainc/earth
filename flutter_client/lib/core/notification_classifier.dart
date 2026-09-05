/// Shared utility to classify notifications into news (corporate/city)
/// vs personal (activity panel) buckets — ensuring zero duplication.
library;

/// Returns `true` if the notification is a corporate or city type
/// that should appear on the News page instead of the Notifications page.
bool isCorpOrCityNotification(Map<String, dynamic> n) {
  final type =
      (n['notification_type'] ?? n['type'] ?? '').toString().toLowerCase();
  final id = (n['id'] ?? '').toString().toLowerCase();

  // Explicit notification_type matches
  if (type == 'corporation' ||
      type == 'city' ||
      type == 'civic' ||
      type == 'technology' ||
      type == 'research') {
    return true;
  }

  // Substring matches on type
  if (type.contains('corp') ||
      type.contains('city') ||
      type.contains('civic')) {
    return true;
  }

  // ID prefix matches
  if (id.startsWith('corp-') ||
      id.startsWith('city-') ||
      id.startsWith('brownout-') ||
      id.startsWith('health-')) {
    return true;
  }

  return false;
}

/// Returns the news category for a notification: 'corporation', 'city', or 'world'.
String notificationNewsCategory(Map<String, dynamic> n) {
  final type =
      (n['notification_type'] ?? n['type'] ?? '').toString().toLowerCase();
  final id = (n['id'] ?? '').toString().toLowerCase();

  if (type == 'corporation' ||
      type == 'technology' ||
      type == 'research' ||
      type.contains('corp') ||
      id.startsWith('corp-')) {
    return 'corporation';
  }
  if (type == 'city' ||
      type == 'civic' ||
      type.contains('city') ||
      type.contains('civic') ||
      id.startsWith('city-') ||
      id.startsWith('brownout-') ||
      id.startsWith('health-')) {
    return 'city';
  }
  return 'world';
}
