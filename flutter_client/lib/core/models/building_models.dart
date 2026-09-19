class BuildingPermissions {
  final bool canBuild;
  final bool canPropose;
  final bool canView;
  final bool canOperate;
  final bool canUpgrade;
  final bool canRetrofit;
  final bool canDemolish;

  const BuildingPermissions({
    required this.canBuild,
    required this.canPropose,
    required this.canView,
    required this.canOperate,
    required this.canUpgrade,
    required this.canRetrofit,
    required this.canDemolish,
  });

  factory BuildingPermissions.fromJson(Map<String, dynamic> json) =>
      BuildingPermissions(
        canBuild: json['canBuild'] == true,
        canPropose: json['canPropose'] == true,
        canView: json['canView'] == true,
        canOperate: json['canOperate'] == true,
        canUpgrade: json['canUpgrade'] == true,
        canRetrofit: json['canRetrofit'] == true,
        canDemolish: json['canDemolish'] == true,
      );
}

class BuildingSettlement {
  final int? latestGameDay;
  final String? status;
  final String? operatingCreditUnits;
  final Map<String, String>? inputUnits;
  final Map<String, String>? outputUnits;

  const BuildingSettlement({
    required this.latestGameDay,
    required this.status,
    required this.operatingCreditUnits,
    required this.inputUnits,
    required this.outputUnits,
  });

  factory BuildingSettlement.fromJson(Map<String, dynamic> json) =>
      BuildingSettlement(
        latestGameDay: int.tryParse('${json['latestGameDay']}'),
        status: json['status']?.toString(),
        operatingCreditUnits: json['operatingCreditUnits']?.toString(),
        inputUnits: json['inputUnits'] is Map
            ? (json['inputUnits'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()))
            : null,
        outputUnits: json['outputUnits'] is Map
            ? (json['outputUnits'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()))
            : null,
      );
}

class BuildingOperatingPolicy {
  final String? currentMode;
  final List<String> allowedModes;
  final Map<String, Map<String, dynamic>> effectsByMode;

  const BuildingOperatingPolicy({
    required this.currentMode,
    required this.allowedModes,
    required this.effectsByMode,
  });

  factory BuildingOperatingPolicy.fromJson(Map<String, dynamic> json) =>
      BuildingOperatingPolicy(
        currentMode: json['currentMode']?.toString(),
        allowedModes: (json['allowedModes'] as List?)
                ?.map((mode) => mode.toString())
                .toList(growable: false) ??
            const [],
        effectsByMode: (json['effectsByMode'] as Map?)?.map((mode, value) =>
                MapEntry(mode.toString(), value is Map
                    ? Map<String, dynamic>.from(value)
                    : <String, dynamic>{})) ??
            const {},
      );
}

class BuildingAsset {
  final String id;
  final String catalogId;
  final String buildingType;
  final String ownerType;
  final String ownerId;
  final String ownershipScope;
  final String status;
  final String? constructionState;
  final int? installedGeneration;
  final int? startedGameDay;
  final int? commissionedGameDay;
  final String slotFootprintUnits;
  final int? utilizationBps;
  final BuildingOperatingPolicy operatingPolicy;
  final BuildingPermissions permissions;
  final List<String> allowedActions;
  final BuildingSettlement settlement;

  const BuildingAsset({
    required this.id,
    required this.catalogId,
    required this.buildingType,
    required this.ownerType,
    required this.ownerId,
    required this.ownershipScope,
    required this.status,
    required this.constructionState,
    required this.installedGeneration,
    required this.startedGameDay,
    required this.commissionedGameDay,
    required this.slotFootprintUnits,
    required this.utilizationBps,
    required this.operatingPolicy,
    required this.permissions,
    required this.allowedActions,
    required this.settlement,
  });

  static int? _int(dynamic value) =>
      value == null ? null : int.tryParse(value.toString());

  factory BuildingAsset.fromJson(Map<String, dynamic> json) => BuildingAsset(
        id: json['id']?.toString() ?? '',
        catalogId: json['catalogId']?.toString() ?? '',
        buildingType: json['buildingType']?.toString() ?? '',
        ownerType: json['ownerType']?.toString() ?? 'HOUSE',
        ownerId: json['ownerId']?.toString() ?? '',
        ownershipScope: json['ownershipScope']?.toString() ?? 'PRIVATE',
        status: json['status']?.toString() ?? 'UNKNOWN',
        constructionState: json['constructionState']?.toString(),
        installedGeneration: _int(json['installedGeneration']),
        startedGameDay: _int(json['startedGameDay']),
        commissionedGameDay: _int(json['commissionedGameDay']),
        slotFootprintUnits: json['slotFootprintUnits']?.toString() ?? '0',
        utilizationBps: _int(json['utilizationBps']),
        operatingPolicy: BuildingOperatingPolicy.fromJson(
            json['operatingPolicy'] is Map
                ? Map<String, dynamic>.from(json['operatingPolicy'] as Map)
                : const {}),
        permissions: BuildingPermissions.fromJson(
            json['permissions'] is Map
                ? Map<String, dynamic>.from(json['permissions'] as Map)
                : const {}),
        allowedActions: (json['allowedActions'] as List?)
                ?.map((value) => value.toString())
                .toList(growable: false) ??
            const [],
        settlement: BuildingSettlement.fromJson(
            json['settlement'] is Map
                ? Map<String, dynamic>.from(json['settlement'] as Map)
                : const {}),
      );
}

