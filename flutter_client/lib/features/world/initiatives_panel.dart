import 'package:flutter/material.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import 'public_projects_panel.dart';
import 'world_programs_panel.dart';

class InitiativesPanel extends StatefulWidget {
  final EarthState state;
  final Map<String, dynamic> personalFinanceData;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final int initialTabIndex;

  const InitiativesPanel({
    super.key,
    required this.state,
    required this.personalFinanceData,
    required this.busy,
    required this.action,
    this.initialTabIndex = 0,
  });

  @override
  State<InitiativesPanel> createState() => _InitiativesPanelState();
}

class _InitiativesPanelState extends State<InitiativesPanel> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex.clamp(0, 1);
  }

  @override
  void didUpdateWidget(covariant InitiativesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      setState(() {
        _selectedTab = widget.initialTabIndex.clamp(0, 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthPageCockpit(
          tag: 'PLANETARY HORIZON',
          status: 'CANONICAL WORLD DATA',
          statusColor: context.primaryColor,
          infoTitle: 'PLANETARY INITIATIVES & PUBLIC GOODS',
          infoDescription:
              'Collective programs and public projects shaping Earth’s future. Technology Generations are tracked in the technology progression surfaces.',
          title: 'INITIATIVES',
          subtitle: 'Strategic programs and concrete public goods',
          metrics: [
            CockpitMetric(
              label: 'Initiatives Focus',
              value: 'Global Horizon',
              icon: Icons.rocket_launch_outlined,
              color: context.primaryColor,
            ),
            CockpitMetric(
              label: 'Governance Scope',
              value: 'World',
              icon: Icons.public_outlined,
              color: context.secondaryColor,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          margin: EdgeInsets.only(bottom: context.spacingControl),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Row(
            children: [
              _buildTabButton(
                context,
                title: 'PROGRAMS',
                icon: Icons.public_outlined,
                isSelected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              _buildTabButton(
                context,
                title: 'PROJECTS',
                icon: Icons.construction_outlined,
                isSelected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _selectedTab == 1
            ? PublicProjectsPanel(
                state: widget.state,
                personalFinanceData: widget.personalFinanceData,
                busy: widget.busy,
                action: widget.action,
              )
            : WorldProgramsPanel(
                personalFinanceData: widget.personalFinanceData,
                busy: widget.busy,
                action: widget.action,
              ),
      ],
    );
  }

  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          EarthAudioEngine.instance.playClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? context.primaryColor.withValues(alpha: .15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: context.primaryColor.withValues(alpha: .4))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? context.primaryColor : context.mutedColor,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.controlStyle.copyWith(
                  color: isSelected ? context.primaryColor : context.mutedColor,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
