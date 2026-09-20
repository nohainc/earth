import 'package:flutter/material.dart';
import 'models/earth_state.dart';

enum NavigationGroup {
  command,
  house,
  economy,
  society,
  world;

  String get displayName => switch (this) {
        NavigationGroup.command => 'COMMAND',
        NavigationGroup.house => 'HOUSE',
        NavigationGroup.economy => 'ECONOMY',
        NavigationGroup.society => 'SOCIETY',
        NavigationGroup.world => 'WORLD',
      };

  IconData get icon => switch (this) {
        NavigationGroup.command => Icons.radar_rounded,
        NavigationGroup.house => Icons.shield_outlined,
        NavigationGroup.economy => Icons.apartment_rounded,
        NavigationGroup.society => Icons.account_balance_rounded,
        NavigationGroup.world => Icons.public_rounded,
      };
}

class NavigationItem {
  final String id;
  final String canonicalRoute;
  final List<String> aliases;
  final NavigationGroup group;
  final String defaultLabel;
  final String defaultPageTitle;
  final IconData icon;
  final bool isPrimary;
  final bool requiresCorporation;
  final String Function(EarthState state)? labelResolver;
  final String Function(EarthState? state)? titleResolver;

  const NavigationItem({
    required this.id,
    required this.canonicalRoute,
    this.aliases = const [],
    required this.group,
    required this.defaultLabel,
    required this.defaultPageTitle,
    required this.icon,
    this.isPrimary = true,
    this.requiresCorporation = false,
    this.labelResolver,
    this.titleResolver,
  });

  String getLabel(EarthState state) {
    if (labelResolver != null) {
      return labelResolver!(state);
    }
    return defaultLabel;
  }

  String getPageTitle(EarthState? state) {
    if (titleResolver != null) {
      return titleResolver!(state);
    }
    return defaultPageTitle;
  }
}