class BuildingCatalogEntry {
  final String id;
  final String code;
  final String? familyCode;
  final int tier;
  final String ownershipScope;
  final String? economicRole;
  final String constructionCreditUnits;
  final int? constructionMinutes;
  final String? operatingCreditUnits;
  final String slotFootprintUnits;
  final String? technologyDomain;
  final String? minimumScaleCapability;
  final List<dynamic> resourceFlows;

  const BuildingCatalogEntry({
    required this.id,
    required this.code,
    required this.familyCode,
    required this.tier,
    required this.ownershipScope,
    required this.economicRole,
    required this.constructionCreditUnits,
    required this.constructionMinutes,
    required this.operatingCreditUnits,
    required this.slotFootprintUnits,
    required this.technologyDomain,
    required this.minimumScaleCapability,
    required this.resourceFlows,
  });

  factory BuildingCatalogEntry.fromJson(Map<String, dynamic> json) =>
      BuildingCatalogEntry(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        familyCode: json['familyCode']?.toString(),
        tier: int.tryParse('${json['tier']}') ?? 0,
        ownershipScope: json['ownershipScope']?.toString() ?? 'PRIVATE',
        economicRole: json['economicRole']?.toString(),
        constructionCreditUnits:
            json['constructionCreditUnits']?.toString() ?? '0',
        constructionMinutes: int.tryParse('${json['constructionMinutes']}'),
        operatingCreditUnits: json['operatingCreditUnits']?.toString(),
        slotFootprintUnits: json['slotFootprintUnits']?.toString() ?? '0',
        technologyDomain: json['technologyDomain']?.toString(),
        minimumScaleCapability: json['minimumScaleCapability']?.toString(),
        resourceFlows: (json['resourceFlows'] as List?)?.toList(growable: false) ??
            const [],
      );
}

class BuildingPortfolio {
  final List<BuildingAsset> houseAssets;
  final List<BuildingAsset> corporationPublicAssets;
  final List<BuildingCatalogEntry> catalog;
  final String generatedFrom;
  final BuildingPermissions corporationPermissions;

  const BuildingPortfolio({
    required this.houseAssets,
    required this.corporationPublicAssets,
    required this.catalog,
    required this.generatedFrom,
    required this.corporationPermissions,
  });

  factory BuildingPortfolio.fromJson(Map<String, dynamic> json) =>
      BuildingPortfolio(
        houseAssets: _assets(json['houseAssets']),
        corporationPublicAssets: _assets(json['corporationPublicAssets']),
        catalog: (json['catalog'] as List?)
                ?.whereType<Map>()
                .map((row) => BuildingCatalogEntry.fromJson(
                    Map<String, dynamic>.from(row)))
                .toList(growable: false) ??
            const [],
        generatedFrom: json['generatedFrom']?.toString() ??
            'postgres-canonical-building-contract-v5',
        corporationPermissions: BuildingPermissions.fromJson(
            json['corporationPermissions'] is Map
                ? Map<String, dynamic>.from(json['corporationPermissions'] as Map)
                : const {}),
      );

  static List<BuildingAsset> _assets(dynamic value) => (value as List?)
          ?.whereType<Map>()
          .map((row) => BuildingAsset.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false) ??
      const [];
}

class BuildingQuote {
  final bool ok;
  final bool eligible;
  final List<String> blockers;
  final String ownerType;
  final String ownerId;
  final String buildingType;
  final String buildingCatalogId;
  final String footprintUnits;
  final String creditCostUnits;
  final Map<String, dynamic>? capacity;
  final bool canConstruct;
  final List<String> allowedActions;
  final List<Map<String, String>> resourceRequirements;
  final int? effectiveConstructionMinutes;

  const BuildingQuote({
    required this.ok,
    required this.eligible,
    required this.blockers,
    required this.ownerType,
    required this.ownerId,
    required this.buildingType,
    required this.buildingCatalogId,
    required this.footprintUnits,
    required this.creditCostUnits,
    required this.capacity,
    required this.canConstruct,
    required this.allowedActions,
    required this.resourceRequirements,
    required this.effectiveConstructionMinutes,
  });

  factory BuildingQuote.fromJson(Map<String, dynamic> json) => BuildingQuote(
        ok: json['ok'] != false,
        eligible: json['eligible'] == true,
        blockers: (json['blockers'] as List?)
                ?.map((value) => value.toString())
                .toList(growable: false) ??
            const [],
        ownerType: json['ownerType']?.toString() ?? 'HOUSE',
        ownerId: json['ownerId']?.toString() ?? '',
        buildingType: json['buildingType']?.toString() ?? '',
        buildingCatalogId: json['buildingCatalogId']?.toString() ?? '',
        footprintUnits: json['footprintUnits']?.toString() ?? '0',
        creditCostUnits: json['creditCostUnits']?.toString() ?? '0',
        capacity: json['capacity'] is Map
            ? Map<String, dynamic>.from(json['capacity'] as Map)
            : null,
        canConstruct: json['permissions'] is Map &&
            (json['permissions'] as Map)['canConstruct'] == true,
        allowedActions: (json['allowedActions'] as List?)
                ?.map((value) => value.toString())
                .toList(growable: false) ??
            const [],
        resourceRequirements: (json['resourceRequirements'] as List?)
                ?.whereType<Map>()
                .map((value) => value.map((key, item) =>
                    MapEntry(key.toString(), item.toString())))
                .toList(growable: false) ??
            const [],
        effectiveConstructionMinutes:
            int.tryParse('${json['effectiveConstructionMinutes']}'),
      );
}
