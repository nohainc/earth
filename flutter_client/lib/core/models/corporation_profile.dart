class CorporationProfile {
  final CorporationIdentity identity;
  final CorporationMembershipProfile membership;
  final CorporationCapacityProfile capacity;
  final CorporationCapacityFinance capacityFinance;
  final CorporationAccounts accounts;
  final CorporationFiscalProfile fiscal;
  final CorporationTechnologyProfile technology;
  final CorporationGovernanceProfile governance;
  final CorporationConstitutionProfile constitution;

  const CorporationProfile({
    required this.identity,
    required this.membership,
    required this.capacity,
    required this.capacityFinance,
    required this.accounts,
    required this.fiscal,
    required this.technology,
    required this.governance,
    required this.constitution,
  });

  factory CorporationProfile.fromJson(Map<String, dynamic> json) =>
      CorporationProfile(
        identity: CorporationIdentity.fromJson(_map(json['identity'])),
        membership:
            CorporationMembershipProfile.fromJson(_map(json['membership'])),
        capacity: CorporationCapacityProfile.fromJson(_map(json['capacity'])),
        capacityFinance:
            CorporationCapacityFinance.fromJson(_map(json['capacityFinance'])),
        accounts: CorporationAccounts.fromJson(_map(json['accounts'])),
        fiscal: CorporationFiscalProfile.fromJson(_map(json['fiscal'])),
        technology:
            CorporationTechnologyProfile.fromJson(_map(json['technology'])),
        governance:
            CorporationGovernanceProfile.fromJson(_map(json['governance'])),
        constitution:
            CorporationConstitutionProfile.fromJson(_map(json['constitution'])),
      );
}

class CorporationIdentity {
  final String id;
  final String name;
  final String admissionPolicy;
  final String charterVersion;
  const CorporationIdentity(
      {required this.id,
      required this.name,
      required this.admissionPolicy,
      required this.charterVersion});
  factory CorporationIdentity.fromJson(Map<String, dynamic> json) =>
      CorporationIdentity(
        id: _text(json['id']),
        name: _text(json['name']),
        admissionPolicy: _text(json['admissionPolicy'], 'UNKNOWN'),
        charterVersion: _text(json['charterVersion'], 'UNKNOWN'),
      );
}

class CorporationMembershipProfile {
  final int memberHouseCount;
  final bool canJoin;
  final String membershipState;
  const CorporationMembershipProfile(
      {required this.memberHouseCount,
      required this.canJoin,
      required this.membershipState});
  factory CorporationMembershipProfile.fromJson(Map<String, dynamic> json) =>
      CorporationMembershipProfile(
        memberHouseCount: _int(json['memberHouseCount']),
        canJoin: json['canJoin'] == true,
        membershipState: _text(json['membershipState'], 'INELIGIBLE'),
      );
}

class CorporationCapacityProfile {
  final String occupiedUnits;
  final String availableUnits;
  final String residentialUnits;
  final String privateProductiveUnits;
  final String publicUnits;
  final String standardBlockUnits;
  final String requiredBlocks;
  final int utilizationBps;
  final String? houseBaseRateUnits;
  final String status;
  const CorporationCapacityProfile(
      {required this.occupiedUnits,
      required this.availableUnits,
      required this.residentialUnits,
      required this.privateProductiveUnits,
      required this.publicUnits,
      required this.standardBlockUnits,
      required this.requiredBlocks,
      required this.utilizationBps,
      required this.houseBaseRateUnits,
      required this.status});
  factory CorporationCapacityProfile.fromJson(Map<String, dynamic> json) =>
      CorporationCapacityProfile(
        occupiedUnits: _text(json['occupiedUnits']),
        availableUnits: _text(json['availableUnits']),
        residentialUnits: _text(json['residentialUnits']),
        privateProductiveUnits: _text(json['privateProductiveUnits']),
        publicUnits: _text(json['publicUnits']),
        standardBlockUnits: _text(json['standardBlockUnits']),
        requiredBlocks: _text(json['requiredBlocks']),
        utilizationBps: _int(json['utilizationBps']),
        houseBaseRateUnits: json['houseBaseRateUnits']?.toString(),
        status: _text(json['status'], 'CURRENT'),
      );
}

class CorporationCapacityFinance {
  final String? houseRevenueUnits;
  final String? earthExpenseUnits;
  final String? marginUnits;
  final String? arrearsUnits;
  const CorporationCapacityFinance(
      {required this.houseRevenueUnits,
      required this.earthExpenseUnits,
      required this.marginUnits,
      required this.arrearsUnits});
  factory CorporationCapacityFinance.fromJson(Map<String, dynamic> json) =>
      CorporationCapacityFinance(
        houseRevenueUnits: _text(json['houseRevenueUnits']),
        earthExpenseUnits: _text(json['earthExpenseUnits']),
        marginUnits: _text(json['marginUnits']),
        arrearsUnits: _text(json['arrearsUnits']),
      );
}

