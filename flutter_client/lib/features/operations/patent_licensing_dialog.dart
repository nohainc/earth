import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showPatentLicensingDialog(
  BuildContext context,
  Future<void> Function(Future<EarthState> Function()) action,
  Map<String, dynamic> patentSpec, {
  String? buildingId,
  String? cityId,
  bool isMemberOfOwningCorp = false,
}) async {
  final patentId = patentSpec['patentId']?.toString() ?? '';
  final patentName = patentSpec['patentName']?.toString() ?? 'Corporate Technology Patent';
  final corpName = patentSpec['owningCorporationName']?.toString() ?? 'Corporate Enterprise';
  final corpId = patentSpec['owningCorporationId']?.toString() ?? '';
  final privCost = asDoubleOr(patentSpec['privateLicenseCostCrd'], 5000);
  final privRoyalty = asDoubleOr(patentSpec['privateDailyRoyaltyCrd'], 80);
  final civicCost = asDoubleOr(patentSpec['cityCivicLicenseCostCrd'], 20000);
  final desc = patentSpec['description']?.toString() ?? '';

  int selectedOption = 0; // 0 = Private 30-day, 1 = City Civic, 2 = Permanent Civic

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: context.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radiusPanel),
          side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
        ),
        title: Row(
          children: [
            Icon(Icons.workspace_premium_outlined, color: context.primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Procure Corporate Patent License',
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
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patentName, style: context.widgetTitleStyle),
                      const SizedBox(height: 2),
                      Text('Proprietary Owner: $corpName ($corpId)', style: context.widgetFooterStyle),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(desc, style: context.bodyStyle),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (isMemberOfOwningCorp)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.successColor.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(context.radiusControl),
                      border: Border.all(color: context.successColor.withValues(alpha: .4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_outlined, color: context.successColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Corporate Member Access: You are affiliated with $corpName. Full patent licensing is included with your corporate membership at no additional fee.',
                            style: context.widgetFooterStyle.copyWith(color: context.successColor),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text('SELECT LICENSING LEVEL & TERMS:', style: context.captionStyle),
                  const SizedBox(height: 8),

                  // Option A: Private 30-Day
                  RadioListTile<int>(
                    value: 0,
                    groupValue: selectedOption,
                    onChanged: (val) => setState(() => selectedOption = val!),
                    title: Text('30-Day Private Building License', style: context.widgetTitleStyle),
                    subtitle: Text(
                      'Cost: ${formatWholeNumber(privCost)} CRD + ${formatWholeNumber(privRoyalty)} CRD/day royalty. Grants full technology bonus for 30 game days.',
                      style: context.widgetFooterStyle,
                    ),
                  ),

                  // Option B: Municipal City-Wide 30-Day
                  RadioListTile<int>(
                    value: 1,
                    groupValue: selectedOption,
                    onChanged: (val) => setState(() => selectedOption = val!),
                    title: Text('30-Day Municipal City-Wide Civic License', style: context.widgetTitleStyle),
                    subtitle: Text(
                      'Cost: ${formatWholeNumber(civicCost)} CRD (from City Treasury). Authorizes all eligible civic public buildings across the entire city.',
                      style: context.widgetFooterStyle,
                    ),
                  ),

                  // Option C: Permanent Civic License
                  RadioListTile<int>(
                    value: 2,
                    groupValue: selectedOption,
                    onChanged: (val) => setState(() => selectedOption = val!),
                    title: Text('Permanent Civic Sovereign License', style: context.widgetTitleStyle),
                    subtitle: Text(
                      'Cost: ${formatWholeNumber(civicCost * 3)} CRD (from City Treasury). Permanent civic authorization with 0 daily royalties.',
                      style: context.widgetFooterStyle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          EarthButton(
            label: 'CANCEL',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          if (!isMemberOfOwningCorp)
            EarthButton(
              label: 'PURCHASE & AUTHORIZE',
              icon: Icons.check_circle_outline,
              variant: EarthButtonVariant.primary,
              onPressed: () async {
                EarthAudioEngine.instance.playClick();
                Navigator.of(dialogContext).pop();
                final isCivic = selectedOption == 1 || selectedOption == 2;
                final isPerm = selectedOption == 2;
                await action(() => const EarthApi().acquireBuildingPatentLicense(
                      patentId: patentId,
                      licenseType: isCivic ? 'city_civic' : 'private_building',
                      buildingId: buildingId,
                      cityId: cityId,
                      isPermanent: isPerm,
                    ));
              },
            ),
        ],
      ),
    ),
  );
}
