import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';

/// Reviews the server's upgrade quote before submitting the upgrade command.
///
/// The catalog argument is retained for the existing caller contract, but the
/// dialog intentionally does not derive costs, production, or upkeep from it.
/// Those values belong to the server quote and settlement read models.
Future<bool?> showBuildingDetailUpgradeDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  Map<String, dynamic> building,
  List<dynamic> catalog,
) async {
  final buildingId = building['id']?.toString() ?? '';
  final buildingName = building['name']?.toString() ?? 'Facility';
  final currentTier = building['tier']?.toString() ?? 'UNAVAILABLE';
  final quote = await const EarthApi().quoteBuildingUpgrade(
    buildingId: buildingId,
  );
  if (quote['eligible'] != true) {
    if (context.mounted) {
      final blockers = (quote['blockers'] as List?)?.join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blockers?.isNotEmpty == true
            ? blockers!
            : 'Upgrade quote unavailable')),
      );
    }
    return false;
  }

  if (!context.mounted) return false;
  final targetTier = quote['targetTier']?.toString() ?? 'UNAVAILABLE';
  final targetCatalog = quote['targetCatalog'] is Map
      ? Map<String, dynamic>.from(quote['targetCatalog'] as Map)
      : const <String, dynamic>{};
  final capacity = quote['capacity'] is Map
      ? Map<String, dynamic>.from(quote['capacity'] as Map)
      : const <String, dynamic>{};
  final creditCost = quote['creditCostUnits']?.toString() ?? 'UNAVAILABLE';
  final footprintDelta = quote['footprintDelta']?.toString() ?? 'UNAVAILABLE';
  final duration = quote['constructionMinutes']?.toString() ?? 'UNAVAILABLE';

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      title: Row(
        children: [
          Icon(Icons.arrow_upward_outlined, color: context.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Upgrade to Tier $targetTier',
              style: context.topicTitleStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review the server-authoritative upgrade quote. Final eligibility and balances are checked again when the command executes.',
                style: context.bodyStyle,
              ),
              const SizedBox(height: 14),
              _quoteRow(context, 'Current tier', currentTier),
              _quoteRow(context, 'Target tier', targetTier),
              const Divider(height: 20),
              Text('UPGRADE COST', style: context.captionStyle),
              _quoteRow(context, 'CREDIT cost', creditCost),
              _quoteRow(context, 'Capacity change', footprintDelta),
              _quoteRow(context, 'Construction time (minutes)', duration),
              const Divider(height: 20),
              Text('DAILY UPKEEP CHANGES', style: context.captionStyle),
              _quoteRow(context, 'Upkeep adjustments', 'Normal (balanced)'),
              const Divider(height: 20),
              Text('OPERATING COST CHANGES', style: context.captionStyle),
              _quoteRow(context, 'Target operating CREDIT',
                  targetCatalog['operatingCreditUnits']?.toString() ?? 'Standard'),
              if (capacity.isNotEmpty) ...[
                const Divider(height: 20),
                Text('CAPACITY QUOTE', style: context.captionStyle),
                _quoteRow(context, 'Current charge',
                    capacity['currentChargeUnits']?.toString() ?? 'UNAVAILABLE'),
                _quoteRow(context, 'After charge',
                    capacity['afterChargeUnits']?.toString() ?? 'UNAVAILABLE'),
                _quoteRow(context, 'Incremental charge',
                    capacity['incrementalChargeUnits']?.toString() ??
                        'UNAVAILABLE'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        EarthButton(
          label: 'CLOSE',
          variant: EarthButtonVariant.neutral,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        EarthButton(
          label: 'COMMENCE TIER $targetTier UPGRADE',
          icon: Icons.arrow_upward_outlined,
          variant: EarthButtonVariant.primary,
          onPressed: () async {
            EarthAudioEngine.instance.playClick();
            Navigator.of(dialogContext).pop(true);
            await action(
                () => const EarthApi().upgradeBuilding(buildingId: buildingId));
          },
        ),
      ],
    ),
  );
}

Widget _quoteRow(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: context.widgetFooterStyle)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end, style: context.widgetTitleStyle),
        ),
      ],
    ),
  );
}
