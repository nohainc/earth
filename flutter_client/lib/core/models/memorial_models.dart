class MemorialCitizenSummary {
  final String humanId;
  final String displayName;
  final String? houseId;
  final String? houseName;
  final int? birthGameDay;
  final int? deathGameDay;
  final int? ageYears;
  final String? finalLegacy;
  final String? finalStanding;
  final String? successorName;
  final int? generation;
  final String? epitaph;

  const MemorialCitizenSummary({
    required this.humanId,
    required this.displayName,
    required this.houseId,
    required this.houseName,
    required this.birthGameDay,
    required this.deathGameDay,
    required this.ageYears,
    required this.finalLegacy,
    required this.finalStanding,
    required this.successorName,
    required this.generation,
    required this.epitaph,
  });

  factory MemorialCitizenSummary.fromJson(Map<String, dynamic> json) =>
      MemorialCitizenSummary(
        humanId: _string(json['humanId'] ?? json['human_id']) ?? '',
        displayName: _string(json['displayName'] ?? json['display_name']) ?? 'Archived citizen',
        houseId: _string(json['houseId'] ?? json['house_id']),
        houseName: _string(json['houseName'] ?? json['house_name']),
        birthGameDay: _int(json['birthGameDay'] ?? json['birth_game_day']),
        deathGameDay: _int(json['deathGameDay'] ?? json['death_game_day']),
        ageYears: _int(json['ageYears'] ?? json['age_years']),
        finalLegacy: _string(json['finalLegacy'] ?? json['final_legacy']),
        finalStanding: _string(json['finalStanding'] ?? json['final_standing']),
        successorName: _string(json['successorName'] ?? json['successor_name']),
        generation: _int(json['generation']),
        epitaph: _string(json['epitaph']),
      );
}

class MemorialCitizenDetail extends MemorialCitizenSummary {
  final String? causeOfDeathCode;
  final Map<String, dynamic>? causeDetails;
  final String? corporationId;
  final String? corporationName;
  final String? successorHumanId;
  final String? recordVersion;
  final int? memorialCreatedGameDay;
  final List<MemorialOffice> offices;
  final List<MemorialAchievement> achievements;
  final MemorialLifetimeSummary lifetimeSummary;

  const MemorialCitizenDetail({
    required super.humanId,
    required super.displayName,
    required super.houseId,
    required super.houseName,
    required super.birthGameDay,
    required super.deathGameDay,
    required super.ageYears,
    required super.finalLegacy,
    required super.finalStanding,
    required super.successorName,
    required super.generation,
    required super.epitaph,
    required this.causeOfDeathCode,
    required this.causeDetails,
    required this.corporationId,
    required this.corporationName,
    required this.successorHumanId,
    required this.recordVersion,
    required this.memorialCreatedGameDay,
    required this.offices,
    required this.achievements,
    required this.lifetimeSummary,
  });

  factory MemorialCitizenDetail.fromJson(Map<String, dynamic> json) {
    final summary = MemorialCitizenSummary.fromJson(json);
    return MemorialCitizenDetail(
      humanId: summary.humanId,
      displayName: summary.displayName,
      houseId: summary.houseId,
      houseName: summary.houseName,
      birthGameDay: summary.birthGameDay,
      deathGameDay: summary.deathGameDay,
      ageYears: summary.ageYears,
      finalLegacy: summary.finalLegacy,
      finalStanding: summary.finalStanding,
      successorName: summary.successorName,
      generation: summary.generation,
      causeOfDeathCode: _string(json['causeOfDeathCode'] ?? json['cause_of_death']),
      causeDetails: _mapOrNull(json['causeDetails'] ?? json['cause_details']),
      corporationId: _string(json['corporationId'] ?? json['corporation_id']),
      corporationName: _string(json['corporationName'] ?? json['corporation_name']),
      successorHumanId: _string(json['successorHumanId'] ?? json['successor_human_id']),
      recordVersion: _string(json['recordVersion'] ?? json['record_version']),
      memorialCreatedGameDay: _int(json['memorialCreatedGameDay'] ?? json['memorial_created_game_day']),
      offices: _list(json['offices']).map(MemorialOffice.fromJson).toList(growable: false),
      achievements: _list(json['achievements']).map(MemorialAchievement.fromJson).toList(growable: false),
      lifetimeSummary: MemorialLifetimeSummary.fromJson(_map(json['lifetimeSummary'] ?? json['lifetime_summary'])),
      epitaph: summary.epitaph,
    );
  }
}

