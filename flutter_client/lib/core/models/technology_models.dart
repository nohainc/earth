class TechnologyEffect {
  final String effectType;
  final String modifierFamily;
  final String targetType;
  final String targetKey;
  final int? modifierBps;

  const TechnologyEffect({
    required this.effectType,
    required this.modifierFamily,
    required this.targetType,
    required this.targetKey,
    required this.modifierBps,
  });

  factory TechnologyEffect.fromJson(Map<String, dynamic> json) =>
      TechnologyEffect(
        effectType: json['effectType']?.toString() ?? '',
        modifierFamily: json['modifierFamily']?.toString() ?? '',
        targetType: json['targetType']?.toString() ?? '',
        targetKey: json['targetKey']?.toString() ?? '',
        modifierBps: int.tryParse('${json['modifierBps']}'),
      );
}

class TechnologyCatalogEntry {
  final String id;
  final String code;
  final String name;
  final String category;
  final String description;
  final String researchCostUnits;
  final int researchDurationGameDays;
  final String researchPointsRequired;
  final List<TechnologyEffect> effects;
  final List<String> prerequisites;
  final String viewerStatus;
  final String? accessSource;

  const TechnologyCatalogEntry({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.description,
    required this.researchCostUnits,
    required this.researchDurationGameDays,
    required this.researchPointsRequired,
    required this.effects,
    required this.prerequisites,
    required this.viewerStatus,
    required this.accessSource,
  });

  factory TechnologyCatalogEntry.fromJson(Map<String, dynamic> json) =>
      TechnologyCatalogEntry(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        researchCostUnits: (json['researchCostUnits'] ?? '0').toString(),
        researchDurationGameDays:
            int.tryParse('${json['researchDurationGameDays']}') ?? 0,
        researchPointsRequired:
            (json['researchPointsRequired'] ?? '0').toString(),
        effects: (json['effects'] as List?)
                ?.whereType<Map>()
                .map((row) =>
                    TechnologyEffect.fromJson(Map<String, dynamic>.from(row)))
                .toList(growable: false) ??
            const [],
        prerequisites: (json['prerequisites'] as List?)
                ?.map((item) => item.toString())
                .where((item) => item.isNotEmpty)
                .toList(growable: false) ??
            const [],
        viewerStatus: json['viewerStatus']?.toString() ?? 'LOCKED',
        accessSource: json['accessSource']?.toString(),
      );
}

class CorporationResearchBudget {
  final String authorizedUnits;
  final String committedUnits;
  final String spentUnits;
  final String availableUnits;
  final String status;

  const CorporationResearchBudget({
    required this.authorizedUnits,
    required this.committedUnits,
    required this.spentUnits,
    required this.availableUnits,
    required this.status,
  });

  factory CorporationResearchBudget.fromJson(Map<String, dynamic> json) =>
      CorporationResearchBudget(
        authorizedUnits: (json['authorizedUnits'] ?? '0').toString(),
        committedUnits: (json['committedUnits'] ?? '0').toString(),
        spentUnits: (json['spentUnits'] ?? '0').toString(),
        availableUnits: (json['availableUnits'] ?? '0').toString(),
        status: json['status']?.toString() ?? 'UNAVAILABLE',
      );
}

class CorporationResearchProject {
  final String id;
  final String name;
  final String targetType;
  final String targetId;
  final String status;
  final String creditCostUnits;
  final int? startedGameDay;
  final int? progressBps;
  final int? remainingGameDays;
  final int? completionGameDay;

  const CorporationResearchProject({
    required this.id,
    required this.name,
    required this.targetType,
    required this.targetId,
    required this.status,
    required this.creditCostUnits,
    required this.startedGameDay,
    required this.progressBps,
    required this.remainingGameDays,
    required this.completionGameDay,
  });

  factory CorporationResearchProject.fromJson(Map<String, dynamic> json) =>
      CorporationResearchProject(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        targetType: json['targetType']?.toString() ??
            json['target_type']?.toString() ??
            '',
        targetId:
            json['targetId']?.toString() ?? json['target_id']?.toString() ?? '',
        status: json['status']?.toString() ?? 'UNKNOWN',
        creditCostUnits:
            (json['creditCostUnits'] ?? json['credit_cost_units'] ?? '0')
                .toString(),
        startedGameDay: int.tryParse(
            '${json['startedGameDay'] ?? json['started_game_day']}'),
        progressBps: int.tryParse('${json['progressBps']}'),
        remainingGameDays: int.tryParse('${json['remainingGameDays']}'),
        completionGameDay: int.tryParse('${json['completionGameDay']}'),
      );
}

