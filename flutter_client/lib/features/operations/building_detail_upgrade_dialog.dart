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
  final resourceReqs = (quote['resourceRequirements'] as List?)
          ?.whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList() ??
      [];
  final minScale = quote['minimumScaleCapability']?.toString();
  final scaleAuth = quote['scaleAuthorization'] is Map
      ? Map<String, dynamic>.from(quote['scaleAuthorization'] as Map)
      : null;
  final beforeRent = quote['beforeRentUnits']?.toString() ??
      capacity['currentChargeUnits']?.toString();
  final afterRent = quote['afterRentUnits']?.toString() ??
      capacity['afterChargeUnits']?.toString();
  final deltaRent = quote['deltaRentUnits']?.toString() ??
      capacity['incrementalChargeUnits']?.toString();

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
              Text('UPGRADE RESOURCE COSTS', style: context.captionStyle),
              _quoteRow(context, 'CREDIT cost', creditCost),
              for (final req in resourceReqs)
                _quoteRow(
                  context,
                  '${req['code']} required',
                  '${req['requiredUnits']} (Available: ${req['availableUnits']})',
                ),
              _quoteRow(context, 'Capacity change', footprintDelta),
              _quoteRow(context, 'Construction time (minutes)', duration),
              if (minScale != null && minScale != 'SCALE_NONE') ...[
                const Divider(height: 20),
                Text('SCALE CAPABILITY', style: context.captionStyle),
                _quoteRow(context, 'Required capability', minScale),
                _quoteRow(
                  context,
                  'Authorization status',
                  scaleAuth?['authorized'] == true
                      ? 'Authorized'
                      : 'Unauthorized (${scaleAuth?['reason'] ?? 'Locked'})',
                ),
              ],
              if (beforeRent != null || afterRent != null) ...[
                const Divider(height: 20),
                Text('CAPACITY RENT IMPACT', style: context.captionStyle),
                if (beforeRent != null)
                  _quoteRow(context, 'Current rent', beforeRent),
                if (afterRent != null)
                  _quoteRow(context, 'After rent', afterRent),
                if (deltaRent != null)
                  _quoteRow(context, 'Rent delta', deltaRent),
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