class MemorialOffice {
  final String roleCode;
  final String roleName;
  final String? institutionId;
  final String? institutionName;
  final String? status;
  final int? effectiveFromGameDay;

  const MemorialOffice({required this.roleCode, required this.roleName, required this.institutionId, required this.institutionName, required this.status, required this.effectiveFromGameDay});

  factory MemorialOffice.fromJson(Map<String, dynamic> json) => MemorialOffice(
    roleCode: _string(json['roleCode'] ?? json['role_code']) ?? 'RECORDED ROLE',
    roleName: _string(json['roleName'] ?? json['role_name']) ?? 'Recorded role',
    institutionId: _string(json['institutionId'] ?? json['institution_id']),
    institutionName: _string(json['institutionName'] ?? json['institution_name']),
    status: _string(json['status']),
    effectiveFromGameDay: _int(json['effectiveFromGameDay'] ?? json['effective_from_game_day']),
  );
}

class MemorialAchievement {
  final String id;
  final String category;
  final String eventType;
  final String title;
  final int? gameDay;
  final int? gameMinute;
  final String? subjectType;
  final String? subjectId;

  const MemorialAchievement({required this.id, required this.category, required this.eventType, required this.title, required this.gameDay, required this.gameMinute, required this.subjectType, required this.subjectId});

  factory MemorialAchievement.fromJson(Map<String, dynamic> json) => MemorialAchievement(
    id: _string(json['id']) ?? '',
    category: _string(json['category']) ?? 'RECORDED',
    eventType: _string(json['eventType'] ?? json['event_type']) ?? 'EVENT',
    title: _string(json['title']) ?? 'Recorded event',
    gameDay: _int(json['gameDay'] ?? json['game_day']),
    gameMinute: _int(json['gameMinute'] ?? json['game_minute']),
    subjectType: _string(json['subjectType'] ?? json['subject_type']),
    subjectId: _string(json['subjectId'] ?? json['subject_id']),
  );
}

class MemorialLifetimeSummary {
  final int governanceEventCount;
  final int researchEventCount;
  final int buildingEventCount;
  final int initiativeEventCount;

  const MemorialLifetimeSummary({required this.governanceEventCount, required this.researchEventCount, required this.buildingEventCount, required this.initiativeEventCount});

  factory MemorialLifetimeSummary.fromJson(Map<String, dynamic> json) => MemorialLifetimeSummary(
    governanceEventCount: _int(json['governanceEventCount'] ?? json['governance_event_count']) ?? 0,
    researchEventCount: _int(json['researchEventCount'] ?? json['research_event_count']) ?? 0,
    buildingEventCount: _int(json['buildingEventCount'] ?? json['building_event_count']) ?? 0,
    initiativeEventCount: _int(json['initiativeEventCount'] ?? json['initiative_event_count']) ?? 0,
  );
}

class MemorialHouseSummary {
  final String houseId;
  final String houseName;
  final String? motto;
  final String status;
  final int? generation;
  final int? foundedGameDay;
  final int? extinctGameDay;
  final int? lifespanDays;
  final int? deceasedCount;
  final bool isExtinct;

  const MemorialHouseSummary({
    required this.houseId,
    required this.houseName,
    required this.motto,
    required this.status,
    required this.generation,
    required this.foundedGameDay,
    required this.extinctGameDay,
    required this.lifespanDays,
    required this.deceasedCount,
    required this.isExtinct,
  });

  factory MemorialHouseSummary.fromJson(Map<String, dynamic> json) =>
      MemorialHouseSummary(
        houseId: _string(json['houseId'] ?? json['id']) ?? '',
        houseName: _string(json['houseName'] ?? json['house_name']) ?? 'House',
        motto: _string(json['motto']),
        status: _string(json['status']) ?? 'UNKNOWN',
        generation: _int(json['generation']),
        foundedGameDay: _int(json['foundedGameDay'] ?? json['founded_game_day']),
        extinctGameDay: _int(json['extinctGameDay'] ?? json['extinct_game_day']),
        lifespanDays: _int(json['lifespanDays'] ?? json['lifespan_days']),
        deceasedCount: _int(json['deceasedCount'] ?? json['deceased_count']),
        isExtinct: json['isExtinct'] == true || json['is_extinct'] == true,
      );
}