class NavigationRegistry {
  static const List<NavigationItem> items = [
    // --- COMMAND ---
    NavigationItem(
      id: 'command',
      canonicalRoute: 'command',
      aliases: ['overview'],
      group: NavigationGroup.command,
      defaultLabel: 'Overview',
      defaultPageTitle: 'OVERVIEW',
      icon: Icons.dashboard_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'briefing',
      canonicalRoute: 'briefing',
      aliases: ['statement', 'daily-summary'],
      group: NavigationGroup.command,
      defaultLabel: 'Daily Briefing',
      defaultPageTitle: 'DAILY BRIEFING',
      icon: Icons.today_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'news',
      canonicalRoute: 'news',
      aliases: [],
      group: NavigationGroup.command,
      defaultLabel: 'News',
      defaultPageTitle: 'NEWS',
      icon: Icons.newspaper_outlined,
      isPrimary: true,
    ),

    // --- HOUSE ---
    NavigationItem(
      id: 'life',
      canonicalRoute: 'life',
      aliases: ['human', 'citizen'],
      group: NavigationGroup.house,
      defaultLabel: 'Citizen',
      defaultPageTitle: 'CITIZEN',
      icon: Icons.person_outline_rounded,
      isPrimary: true,
      labelResolver: _resolveHumanLabel,
      titleResolver: _resolveHumanPageTitle,
    ),
    NavigationItem(
      id: 'house',
      canonicalRoute: 'house',
      aliases: [],
      group: NavigationGroup.house,
      defaultLabel: 'House',
      defaultPageTitle: 'HOUSE',
      icon: Icons.shield_outlined,
      isPrimary: true,
      labelResolver: _resolveHouseLabel,
    ),
    NavigationItem(
      id: 'finance',
      canonicalRoute: 'finance',
      aliases: ['personal-finance', 'net_worth'],
      group: NavigationGroup.house,
      defaultLabel: 'Finance',
      defaultPageTitle: 'FINANCE',
      icon: Icons.account_balance_wallet_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'policies',
      canonicalRoute: 'policies',
      aliases: ['automation', 'operating-rules'],
      group: NavigationGroup.house,
      defaultLabel: 'Automation',
      defaultPageTitle: 'AUTOMATION',
      icon: Icons.tune_outlined,
      isPrimary: true,
    ),

    // --- ECONOMY ---
    NavigationItem(
      id: 'buildings',
      canonicalRoute: 'buildings',
      aliases: ['assets', 'real_estate', 'operations'],
      group: NavigationGroup.economy,
      defaultLabel: 'Buildings',
      defaultPageTitle: 'BUILDINGS',
      icon: Icons.domain_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'market',
      canonicalRoute: 'market',
      aliases: ['trade'],
      group: NavigationGroup.economy,
      defaultLabel: 'Market',
      defaultPageTitle: 'MARKET',
      icon: Icons.swap_horiz_rounded,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'technology',
      canonicalRoute: 'technology',
      aliases: ['research', 'r-and-d'],
      group: NavigationGroup.economy,
      defaultLabel: 'Technology',
      defaultPageTitle: 'TECHNOLOGY',
      icon: Icons.biotech_outlined,
      isPrimary: true,
    ),

    // --- SOCIETY ---
    NavigationItem(
      id: 'corporation',
      canonicalRoute: 'corporation',
      aliases: ['my-corporation', 'organization'],
      group: NavigationGroup.society,
      defaultLabel: 'My Corporation',
      defaultPageTitle: 'MY CORPORATION',
      icon: Icons.account_balance_outlined,
      isPrimary: true,
      requiresCorporation: true,
      labelResolver: _resolveCorporationLabel,
      titleResolver: _resolveCorporationPageTitle,
    ),
    NavigationItem(
      id: 'corporations',
      canonicalRoute: 'corporations',
      aliases: ['directory', 'organizations'],
      group: NavigationGroup.society,
      defaultLabel: 'Corporations',
      defaultPageTitle: 'CORPORATIONS',
      icon: Icons.account_tree_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'territories',
      canonicalRoute: 'territories',
      // `city` is a deprecated transition alias only; V5 has no City entity.
      aliases: ['city', 'territory', 'territory-commons'],
      group: NavigationGroup.society,
      defaultLabel: 'Territories',
      defaultPageTitle: 'TERRITORIES',
      icon: Icons.map_outlined,
      // Keep the route and legacy aliases available for deep links, but do
      // not present Territory as a primary Society gameplay destination.
      isPrimary: false,
    ),
    NavigationItem(
      id: 'communities',
      canonicalRoute: 'communities',
      aliases: ['my-community'],
      group: NavigationGroup.society,
      defaultLabel: 'Communities',
      defaultPageTitle: 'COMMUNITIES',
      icon: Icons.diversity_3_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'civic',
      canonicalRoute: 'civic',
      aliases: ['governance', 'proposals', 'public-finance'],
      group: NavigationGroup.society,
      defaultLabel: 'Governance',
      defaultPageTitle: 'GOVERNANCE',
      icon: Icons.public_outlined,
      isPrimary: true,
    ),

    // --- WORLD ---
    NavigationItem(
      id: 'world',
      canonicalRoute: 'world',
      aliases: ['conditions', 'biosphere'],
      group: NavigationGroup.world,
      defaultLabel: 'Conditions',
      defaultPageTitle: 'CONDITIONS',
      icon: Icons.public_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'civic-rankings',
      canonicalRoute: 'civic-rankings',
      aliases: ['rankings', 'leaderboard'],
      group: NavigationGroup.world,
      defaultLabel: 'Rankings',
      defaultPageTitle: 'RANKINGS',
      icon: Icons.leaderboard_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'initiatives',
      canonicalRoute: 'initiatives',
      aliases: ['programs', 'public-projects', 'generations'],
      group: NavigationGroup.world,
      defaultLabel: 'Initiatives',
      defaultPageTitle: 'INITIATIVES',
      icon: Icons.rocket_launch_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'constitution',
      canonicalRoute: 'constitution',
      aliases: ['charter', 'rules', 'world-rules'],
      group: NavigationGroup.world,
      defaultLabel: 'Constitution',
      defaultPageTitle: 'CONSTITUTION',
      icon: Icons.gavel_outlined,
      isPrimary: true,
    ),
    NavigationItem(
      id: 'history',
      canonicalRoute: 'history',
      aliases: ['memorial', 'pantheon', 'archive'],
      group: NavigationGroup.world,
      defaultLabel: 'Memorial',
      defaultPageTitle: 'MEMORIAL',
      icon: Icons.military_tech_outlined,
      isPrimary: true,
    ),

    // --- SECONDARY / UTILITY ROUTES ---
    NavigationItem(
      id: 'account',
      canonicalRoute: 'account',
      aliases: ['profile', 'settings'],
      group: NavigationGroup.house,
      defaultLabel: 'Account',
      defaultPageTitle: 'ACCOUNT',
      icon: Icons.manage_accounts_outlined,
      isPrimary: false,
    ),
    NavigationItem(
      id: 'messages',
      canonicalRoute: 'messages',
      aliases: ['comm', 'comms'],
      group: NavigationGroup.society,
      defaultLabel: 'Messages',
      defaultPageTitle: 'MESSAGES',
      icon: Icons.forum_outlined,
      isPrimary: false,
    ),
    NavigationItem(
      id: 'notifications',
      canonicalRoute: 'notifications',
      aliases: ['activity'],
      group: NavigationGroup.command,
      defaultLabel: 'Notifications',
      defaultPageTitle: 'NOTIFICATIONS',
      icon: Icons.notifications_none_outlined,
      isPrimary: false,
    ),
    NavigationItem(
      id: 'contracts',
      canonicalRoute: 'contracts',
      aliases: [],
      group: NavigationGroup.economy,
      defaultLabel: 'Contracts',
      defaultPageTitle: 'CONTRACTS',
      icon: Icons.handshake_outlined,
      isPrimary: false,
    ),
    NavigationItem(
      id: 'mutual-credit',
      canonicalRoute: 'mutual-credit',
      aliases: [],
      group: NavigationGroup.society,
      defaultLabel: 'Mutual Credit',
      defaultPageTitle: 'MUTUAL CREDIT',
      icon: Icons.account_balance_outlined,
      isPrimary: false,
    ),
  ];

