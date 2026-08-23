import 'package:flutter/foundation.dart';

@immutable
class BuildingModel {
  final String id;
  final String cityId;
  final String ownerId;
  final String ownershipClass;
  final String? businessId;
  final String buildingType;
  final String name;
  final int tier;
  final double condition;
  final int slotFootprint;
  final String operatingPolicy;
  final bool autoRepairEnabled;
  final double dailyOperatingCredits;
  final String? resourceOutputType;
  final double resourceOutputAmount;
  final int constructionStartedGameDay;
  final int constructionCompleteGameDay;
  final double constructionProgress;
  final String status;
  final String? requiredPatentId;
  final String? patentLicenseStatus;

  const BuildingModel({
    required this.id,
    required this.cityId,
    required this.ownerId,
    required this.ownershipClass,
    this.businessId,
    required this.buildingType,
    required this.name,
    required this.tier,
    required this.condition,
    required this.slotFootprint,
    required this.operatingPolicy,
    required this.autoRepairEnabled,
    required this.dailyOperatingCredits,
    this.resourceOutputType,
    required this.resourceOutputAmount,
    required this.constructionStartedGameDay,
    required this.constructionCompleteGameDay,
    required this.constructionProgress,
    required this.status,
    this.requiredPatentId,
    this.patentLicenseStatus,
  });

  bool get isUnderConstruction => status == 'under_construction';
  bool get isActive => status == 'active';
  bool get isClosed => status == 'closed' || status == 'foreclosed';
  bool get isCivic => ownershipClass == 'civic';
  bool get isPublicInvestment => ownershipClass == 'public_investment';
  bool get isPrivate => ownershipClass == 'private';

  factory BuildingModel.fromJson(Map<String, dynamic> json) {
    return BuildingModel(
      id: json['id']?.toString() ?? '',
      cityId: json['city_id']?.toString() ?? '',
      ownerId: json['owner_id']?.toString() ?? '',
      ownershipClass: json['ownership_class']?.toString() ?? 'private',
      businessId: json['business_id']?.toString(),
      buildingType: json['building_type']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Facility',
      tier: (json['tier'] is num) ? (json['tier'] as num).toInt() : int.tryParse(json['tier']?.toString() ?? '') ?? 1,
      condition: (json['condition'] is num) ? (json['condition'] as num).toDouble() : double.tryParse(json['condition']?.toString() ?? '') ?? 100.0,
      slotFootprint: (json['slot_footprint'] is num) ? (json['slot_footprint'] as num).toInt() : int.tryParse(json['slot_footprint']?.toString() ?? '') ?? 1,
      operatingPolicy: json['operating_policy']?.toString() ?? 'balanced',
      autoRepairEnabled: json['auto_repair_enabled'] == true || json['auto_repair_enabled']?.toString() == 'true',
      dailyOperatingCredits: (json['daily_operating_credits'] is num) ? (json['daily_operating_credits'] as num).toDouble() : double.tryParse(json['daily_operating_credits']?.toString() ?? '') ?? 0.0,
      resourceOutputType: json['resource_output_type']?.toString(),
      resourceOutputAmount: (json['resource_output_amount'] is num) ? (json['resource_output_amount'] as num).toDouble() : double.tryParse(json['resource_output_amount']?.toString() ?? '') ?? 0.0,
      constructionStartedGameDay: (json['construction_started_game_day'] is num) ? (json['construction_started_game_day'] as num).toInt() : int.tryParse(json['construction_started_game_day']?.toString() ?? '') ?? 1,
      constructionCompleteGameDay: (json['construction_complete_game_day'] is num) ? (json['construction_complete_game_day'] as num).toInt() : int.tryParse(json['construction_complete_game_day']?.toString() ?? '') ?? 1,
      constructionProgress: (json['construction_progress'] is num) ? (json['construction_progress'] as num).toDouble() : double.tryParse(json['construction_progress']?.toString() ?? '') ?? 100.0,
      status: json['status']?.toString() ?? 'active',
      requiredPatentId: json['required_patent_id']?.toString(),
      patentLicenseStatus: json['patent_license_status']?.toString(),
    );
  }
}