class MemorialHouseDetail extends MemorialHouseSummary {
  final List<MemorialCitizenSummary> members;
  final List<MemorialSuccession> successions;

  const MemorialHouseDetail({
    required super.houseId,
    required super.houseName,
    required super.motto,
    required super.status,
    required super.generation,
    required super.foundedGameDay,
    required super.extinctGameDay,
    required super.lifespanDays,
    required super.deceasedCount,
    required super.isExtinct,
    required this.members,
    required this.successions,
  });

  factory MemorialHouseDetail.fromJson(Map<String, dynamic> json) {
    final summary = MemorialHouseSummary.fromJson(json);
    final members = _list(json['members'])
        .map(MemorialCitizenSummary.fromJson)
        .toList(growable: false);
    final successions = _list(json['successions'])
        .map(MemorialSuccession.fromJson)
        .toList(growable: false);
    return MemorialHouseDetail(
      houseId: summary.houseId,
      houseName: summary.houseName,
      motto: summary.motto,
      status: summary.status,
      generation: summary.generation,
      foundedGameDay: summary.foundedGameDay,
      extinctGameDay: summary.extinctGameDay,
      lifespanDays: summary.lifespanDays,
      deceasedCount: summary.deceasedCount,
      isExtinct: summary.isExtinct,
      members: members,
      successions: successions,
    );
  }
}

class MemorialSuccession {
  final String? predecessorHumanId;
  final String? predecessorName;
  final String? successorHumanId;
  final String? successorName;
  final int? gameDay;
  final int? effectiveGameDay;

  const MemorialSuccession({
    this.predecessorHumanId,
    this.predecessorName,
    this.successorHumanId,
    this.successorName,
    this.gameDay,
    this.effectiveGameDay,
  });

  factory MemorialSuccession.fromJson(Map<String, dynamic> json) => MemorialSuccession(
    predecessorHumanId: _string(json['predecessorHumanId'] ?? json['predecessor_human_id']),
    predecessorName: _string(json['predecessorName'] ?? json['predecessor_name']),
    successorHumanId: _string(json['successorHumanId'] ?? json['successor_human_id']),
    successorName: _string(json['successorName'] ?? json['successor_name']),
    gameDay: _int(json['gameDay'] ?? json['game_day']),
    effectiveGameDay: _int(json['effectiveGameDay'] ?? json['effective_game_day']),
  );
}

class HouseLineage {
  final MemorialHouseDetail house;

  const HouseLineage({required this.house});

  factory HouseLineage.fromJson(Map<String, dynamic> json) => HouseLineage(
    house: MemorialHouseDetail.fromJson(_map(json['house'] ?? json)),
  );
}

class MemorialArchivePage {
  final List<MemorialCitizenSummary> citizens;
  final List<MemorialHouseSummary> houses;
  final int citizenTotalCount;
  final int houseTotalCount;
  final String? citizenNextCursor;
  final String? houseNextCursor;

  const MemorialArchivePage({
    required this.citizens,
    required this.houses,
    required this.citizenTotalCount,
    required this.houseTotalCount,
    required this.citizenNextCursor,
    required this.houseNextCursor,
  });

  factory MemorialArchivePage.fromJson(Map<String, dynamic> json) => MemorialArchivePage(
    citizens: _list(json['citizens'] ?? json['deceasedPantheon']).map((row) => MemorialCitizenSummary.fromJson(row)).toList(growable: false),
    houses: _list(json['houses']).map((row) => MemorialHouseSummary.fromJson(row)).toList(growable: false),
    citizenTotalCount: _int(json['citizenTotalCount'] ?? json['deceasedTotalCount']) ?? 0,
    houseTotalCount: _int(json['houseTotalCount']) ?? 0,
    citizenNextCursor: _string(json['citizenNextCursor'] ?? json['deceasedNextCursor']),
    houseNextCursor: _string(json['houseNextCursor']),
  );
}

String? _string(dynamic value) => value == null || value.toString().isEmpty ? null : value.toString();
int? _int(dynamic value) => value == null ? null : int.tryParse(value.toString());
Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
Map<String, dynamic>? _mapOrNull(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : null;
List<Map<String, dynamic>> _list(dynamic value) => value is List ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : <Map<String, dynamic>>[];
