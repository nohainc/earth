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
  final partnerSearchScope = FocusScopeNode();
  final credits = TextEditingController(text: '0');
  final deadline = TextEditingController(text: '7');
  final target = TextEditingController(text: '100');
  final institution = TextEditingController();
  final projectAmount = TextEditingController(text: '10');
  List<dynamic> people = const [];
  List<dynamic> timeline = const [];
  List<dynamic> relationships = const [];
  Map<String, dynamic>? selectedPerson;
  String? targetId;
  String kind = 'alliance';
  bool loading = false;
  String? error;

  Color get _groupSurface => EarthThemeController.instance.cardSurface;
  @override
  void initState() {
    super.initState();
    partnerSearchScope.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistory();
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    search.dispose();
    partnerSearchScope.dispose();
    credits.dispose();
    deadline.dispose();
    target.dispose();
    institution.dispose();
    projectAmount.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory([String query = '']) async {
    if (query.trim().isEmpty) {
      setState(() => people = const []);
      return;
    }
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

  void _onPartnerSearch(String query) {
    if (targetId != null) {
      setState(() {
        targetId = null;
        selectedPerson = null;
      });
    }
    _loadDirectory(query);
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

  void _selectPartner(Map<String, dynamic> partner) {
    final partnerName = (partner['display_name'] ??
            partner['dynasty_name'] ??
            partner['city_name'] ??
            partner['name'] ??
            partner['id'])
        .toString();
    setState(() {
      targetId = partner['id']?.toString();
      selectedPerson = partner;
      search.value = TextEditingValue(
        text: partnerName,
        selection: TextSelection.collapsed(offset: partnerName.length),
      );
    });
    partnerSearchScope.unfocus();
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
    final effect = _projectEffect;
    final effectAmount = int.tryParse(projectAmount.text) ?? 0;
    if (kind == 'shared_project' &&
        (institution.text.trim().isEmpty || effectAmount < 1)) {
      setState(() =>
          error = 'Shared projects need an institution ID and effect amount.');
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Preview social proposal'),
                content: Text(
                    'Partner: ${selectedPerson?['display_name'] ?? targetId}\nType: ${kind.replaceAll('_', ' ')}\n${kind == 'shared_project' ? 'Institution: ${institution.text.trim()}\nEffect: ${effect.replaceAll('_', ' ')} +$effectAmount\n' : ''}Escrow: $credit Credits\nDeadline: game day ${widget.gameDay + day}\nCompletion target: $targetProgress%\n\nAccepting this proposal will update both players\' trust. Escrow is released on completion or forfeited at the deadline.'),
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
            'contributionTarget': targetProgress,
            if (kind == 'shared_project') ...{
              'institutionId': institution.text.trim(),
              'projectEffect': effect,
              'projectAmount': effectAmount,
            }
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

  String get _projectEffect => _selectedProjectEffect;
  String _selectedProjectEffect = 'housing';

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
      result.add(const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('No relationship history yet.',
            style: TextStyle(color: mutedColor, fontSize: 11)),
      ));
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
      result.add(const Text('No social timeline events yet.',
          style: TextStyle(color: mutedColor, fontSize: 11)));
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
      title: 'COLLABORATIVE INITIATIVES',
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
          if (error != null) ...[
            Text(error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
            const SizedBox(height: 10),
          ],
          _buildInitiatives(),
          const SizedBox(height: 12),
          _buildComposer(),
          const SizedBox(height: 20),
          const Text('RELATIONSHIPS & HISTORY',
              style: TextStyle(
                  color: mutedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1)),
          const SizedBox(height: 8),
          ..._historyWidgets(),
        ],
      ),
    );
  }

  Widget _buildTopicHeading(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          const Flexible(
            child: Text('COLLABORATIVE INITIATIVES',
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
              title: 'COLLABORATIVE INITIATIVES',
              description:
                  '• Find other citizens and form initiatives that build trust and reputation.\n\n'
                  '• Review invitations and contribute to active shared projects.',
            ),
          ),
        ]),
      );

  Widget _buildInitiatives() {
    if (widget.initiatives.isEmpty) {
      return Row(
        children: [
          const Expanded(
            child: Text('No active initiatives yet.',
                style: TextStyle(color: mutedColor, fontSize: 11)),
          ),
          IconButton(
            tooltip: 'Refresh initiatives',
            onPressed: widget.onChanged,
            icon: const Icon(Icons.refresh_rounded, size: 16),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
                '${widget.initiatives.length} ACTIVE INITIATIVE${widget.initiatives.length == 1 ? '' : 'S'}',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                    color: mutedColor)),
          ),
          IconButton(
            tooltip: 'Refresh initiatives',
            onPressed: widget.onChanged,
            icon: const Icon(Icons.refresh_rounded, size: 16),
          ),
        ]),
        const SizedBox(height: 18),
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
        color: _groupSurface,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CREATE AN INITIATIVE',
            style: TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _groupSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FocusScope(
                node: partnerSearchScope,
                child: Column(
                  children: [
                    TextField(
                        controller: search,
                        onChanged: _onPartnerSearch,
                        decoration: const InputDecoration(
                          labelText: 'Search citizens or dynasties',
                          prefixIcon:
                              Icon(Icons.search, size: 16, color: mutedColor),
                        )),
                    if (partnerSearchScope.hasFocus &&
                        search.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 74,
                        child: people.isEmpty
                            ? const Center(
                                child: Text(
                                    'No public citizens match this search.',
                                    style: TextStyle(
                                        color: mutedColor, fontSize: 11)))
                            : ListView(
                                scrollDirection: Axis.horizontal,
                                children: people.map((raw) {
                                  final p =
                                      Map<String, dynamic>.from(raw as Map);
                                  final selected =
                                      p['id']?.toString() == targetId;
                                  return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        selected: selected,
                                        label: Text(
                                            '${p['display_name'] ?? p['id']}\nStanding ${p['standing'] ?? 0}'),
                                        onSelected: (_) => _selectPartner(p),
                                      ));
                                }).toList()),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, constraints) {
                final controlWidth = (constraints.maxWidth - 24) / 4;
                final controls = [
                  SizedBox(
                    width: controlWidth,
                    child: DropdownButtonFormField<String>(
                        value: kind,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Initiative type'),
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
                                child: Text(
                                    v.replaceAll('_', ' ').toUpperCase(),
                                    style: const TextStyle(fontSize: 11))))
                            .toList(),
                        onChanged: (v) => setState(() => kind = v ?? kind)),
                  ),
                  SizedBox(
                      width: controlWidth,
                      child: TextField(
                          controller: credits,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Escrow credits'))),
                  SizedBox(
                      width: controlWidth,
                      child: TextField(
                          controller: deadline,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Days to complete'))),
                  SizedBox(
                      width: controlWidth,
                      child: TextField(
                          controller: target,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Progress target'))),
                ];
                return Wrap(spacing: 8, runSpacing: 8, children: controls);
              }),
              if (kind == 'shared_project') ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: institution,
                      decoration: const InputDecoration(
                        labelText: 'City or corporation ID',
                        hintText: 'e.g. CITY-0084',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      value: _selectedProjectEffect,
                      decoration:
                          const InputDecoration(labelText: 'Project effect'),
                      items: const [
                        'housing',
                        'energy',
                        'connectivity',
                        'health',
                        'corporation_treasury'
                      ]
                          .map((v) => DropdownMenuItem(
                              value: v, child: Text(v.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: (v) => setState(() =>
                          _selectedProjectEffect = v ?? _selectedProjectEffect),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: projectAmount,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Effect amount'),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 16),
              TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'What are you proposing?',
                  )),
              const SizedBox(height: 16),
              TextField(
                  controller: body,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Describe the goal and public terms',
                  )),
              Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: FilledButton.icon(
                          onPressed: loading ? null : _create,
                          icon: const Icon(Icons.send, size: 16),
                          label: const Text('PREVIEW & PROPOSE'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.bold),
                          )))),
            ],
          ),
        ),
      ],
    );
  }
}
