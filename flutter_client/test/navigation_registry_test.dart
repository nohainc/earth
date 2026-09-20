import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/navigation_registry.dart';

void main() {
  group('NavigationRegistry', () {
    test('normalizes canonical routes and legacy aliases', () {
      expect(NavigationRegistry.normalizeRoute('overview'), 'command');
      expect(NavigationRegistry.normalizeRoute('command'), 'command');
      expect(NavigationRegistry.normalizeRoute('daily-summary'), 'briefing');
      expect(NavigationRegistry.normalizeRoute('statement'), 'briefing');
      expect(NavigationRegistry.normalizeRoute('briefing'), 'briefing');
      expect(NavigationRegistry.normalizeRoute('automation'), 'policies');
      expect(NavigationRegistry.normalizeRoute('operating-rules'), 'policies');
      expect(NavigationRegistry.normalizeRoute('policies'), 'policies');
      expect(NavigationRegistry.normalizeRoute('assets'), 'buildings');
      expect(NavigationRegistry.normalizeRoute('real_estate'), 'buildings');
      expect(NavigationRegistry.normalizeRoute('buildings'), 'buildings');
      expect(NavigationRegistry.normalizeRoute('research'), 'technology');
      expect(NavigationRegistry.normalizeRoute('technology'), 'technology');
      expect(
          NavigationRegistry.normalizeRoute('my-corporation'), 'corporation');
      expect(NavigationRegistry.normalizeRoute('directory'), 'corporations');
      expect(NavigationRegistry.normalizeRoute('corporations'), 'corporations');
      expect(NavigationRegistry.normalizeRoute('governance'), 'civic');
      expect(NavigationRegistry.normalizeRoute('civic'), 'civic');
      expect(NavigationRegistry.normalizeRoute('programs'), 'initiatives');
      expect(
          NavigationRegistry.normalizeRoute('public-projects'), 'initiatives');
      expect(NavigationRegistry.normalizeRoute('initiatives'), 'initiatives');
      expect(
          NavigationRegistry.normalizeRoute('conditions'), 'world/conditions');
      expect(NavigationRegistry.normalizeRoute('world'), 'world/conditions');
      expect(NavigationRegistry.normalizeRoute('world/conditions'),
          'world/conditions');
      expect(NavigationRegistry.normalizeRoute('pantheon'), 'history');
      expect(NavigationRegistry.normalizeRoute('memorial'), 'history');
      expect(NavigationRegistry.normalizeRoute('history'), 'history');
      expect(NavigationRegistry.findItem('territory'), isNull);
      expect(NavigationRegistry.findItem('territory-commons'), isNull);
    });

    test('resolves correct group index for section', () {
      expect(NavigationRegistry.groupIndexForSection('command'), 0); // COMMAND
      expect(NavigationRegistry.groupIndexForSection('briefing'), 0);
      expect(NavigationRegistry.groupIndexForSection('news'), 0);

      expect(NavigationRegistry.groupIndexForSection('life'), 1); // HOUSE
      expect(NavigationRegistry.groupIndexForSection('house'), 1);
      expect(NavigationRegistry.groupIndexForSection('finance'), 1);
      expect(NavigationRegistry.groupIndexForSection('policies'), 1);

      expect(
          NavigationRegistry.groupIndexForSection('buildings'), 2); // ECONOMY
      expect(NavigationRegistry.groupIndexForSection('market'), 2);
      expect(NavigationRegistry.groupIndexForSection('technology'), 2);

      expect(
          NavigationRegistry.groupIndexForSection('corporation'), 3); // SOCIETY
      expect(NavigationRegistry.groupIndexForSection('corporations'), 3);
      // Hidden routes remain deep-linkable but do not open a primary group.
      expect(NavigationRegistry.groupIndexForSection('communities'), 3);
      expect(NavigationRegistry.groupIndexForSection('civic'), 3);

      expect(NavigationRegistry.groupIndexForSection('world/conditions'),
          4); // WORLD
      expect(NavigationRegistry.groupIndexForSection('civic-rankings'), 4);
      expect(NavigationRegistry.groupIndexForSection('initiatives'), 4);
      expect(NavigationRegistry.groupIndexForSection('constitution'), 4);
      expect(NavigationRegistry.groupIndexForSection('history'), 4);

      // Secondary / Footer / Utility routes do NOT expand accordion groups
      expect(NavigationRegistry.groupIndexForSection('account'), -1);
      expect(NavigationRegistry.groupIndexForSection('messages'), -1);
      expect(NavigationRegistry.groupIndexForSection('notifications'), -1);
      expect(NavigationRegistry.groupIndexForSection('unknown'), -1);
    });

    test(
        'resolves dynamic labels and titles correctly without hardcoded spelling changes',
        () {
      const state = EarthState({
        'human': {'name': 'Vitalii Noha', 'display_name': 'Vitalii Noha'},
        'life': {'houseName': 'House of Noha'},
        'membership': {'corporation_id': 'CORP-01'},
        'institutions': {
          'corporation': {'name': 'Aether Dynamics'},
        },
      });

      final humanItem = NavigationRegistry.findItem('life')!;
      expect(humanItem.getLabel(state), 'Vitalii');
      expect(humanItem.getPageTitle(state), 'VITALII');

      final houseItem = NavigationRegistry.findItem('house')!;
      expect(houseItem.getLabel(state), 'Noha');
      expect(houseItem.getPageTitle(state), 'HOUSE');

      final corpItem = NavigationRegistry.findItem('corporation')!;
      expect(corpItem.getLabel(state), 'Aether Dynamics');
      expect(corpItem.getPageTitle(state), 'AETHER DYNAMICS');

      // Society group items with corporation membership
      final societyItemsWithCorp = NavigationRegistry.itemsForGroup(
        NavigationGroup.society,
        state,
      );
      expect(
        societyItemsWithCorp.map((i) => i.id).toList(),
        ['corporation', 'corporations', 'communities', 'civic'],
      );

      // Society group items without corporation membership
      const independentState = EarthState({
        'human': {'name': 'Vitalii Noha'},
        'membership': {},
        'institutions': {},
      });
      final societyItemsWithoutCorp = NavigationRegistry.itemsForGroup(
        NavigationGroup.society,
        independentState,
      );
      expect(
        societyItemsWithoutCorp.map((i) => i.id).toList(),
        ['corporations', 'communities', 'civic'],
      );

      expect(NavigationRegistry.findItem('territories'), isNull);
    });

    test('keeps Communities as one stable sidebar destination', () {
      const state = EarthState({
        'membership': {},
        'communities': [
          {
            'id': 'COM-1',
            'name': 'First Community',
            'viewer': {'membershipStatus': 'ACTIVE', 'role': 'MEMBER'},
          },
          {
            'id': 'COM-2',
            'name': 'Second Community',
            'viewer': {'membershipStatus': 'ACTIVE', 'role': 'MEMBER'},
          },
        ],
      });

      final societyIds = NavigationRegistry.itemsForGroup(
        NavigationGroup.society,
        state,
      ).map((item) => item.id).toList();
      expect(societyIds, ['corporations', 'communities', 'civic']);
      expect(societyIds.where((id) => id.startsWith('community:')), isEmpty);
    });

    test('resolves page titles uniformly', () {
      expect(NavigationRegistry.pageTitle('command'), 'OVERVIEW');
      expect(NavigationRegistry.pageTitle('briefing'), 'DAILY BRIEFING');
      expect(NavigationRegistry.pageTitle('news'), 'NEWS');
      expect(NavigationRegistry.pageTitle('buildings'), 'BUILDINGS');
      expect(NavigationRegistry.pageTitle('technology'), 'TECHNOLOGY');
      expect(NavigationRegistry.pageTitle('market'), 'MARKET');
      expect(NavigationRegistry.pageTitle('policies'), 'AUTOMATION');
      expect(NavigationRegistry.pageTitle('initiatives'), 'INITIATIVES');
      expect(NavigationRegistry.pageTitle('world/conditions'), 'CONDITIONS');
      expect(NavigationRegistry.pageTitle('civic-rankings'), 'RANKINGS');
      expect(NavigationRegistry.pageTitle('constitution'), 'CONSTITUTION');
      expect(NavigationRegistry.pageTitle('history'), 'MEMORIAL');
      expect(NavigationRegistry.pageTitle('account'), 'ACCOUNT');
    });

    test('member community routes never resolve through the public directory',
        () {
      const memberState = EarthState({
        'communities': [
          {
            'id': 'COM-MEMBER',
            'name': 'Member Community',
            'viewer': {
              'membershipStatus': 'ACTIVE',
              'role': 'MEMBER',
            },
          },
          {
            'id': 'COM-PUBLIC',
            'name': 'Public Community',
            'viewer': {
              'membershipStatus': null,
              'role': null,
            },
          },
        ],
      });

      expect(
        NavigationRegistry.normalizeRoute('my-community:COM-MEMBER'),
        'community:COM-MEMBER',
      );
      expect(
        NavigationRegistry.normalizeRoute('community:COM-MEMBER'),
        'community:COM-MEMBER',
      );
      expect(
        NavigationRegistry.pageTitle('my-community:COM-MEMBER', memberState),
        'MEMBER COMMUNITY',
      );
      expect(
        NavigationRegistry.pageTitle('my-community:COM-PUBLIC', memberState),
        'COMMUNITY',
      );
      expect(memberState.myCommunities.map((row) => row['id']), ['COM-MEMBER']);
    });

    test('Community route identity is stable across rename and membership removal',
        () {
      const beforeRename = EarthState({
        'communities': [
          {
            'id': 'COM-STABLE',
            'name': 'Old Name',
            'viewer': {'membershipStatus': 'ACTIVE', 'role': 'MEMBER'},
          },
        ],
      });
      const afterRename = EarthState({
        'communities': [
          {
            'id': 'COM-STABLE',
            'name': 'New Name',
            'viewer': {'membershipStatus': 'ACTIVE', 'role': 'MEMBER'},
          },
        ],
      });
      const afterRemoval = EarthState({'communities': []});

      expect(NavigationRegistry.normalizeRoute('community:COM-STABLE'),
          'community:COM-STABLE');
      expect(NavigationRegistry.pageTitle('community:COM-STABLE', beforeRename),
          'OLD NAME');
      expect(NavigationRegistry.pageTitle('community:COM-STABLE', afterRename),
          'NEW NAME');
      expect(afterRemoval.myCommunities, isEmpty);
      expect(
        NavigationRegistry.itemsForGroup(NavigationGroup.society, afterRemoval)
            .map((item) => item.id)
            .where((id) => id.startsWith('community:')),
        isEmpty,
      );
    });
  });
}
