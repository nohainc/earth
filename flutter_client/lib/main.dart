import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const EarthApp());

class EarthApp extends StatelessWidget {
  const EarthApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EARTH — An OUC World',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xfff3f5fa),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff7163e8)),
          fontFamily: 'Manrope',
          useMaterial3: true,
        ),
        home: const CommandCenter(),
      );
}

class EarthState {
  final int day;
  final double credits;
  final int standing;
  final int legacy;
  final int health;
  final int research;

  const EarthState({required this.day, required this.credits, required this.standing, required this.legacy, required this.health, required this.research});

  factory EarthState.fromJson(Map<String, dynamic> json) {
    final human = json['human'] as Map<String, dynamic>;
    final world = json['world'] as Map<String, dynamic>;
    final technology = json['technology']['research'] as Map<String, dynamic>;
    return EarthState(day: json['clock']['day'] as int, credits: (human['credits'] as num).toDouble(), standing: human['standing'] as int, legacy: human['legacy'] as int, health: world['health'] as int, research: (technology['progress'] as num).round());
  }
}

class EarthApi {
  final String baseUrl;
  const EarthApi({this.baseUrl = 'http://localhost:8787'});

  Future<EarthState> world() async {
    final response = await http.get(Uri.parse('$baseUrl/api/world'));
    if (response.statusCode != 200) throw Exception('World unavailable');
    return EarthState.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<EarthState> advanceDay() async {
    final response = await http.post(Uri.parse('$baseUrl/api/day/advance'));
    if (response.statusCode != 200) throw Exception('Day advance failed');
    return EarthState.fromJson((jsonDecode(response.body) as Map<String, dynamic>)['state'] as Map<String, dynamic>);
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

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final value = await api.world(); if (mounted) setState(() => state = value); } catch (_) { if (mounted) setState(() => error = 'Start the EARTH server to connect to the world.'); } }
  Future<void> _advance() async { try { final value = await api.advanceDay(); if (mounted) setState(() => state = value); } catch (_) { if (mounted) setState(() => error = 'The world could not advance.'); } }

  @override
  Widget build(BuildContext context) {
    final current = state;
    return Scaffold(
      appBar: AppBar(title: const Text('EARTH  ·  COMMAND CENTER'), actions: [TextButton(onPressed: _advance, child: const Text('ADVANCE DAY  →'))]),
      body: Padding(padding: const EdgeInsets.all(28), child: current == null ? Center(child: Text(error ?? 'Connecting to the world…')) : _Dashboard(state: current)),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final EarthState state;
  const _Dashboard({required this.state});
  @override
  Widget build(BuildContext context) => ListView(children: [
        Text('The world is moving.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6), Text('Day ${state.day} · Your position is stable. Three signals are worth your attention today.'),
        const SizedBox(height: 24),
        Wrap(spacing: 14, runSpacing: 14, children: [
          _Metric(label: 'CREDITS', value: '${state.credits.toStringAsFixed(0)} C', accent: Colors.deepPurple),
          _Metric(label: 'STANDING', value: '${state.standing}', accent: Colors.teal),
          _Metric(label: 'LEGACY', value: '${state.legacy}', accent: Colors.indigo),
          _Metric(label: 'WORLD HEALTH', value: '${state.health} / 100', accent: Colors.orange),
        ]),
        const SizedBox(height: 24),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('ADAPTIVE MAINTENANCE AI', style: TextStyle(fontSize: 11, letterSpacing: 1.2)), const SizedBox(height: 10), Text('${state.research}% complete', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 12), LinearProgressIndicator(value: state.research / 100)]))),
      ]);
}

class _Metric extends StatelessWidget {
  final String label; final String value; final Color accent;
  const _Metric({required this.label, required this.value, required this.accent});
  @override
  Widget build(BuildContext context) => SizedBox(width: 210, child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10, letterSpacing: 1, color: accent)), const SizedBox(height: 12), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))]))));
}
