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
    final health = asDoubleOr(state.human['health'], 100);
    final credits = asDoubleOr(state.human['credits'], 0);
    final isBankrupt = state.human['bankruptcy_status'] == true;

    final String statusText;
    final Color statusColor;
    if (health < 30) {
      statusText = 'CRITICAL CARE';
      statusColor = context.errorColor;
    } else if (isBankrupt) {
      statusText = 'INSOLVENT';
      statusColor = context.errorColor;
    } else if (credits < 500) {
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
    final citizenAge = state.human['age_years'] ?? state.human['age'] ?? '31';
    final citizenGen = state.human['generation'] ?? '1';

    final cityRaw = state.institutions['city'];
    final cityName =
        (cityRaw is Map ? cityRaw['name'] : null)?.toString().toUpperCase() ??
            'NEW CARTHAGE';

    final corpRaw = state.institutions['corporation'];
    final corpName =
        (corpRaw is Map ? corpRaw['name'] : null)?.toString().toUpperCase();

    final subtitleBuffer = StringBuffer('AGE $citizenAge  ·  GEN $citizenGen  ·  $cityName');
    if (corpName != null && corpName.isNotEmpty) {
      subtitleBuffer.write('  ·  $corpName');
    }

    // Dynamic metrics for the center telemetry slot
    final metrics = [
      CockpitMetric(
        label: 'Health',
        value: '${formatWholeNumber(health)}%',
        icon: Icons.favorite_rounded,
        color: health < 40 ? context.errorColor : context.successColor,
      ),
      CockpitMetric(
        label: 'Standing',
        value: formatWholeNumber(state.human['standing'] ?? 0),
        icon: Icons.military_tech_outlined,
        color: context.primaryColor,
      ),
      CockpitMetric(
        label: 'Liquidity',
        value: formatWholeNumber(credits),
        icon: Icons.account_balance_wallet_outlined,
        color: credits < 500 ? context.warningColor : context.goldColor,
      ),
    ];

    return EarthPageCockpit(
      status: statusText,
      statusColor: statusColor,
      infoTitle: 'CITIZEN STATUS & VITALS',
      infoDescription:
          '• Citizen Status & Residency: Real-time vitality status, generational lineage, age in game cycles, and legal residential city jurisdiction.\n\n• Biometric Health: Physical vitality score (0–100%). Low health increases mortality risk and triggers emergency healthcare protocols.\n\n• Civic Standing: Reputation and trust rating earned through lawful contracts, proposal votes, and public treasury contributions.\n\n• Legacy Score: Cumulative generational prestige inherited by designated successors upon succession.\n\n• Planetary World Health: Global ecological equilibrium index. Environmental degradation increases municipal costs and market volatility.',
      title: citizenName,
      subtitle: subtitleBuffer.toString(),
      metrics: metrics,
    );
  }
}
