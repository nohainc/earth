import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _violet = Color(0xff8b7cf6);
const _ink = Color(0xfff1f0ff);
const _canvas = Color(0xff111327);
const _surface = Color(0xff1b1e38);
const _muted = Color(0xff9698b5);
const _apiVersion = '2026-08';

void main() => runApp(const EarthApp());

class EarthApp extends StatelessWidget {
  const EarthApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EARTH — United Corporations',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _canvas,
          colorScheme: ColorScheme.fromSeed(seedColor: _violet, brightness: Brightness.dark),
          fontFamily: 'Manrope',
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: _ink,
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            color: _surface.withValues(alpha: .72),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white12),
            ),
          ),
          textTheme: ThemeData.dark().textTheme.apply(
                bodyColor: _ink,
                displayColor: _ink,
              ),
        ),
        home: const CommandCenter(),
      );
}

class EarthState {
  final Map<String, dynamic> json;
  const EarthState(this.json);
  Map<String, dynamic> get clock => json['clock'] as Map<String, dynamic>;
  Map<String, dynamic> get human => json['human'] as Map<String, dynamic>;
  Map<String, dynamic> get world => json['world'] as Map<String, dynamic>;
  Map<String, dynamic> get resources =>
      json['resources'] as Map<String, dynamic>;
  Map<String, dynamic> get business => json['business'] as Map<String, dynamic>;
  Map<String, dynamic> get technology =>
      (json['technology'] as Map<String, dynamic>)['research']
          as Map<String, dynamic>;
  Map<String, dynamic> get technologyRegistry =>
      (json['technology'] as Map<String, dynamic>);
  Map<String, dynamic> get governance =>
      json['governance'] as Map<String, dynamic>;
  Map<String, dynamic> get institutions =>
      json['institutions'] as Map<String, dynamic>;
  Map<String, dynamic> get life => json['life'] as Map<String, dynamic>;
  List<dynamic> get machines =>
      (json['machines'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get market =>
      (json['market'] as Map<String, dynamic>)['products']
          as Map<String, dynamic>;
  List<dynamic> get marketBook =>
      ((json['market'] as Map<String, dynamic>)['book'] as List<dynamic>?) ?? const [];
  List<dynamic> get marketTrades =>
      ((json['market'] as Map<String, dynamic>)['trades'] as List<dynamic>?) ?? const [];
  List<dynamic> get communities =>
      (json['communities'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get audit =>
      (json['audit'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get finance =>
      (json['finance'] as Map<String, dynamic>?) ?? const {};
  List<dynamic> get ledgerEntries =>
      (json['ledgerEntries'] as List<dynamic>?) ?? const [];
  List<dynamic> get publicActivity =>
      (json['publicActivity'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get rankings =>
      (json['rankings'] as Map<String, dynamic>?) ?? const {};
}

class EarthApi {
  final String baseUrl;
  const EarthApi({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('EARTH_API_URL',
                defaultValue: '');

  Future<dynamic> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = method == 'POST'
        ? await http.post(uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body ?? {}))
        : await http.get(uri);
    final apiVersion = response.headers['x-earth-api-version'];
    if (apiVersion != null && apiVersion != _apiVersion) {
      throw Exception('Incompatible EARTH API version $apiVersion (expected $_apiVersion)');
    }
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final requestId = response.headers['x-request-id'];
      throw Exception(decoded is Map
          ? '${decoded['error'] ?? 'Request failed'}${requestId == null ? '' : ' (request $requestId)'}'
          : 'Request failed${requestId == null ? '' : ' (request $requestId)'}');
    }
    return decoded;
  }

  Future<EarthState> world() async =>
      EarthState(await _request('/api/world') as Map<String, dynamic>);
  Future<EarthState> advanceDay() async {
    await _request('/api/day/advance', method: 'POST');
    return world();
  }

  Future<EarthState> setPolicy(String policy) async {
    await _request('/api/businesses/kline-works/policy',
        method: 'POST', body: {'policy': policy});
    return world();
  }

  Future<EarthState> fundResearch() async {
    await _request('/api/technology/TECH-001/fund',
        method: 'POST', body: {'amount': 240});
    return world();
  }

  Future<EarthState> grantPatent() async {
    await _request('/api/technology/TECH-001/patent', method: 'POST');
    return world();
  }

  Future<EarthState> licenseTechnology() async {
    await _request('/api/technology/TECH-001/license', method: 'POST', body: {
      'licenseeId': 'H-0044',
      'royaltyRate': 0.05,
    });
    return world();
  }

  Future<EarthState> maintainMachine(String machineId) async {
    await _request('/api/machines/$machineId/maintenance',
        method: 'POST', body: {'amount': 10});
    return world();
  }

  Future<EarthState> submitOrder(String product, double limitPrice) async {
    await _request('/api/market/orders', method: 'POST', body: {
      'product': product,
      'quantity': 1,
      'limitPrice': limitPrice,
    });
    return world();
  }

  Future<EarthState> settleMarket(String product) async {
    await _request('/api/market/settle',
        method: 'POST', body: {'product': product});
    return world();
  }

  Future<EarthState> registerSuccessor(String name) async {
    await _request('/api/successor', method: 'POST', body: {'name': name});
    return world();
  }

  Future<EarthState> vote(String choice) async {
    await _request('/api/governance/proposals/042/vote',
        method: 'POST', body: {'vote': choice});
    return world();
  }

  Future<EarthState> setCityBudget(String category) async {
    await _request('/api/cities/CITY-0084/budget', method: 'POST', body: {
      'category': category,
      'amount': 0,
    });
    return world();
  }

  Future<EarthState> joinCorporation() async {
    await _request('/api/corporations/CORP-001/membership', method: 'POST', body: {'humanId': 'H-0044'});
    return world();
  }

  Future<EarthState> createCommunity() async {
    await _request('/api/communities', method: 'POST', body: {
      'name': 'Carthage Makers',
      'founderId': 'H-0044',
    });
    return world();
  }
}

class CommandCenter extends StatefulWidget {
  const CommandCenter({super.key});
  @override
  State<CommandCenter> createState() => _CommandCenterState();
}

class _CommandCenterState extends State<CommandCenter> {
  final api = const EarthApi();
  EarthState? state;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _run(api.world);
  }

  Future<void> _run(Future<EarthState> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await action();
      if (mounted) setState(() => state = value);
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = exception.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EARTH  ·  COMMAND CENTER',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        actions: [
          if (busy)
            const Padding(
                padding: EdgeInsets.all(18),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          TextButton(
              onPressed: busy ? null : () => _run(api.advanceDay),
              child: const Text('ADVANCE DAY  →'))
        ],
      ),
      body: current == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : _ErrorState(message: error!, retry: () => _run(api.world)))
          : RefreshIndicator(
              onRefresh: () async => _run(api.world),
              child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_canvas, Color(0xff171936), _canvas],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(children: [
                    const _Sidebar(),
                    Expanded(
                        child: ListView(
                            padding: const EdgeInsets.fromLTRB(34, 26, 42, 56),
                            children: [
                              _Dashboard(state: current, busy: busy, action: _run)
                            ]))
                  ]))),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  const _Dashboard(
      {required this.state, required this.busy, required this.action});
  @override
  Widget build(BuildContext context) {
    final proposal =
        (state.governance['proposals'] as List).first as Map<String, dynamic>;
    final votes = proposal['votes'] as Map<String, dynamic>;
    final resourceText = state.resources.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('  ·  ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _HeroCard(state: state),
      const SizedBox(height: 16),
      Text('The world is moving.',
          style: Theme.of(context)
              .textTheme
              .displaySmall
              ?.copyWith(color: _ink, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
      const SizedBox(height: 8),
      Text(
          'DAY ${state.clock['day']}  ·  ${state.institutions['city']['name']}  ·  ${state.institutions['corporation']['name']}',
          style: const TextStyle(color: _muted, fontSize: 11, letterSpacing: .7)),
      const SizedBox(height: 24),
      Wrap(spacing: 14, runSpacing: 14, children: [
        _Metric(
            label: 'CREDITS',
            value: '${state.human['credits']} C',
            accent: _violet),
        _Metric(
            label: 'STANDING',
            value: '${state.human['standing']}',
            accent: Colors.teal),
        _Metric(
            label: 'LEGACY',
            value: '${state.human['legacy']}',
            accent: Colors.indigo),
        _Metric(
            label: 'WORLD HEALTH',
            value: '${state.world['health']} / 100',
            accent: Colors.orange),
      ]),
      const SizedBox(height: 18),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('RESOURCE RESERVES   $resourceText',
                  style: const TextStyle(
                      fontSize: 11, letterSpacing: .8, color: _muted)))),
      const SizedBox(height: 14),
      _Panel(
          title: 'INSTITUTIONS / CAPACITY',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CITY  ${state.institutions['city']['residents']} residents  ·  housing ${state.institutions['city']['housing_capacity']}  ·  energy ${state.institutions['city']['energy_capacity']}'),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: busy ? null : () => action(() => const EarthApi().setCityBudget('maintenance')), child: const Text('PROPOSE MAINTENANCE BUDGET')),
            const SizedBox(height: 8),
            Text('CORPORATION  ${state.institutions['corporation']['member_count']} members  ·  constitution v${state.institutions['corporation']['constitution_version']}'),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: busy ? null : () => action(() => const EarthApi().joinCorporation()), child: const Text('JOIN HELIOS COOPERATIVE')),
          ])),
      const SizedBox(height: 14),
      Wrap(spacing: 14, runSpacing: 14, children: [
        _Panel(
            title: 'BUSINESS / KLINE WORKS',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Policy: ${state.business['policy']}'),
              Text('Condition: ${state.business['condition']}%'),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 8,
                  children: ['reliability', 'margin', 'capacity']
                      .map((policy) => OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(
                                  () => const EarthApi().setPolicy(policy)),
                          child: Text(policy)))
                      .toList())
            ])),
        _Panel(
            title: 'ADAPTIVE MAINTENANCE AI',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${state.technology['progress']}% complete',
                  style: Theme.of(context).textTheme.headlineSmall),
              Text('Patents ${state.technologyRegistry['activePatents']}  ·  Licenses ${state.technologyRegistry['activeLicenses']}', style: const TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value:
                      (state.technology['progress'] as num).toDouble() / 100),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: busy
                      ? null
                      : () => action(() => const EarthApi().fundResearch()),
                  child: const Text('FUND 240 C')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: busy ? null : () => action(() => const EarthApi().grantPatent()), child: const Text('GRANT PATENT')),
                OutlinedButton(onPressed: busy ? null : () => action(() => const EarthApi().licenseTechnology()), child: const Text('LICENSE 5%')),
              ])
            ])),
        _Panel(
            title: 'UC PROPOSAL ${proposal['id']}',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(proposal['title']),
              const SizedBox(height: 8),
              Text(
                  'Support ${votes['support']}  ·  Oppose ${votes['oppose']}  ·  Uncast ${votes['uncast']}'),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 8,
                  children: ['support', 'oppose', 'abstain']
                      .map((choice) => OutlinedButton(
                          onPressed: busy
                              ? null
                              : () =>
                                  action(() => const EarthApi().vote(choice)),
                          child: Text(choice)))
                      .toList())
            ])),
        _Panel(
            title: 'AUTOMATION / MACHINES',
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: state.machines.isEmpty
                    ? [const Text('No registered machines.')]
                    : state.machines.map((raw) {
                        final machine = raw as Map<String, dynamic>;
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(
                                          '${machine['name']}\n${machine['machine_type']}')),
                                  Text(
                                      '${machine['condition']}%\n${machine['maintenance_due']} due',
                                      textAlign: TextAlign.right),
                                  const SizedBox(width: 10),
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => action(() => const EarthApi()
                                              .maintainMachine(
                                                  machine['id'] as String)),
                                      child: const Text('MAINTAIN'))
                                ]));
                      }).toList())),
        _Panel(
            title: 'CENTRAL MARKET / LIVE SIGNALS',
            child: Wrap(
                spacing: 18,
                runSpacing: 12,
                children: state.market.entries.map((entry) {
                  final product = entry.value as Map<String, dynamic>;
                  return SizedBox(
                      width: 150,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.key.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Text('${product['price']} C',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                                'S ${product['supply']}  ·  D ${product['demand']}',
                                style: const TextStyle(fontSize: 11)),
                            const SizedBox(height: 6),
                            OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => action(() => const EarthApi()
                                        .submitOrder(
                                            entry.key,
                                            (product['price'] as num)
                                                .toDouble())),
                                child: const Text('BUY 1')),
                            OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => action(() => const EarthApi()
                                        .settleMarket(entry.key)),
                                child: const Text('SETTLE'))
                          ]));
                }).toList())),
        _Panel(
            title: 'CENTRAL MARKET / ORDER BOOK',
            child: state.marketBook.isEmpty
                ? const Text('No open orders. The market is waiting for a new signal.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: state.marketBook.map((raw) {
                    final row = raw as Map<String, dynamic>;
                    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${row['product']}  ·  ${row['open_quantity']} open  ·  best ${row['best_price']} C', style: const TextStyle(fontSize: 11)));
                  }).toList())),
        _Panel(
            title: 'LIFE / SUCCESSION',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.life['successor'] == null
                  ? 'No successor registered.'
                  : 'Successor: ${(state.life['successor'] as Map<String, dynamic>)['successor_name']}'),
              const SizedBox(height: 8),
              Text('Estate period: ${state.life['estatePeriodDays']} days',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(() =>
                          const EarthApi().registerSuccessor('Alex Kline')),
                  child: const Text('REGISTER ALEX KLINE'))
            ])),
        _Panel(
            title: 'CENTRAL LEDGER / RECENT ACTIVITY',
            child: state.ledgerEntries.isEmpty
                ? const Text('No ledger activity yet.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.ledgerEntries.take(8).map((raw) {
                      final entry = raw as Map<String, dynamic>;
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '${entry['reason_type']}  ·  ${entry['amount']} ${entry['currency']}\n${entry['debit_account']} → ${entry['credit_account']}',
                              style: const TextStyle(fontSize: 12)));
                    }).toList()))
        ,
        _Panel(
            title: 'WORLD FEED / RECENT EVENTS',
            child: state.publicActivity.isEmpty
                ? const Text('No public events recorded yet.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: state.publicActivity.take(8).map((raw) {
                    final event = raw as Map<String, dynamic>;
                    return Padding(padding: const EdgeInsets.only(bottom: 7), child: Text('DAY ${event['game_day']}  ·  ${event['reason_type']}  ·  ${event['rule_version']}', style: const TextStyle(fontSize: 11)));
                  }).toList())),
        _Panel(
            title: 'WORLD RANKINGS / D1 LIVE',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _RankingLine('CITIES', state.rankings['cities']),
              const SizedBox(height: 12),
              _RankingLine('CORPORATIONS', state.rankings['corporations']),
            ])),
        _Panel(
            title: 'COMMUNITIES / SHARED LIFE',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (state.communities.isEmpty)
                const Text('No communities registered yet.')
              else
                ...state.communities.take(5).map((raw) {
                  final community = raw as Map<String, dynamic>;
                  return Padding(padding: const EdgeInsets.only(bottom: 7), child: Text('${community['name']}  ·  ${community['status']}', style: const TextStyle(fontSize: 11)));
                }),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: busy ? null : () => action(() => const EarthApi().createCommunity()), child: const Text('FOUND CARTHAGE MAKERS')),
            ])),
        _Panel(
            title: 'WORLD INTEGRITY / AUDIT',
            child: Wrap(spacing: 8, runSpacing: 8, children: state.audit.entries.map((entry) => Chip(
                label: Text('${entry.key}: ${entry.value ? 'OK' : 'CHECK'}', style: const TextStyle(fontSize: 10)),
                avatar: Icon(entry.value ? Icons.check_circle : Icons.warning, size: 14, color: entry.value ? _cyanAccent : Colors.orange),
                backgroundColor: Colors.white10,
              )).toList()))
        ,
        _Panel(
            title: 'PUBLIC FINANCE / GOVERNANCE',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...((state.finance['taxRules'] as List<dynamic>?) ?? const []).map((raw) {
                final rule = raw as Map<String, dynamic>;
                return Text('${rule['scope']} / ${rule['category']}  ·  ${(NumberFormatHelper.percent(rule['rate']))}  ·  v${rule['version']}', style: const TextStyle(color: _muted, fontSize: 11));
              }),
              const SizedBox(height: 8),
              const Text('Treasury settlement and public spending require authenticated player action.', style: TextStyle(color: _muted, fontSize: 10)),
            ]))
      ]),
    ]);
  }
}

