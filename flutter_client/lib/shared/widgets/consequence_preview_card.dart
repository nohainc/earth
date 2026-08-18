import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/decision_consequence.dart';

class ConsequencePreviewCard extends StatelessWidget {
  final DecisionConsequence consequence;

  const ConsequencePreviewCard({
    super.key,
    required this.consequence,
  });

  @override
  Widget build(BuildContext context) {
    final c = consequence;
    final isPerm = c.isPermanent;

    return Container(
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(120), width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: EarthColors.panelSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              border: const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(c.icon, size: 14, color: EarthThemeController.instance.primaryAccent),
                    const SizedBox(width: 6),
                    Text(
                      c.actionCategory,
                      style: TextStyle(
                        color: EarthThemeController.instance.primaryAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isPerm ? const Color(0xFFFF5252).withAlpha(25) : const Color(0xFF38BDF8).withAlpha(25),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: isPerm ? const Color(0xFFFF5252) : const Color(0xFF38BDF8)),
                  ),
                  child: Text(
                    isPerm ? 'PERMANENT' : 'REVERSIBLE',
                    style: TextStyle(
                      color: isPerm ? const Color(0xFFFF5252) : const Color(0xFF38BDF8),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.actionTitle,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                const SizedBox(height: 8),

                // 1. Immediate Cost
                _buildPillarRow(
                  Icons.monetization_on_outlined,
                  'IMMEDIATE COST',
                  c.immediateCost,
                  const Color(0xFFFF5252),
                ),
                const SizedBox(height: 6),

                // 2. Expected Benefit
                _buildPillarRow(
                  Icons.trending_up,
                  'EXPECTED BENEFIT',
                  c.expectedBenefit,
                  const Color(0xFF00E676),
                ),
                const SizedBox(height: 6),

                // 3. Operational Risk
                _buildPillarRow(
                  Icons.warning_amber_rounded,
                  'SYSTEMIC & OPERATIONAL RISK',
                  c.risk,
                  const Color(0xFFFFB300),
                ),
                const SizedBox(height: 6),

                // 4. Affected Entities & Horizon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EarthColors.panelSurface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: EarthColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'IMPACT HORIZON',
                            style: TextStyle(color: EarthColors.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.impactHorizon,
                              style: TextStyle(color: EarthThemeController.instance.primaryAccent, fontSize: 9, fontWeight: FontWeight.w700),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'AFFECTED ENTITIES & NETWORKS',
                        style: TextStyle(color: EarthColors.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 4,
                        runSpacing: 3,
                        children: c.affectedEntities.map((e) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 8.5)),
                            )).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillarRow(IconData icon, String label, String content, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: accent.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: accent, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: .5),
                ),
                const SizedBox(height: 1),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