  static NavigationItem? findItem(String section) {
    final clean = normalizeRoute(section);
    for (final item in items) {
      if (item.id == clean || item.canonicalRoute == clean) return item;
      if (item.aliases.contains(clean)) return item;
    }
    return null;
  }

  static String normalizeRoute(String rawSection) {
    final section = rawSection.trim().toLowerCase();
    if (section.startsWith('my-community')) return 'communities';
    if (section.startsWith('messages')) return 'messages';

    for (final item in items) {
      if (item.id == section || item.canonicalRoute == section) {
        return item.canonicalRoute;
      }
      if (item.aliases.contains(section)) {
        return item.canonicalRoute;
      }
    }
    return section;
  }

  static int groupIndexForSection(String section) {
    final clean = normalizeRoute(section);
    if (clean == 'account' || clean == 'messages' || clean == 'notifications') {
      return -1;
    }
    if (clean.startsWith('my-community')) {
      return NavigationGroup.society.index;
    }
    final item = findItem(clean);
    if (item != null && item.isPrimary) {
      return item.group.index;
    }
    return -1;
  }

  static String pageTitle(String section, [EarthState? state]) {
    if (section.startsWith('my-community:')) {
      final communityId = section.substring('my-community:'.length);
      Map<String, dynamic>? community;
      for (final item
          in state?.myCommunities ?? const <Map<String, dynamic>>[]) {
        if (item['id']?.toString() == communityId) {
          community = item;
          break;
        }
      }
      final name = community?['name']?.toString().trim();
      return name == null || name.isEmpty ? 'COMMUNITY' : name.toUpperCase();
    }
    final clean = normalizeRoute(section);
    final item = findItem(clean);
    if (item != null) {
      return item.getPageTitle(state);
    }
    if (section.startsWith('messages')) return 'MESSAGES';
    if (section.startsWith('my-community')) return 'COMMUNITY';
    return section.toUpperCase().replaceAll('-', ' ');
  }