class _RankingLine extends StatelessWidget {
  final String label;
  final dynamic rows;
  const _RankingLine(this.label, this.rows);
  @override
  Widget build(BuildContext context) {
    final list = rows is List ? rows : const [];
    final first = list.isEmpty ? null : list.first as Map<String, dynamic>;
    final value = first == null
        ? 'No entries yet'
        : label == 'CITIES'
            ? '${first['id']}  ·  ${first['residents']} residents'
            : '${first['id']}  ·  ${first['member_count']} members';
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 10, letterSpacing: 1)),
      Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))
    ]);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();
  @override
  Widget build(BuildContext context) => Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 20),
      decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Colors.white12))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('◌  EARTH', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 3)),
        const Padding(
            padding: EdgeInsets.only(left: 28, top: 2, bottom: 26),
            child: Text('UNITED CORPORATIONS', style: TextStyle(fontSize: 8, color: _muted, letterSpacing: 1.2))),
        Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: _surface.withValues(alpha: .8), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
            child: const Row(children: [
              CircleAvatar(radius: 16, backgroundColor: _violet, child: Text('AK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
              SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Amara Kline', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), Text('Independent · New Carthage', style: TextStyle(fontSize: 8, color: _muted))]))
            ])),
        const SizedBox(height: 22),
        for (final item in ['✦  Command center', '⌁  Central Market', '◈  Kline Works', '⊙  Civic life', '⌖  New Carthage', '✧  Technology'])
          Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(item, style: TextStyle(color: item.startsWith('✦') ? _violet : _muted, fontSize: 11, fontWeight: item.startsWith('✦') ? FontWeight.w700 : FontWeight.w500))),
        const Spacer(),
        const Divider(color: Colors.white12),
        const Text('●  WORLD CLOCK', style: TextStyle(color: _cyanAccent, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 7),
        const Text('DAY 184 · 07:42', style: TextStyle(fontSize: 10, letterSpacing: 1))
      ]));
}

