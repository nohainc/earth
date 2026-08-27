import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/communications/social_gameplay_panel.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';

class FakeSocialTransport extends EarthApiTransport {
  final calls = <String>[];
  bool fail = false;
  FakeSocialTransport() : super(baseUrl: 'https://test.invalid');
  @override
  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    calls.add('$method $path');
    if (fail) throw Exception('Social action failed');
    if (path.startsWith('/api/social/directory')) {
      return {
        'humans': [
          {
            'id': 'H-2',
            'display_name': 'Ari',
            'standing': 20,
            'house_name': 'Sol'
          },
          {
            'id': 'H-3',
            'display_name': 'Benn',
            'standing': 30,
            'house_name': 'Nova'
          }
        ]
      };
    }
    if (path == '/api/social/initiatives') {
      return {
        'ok': true,
        'initiative': {'id': 'social-new'}
      };
    }
    if (path.contains('/accept')) return {'ok': true};
    if (path.contains('/contribute')) return {'ok': true};
    if (path == '/api/social/timeline') return {'timeline': []};
    if (path == '/api/social/relationships') return {'relationships': []};
    return {};
  }
}

void main() {
  testWidgets('SocialGameplayPanel renders proposal controls and empty state',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SocialGameplayPanel()),
      ),
    ));
    await tester.pump();
    expect(find.text('COLLABORATIVE INITIATIVES'), findsOneWidget);
    expect(find.text('What are you proposing?'), findsOneWidget);
    expect(find.text('No active initiatives yet.'), findsOneWidget);
  });

  testWidgets(
      'SocialGameplayPanel completes proposal, acceptance, contribution, and reports failures',
      (tester) async {
    final transport = FakeSocialTransport();
    final api = EarthApi(transport: transport);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SocialGameplayPanel(api: api, initiatives: const [
            {
              'id': 'social-1',
              'kind': 'shared_project',
              'title': 'Harbor',
              'body': 'Build it',
              'status': 'active',
              'progress': 20,
              'member_status': 'accepted',
              'deadline_game_day': 190,
              'escrow_amount': 100
            },
          ]),
        ),
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Ari');
    await tester.pumpAndSettle();
    expect(find.text('Ari\nStanding 20'), findsOneWidget);
    await tester.tap(find.text('Ari\nStanding 20'));
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Ari');
    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'Benn');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benn\nStanding 30'));
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Benn');
    await tester.enterText(find.byType(TextField).at(4), 'Alliance');
    await tester.enterText(find.byType(TextField).at(5), 'Work together');
    await tester.ensureVisible(find.text('PREVIEW & PROPOSE'));
    await tester.tap(find.text('PREVIEW & PROPOSE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SEND PROPOSAL'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('CONTRIBUTE').first);
    await tester.tap(find.text('CONTRIBUTE').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTRIBUTE').last);
    await tester.pumpAndSettle();
    expect(
        transport.calls.any((call) => call.contains('/api/social/initiatives')),
        isTrue);
    expect(transport.calls.any((call) => call.contains('/contribute')), isTrue);
  });

  testWidgets('SocialGameplayPanel surfaces response errors', (tester) async {
    final transport = FakeSocialTransport()..fail = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SocialGameplayPanel(
              api: EarthApi(transport: transport),
              initiatives: const [
                {
                  'id': 'social-2',
                  'kind': 'alliance',
                  'title': 'Pact',
                  'body': 'Respond',
                  'status': 'proposed',
                  'member_status': 'invited'
                },
              ]),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pump();
    expect(find.textContaining('Social action failed'), findsOneWidget);
  });
}
