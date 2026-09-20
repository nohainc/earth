class HumanProfile {
  final String id;
  final String displayName;
  final String? epitaph;
  final String houseId;
  final String houseName;
  final int? birthGameDay;
  final int? ageYears;
  final String status;
  final int? standing;
  final int? finalLegacy;
  final String? corporationId;
  final String? corporationName;

  const HumanProfile({
    required this.id,
    required this.displayName,
    required this.epitaph,
    required this.houseId,
    required this.houseName,
    required this.birthGameDay,
    required this.ageYears,
    required this.status,
    required this.standing,
    required this.finalLegacy,
    required this.corporationId,
    required this.corporationName,
  });

  static int? _int(dynamic value) => value == null
      ? null
      : int.tryParse(value.toString());

  factory HumanProfile.fromJson(Map<String, dynamic> json) {
    return HumanProfile(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      epitaph: json['epitaph']?.toString(),
      houseId: json['houseId']?.toString() ?? '',
      houseName: json['houseName']?.toString() ?? '',
      birthGameDay: _int(json['birthGameDay']),
      ageYears: _int(json['ageYears']),
      status: json['status']?.toString() ?? 'UNKNOWN',
      standing: _int(json['standing']),
      finalLegacy: _int(json['finalLegacy']),
      corporationId: json['corporationId']?.toString(),
      corporationName: json['corporationName']?.toString(),
    );
  }
}