const _cyanAccent = Color(0xff55d8b2);

class NumberFormatHelper {
  static String percent(dynamic value) => '${(double.tryParse('$value') ?? 0) * 100}%';
}

class _HeroCard extends StatelessWidget {
  final EarthState state;
  const _HeroCard({required this.state});
  @override
  Widget build(BuildContext context) => Container(
      height: 218,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
          gradient: const LinearGradient(colors: [_surface, Color(0xff24234c)])),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('●  WORLD HEALTH · STABLE', style: TextStyle(color: _cyanAccent, fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 13),
          Text('${state.world['health']}', style: const TextStyle(fontSize: 58, fontWeight: FontWeight.w300, letterSpacing: -4)),
          const Text('Scarcity is beginning to reallocate investment across the Central Market.', style: TextStyle(color: _muted, fontSize: 10)),
        ]),
        Positioned(right: 55, top: 3, child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _violet.withValues(alpha: .5), width: 1), boxShadow: [BoxShadow(color: _violet.withValues(alpha: .22), blurRadius: 40)]), child: Center(child: Container(width: 82, height: 82, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [_violet, Color(0xff5145b7)])), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('EARTH', style: TextStyle(fontSize: 8, letterSpacing: 2)), Text('184', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), Text('DAY', style: TextStyle(fontSize: 8, letterSpacing: 1))])))))
      ]));

}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 360,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 10,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 14),
                    child
                  ]))));
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _Metric(
      {required this.label, required this.value, required this.accent});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 210,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 10, letterSpacing: 1, color: accent)),
                    const SizedBox(height: 12),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.5))
                  ]))));
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const _ErrorState({required this.message, required this.retry});
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('RECONNECT'))
      ]);
}