  static List<NavigationItem> itemsForGroup(
      NavigationGroup group, EarthState state) {
    final isCorpMember = state.membership?['corporation_id'] != null;
    final registered = items.where((item) {
      if (item.group != group) return false;
      if (!item.isPrimary) return false;
      if (item.requiresCorporation && !isCorpMember) return false;
      return true;
    }).toList();

    if (group != NavigationGroup.society) return registered;

    // Each active community the House belongs to gets a contextual Society
    // destination. The registry entry remains stable while the community
    // profile itself is loaded by the existing MyCommunityPanel route.
    final communityItems = <NavigationItem>[];
    final seen = <String>{};
    for (final community in state.myCommunities) {
      final id = community['id']?.toString().trim() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      final name = community['name']?.toString().trim();
      communityItems.add(
        NavigationItem(
          id: 'my-community:$id',
          canonicalRoute: 'my-community:$id',
          group: NavigationGroup.society,
          defaultLabel: name == null || name.isEmpty ? 'Community' : name,
          defaultPageTitle:
              name == null || name.isEmpty ? 'COMMUNITY' : name.toUpperCase(),
          icon: Icons.groups_outlined,
          isPrimary: true,
        ),
      );
    }
    return [...registered, ...communityItems];
  }

  static String _resolveHumanLabel(EarthState state) {
    final fullName = (state.human['name'] ??
            state.human['display_name'] ??
            state.life['name'] ??
            'Citizen')
        .toString()
        .trim();
    final tokens = fullName.split(RegExp(r'\s+'));
    return tokens.isNotEmpty && tokens.first.isNotEmpty
        ? tokens.first
        : 'Citizen';
  }

  static String _resolveHumanPageTitle(EarthState? state) {
    if (state == null) return 'CITIZEN';
    final raw =
        (state.human['display_name'] ?? state.human['name'])?.toString().trim();
    if (raw == null || raw.isEmpty) return 'CITIZEN';
    return raw.split(RegExp(r'\s+')).first.toUpperCase();
  }

  static String _resolveHouseLabel(EarthState state) {
    final rawHouseName = (state.life['houseName'] ??
            state.life['dynastyName'] ??
            state.human['house_name'] ??
            state.human['houseName'] ??
            state.human['dynasty_name'])
        ?.toString()
        .trim();

    if (rawHouseName != null && rawHouseName.isNotEmpty) {
      return rawHouseName.replaceFirst(
          RegExp(r'^house\s+(of\s+)?', caseSensitive: false), '');
    }

    final fullName =
        (state.human['name'] ?? state.human['display_name'])?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) {
      final tokens = fullName.split(RegExp(r'\s+'));
      if (tokens.length > 1 && tokens.last.isNotEmpty) {
        return tokens.last;
      }
    }
    return 'House';
  }

  static String _resolveCorporationLabel(EarthState state) {
    final corporation = state.institutions['corporation'];
    if (corporation is Map && corporation['name'] != null) {
      final name = corporation['name'].toString().trim();
      if (name.isNotEmpty) return name;
    }
    return 'My Corporation';
  }

  static String _resolveCorporationPageTitle(EarthState? state) {
    if (state != null) {
      final corporation = state.institutions['corporation'];
      if (corporation is Map && corporation['name'] != null) {
        final name = corporation['name'].toString().trim();
        if (name.isNotEmpty) return name.toUpperCase();
      }
    }
    return 'MY CORPORATION';
  }
}
