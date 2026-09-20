class ResolvedConstitutionValue {
  final dynamic value;
  final String? source;
  final String? versionId;
  final int? effectiveFromGameDay;

  const ResolvedConstitutionValue({
    required this.value,
    required this.source,
    required this.versionId,
    required this.effectiveFromGameDay,
  });

  factory ResolvedConstitutionValue.fromJson(Map<String, dynamic> json) {
    return ResolvedConstitutionValue(
      value: json['value'],
      source: json['source']?.toString(),
      versionId: json['versionId']?.toString(),
      effectiveFromGameDay: _intOrNull(json['effectiveFromGameDay']),
    );
  }
}

class ConstitutionInputSpec {
  final String inputKind;
  final String? min;
  final String? max;
  final String? step;
  final List<String> allowedValues;

  const ConstitutionInputSpec({
    required this.inputKind,
    required this.min,
    required this.max,
    required this.step,
    required this.allowedValues,
  });

  factory ConstitutionInputSpec.fromJson(Map<String, dynamic> json,
      {required String valueType, List<String> fallbackAllowed = const []}) {
    final allowed = json['allowedValues'] is List
        ? (json['allowedValues'] as List)
            .map((value) => value.toString())
            .toList()
        : fallbackAllowed;
    return ConstitutionInputSpec(
      inputKind: json['inputKind']?.toString() ?? valueType,
      min: json['min']?.toString(),
      max: json['max']?.toString(),
      step: json['step']?.toString(),
      allowedValues: allowed,
    );
  }
}

class ConstitutionRuleView {
  final String code;
  final String articleCode;
  final String valueType;
  final String authorityModel;
  final String policyGroup;
  final String amendmentClass;
  final String calculationKey;
  final List<dynamic> allowedValues;
  final dynamic validation;
  final String displayName;
  final String description;
  final String articleLabel;
  final int order;
  final String inputHint;
  final String displayHint;
  final ConstitutionInputSpec inputSpec;
  final ResolvedConstitutionValue resolved;
  final ResolvedConstitutionValue? earthDefault;
  final String? inheritanceStatus;

  const ConstitutionRuleView({
    required this.code,
    required this.articleCode,
    required this.valueType,
    required this.authorityModel,
    required this.policyGroup,
    required this.amendmentClass,
    required this.calculationKey,
    required this.allowedValues,
    required this.validation,
    required this.displayName,
    required this.description,
    required this.articleLabel,
    required this.order,
    required this.inputHint,
    required this.displayHint,
    required this.inputSpec,
    required this.resolved,
    required this.earthDefault,
    required this.inheritanceStatus,
  });

  factory ConstitutionRuleView.fromJson(Map<String, dynamic> json) {
    final resolved = json['resolved'] is Map
        ? Map<String, dynamic>.from(json['resolved'] as Map)
        : const <String, dynamic>{};
    final allowedValues = json['allowedValues'] is List
        ? (json['allowedValues'] as List)
            .map((value) => value.toString())
            .toList()
        : const <String>[];
    return ConstitutionRuleView(
      code: json['code']?.toString() ?? '',
      articleCode: json['articleCode']?.toString() ?? 'OTHER_POLICY',
      valueType: json['valueType']?.toString() ?? 'POLICY',
      authorityModel: json['authorityModel']?.toString() ?? 'UNKNOWN',
      policyGroup: json['policyGroup']?.toString() ?? 'UNKNOWN',
      amendmentClass: json['amendmentClass']?.toString() ?? 'UNKNOWN',
      calculationKey: json['calculationKey']?.toString() ?? '',
      allowedValues: allowedValues,
      validation: json['validation'],
      displayName: json['displayName']?.toString() ??
          _humanize(json['code']?.toString() ?? 'Rule'),
      description: json['description']?.toString() ?? '',
      articleLabel: json['articleLabel']?.toString() ??
          json['articleCode']?.toString() ??
          'OTHER POLICY',
      order: _int(json['order']),
      inputHint: json['inputHint']?.toString() ?? '',
      displayHint: json['displayHint']?.toString() ??
          json['valueType']?.toString() ??
          '',
      inputSpec: ConstitutionInputSpec.fromJson(
          json['inputSpec'] is Map
              ? Map<String, dynamic>.from(json['inputSpec'] as Map)
              : const <String, dynamic>{},
          valueType: json['valueType']?.toString() ?? 'POLICY',
          fallbackAllowed: allowedValues),
      resolved: ResolvedConstitutionValue.fromJson(resolved),
      earthDefault: json['earthDefault'] is Map
          ? ResolvedConstitutionValue.fromJson(
              Map<String, dynamic>.from(json['earthDefault'] as Map))
          : null,
      inheritanceStatus: json['inheritanceStatus']?.toString(),
    );
  }
}

class ConstitutionArticle {
  final String articleCode;
  final String displayName;
  final List<String> ruleCodes;

  const ConstitutionArticle({
    required this.articleCode,
    required this.displayName,
    required this.ruleCodes,
  });

  factory ConstitutionArticle.fromJson(Map<String, dynamic> json) {
    return ConstitutionArticle(
      articleCode: json['articleCode']?.toString() ?? '',
      displayName: json['displayName']?.toString() ??
          _humanize(json['articleCode']?.toString() ?? 'Article'),
      ruleCodes: json['ruleCodes'] is List
          ? (json['ruleCodes'] as List)
              .map((value) => value.toString())
              .toList()
          : const [],
    );
  }
}

class ConstitutionProgressiveBracket {
  final int ordinal;
  final String lowerBoundUnits;
  final String? upperBoundUnits;
  final String marginalMultiplierNumerator;
  final String marginalMultiplierDenominator;

