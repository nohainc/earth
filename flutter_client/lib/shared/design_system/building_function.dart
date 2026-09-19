import '../../core/models/building_models.dart';

String _flowLabel(String code) => code.replaceAll('_', ' ').toUpperCase();

String _flowSummary(Iterable<String> codes) =>
    codes.map(_flowLabel).join(' · ');

String _positiveFlowCode(
  Iterable<BuildingResourceFlow> flows,
  String Function(BuildingResourceFlow) amount,
) {
  return _flowSummary(
    flows
        .where((flow) => int.tryParse(amount(flow)) != null)
        .where((flow) => int.parse(amount(flow)) > 0)
        .map((flow) => flow.assetCode),
  );
}

/// Formats the mechanical function of a V5 building from canonical catalog
/// facts. This intentionally contains no gameplay lore or client-side claims.
String buildingEconomicFunction(BuildingCatalogEntry entry) {
  final inputs = _positiveFlowCode(
      entry.resourceFlows, (flow) => flow.operatingInputUnits);
  final outputs = _positiveFlowCode(
      entry.resourceFlows, (flow) => flow.operatingOutputUnits);
  final service = entry.serviceType?.trim();

  if (service != null && service.isNotEmpty) {
    final capacity = entry.serviceCapacityUnits?.trim();
    return capacity == null || capacity.isEmpty
        ? 'SERVICE · ${_flowLabel(service)}'
        : 'SERVICE · ${_flowLabel(service)} · CAPACITY $capacity';
  }
  if (inputs.isNotEmpty && outputs.isNotEmpty) {
    return 'TRANSFORMER · $inputs → $outputs';
  }
  if (outputs.isNotEmpty) return 'PRODUCER · $outputs';
  if (inputs.isNotEmpty) return 'CONSUMER · $inputs';
  return (entry.economicRole ?? entry.category)
      .replaceAll('_', ' ')
      .toUpperCase();
}

/// Compatibility adapter for older read-only panels that have not yet moved
/// to BuildingCatalogEntry. It only consumes authoritative V5 field names.
String buildingEconomicFunctionFromJson(Map<String, dynamic> json) {
  final rawFlows = json['resourceFlows'] ?? json['resource_flows'];
  final flows = rawFlows is List
      ? rawFlows
          .whereType<Map>()
          .map((row) => BuildingResourceFlow(
                assetCode: row['assetCode']?.toString() ??
                    row['asset_code']?.toString() ??
                    '',
                constructionUnits: row['constructionUnits']?.toString() ?? '0',
                operatingInputUnits:
                    row['operatingInputUnits']?.toString() ?? '0',
                operatingOutputUnits:
                    row['operatingOutputUnits']?.toString() ?? '0',
              ))
          .toList(growable: false)
      : const <BuildingResourceFlow>[];
  return buildingEconomicFunction(BuildingCatalogEntry(
    id: json['id']?.toString() ?? '',
    code: json['code']?.toString() ?? json['building_type']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    familyCode:
        json['familyCode']?.toString() ?? json['family_code']?.toString(),
    tier: int.tryParse('${json['tier']}') ?? 0,
    ownershipScope: json['ownershipScope']?.toString() ??
        json['ownership_scope']?.toString() ??
        'PRIVATE',
    economicRole:
        json['economicRole']?.toString() ?? json['economic_role']?.toString(),
    constructionCreditUnits: json['constructionCreditUnits']?.toString() ??
        json['construction_credit_units']?.toString() ??
        '0',
    constructionMinutes: int.tryParse(
            '${json['constructionMinutes'] ?? json['construction_minutes']}') ??
        0,
    operatingCreditUnits: json['operatingCreditUnits']?.toString() ??
        json['operating_credit_units']?.toString(),
    slotFootprintUnits: json['slotFootprintUnits']?.toString() ??
        json['slot_footprint']?.toString() ??
        '0',
    technologyDomain: json['technologyDomain']?.toString() ??
        json['technology_domain']?.toString(),
    minimumScaleCapability: json['minimumScaleCapability']?.toString() ??
        json['minimum_scale_capability']?.toString(),
    serviceType:
        json['serviceType']?.toString() ?? json['service_type']?.toString(),
    serviceCapacityUnits: json['serviceCapacityUnits']?.toString() ??
        json['service_capacity_units']?.toString(),
    resourceFlows: flows,
  ));
}
