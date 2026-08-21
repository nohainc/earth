import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'technology_dialogs.dart';

class TechnologyPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const TechnologyPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final tech = state.technology;
    final research = tech['research'] is Map<String, dynamic>
        ? (tech['research'] as Map<String, dynamic>)
        : tech;
    final techName = (research['name'] as String?)?.toUpperCase() ??
        (tech['name'] as String?)?.toUpperCase() ??
        'ADAPTIVE MAINTENANCE AI';
    final techId = research['id']?.toString() ?? 'TECH-001';
    final progress =
        (asDouble(research['progress']) ?? asDouble(tech['progress']) ?? 0.0)
            .clamp(0.0, 100.0);
    final focus = (research['focus'] ?? tech['focus'] ?? 'efficiency')
        .toString()
        .toUpperCase();
    final budgetNum = research['budget'] ?? research['budgetPerDay'] ?? 240;
    final budget = asDoubleOr(budgetNum, 240.0);
    final isComplete = progress >= 100;

    final activePatents = asIntOr(
        state.technologyRegistry['activePatents'], isComplete ? 1 : 0);
    final activeLicenses =
        asIntOr(state.technologyRegistry['activeLicenses'], 1);

    Color focusColor = cyanAccentColor;
    if (focus == 'DURABILITY') focusColor = Colors.tealAccent;
    if (focus == 'SAFETY') focusColor = Colors.lightGreenAccent;
    if (focus == 'COST') focusColor = Colors.amberAccent;

    final currentDay = asIntOr(state.clock['day'], 184);
    final patentGrantedDay = asIntOr(research['patentGrantedDay'], 1);
    const patentDurationDays = 288; // 24 simulation years (12 sim days/yr)
    final patentExpiryDay = patentGrantedDay + patentDurationDays;
    final daysToPublicDomain = (patentExpiryDay - currentDay).clamp(0, patentDurationDays);
    final isPublicDomain = isComplete && daysToPublicDomain <= 0;

    return EarthPanel(
      key: panelKey,
      title: 'TECHNOLOGY / RESEARCH & PATENTS',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Research Laboratory: Choose and fund capabilities that improve the player\'s businesses and future options.\n\n• Focus Specialization:\n  - EFFICIENCY: More output from existing capacity.\n  - DURABILITY: Lower wear and maintenance cost.\n  - SAFETY: Less risk during demanding operations.\n  - COST: Better margins from lower input requirements.\n\n• Intellectual Property: Completed research can become a patent, generate licensing income, or enter the public domain. Physical machines and production decisions belong in Businesses & Operations.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. ACTIVE RESEARCH PROJECT COCKPIT
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: violetColor.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: violetColor.withValues(alpha: .4)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.biotech_outlined,
                        size: 22,
                        color: cyanAccentColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  techName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: inkColor,
                                    letterSpacing: .5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: (isComplete
                                          ? cyanAccentColor
                                          : Colors.lightBlueAccent)
                                      .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: (isComplete
                                            ? cyanAccentColor
                                            : Colors.lightBlueAccent)
                                        .withValues(alpha: .4),
                                  ),
                                ),
                                child: Text(
                                  isComplete ? 'COMPLETED' : 'IN RESEARCH',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                    color: isComplete
                                        ? cyanAccentColor
                                        : Colors.lightBlueAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PROJECT ID: $techId  ·  FOCUS: ${focus.toLowerCase()}  ·  STATUS: ${isComplete ? 'COMPLETED' : 'IN RESEARCH'}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: mutedColor,
                              letterSpacing: .6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Progress Bar & Percentage
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RESEARCH PROGRESSION',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: mutedColor.withValues(alpha: .9),
                      ),
                    ),
                    Text(
                      '${progress.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                        color: isComplete ? cyanAccentColor : inkColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    minHeight: 8,
                    color: isComplete ? cyanAccentColor : Colors.lightBlueAccent,
                    backgroundColor: Colors.white10,
                  ),
                ),

                const SizedBox(height: 14),

                // Focus & Budget Breakdown Badges (Wrap to prevent horizontal overflow)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: focusColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: focusColor.withValues(alpha: .3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 12, color: focusColor),
                          const SizedBox(width: 5),
                          Text(
                            'FOCUS: $focus',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: focusColor,
                              letterSpacing: .5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .04),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        'Focus: ${focus.toLowerCase()} · Budget: ${formatWholeNumber(budget)} C · Status: ${isComplete ? 'COMPLETED' : 'IN RESEARCH'}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: mutedColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. INTELLECTUAL PROPERTY & LICENSING METRICS
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'INTELLECTUAL PROPERTY & 24-YEAR STATUTORY TERM',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
          ),
          const SizedBox(height: 8),

          LayoutBuilder(
            builder: (context, ipConstraints) {
              final ipWidth = ipConstraints.maxWidth;
              final numCols = ipWidth >= 650 ? 3 : (ipWidth >= 440 ? 2 : 1);
              final itemWidth = (ipWidth - (numCols - 1) * 12) / numCols;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ipMetricCard(
                    width: itemWidth,
                    title: 'PATENTS REGISTERED',
                    value: '$activePatents',
                    subtext: 'Patents granted: $activePatents',
                    accent: violetColor,
                    icon: Icons.verified_user_outlined,
                  ),
                  _ipMetricCard(
                    width: itemWidth,
                    title: 'COMMERCIAL LICENSES',
                    value: '$activeLicenses',
                    subtext: 'Active licenses: $activeLicenses (5.00% royalty)',
                    accent: cyanAccentColor,
                    icon: Icons.gavel_outlined,
                  ),
                  _ipMetricCard(
                    width: itemWidth,
                    title: 'PUBLIC DOMAIN TERM',
                    value: isPublicDomain ? 'PUBLIC DOMAIN' : '${daysToPublicDomain}d remaining',
                    subtext: isPublicDomain ? '0% open royalty blueprint' : '24-year statutory term',
                    accent: isPublicDomain ? Colors.lightGreenAccent : Colors.amberAccent,
                    icon: Icons.public_outlined,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 18),

          // 3. R&D ACTIONS & IP MONETIZATION HUB
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'R&D OPERATIONS & IP MONETIZATION',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cyanAccentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy || isComplete
                      ? null
                      : () => action(() => const EarthApi().fundResearch()),
                  icon: const Icon(Icons.bolt_rounded, size: 15),
                  label: const Text(
                    'FUND 240 C',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: inkColor,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy
                      ? null
                      : () => showResearchComposerDialog(context, action),
                  icon: const Icon(Icons.science_outlined, size: 15),
                  label: const Text(
                    'NEW PROJECT · 240 C',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: violetColor,
                    side: BorderSide(
                        color: violetColor.withValues(alpha: .4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy || !isComplete
                      ? null
                      : () => action(() => const EarthApi().grantPatent()),
                  icon: const Icon(Icons.verified_user_outlined, size: 15),
                  label: const Text(
                    'GRANT PATENT',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cyanAccentColor,
                    side: BorderSide(
                        color: cyanAccentColor.withValues(alpha: .3)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy
                      ? null
                      : () => action(
                          () => const EarthApi().licenseTechnology()),
                  icon: const Icon(Icons.share_outlined, size: 15),
                  label: const Text(
                    'LICENSE (5%)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: BorderSide(
                        color: Colors.tealAccent.withValues(alpha: .3)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy
                      ? null
                      : () => showLicenseComposerDialog(context, action),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
                  label: const Text(
                    'LICENSE TO HUMAN',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ipMetricCard({
    required double width,
    required String title,
    required String value,
    required String subtext,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .9,
                  color: mutedColor,
                ),
              ),
              Icon(icon, size: 14, color: accent),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: const TextStyle(
              fontSize: 9.5,
              color: mutedColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