  const ConstitutionProgressiveBracket({
    required this.ordinal,
    required this.lowerBoundUnits,
    required this.upperBoundUnits,
    required this.marginalMultiplierNumerator,
    required this.marginalMultiplierDenominator,
  });

  factory ConstitutionProgressiveBracket.fromJson(Map<String, dynamic> json) {
    return ConstitutionProgressiveBracket(
      ordinal: _int(json['ordinal']),
      lowerBoundUnits: json['lowerBoundUnits']?.toString() ?? '0',
      upperBoundUnits: json['upperBoundUnits']?.toString(),
      marginalMultiplierNumerator:
          json['marginalMultiplierNumerator']?.toString() ?? '1',
      marginalMultiplierDenominator:
          json['marginalMultiplierDenominator']?.toString() ?? '1',
    );
  }
}

class ConstitutionProgressiveSchedule {
  final String id;
  final String code;
  final String basisType;
  final String authorityInstitutionId;
  final int version;
  final int effectiveFromGameDay;
  final List<ConstitutionProgressiveBracket> brackets;

  const ConstitutionProgressiveSchedule({
    required this.id,
    required this.code,
    required this.basisType,
    required this.authorityInstitutionId,
    required this.version,
    required this.effectiveFromGameDay,
    required this.brackets,
  });

  factory ConstitutionProgressiveSchedule.fromJson(Map<String, dynamic> json) {
    return ConstitutionProgressiveSchedule(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      basisType: json['basisType']?.toString() ?? '',
      authorityInstitutionId: json['authorityInstitutionId']?.toString() ?? '',
      version: _int(json['version']),
      effectiveFromGameDay: _int(json['effectiveFromGameDay']),
      brackets: json['brackets'] is List
          ? (json['brackets'] as List)
              .whereType<Map>()
              .map((row) => ConstitutionProgressiveBracket.fromJson(
                  Map<String, dynamic>.from(row)))
              .toList(growable: false)
          : const [],
    );
  }
}

class ConstitutionChangeSet {
  final String proposalId;
  final String authorityType;
  final String authorityId;
  final String policyGroup;
  final List<dynamic> changes;
  final Map<String, dynamic> baseVersionSnapshot;
  final int? effectiveFromGameDay;

  const ConstitutionChangeSet({
    required this.proposalId,
    required this.authorityType,
    required this.authorityId,
    required this.policyGroup,
    required this.changes,
    required this.baseVersionSnapshot,
    required this.effectiveFromGameDay,
  });

  factory ConstitutionChangeSet.fromJson(Map<String, dynamic> json) {
    return ConstitutionChangeSet(
      proposalId: json['proposalId']?.toString() ?? '',
      authorityType: json['authorityType']?.toString() ?? 'EARTH',
      authorityId: json['authorityId']?.toString() ?? '',
      policyGroup: json['policyGroup']?.toString() ?? '',
      changes: json['changes'] is List ? json['changes'] as List : const [],
      baseVersionSnapshot: json['baseVersionSnapshot'] is Map
          ? Map<String, dynamic>.from(json['baseVersionSnapshot'] as Map)
          : const {},
      effectiveFromGameDay: _intOrNull(json['effectiveFromGameDay']),
    );
  }
}

class ScheduledConstitutionChange {
  final String ruleCode;
  final String authorityType;
  final String authorityId;
  final String versionId;
  final int version;
  final int effectiveFromGameDay;
  final String? proposalId;
  final dynamic value;

  const ScheduledConstitutionChange({
    required this.ruleCode,
    required this.authorityType,
    required this.authorityId,
    required this.versionId,
    required this.version,
    required this.effectiveFromGameDay,
    required this.proposalId,
    required this.value,
  });

  factory ScheduledConstitutionChange.fromJson(Map<String, dynamic> json) {
    return ScheduledConstitutionChange(
      ruleCode: json['ruleCode']?.toString() ?? '',
      authorityType: json['authorityType']?.toString() ?? 'EARTH',
      authorityId: json['authorityId']?.toString() ?? '',
      versionId: json['versionId']?.toString() ?? '',
      version: _int(json['version']),
      effectiveFromGameDay: _int(json['effectiveFromGameDay']),
      proposalId: json['proposalId']?.toString(),
      value: json['value'],
    );
  }
}

class ConstitutionVersionHistory {
  final String ruleCode;
  final String authorityType;
  final String authorityId;
  final String versionId;
  final int version;
  final int effectiveFromGameDay;
  final int? effectiveToGameDay;
  final String status;
  final String? proposalId;
  final dynamic value;

  const ConstitutionVersionHistory({
    required this.ruleCode,
    required this.authorityType,
    required this.authorityId,
    required this.versionId,
    required this.version,
    required this.effectiveFromGameDay,
    required this.effectiveToGameDay,
    required this.status,
    required this.proposalId,
    required this.value,
  });

  factory ConstitutionVersionHistory.fromJson(Map<String, dynamic> json) {
    return ConstitutionVersionHistory(
      ruleCode: json['ruleCode']?.toString() ?? '',
      authorityType: json['authorityType']?.toString() ?? 'EARTH',
      authorityId: json['authorityId']?.toString() ?? '',
      versionId: json['versionId']?.toString() ?? '',
      version: _int(json['version']),
      effectiveFromGameDay: _int(json['effectiveFromGameDay']),
      effectiveToGameDay: _intOrNull(json['effectiveToGameDay']),
      status: json['status']?.toString() ?? 'UNKNOWN',
      proposalId: json['proposalId']?.toString(),
      value: json['value'],
    );
  }
}

int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
int? _intOrNull(dynamic value) => value == null ? null : _int(value);

String _humanize(String value) {
  final last = value.split('.').last;
  return last
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0]}${part.substring(1).toLowerCase()}')
      .join(' ');
}
