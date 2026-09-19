class HumanAuthoritySummary {
  final String institutionType;
  final String institutionId;
  final String institutionName;
  final String roleCode;
  final String roleName;
  final int effectiveFromDay;

  const HumanAuthoritySummary({
    required this.institutionType,
    required this.institutionId,
    required this.institutionName,
    required this.roleCode,
    required this.roleName,
    required this.effectiveFromDay,
  });

  factory HumanAuthoritySummary.fromJson(Map<String, dynamic> json) {
    return HumanAuthoritySummary(
      institutionType: json['institutionType']?.toString() ?? 'UNKNOWN',
      institutionId: json['institutionId']?.toString() ?? '',
      institutionName: json['institutionName']?.toString() ?? '',
      roleCode: json['roleCode']?.toString() ?? '',
      roleName: json['roleName']?.toString() ?? '',
      effectiveFromDay: int.tryParse('${json['effectiveFromDay'] ?? 0}') ?? 0,
    );
  }
}