@immutable
class PatentLicenseModel {
  final String id;
  final String patentId;
  final String patentName;
  final String licenseType;
  final String licenseeId;
  final String licensorCorporationId;
  final String? buildingId;
  final String? cityId;
  final bool isPermanent;
  final int grantedGameDay;
  final int expiryGameDay;
  final double royaltyPerDayCrd;
  final String status;

  const PatentLicenseModel({
    required this.id,
    required this.patentId,
    required this.patentName,
    required this.licenseType,
    required this.licenseeId,
    required this.licensorCorporationId,
    this.buildingId,
    this.cityId,
    required this.isPermanent,
    required this.grantedGameDay,
    required this.expiryGameDay,
    required this.royaltyPerDayCrd,
    required this.status,
  });

  bool get isActive => status == 'active';
  bool get isInRenewalWindow => status == 'renewal_window';
  bool get isExpired => status == 'expired';

  factory PatentLicenseModel.fromJson(Map<String, dynamic> json) {
    return PatentLicenseModel(
      id: json['id']?.toString() ?? '',
      patentId: json['patent_id']?.toString() ?? '',
      patentName: json['patent_name']?.toString() ?? '',
      licenseType: json['license_type']?.toString() ?? 'private_building',
      licenseeId: json['licensee_id']?.toString() ?? '',
      licensorCorporationId: json['licensor_corporation_id']?.toString() ?? '',
      buildingId: json['building_id']?.toString(),
      cityId: json['city_id']?.toString(),
      isPermanent: json['is_permanent'] == true || json['is_permanent']?.toString() == 'true',
      grantedGameDay: (json['granted_game_day'] is num) ? (json['granted_game_day'] as num).toInt() : int.tryParse(json['granted_game_day']?.toString() ?? '') ?? 1,
      expiryGameDay: (json['expiry_game_day'] is num) ? (json['expiry_game_day'] as num).toInt() : int.tryParse(json['expiry_game_day']?.toString() ?? '') ?? 30,
      royaltyPerDayCrd: (json['royalty_per_day_crd'] is num) ? (json['royalty_per_day_crd'] as num).toDouble() : double.tryParse(json['royalty_per_day_crd']?.toString() ?? '') ?? 0.0,
      status: json['status']?.toString() ?? 'active',
    );
  }
}

@immutable
class DistrictZoningModel {
  final String cityId;
  final int totalSlots;
  final int occupiedSlots;
  final int availableSlots;
  final int civicSlotsReserved;
  final int civicSlotsUsed;
  final double occupancyRate;

  const DistrictZoningModel({
    required this.cityId,
    required this.totalSlots,
    required this.occupiedSlots,
    required this.availableSlots,
    required this.civicSlotsReserved,
    required this.civicSlotsUsed,
    required this.occupancyRate,
  });

  factory DistrictZoningModel.fromJson(Map<String, dynamic> json) {
    return DistrictZoningModel(
      cityId: json['cityId']?.toString() ?? '',
      totalSlots: (json['totalSlots'] is num) ? (json['totalSlots'] as num).toInt() : 0,
      occupiedSlots: (json['occupiedSlots'] is num) ? (json['occupiedSlots'] as num).toInt() : 0,
      availableSlots: (json['availableSlots'] is num) ? (json['availableSlots'] as num).toInt() : 0,
      civicSlotsReserved: (json['civicSlotsReserved'] is num) ? (json['civicSlotsReserved'] as num).toInt() : 0,
      civicSlotsUsed: (json['civicSlotsUsed'] is num) ? (json['civicSlotsUsed'] as num).toInt() : 0,
      occupancyRate: (json['occupancyRate'] is num) ? (json['occupancyRate'] as num).toDouble() : 0.0,
    );
  }
}
