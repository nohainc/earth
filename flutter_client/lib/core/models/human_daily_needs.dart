class HumanDailyNeeds {
  final int gameDay;
  final String foodRequiredUnits;
  final String foodConsumedUnits;
  final String foodShortfallUnits;
  final String energyRequiredUnits;
  final String energyConsumedUnits;
  final String energyShortfallUnits;
  final String status;

  const HumanDailyNeeds({
    required this.gameDay,
    required this.foodRequiredUnits,
    required this.foodConsumedUnits,
    required this.foodShortfallUnits,
    required this.energyRequiredUnits,
    required this.energyConsumedUnits,
    required this.energyShortfallUnits,
    required this.status,
  });

  factory HumanDailyNeeds.fromJson(Map<String, dynamic> json) {
    return HumanDailyNeeds(
      gameDay: int.tryParse('${json['gameDay'] ?? 0}') ?? 0,
      foodRequiredUnits: '${json['foodRequiredUnits'] ?? '0'}',
      foodConsumedUnits: '${json['foodConsumedUnits'] ?? '0'}',
      foodShortfallUnits: '${json['foodShortfallUnits'] ?? '0'}',
      energyRequiredUnits: '${json['energyRequiredUnits'] ?? '0'}',
      energyConsumedUnits: '${json['energyConsumedUnits'] ?? '0'}',
      energyShortfallUnits: '${json['energyShortfallUnits'] ?? '0'}',
      status: json['status']?.toString() ?? 'UNKNOWN',
    );
  }

  bool get foodMet => BigInt.tryParse(foodShortfallUnits) == BigInt.zero;
  bool get energyMet => BigInt.tryParse(energyShortfallUnits) == BigInt.zero;
}