class BuildingBlueprintResearch {
  final String projectId;
  final String catalogId;
  final String familyCode;
  final int? tier;
  final String status;
  final int? completedGameDay;

  const BuildingBlueprintResearch({
    required this.projectId,
    required this.catalogId,
    required this.familyCode,
    required this.tier,
    required this.status,
    required this.completedGameDay,
  });

  factory BuildingBlueprintResearch.fromJson(Map<String, dynamic> json) =>
      BuildingBlueprintResearch(
        projectId: (json['projectId'] ?? json['project_id'] ?? '').toString(),
        catalogId: (json['catalogId'] ?? json['catalog_id'] ?? '').toString(),
        familyCode:
            (json['familyCode'] ?? json['family_code'] ?? '').toString(),
        tier: int.tryParse('${json['tier']}'),
        status: json['status']?.toString() ?? 'UNKNOWN',
        completedGameDay: int.tryParse(
            '${json['completedGameDay'] ?? json['completed_game_day']}'),
      );
}

class TechnologyFrontierDomain {
  final String id;
  final String code;
  final String name;
  final int frontierGeneration;
  final int effectiveFromGameDay;
  final int? nextGeneration;
  final int? nextGenerationMinimumGameDay;
  final int? corporationAccessibleGeneration;
  final String governanceStatus;

  const TechnologyFrontierDomain({
    required this.id,
    required this.code,
    required this.name,
    required this.frontierGeneration,
    required this.effectiveFromGameDay,
    required this.nextGeneration,
    required this.nextGenerationMinimumGameDay,
    required this.corporationAccessibleGeneration,
    required this.governanceStatus,
  });

  factory TechnologyFrontierDomain.fromJson(Map<String, dynamic> json) =>
      TechnologyFrontierDomain(
        id: (json['id'] ?? json['domain_id'] ?? '').toString(),
        code: (json['code'] ?? json['domain_code'] ?? '').toString(),
        name: json['name']?.toString() ?? '',
        frontierGeneration: int.tryParse(
                '${json['frontierGeneration'] ?? json['max_generation_number']}') ??
            0,
        effectiveFromGameDay: int.tryParse(
                '${json['effectiveFromGameDay'] ?? json['effective_from_game_day']}') ??
            1,
        nextGeneration: int.tryParse(
            '${json['nextGeneration'] ?? json['next_generation_number']}'),
        nextGenerationMinimumGameDay: int.tryParse(
            '${json['nextGenerationMinimumGameDay'] ?? json['next_generation_minimum_game_day']}'),
        corporationAccessibleGeneration: int.tryParse(
            '${json['corporationAccessibleGeneration']}'),
        governanceStatus: json['governanceStatus']?.toString() ?? 'CURRENT',
      );
}

class TechnologyWorkspace {
  final List<TechnologyCatalogEntry> catalog;
  final List<CorporationResearchProject> projects;
  final List<String> adoptedCodes;
  final CorporationResearchBudget? researchBudget;
  final List<TechnologyFrontierDomain> frontier;

  const TechnologyWorkspace({
    required this.catalog,
    required this.projects,
    required this.adoptedCodes,
    required this.researchBudget,
    required this.frontier,
  });

  factory TechnologyWorkspace.fromJson(Map<String, dynamic> json) =>
      TechnologyWorkspace(
        catalog: (json['catalog'] as List?)
                ?.whereType<Map>()
                .map((row) => TechnologyCatalogEntry.fromJson(
                    Map<String, dynamic>.from(row)))
                .toList(growable: false) ??
            const [],
        projects: (json['projects'] as List?)
                ?.whereType<Map>()
                .map((row) => CorporationResearchProject.fromJson(
                    Map<String, dynamic>.from(row)))
                .toList(growable: false) ??
            const [],
        adoptedCodes: (json['adoptedCodes'] as List?)
                ?.map((value) => value.toString())
            .toList(growable: false) ??
            const [],
        researchBudget: json['researchBudget'] is Map
            ? CorporationResearchBudget.fromJson(
                Map<String, dynamic>.from(json['researchBudget'] as Map))
            : null,
        frontier: (json['frontier'] as List?)
                ?.whereType<Map>()
                .map((row) => TechnologyFrontierDomain.fromJson(
                    Map<String, dynamic>.from(row)))
                .toList(growable: false) ??
            const [],
      );
}
