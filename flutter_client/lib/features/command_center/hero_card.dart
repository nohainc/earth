import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';

/// The command-center executive citizen and planetary cockpit banner.
class HeroCard extends StatelessWidget {
  final EarthState state;
  final ValueChanged<String>? onNavigate;

  const HeroCard({
    super.key,
    required this.state,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamic status determination based on real player telemetry
    final health = asDouble(state.human['health'] ?? state.life['health']);
    final credits = asDouble(state.finance['balance'] ??
        state.personalFinance['balance'] ?? state.human['credits']);
    final isBankrupt = state.human['bankruptcy_status'] == true;

    final String statusText;
    final Color statusColor;
    if (health != null && health < 30) {
      statusText = 'CRITICAL CARE';
      statusColor = context.errorColor;
    } else if (isBankrupt) {
      statusText = 'INSOLVENT';
      statusColor = context.errorColor;
    } else if (credits != null && credits < 500) {
      statusText = 'DISTRESSED';
      statusColor = context.warningColor;
    } else {
      statusText = 'NOMINAL';
      statusColor = context.primaryColor;
    }

    final citizenName = (state.human['display_name'] ?? state.human['name'])
            ?.toString()
            .toUpperCase() ??
        'AMARA KLINE';
    final citizenAge = state.human['age_years'] ?? state.human['age'];
    final citizenGen = state.human['generation'];

    final territoryRaw = state.residency['territory'] ?? state.institutions['territory'];
    final territoryName =
        (territoryRaw is Map ? territoryRaw['name'] : null)?.toString().toUpperCase() ??
            'TERRITORY UNAVAILABLE';

    final corpRaw = state.institutions['corporation'];
    final corpName =
        (corpRaw is Map ? corpRaw['name'] : null)?.toString().toUpperCase();

    final identity = <String>[
      if (citizenAge != null) 'AGE $citizenAge',
      if (citizenGen != null) 'GEN $citizenGen',
      territoryName,
    ].join('  ·  ');
    final subtitleBuffer = StringBuffer(identity);
    if (corpName != null && corpName.isNotEmpty) {
      subtitleBuffer.write('  ·  $corpName');
    }

    // Dynamic metrics for the center telemetry slot
    final metrics = [
      CockpitMetric(
        label: 'Health',
        value: health == null ? 'UNAVAILABLE' : '${formatWholeNumber(health)}%',
        icon: Icons.favorite_rounded,
        color: health != null && health < 40 ? context.errorColor : context.successColor,
      ),
      CockpitMetric(
        label: 'Standing',
        value: state.human['standing'] == null
            ? 'UNAVAILABLE'
            : formatWholeNumber(state.human['standing']),
        icon: Icons.military_tech_outlined,
        color: context.primaryColor,
      ),
      CockpitMetric(
        label: 'Liquidity',
        value: credits == null ? 'UNAVAILABLE' : formatWholeNumber(credits),
        icon: Icons.account_balance_wallet_outlined,
        color: credits != null && credits < 500 ? context.warningColor : context.goldColor,
      ),
    ];

    return EarthPageCockpit(
      status: statusText,
      statusColor: statusColor,
      infoTitle: 'CITIZEN STATUS & VITALS',
      infoDescription:
          '• Citizen Status & Residency: Real-time vitality status, generational lineage, age in game cycles, and legal residential territory.\n\n• Biometric Health: Physical vitality score (0–100%). Low health increases mortality risk and triggers emergency healthcare protocols.\n\n• Civic Standing: Reputation and trust rating earned through lawful contracts, proposal votes, and public treasury contributions.\n\n• Legacy Score: Cumulative generational prestige inherited by designated successors upon succession.\n\n• Planetary World Health: Global ecological equilibrium index. Environmental degradation increases territorial costs and market volatility.',
      title: citizenName,
      subtitle: subtitleBuffer.toString(),
      metrics: metrics,
    );
  }
}
