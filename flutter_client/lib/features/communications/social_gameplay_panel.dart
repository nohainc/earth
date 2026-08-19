import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../shared/widgets/earth_primitives.dart';

class SocialGameplayPanel extends StatefulWidget {
  final List<dynamic> initiatives;
  final int gameDay;
  final EarthApi api;
  final VoidCallback? onChanged;
  const SocialGameplayPanel(
      {super.key,
      this.initiatives = const [],
      this.gameDay = 1,
      this.api = const EarthApi(),
      this.onChanged});
  @override
  State<SocialGameplayPanel> createState() => _SocialGameplayPanelState();
}

class _SocialGameplayPanelState extends State<SocialGameplayPanel> {
  final title = TextEditingController();
  final body = TextEditingController();
  final search = TextEditingController();
  final credits = TextEditingController(text: '0');
  final deadline = TextEditingController(text: '7');
  final target = TextEditingController(text: '100');
  List<dynamic> people = const [];
  List<dynamic> timeline = const [];
  List<dynamic> relationships = const [];
  Map<String, dynamic>? selectedPerson;
  String? targetId;
  String kind = 'alliance';
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    search.dispose();
    credits.dispose();
    deadline.dispose();
    target.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory([String query = '']) async {
    try {
      final r = await widget.api.socialDirectory(query: query);
      if (mounted) {
        setState(() {
          people = r['humans'] as List<dynamic>? ?? const [];
          error = null;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadHistory() async {
    try {
      final r = await Future.wait(
          [widget.api.socialTimeline(), widget.api.socialRelationships()]);
      if (mounted)
        setState(() {
          timeline = r[0];
          relationships = r[1];
        });
    } catch (_) {}
  }

  Future<void> _create() async {
    if (title.text.trim().isEmpty ||
        body.text.trim().isEmpty ||
        targetId == null) {
      setState(() => error = 'Choose a public partner before proposing.');
      return;
    }
    final credit = double.tryParse(credits.text) ?? 0;
    final day = int.tryParse(deadline.text) ?? 7;
    final targetProgress = int.tryParse(target.text) ?? 100;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Preview social proposal'),
                content: Text(
                    'Partner: ${selectedPerson?['display_name'] ?? targetId}\nType: ${kind.replaceAll('_', ' ')}\nEscrow: $credit Credits\nDeadline: game day ${widget.gameDay + day}\nCompletion target: $targetProgress%\n\nAccepting this proposal will update both players\' trust. Escrow is released on completion or forfeited at the deadline.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('EDIT')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('SEND PROPOSAL'))
                ]));
    if (confirmed != true) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.api.createSocialInitiative(
          kind: kind,
          title: title.text.trim(),
          body: body.text.trim(),
          targetId: targetId,
          terms: {
            'creditAmount': credit,
            'deadlineGameDay': widget.gameDay + day,
            'contributionTarget': targetProgress
          });
      title.clear();
      body.clear();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _respond(String id, bool accept) async {
    try {
      await widget.api.respondToSocialInitiative(id, accept: accept);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _contribute(String id) async {
    final amount = await showDialog<int>(
        context: context,
        builder: (ctx) {
          final c = TextEditingController(text: '10');
          return AlertDialog(
              title: const Text('Contribute to project'),
              content: TextField(
                  controller: c,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Progress contribution (1–100)')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('CANCEL')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
                    child: const Text('CONTRIBUTE'))
              ]);
        });
    if (amount == null) return;
    try {
      await widget.api.contributeToSocialInitiative(id, amount);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<Widget> _historyWidgets() {
    final result = <Widget>[];
    if (relationships.isEmpty) {
      result.add(const ListTile(title: Text('No relationship history yet.')));
    } else {
      result.addAll(relationships.map((r) => ListTile(
          leading: const Icon(Icons.handshake_outlined),
          title: Text(r['display_name']?.toString() ??
              r['other_human_id']?.toString() ??
              ''),
          subtitle: Text(
              'Trust ${r['trust'] ?? 0} · reputation ${r['public_reputation'] ?? 0} · completed ${r['completed_agreements'] ?? 0} · broken ${r['broken_commitments'] ?? 0}'))));
    }
    if (timeline.isEmpty) {
      result.add(const ListTile(title: Text('No social timeline events yet.')));
    } else {
      result.addAll(timeline.map((e) => ListTile(
          leading: const Icon(Icons.timeline),
          title: Text(e['title']?.toString() ?? 'Social event'),
          subtitle: Text('Game day ${e['game_day'] ?? '—'}'))));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'SOCIAL COMMONS',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Find other citizens and form initiatives that build trust and reputation.\n'
          '• Review invitations and contribute to active shared projects.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopicHeading(context),
          _buildIntro(),
          const SizedBox(height: 14),
          if (error != null) ...[
            Text(error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
            const SizedBox(height: 10),
          ],
          _buildInitiatives(),
          const SizedBox(height: 12),
          _buildComposer(),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('RELATIONSHIPS & HISTORY',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            subtitle: const Text('Your trust, reputation, and social timeline',
                style: TextStyle(fontSize: 10.5, color: mutedColor)),
            onExpansionChanged: (open) {
              if (open) _loadHistory();
            },
            children: _historyWidgets(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicHeading(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          const Flexible(
            child: Text('SOCIAL COMMONS',
                style: TextStyle(
                    color: mutedColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1)),
          ),
          const SizedBox(width: 5),
          IconButton(
            tooltip: 'About social commons',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.info_outline,
                size: 14, color: mutedColor.withValues(alpha: .8)),
            onPressed: () => showEarthInfoDialog(
              context,
              title: 'SOCIAL COMMONS',
              description:
                  '• Find other citizens and form initiatives that build trust and reputation.\n\n'
                  '• Review invitations and contribute to active shared projects.',
            ),
          ),
        ]),
      );

  Widget _buildIntro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.people_outline, size: 18, color: mutedColor),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Build relationships with other citizens',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(height: 3),
                Text(
                    'Choose a partner, propose clear terms, then track progress together.',
                    style: TextStyle(
                        fontSize: 11, color: mutedColor, height: 1.35)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh people',
            onPressed: _loadDirectory,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildInitiatives() {
    if (widget.initiatives.isEmpty) {
      return const Text('No active initiatives yet.',
          style: TextStyle(color: mutedColor, fontSize: 11));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ACTIVE INITIATIVES',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
                color: mutedColor)),
        const SizedBox(height: 8),
        ...widget.initiatives.map(_buildInitiative),
      ],
    );
  }

  Widget _buildInitiative(dynamic raw) {
    final i = Map<String, dynamic>.from(raw as Map);
    final status = i['status']?.toString() ?? 'proposed';
    final memberStatus = i['member_status']?.toString();
    final id = i['id']?.toString() ?? '';
    final terms = i['terms'] is Map
        ? Map<String, dynamic>.from(i['terms'] as Map)
        : const <String, dynamic>{};
    final deadlineDay = int.tryParse('${i['deadline_game_day'] ?? ''}');
    final remaining = deadlineDay == null ? null : deadlineDay - widget.gameDay;
    final isInvited = memberStatus == 'invited';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isInvited
                ? EarthThemeController.instance.primaryAccent
                    .withValues(alpha: .4)
                : EarthColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.handshake_outlined, size: 17, color: mutedColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${(i['kind'] ?? 'social').toString().replaceAll('_', ' ').toUpperCase()} · ${i['title'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700)),
                if ((i['body']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(i['body'].toString(),
                      style:
                          const TextStyle(fontSize: 10.5, color: mutedColor)),
                ],
                const SizedBox(height: 5),
                Text(
                    '$status · ${i['progress'] ?? 0}% progress · ${remaining == null ? 'no deadline' : remaining <= 0 ? 'deadline passed' : '$remaining game days remaining'}',
                    style: const TextStyle(fontSize: 10, color: mutedColor)),
                Text(
                    'Escrow: ${i['escrow_amount'] ?? terms['creditAmount'] ?? 0} credits · target ${terms['contributionTarget'] ?? 100}%',
                    style: const TextStyle(fontSize: 10, color: mutedColor)),
              ],
            ),
          ),
          if (isInvited)
            Row(children: [
              IconButton(
                  tooltip: 'Accept',
                  onPressed: () => _respond(id, true),
                  icon:
                      const Icon(Icons.check_rounded, color: cyanAccentColor)),
              IconButton(
                  tooltip: 'Decline',
                  onPressed: () => _respond(id, false),
                  icon:
                      const Icon(Icons.close_rounded, color: Colors.redAccent)),
            ])
          else if (status == 'active')
            TextButton(
                onPressed: () => _contribute(id),
                child: const Text('CONTRIBUTE')),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('CREATE AN INITIATIVE',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      subtitle: Text(
          selectedPerson == null
              ? '1. Choose a partner  ·  2. Define the agreement  ·  3. Send it'
              : 'Partner selected: ${selectedPerson!['display_name'] ?? targetId}',
          style: const TextStyle(fontSize: 10.5, color: mutedColor)),
      children: [
        _composerSection(
          '1. CHOOSE A PARTNER',
          Column(children: [
            TextField(
                controller: search,
                onChanged: _loadDirectory,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search citizens or dynasties')),
            const SizedBox(height: 10),
            SizedBox(
              height: 74,
              child: people.isEmpty
                  ? const Center(
                      child: Text('No public citizens match this search.',
                          style: TextStyle(color: mutedColor, fontSize: 11)))
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      children: people.map((raw) {
                        final p = Map<String, dynamic>.from(raw as Map);
                        final selected = p['id']?.toString() == targetId;
                        return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              selected: selected,
                              label: Text(
                                  '${p['display_name'] ?? p['id']}\nStanding ${p['standing'] ?? 0}'),
                              onSelected: (_) => setState(() {
                                targetId = p['id']?.toString();
                                selectedPerson = p;
                              }),
                            ));
                      }).toList()),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        _composerSection(
          '2. DEFINE THE AGREEMENT',
          Wrap(spacing: 8, runSpacing: 8, children: [
            DropdownButton<String>(
                value: kind,
                items: const [
                  'alliance',
                  'negotiation',
                  'campaign',
                  'announcement',
                  'lobbying',
                  'shared_project',
                  'agreement'
                ]
                    .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.replaceAll('_', ' ').toUpperCase())))
                    .toList(),
                onChanged: (v) => setState(() => kind = v ?? kind)),
            SizedBox(
                width: 110,
                child: TextField(
                    controller: credits,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Escrow credits'))),
            SizedBox(
                width: 110,
                child: TextField(
                    controller: deadline,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Days to complete'))),
            SizedBox(
                width: 110,
                child: TextField(
                    controller: target,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Progress target'))),
          ]),
        ),
        const SizedBox(height: 8),
        TextField(
            controller: title,
            decoration:
                const InputDecoration(labelText: 'What are you proposing?')),
        TextField(
            controller: body,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Describe the goal and public terms')),
        Align(
            alignment: Alignment.centerRight,
            child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton.icon(
                    onPressed: loading ? null : _create,
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('PREVIEW & PROPOSE')))),
      ],
    );
  }

  Widget _composerSection(String label, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EarthColors.borderSubtle),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: mutedColor)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}
