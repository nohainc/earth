import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../shared/design_system/design_system.dart';

class SocialGameplayPanel extends StatefulWidget {
  final List<dynamic> initiatives;
  final int gameDay;
  final EarthApi api;
  final VoidCallback? onChanged;

  const SocialGameplayPanel({
    super.key,
    this.initiatives = const [],
    this.gameDay = 1,
    this.api = const EarthApi(),
    this.onChanged,
  });

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
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
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
      if (mounted) {
        setState(() {
          timeline = r[0];
          relationships = r[1];
        });
      }
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
                backgroundColor: ctx.panelColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ctx.radiusPanel),
                  side: BorderSide(color: ctx.subtleBorderColor),
                ),
                title: Text('Preview social proposal', style: ctx.pageTitleStyle),
                content: Text(
                    'Partner: ${selectedPerson?['display_name'] ?? targetId}\nType: ${kind.replaceAll('_', ' ')}\n${kind == 'shared_project' ? 'Institution: ${institution.text.trim()}\nEffect: ${effect.replaceAll('_', ' ')} +$effectAmount\n' : ''}Escrow: $credit Credits\nDeadline: game day ${widget.gameDay + day}\nCompletion target: $targetProgress%\n\nAccepting this proposal will update both players\' trust. Escrow is released on completion or forfeited at the deadline.',
                    style: ctx.widgetFooterStyle),
                actions: [
                  EarthButton(
                    label: 'EDIT',
                    variant: EarthButtonVariant.neutral,
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                  EarthButton(
                    label: 'SEND PROPOSAL',
                    variant: EarthButtonVariant.primary,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
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
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
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
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _contribute(String id) async {
    final amount = await showDialog<int>(
        context: context,
        builder: (ctx) {
          final c = TextEditingController(text: '10');
          return AlertDialog(
              backgroundColor: ctx.panelColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ctx.radiusPanel),
                side: BorderSide(color: ctx.subtleBorderColor),
              ),
              title: Text('Contribute to project', style: ctx.pageTitleStyle),
              content: TextField(
                  controller: c,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Progress contribution (1–100)')),
              actions: [
                EarthButton(
                  label: 'CANCEL',
                  variant: EarthButtonVariant.neutral,
                  onPressed: () => Navigator.pop(ctx),
                ),
                EarthButton(
                  label: 'CONTRIBUTE',
                  variant: EarthButtonVariant.primary,
                  onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
                ),
              ]);
        });
    if (amount == null) return;
    try {
      await widget.api.contributeToSocialInitiative(id, amount);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  List<Widget> _historyWidgets() {
    final result = <Widget>[];
    if (relationships.isEmpty) {
      result.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('No relationship history yet.',
            style: context.widgetFooterStyle),
      ));
    } else {
      result.add(
        EarthDataList(
          children: relationships.map((r) {
            final name = r['display_name']?.toString() ??
                r['other_human_id']?.toString() ??
                '';
            final trust = r['trust'] ?? 0;
            final rep = r['public_reputation'] ?? 0;
            final comp = r['completed_agreements'] ?? 0;
            final broken = r['broken_commitments'] ?? 0;

            return EarthDataRow(
              title: name,
              subtitle: 'Trust $trust · Reputation $rep · Completed $comp · Broken $broken',
              leading: Icon(Icons.handshake_outlined, size: context.iconSize, color: context.primaryColor),
            );
          }).toList(),
        ),
      );
    }

    if (timeline.isEmpty) {
      result.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('No social timeline events yet.',
            style: context.widgetFooterStyle),
      ));
    } else {
      result.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: EarthDataList(
            children: timeline.map((e) {
              final title = e['title']?.toString() ?? 'Social event';
              final day = e['game_day'] ?? '—';
              return EarthDataRow(
                title: title,
                subtitle: 'Game day $day',
                leading: Icon(Icons.timeline, size: context.iconSize, color: context.secondaryColor),
              );
            }).toList(),
          ),
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return EarthSection(
      title: 'COLLABORATIVE INITIATIVES',
      showSurface: false,
      infoBulletPoints: const [
        'Find other citizens and form projects that build trust and reputation.',
        'Review invitations and contribute to active shared projects.',
      ],
      trailing: EarthButton(
        label: 'REFRESH',
        icon: Icons.refresh_rounded,
        onPressed: widget.onChanged,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.errorColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(context.radiusControl),
                border: Border.all(color: context.errorColor.withValues(alpha: .4)),
              ),
              child: Text(error!, style: context.widgetFooterStyle.copyWith(color: context.errorColor)),
            ),
          ],
          _buildInitiatives(),
          SizedBox(height: context.spacingTopic),
          _buildComposer(),
          SizedBox(height: context.spacingTopic),
          Text(
            'RELATIONSHIPS & HISTORY',
            style: context.widgetTitleStyle,
          ),
          const SizedBox(height: 8),
          ..._historyWidgets(),
        ],
      ),
    );
  }

  Widget _buildInitiatives() {
    if (widget.initiatives.isEmpty) {
      return const EarthEmptyState(
        message: 'No active initiatives yet.',
        icon: Icons.handshake_outlined,
      );
    }
    return EarthDataList(
      children: widget.initiatives.map(_buildInitiative).toList(),
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

    final kindTitle = (i['kind'] ?? 'social').toString().replaceAll('_', ' ').toUpperCase();
    final projectTitle = '${i['title'] ?? ''}';
    final escrow = i['escrow_amount'] ?? terms['creditAmount'] ?? 0;
    final progress = i['progress'] ?? 0;
    final targetProgress = terms['contributionTarget'] ?? 100;

    return EarthDataRow(
      title: '$kindTitle · $projectTitle',
      subtitle: '${(i['body']?.toString() ?? '').isNotEmpty ? '${i['body']}\n' : ''}$status · $progress% progress · ${remaining == null ? 'no deadline' : remaining <= 0 ? 'deadline passed' : '$remaining game days remaining'} · Escrow: $escrow CR · Target $targetProgress%${i['kind']?.toString() == 'shared_project' && terms['institutionId'] != null ? '\nInstitution effect: ${terms['projectEffect'] ?? 'development'} +${terms['projectAmount'] ?? 0}' : ''}',
      leading: Icon(Icons.handshake_outlined, size: context.iconSize, color: context.primaryColor),
      badges: [
        EarthBadge(
          label: status.toUpperCase(),
          variant: status == 'active' ? EarthBadgeVariant.success : EarthBadgeVariant.primary,
        ),
      ],
      trailing: isInvited
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EarthButton(
                  label: 'ACCEPT',
                  icon: Icons.check_rounded,
                  variant: EarthButtonVariant.primary,
                  onPressed: () {
                    EarthAudioEngine.instance.playClick();
                    _respond(id, true);
                  },
                ),
                const SizedBox(width: 4),
                EarthButton(
                  label: 'DECLINE',
                  icon: Icons.close_rounded,
                  variant: EarthButtonVariant.danger,
                  onPressed: () {
                    EarthAudioEngine.instance.playClick();
                    _respond(id, false);
                  },
                ),
              ],
            )
          : status == 'active'
              ? EarthButton(
                  label: 'CONTRIBUTE',
                  variant: EarthButtonVariant.primary,
                  onPressed: () {
                    EarthAudioEngine.instance.playClick();
                    _contribute(id);
                  },
                )
              : null,
    );
  }

  Widget _buildComposer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CREATE A PROJECT',
          style: context.widgetTitleStyle,
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(context.cardPadding),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: context.subtleBorderColor),
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
                        prefixIcon: Icon(Icons.search, size: 16),
                      ),
                    ),
                    if (partnerSearchScope.hasFocus && search.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 74,
                        child: people.isEmpty
                            ? Center(
                                child: Text(
                                  'No public citizens match this search.',
                                  style: context.widgetFooterStyle,
                                ),
                              )
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
                                        '${p['display_name'] ?? p['id']}\nStanding ${p['standing'] ?? 0}',
                                        style: context.captionStyle,
                                      ),
                                      onSelected: (_) => _selectPartner(p),
                                    ),
                                  );
                                }).toList(),
                              ),
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
                      initialValue: kind,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Project type'),
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
                                style: context.captionStyle,
                              )))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => kind = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: controlWidth,
                    child: TextField(
                      controller: credits,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Escrow credits (CR)'),
                    ),
                  ),
                  SizedBox(
                    width: controlWidth,
                    child: TextField(
                      controller: deadline,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Days to complete'),
                    ),
                  ),
                  SizedBox(
                    width: controlWidth,
                    child: TextField(
                      controller: target,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Progress target %'),
                    ),
                  ),
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
                      initialValue: _selectedProjectEffect,
                      decoration: const InputDecoration(labelText: 'Project effect'),
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
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedProjectEffect = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: projectAmount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Effect amount'),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'What are you proposing?',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: body,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Describe the goal and public terms',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: EarthButton(
                    label: 'PREVIEW & PROPOSE',
                    icon: Icons.send,
                    variant: EarthButtonVariant.primary,
                    onPressed: loading
                        ? null
                        : () {
                            EarthAudioEngine.instance.playClick();
                            _create();
                          },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
