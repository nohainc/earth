import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _violet = Color(0xff7163e8);
const _ink = Color(0xff172033);

void main() => runApp(const EarthApp());

class EarthApp extends StatelessWidget {
  const EarthApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EARTH — An OUC World',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xfff4f6fb),
          colorScheme: ColorScheme.fromSeed(seedColor: _violet),
          fontFamily: 'Manrope',
          useMaterial3: true,
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
  Map<String, dynamic> get governance =>
      json['governance'] as Map<String, dynamic>;
  Map<String, dynamic> get institutions =>
      json['institutions'] as Map<String, dynamic>;
  List<dynamic> get machines =>
      (json['machines'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get market =>
      (json['market'] as Map<String, dynamic>)['products']
          as Map<String, dynamic>;
}

class EarthApi {
  final String baseUrl;
  const EarthApi({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('EARTH_API_URL',
                defaultValue: 'https://earth-world.vitalii-e07.workers.dev');

  Future<dynamic> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = method == 'POST'
        ? await http.post(uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body ?? {}))
        : await http.get(uri);
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(decoded is Map
          ? decoded['error'] ?? 'Request failed'
          : 'Request failed');
    }
    return decoded;
  }

  Future<EarthState> world() async =>
      EarthState(await _request('/api/world') as Map<String, dynamic>);
  Future<EarthState> advanceDay() async =>
      EarthState((await _request('/api/day/advance', method: 'POST'))['state']
          as Map<String, dynamic>);
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

  Future<EarthState> maintainMachine(String machineId) async {
    await _request('/api/machines/$machineId/maintenance',
        method: 'POST', body: {'amount': 10});
    return world();
  }

  Future<EarthState> vote(String choice) async {
    await _request('/api/governance/proposals/042/vote',
        method: 'POST', body: {'vote': choice});
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
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 48),
                  children: [
                    _Dashboard(state: current, busy: busy, action: _run)
                  ])),
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
      Text('The world is moving.',
          style: Theme.of(context)
              .textTheme
              .displaySmall
              ?.copyWith(color: _ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
          'Day ${state.clock['day']} · ${state.institutions['city']['name']} · ${state.institutions['corporation']['name']}'),
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
                      fontSize: 12, letterSpacing: .8, color: _ink)))),
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
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value:
                      (state.technology['progress'] as num).toDouble() / 100),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: busy
                      ? null
                      : () => action(() => const EarthApi().fundResearch()),
                  child: const Text('FUND 240 C'))
            ])),
        _Panel(
            title: 'OUC PROPOSAL ${proposal['id']}',
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
                                style: const TextStyle(fontSize: 11))
                          ]));
                }).toList()))
      ]),
    ]);
  }
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
                            fontSize: 11,
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
                            ?.copyWith(fontWeight: FontWeight.w700))
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
