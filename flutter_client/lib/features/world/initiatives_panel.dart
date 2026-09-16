import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/design_system/earth_theme_context.dart';
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

class _InitiativesPanelState extends State<InitiativesPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void didUpdateWidget(covariant InitiativesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex.clamp(0, 2));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              'Long-horizon global programs, collaborative public goods, and discovered Technology Generations shaping the future of EARTH.',
          title: 'INITIATIVES',
          subtitle:
              'Global programs, public infrastructure projects, and technology generations',
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
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: context.primaryColor.withValues(alpha: 0.14),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: context.primaryColor,
            unselectedLabelColor: context.mutedColor,
            indicatorColor: context.primaryColor,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
            tabs: const [
              Tab(
                text: 'GLOBAL PROGRAMS',
                icon: Icon(Icons.public_outlined, size: 18),
              ),
              Tab(
                text: 'PUBLIC PROJECTS',
                icon: Icon(Icons.construction_outlined, size: 18),
              ),
              Tab(
                text: 'TECHNOLOGY GENERATIONS',
                icon: Icon(Icons.biotech_outlined, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            switch (_tabController.index) {
              case 1:
                return PublicProjectsPanel(
                  state: widget.state,
                  personalFinanceData: widget.personalFinanceData,
                  busy: widget.busy,
                  action: widget.action,
                );
              case 2:
                return const WorldProgramsPanel();
              case 0:
              default:
                return const WorldProgramsPanel();
            }
          },
        ),
      ],
    );
  }
}
