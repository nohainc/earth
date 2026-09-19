class HouseProfile {
  final String profileVersion;
  final HouseIdentity identity;
  final HouseHuman currentHuman;
  final HouseAffiliation? affiliation;
  final HouseSuccession? succession;
  final HouseSuccessionPolicy successionPolicy;
  final HouseSuccessionQuote successionQuote;
  final List<HouseLineageEntry> lineage;
  final List<HouseHistoryEntry> history;
  final HouseSettlementProfile? settlementProfile;
  final HouseEconomics economics;

  const HouseProfile({
    required this.profileVersion,
    required this.identity,
    required this.currentHuman,
    required this.affiliation,
    required this.succession,
    required this.successionPolicy,
    required this.successionQuote,
    required this.lineage,
    required this.history,
    required this.settlementProfile,
    required this.economics,
  });

  factory HouseProfile.fromJson(Map<String, dynamic> json) {
    return HouseProfile(
      profileVersion: json['profileVersion']?.toString() ?? 'UNKNOWN',
      identity: HouseIdentity.fromJson(_map(json['identity'])),
      currentHuman: HouseHuman.fromJson(_map(json['currentHuman'])),
      affiliation: json['affiliation'] is Map
          ? HouseAffiliation.fromJson(_map(json['affiliation']))
          : null,
      succession: json['succession'] is Map
          ? HouseSuccession.fromJson(_map(json['succession']))
          : null,
      successionPolicy:
          HouseSuccessionPolicy.fromJson(_map(json['successionPolicy'])),
      successionQuote:
          HouseSuccessionQuote.fromJson(_map(json['successionQuote'])),
      lineage: (json['lineage'] is List)
          ? (json['lineage'] as List)
              .whereType<Map>()
              .map((entry) =>
                  HouseLineageEntry.fromJson(Map<String, dynamic>.from(entry)))
              .toList(growable: false)
          : const <HouseLineageEntry>[],
      history: (json['history'] is List)
          ? (json['history'] as List)
              .whereType<Map>()
              .map((entry) =>
                  HouseHistoryEntry.fromJson(Map<String, dynamic>.from(entry)))
              .toList(growable: false)
          : const <HouseHistoryEntry>[],
      settlementProfile: json['settlementProfile'] is Map
          ? HouseSettlementProfile.fromJson(_map(json['settlementProfile']))
          : null,
      economics: HouseEconomics.fromJson(_map(json['economics'])),
    );
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
}

class HouseIdentity {
  final String id;
  final String name;
  final String? motto;
  final String status;
  final int generation;
  final String createdAt;

  const HouseIdentity({
    required this.id,
    required this.name,
    required this.motto,
    required this.status,
    required this.generation,
    required this.createdAt,
  });

  factory HouseIdentity.fromJson(Map<String, dynamic> json) => HouseIdentity(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        motto: json['motto']?.toString(),
        status: json['status']?.toString() ?? 'UNKNOWN',
        generation: int.tryParse('${json['generation'] ?? 0}') ?? 0,
        createdAt: json['createdAt']?.toString() ?? '',
      );
}

class HouseHuman {
  final String id;
  final String displayName;
  final int birthGameDay;
  final int ageYears;
  final String status;
  final String standing;
  final String finalLegacy;

  const HouseHuman({
    required this.id,
    required this.displayName,
    required this.birthGameDay,
    required this.ageYears,
    required this.status,
    required this.standing,
    required this.finalLegacy,
  });

  factory HouseHuman.fromJson(Map<String, dynamic> json) => HouseHuman(
        id: json['id']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '',
        birthGameDay: int.tryParse('${json['birthGameDay'] ?? 0}') ?? 0,
        ageYears: int.tryParse('${json['ageYears'] ?? 0}') ?? 0,
        status: json['status']?.toString() ?? 'UNKNOWN',
        standing: json['standing']?.toString() ?? '0',
        finalLegacy: json['finalLegacy']?.toString() ?? '0',
      );
}

class HouseAffiliation {
  final String corporationId;
  final String corporationName;
  final int joinedGameDay;
  final String status;

  const HouseAffiliation({
    required this.corporationId,
    required this.corporationName,
    required this.joinedGameDay,
    required this.status,
  });

  factory HouseAffiliation.fromJson(Map<String, dynamic> json) =>
      HouseAffiliation(
        corporationId: json['corporationId']?.toString() ?? '',
        corporationName: json['corporationName']?.toString() ?? '',
        joinedGameDay: int.tryParse('${json['joinedGameDay'] ?? 0}') ?? 0,
        status: json['status']?.toString() ?? 'UNKNOWN',
      );
}

class HouseSuccession {
  final String successorName;
  final int registeredGameDay;
  final String status;

  const HouseSuccession({
    required this.successorName,
    required this.registeredGameDay,
    required this.status,
  });

  factory HouseSuccession.fromJson(Map<String, dynamic> json) =>
      HouseSuccession(
        successorName: json['successorName']?.toString() ?? '',
        registeredGameDay:
            int.tryParse('${json['registeredGameDay'] ?? 0}') ?? 0,
        status: json['status']?.toString() ?? 'UNKNOWN',
      );
}

class HouseSuccessionPolicy {
  final String fixedCostUnits;
  final String percentageCostBps;
  final int transitionDays;
  final String? rulesVersion;

  const HouseSuccessionPolicy({
    required this.fixedCostUnits,
    required this.percentageCostBps,
    required this.transitionDays,
    required this.rulesVersion,
  });

  factory HouseSuccessionPolicy.fromJson(Map<String, dynamic> json) =>
      HouseSuccessionPolicy(
        fixedCostUnits: json['fixedCostUnits']?.toString() ?? '0',
        percentageCostBps: json['percentageCostBps']?.toString() ?? '0',
        transitionDays: int.tryParse('${json['transitionDays'] ?? 1}') ?? 1,
        rulesVersion: json['rulesVersion']?.toString(),
      );
}

class HouseSuccessionQuote {
  final String houseWalletUnits;
  final String estimatedCostUnits;
  final String calculation;
  final bool affordable;

  const HouseSuccessionQuote({
    required this.houseWalletUnits,
    required this.estimatedCostUnits,
    required this.calculation,
    required this.affordable,
  });

  factory HouseSuccessionQuote.fromJson(Map<String, dynamic> json) =>
      HouseSuccessionQuote(
        houseWalletUnits: json['houseWalletUnits']?.toString() ?? '0',
        estimatedCostUnits: json['estimatedCostUnits']?.toString() ?? '0',
        calculation: json['calculation']?.toString() ?? 'NONE',
        affordable: json['affordable'] == true,
      );
}

class HouseLineageEntry {
  final String humanId;
  final String displayName;
  final int generation;
  final int birthGameDay;
  final int? deathGameDay;
  final String status;
  final String standing;
  final String finalLegacy;
  final String relationship;
  final String? relatedHumanId;
  final String? successionEventId;
  final String? successionStatus;
  final int? effectiveGameDay;

  const HouseLineageEntry({
    required this.humanId,
    required this.displayName,
    required this.generation,
    required this.birthGameDay,
    required this.deathGameDay,
    required this.status,
    required this.standing,
    required this.finalLegacy,
    required this.relationship,
    required this.relatedHumanId,
    required this.successionEventId,
    required this.successionStatus,
    required this.effectiveGameDay,
  });

  factory HouseLineageEntry.fromJson(Map<String, dynamic> json) =>
      HouseLineageEntry(
        humanId: json['humanId']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? 'Unknown Human',
        generation: int.tryParse('${json['generation'] ?? 0}') ?? 0,
        birthGameDay: int.tryParse('${json['birthGameDay'] ?? 0}') ?? 0,
        deathGameDay: json['deathGameDay'] == null
            ? null
            : int.tryParse('${json['deathGameDay']}'),
        status: json['status']?.toString() ?? 'UNKNOWN',
        standing: json['standing']?.toString() ?? '0',
        finalLegacy: json['finalLegacy']?.toString() ?? '0',
        relationship: json['relationship']?.toString() ?? 'UNLINKED',
        relatedHumanId: json['relatedHumanId']?.toString(),
        successionEventId: json['successionEventId']?.toString(),
        successionStatus: json['successionStatus']?.toString(),
        effectiveGameDay: json['effectiveGameDay'] == null
            ? null
            : int.tryParse('${json['effectiveGameDay']}'),
      );
}

class HouseHistoryEntry {
  final String id;
  final int gameDay;
  final int? gameMinute;
  final String category;
  final String eventType;
  final String title;
  final String? subjectType;
  final String? subjectId;

  const HouseHistoryEntry({
    required this.id,
    required this.gameDay,
    required this.gameMinute,
    required this.category,
    required this.eventType,
    required this.title,
    required this.subjectType,
    required this.subjectId,
  });

  factory HouseHistoryEntry.fromJson(Map<String, dynamic> json) =>
      HouseHistoryEntry(
        id: json['id']?.toString() ?? '',
        gameDay: int.tryParse('${json['gameDay'] ?? 0}') ?? 0,
        gameMinute: json['gameMinute'] == null
            ? null
            : int.tryParse('${json['gameMinute']}'),
        category: json['category']?.toString() ?? 'SYSTEM',
        eventType: json['eventType']?.toString() ?? 'EVENT',
        title: json['title']?.toString() ?? 'House event',
        subjectType: json['subjectType']?.toString(),
        subjectId: json['subjectId']?.toString(),
      );
}

class HouseSettlementProfile {
  final String? corporationId;
  final String residentialCapacityUnits;
  final String productiveCapacityUnits;
  final String totalCapacityUnits;
  final int activeBuildingCount;
  final String profileVersion;
  final int sourceGameDay;
  final bool dirty;

  const HouseSettlementProfile({
    required this.corporationId,
    required this.residentialCapacityUnits,
    required this.productiveCapacityUnits,
    required this.totalCapacityUnits,
    required this.activeBuildingCount,
    required this.profileVersion,
    required this.sourceGameDay,
    required this.dirty,
  });

  factory HouseSettlementProfile.fromJson(Map<String, dynamic> json) =>
      HouseSettlementProfile(
        corporationId: json['corporationId']?.toString(),
        residentialCapacityUnits:
            json['residentialCapacityUnits']?.toString() ?? '0',
        productiveCapacityUnits:
            json['productiveCapacityUnits']?.toString() ?? '0',
        totalCapacityUnits: json['totalCapacityUnits']?.toString() ?? '0',
        activeBuildingCount:
            int.tryParse('${json['activeBuildingCount'] ?? 0}') ?? 0,
        profileVersion: json['profileVersion']?.toString() ?? 'UNKNOWN',
        sourceGameDay: int.tryParse('${json['sourceGameDay'] ?? 0}') ?? 0,
        dirty: json['dirty'] == true,
      );
}

class HouseEconomics {
  final String walletUnits;
  final String dynastyLegacyUnits;

  const HouseEconomics({
    required this.walletUnits,
    required this.dynastyLegacyUnits,
  });

  factory HouseEconomics.fromJson(Map<String, dynamic> json) => HouseEconomics(
        walletUnits: json['walletUnits']?.toString() ?? '0',
        dynastyLegacyUnits: json['dynastyLegacyUnits']?.toString() ?? '0',
      );
}