class CorporationAccounts {
  final String treasuryUnits;
  final String operationsUnits;
  final String reserveUnits;
  const CorporationAccounts(
      {required this.treasuryUnits,
      required this.operationsUnits,
      required this.reserveUnits});
  factory CorporationAccounts.fromJson(Map<String, dynamic> json) =>
      CorporationAccounts(
        treasuryUnits: _text(json['treasuryUnits']),
        operationsUnits: _text(json['operationsUnits']),
        reserveUnits: _text(json['reserveUnits']),
      );
}

class CorporationFiscalProfile {
  final String? authorizedUnits;
  final String? committedUnits;
  final String? availableUnits;
  final String? dailyRevenueUnits;
  final String? dailyExpenseUnits;
  const CorporationFiscalProfile(
      {required this.authorizedUnits,
      required this.committedUnits,
      required this.availableUnits,
      required this.dailyRevenueUnits,
      required this.dailyExpenseUnits});
  factory CorporationFiscalProfile.fromJson(Map<String, dynamic> json) =>
      CorporationFiscalProfile(
        authorizedUnits: _text(json['authorizedUnits']),
        committedUnits: _text(json['committedUnits']),
        availableUnits: _text(json['availableUnits']),
        dailyRevenueUnits: _text(json['dailyRevenueUnits']),
        dailyExpenseUnits: _text(json['dailyExpenseUnits']),
      );
}

class CorporationTechnologyProfile {
  final int adoptedCount;
  final int activeResearchCount;
  const CorporationTechnologyProfile(
      {required this.adoptedCount, required this.activeResearchCount});
  factory CorporationTechnologyProfile.fromJson(Map<String, dynamic> json) =>
      CorporationTechnologyProfile(
          adoptedCount: _int(json['adoptedCount']),
          activeResearchCount: _int(json['activeResearchCount']));
}

class CorporationGovernanceProfile {
  final int openProposalCount;
  final List<String> roles;
  final List<String> permissions;
  const CorporationGovernanceProfile(
      {required this.openProposalCount,
      required this.roles,
      required this.permissions});
  factory CorporationGovernanceProfile.fromJson(Map<String, dynamic> json) =>
      CorporationGovernanceProfile(
        openProposalCount: _int(json['openProposalCount']),
        roles: _strings(json['roles']),
        permissions: _strings(json['permissions']),
      );
}

class CorporationConstitutionProfile {
  final Map<String, dynamic> rules;
  final Map<String, dynamic> provenance;
  final List<CorporationPolicy> policies;
  const CorporationConstitutionProfile(
      {required this.rules, required this.provenance, required this.policies});
  factory CorporationConstitutionProfile.fromJson(Map<String, dynamic> json) =>
      CorporationConstitutionProfile(
          rules: _map(json['rules']),
          provenance: _map(json['provenance']),
          policies: (json['policies'] is List
                  ? json['policies'] as List
                  : const [])
              .whereType<Map>()
              .map((row) =>
                  CorporationPolicy.fromJson(Map<String, dynamic>.from(row)))
              .toList());
}

class CorporationPolicy {
  final String ruleCode;
  final dynamic value;
  final String source;
  final String? version;
  final int? effectiveFromGameDay;
  final String? calculationKey;
  final String? policyGroup;
  final String? valueType;
  final String? articleCode;
  const CorporationPolicy({
    required this.ruleCode,
    required this.value,
    required this.source,
    required this.version,
    required this.effectiveFromGameDay,
    required this.calculationKey,
    required this.policyGroup,
    required this.valueType,
    required this.articleCode,
  });
  factory CorporationPolicy.fromJson(Map<String, dynamic> json) =>
      CorporationPolicy(
        ruleCode: _text(json['ruleCode'], 'UNKNOWN_RULE'),
        value: json['value'],
        source: _text(json['source'], 'EARTH'),
        version: json['version']?.toString(),
        effectiveFromGameDay:
            int.tryParse(json['effectiveFromGameDay']?.toString() ?? ''),
        calculationKey: json['calculationKey']?.toString(),
        policyGroup: json['policyGroup']?.toString(),
        valueType: json['valueType']?.toString(),
        articleCode: json['articleCode']?.toString(),
      );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
String _text(dynamic value, [String fallback = '0']) =>
    value?.toString() ?? fallback;
int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
List<String> _strings(dynamic value) =>
    value is List ? value.map((item) => item.toString()).toList() : <String>[];
