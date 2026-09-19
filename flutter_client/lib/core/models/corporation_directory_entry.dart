class CorporationDirectoryEntry {
  final String id;
  final String name;
  final String admissionPolicy;
  final int memberHouseCount;
  final int? incomeTaxBps;
  final int? salesTaxBps;
  final int? corporateTaxBps;
  final int? propertyTaxBps;
  final String? houseCapacityBaseRateUnits;
  final String occupiedCapacityUnits;
  final String standardCapacityUnits;
  final String requiredStandardUnits;
  final int capacityUtilizationBps;
  final String houseCapacityRevenueUnits;
  final String earthCapacityExpenseUnits;
  final String capacityMarginUnits;
  final String capacityStatus;
  final String treasuryUnits;
  final String operationsUnits;
  final String reserveUnits;
  final int technologyCount;
  final int activeResearchCount;
  final bool canJoin;
  final String membershipState;

  const CorporationDirectoryEntry({
    required this.id,
    required this.name,
    required this.admissionPolicy,
    required this.memberHouseCount,
    required this.incomeTaxBps,
    required this.salesTaxBps,
    required this.corporateTaxBps,
    required this.propertyTaxBps,
    required this.houseCapacityBaseRateUnits,
    required this.occupiedCapacityUnits,
    required this.standardCapacityUnits,
    required this.requiredStandardUnits,
    required this.capacityUtilizationBps,
    required this.houseCapacityRevenueUnits,
    required this.earthCapacityExpenseUnits,
    required this.capacityMarginUnits,
    required this.capacityStatus,
    required this.treasuryUnits,
    required this.operationsUnits,
    required this.reserveUnits,
    required this.technologyCount,
    required this.activeResearchCount,
    required this.canJoin,
    required this.membershipState,
  });

  factory CorporationDirectoryEntry.fromJson(Map<String, dynamic> json) {
    String text(String key, [String fallback = '0']) =>
        json[key]?.toString() ?? fallback;
    int? optionalInt(String key) =>
        json[key] == null ? null : int.tryParse(json[key].toString());
    return CorporationDirectoryEntry(
      id: text('id', ''),
      name: text('name', 'Unknown Corporation'),
      admissionPolicy: text('admissionPolicy', 'UNKNOWN'),
      memberHouseCount: int.tryParse(text('memberHouseCount')) ?? 0,
      incomeTaxBps: optionalInt('incomeTaxBps'),
      salesTaxBps: optionalInt('salesTaxBps'),
      corporateTaxBps: optionalInt('corporateTaxBps'),
      propertyTaxBps: optionalInt('propertyTaxBps'),
      houseCapacityBaseRateUnits:
          json['houseCapacityBaseRateUnits']?.toString(),
      occupiedCapacityUnits: text('occupiedCapacityUnits'),
      standardCapacityUnits: text('standardCapacityUnits'),
      requiredStandardUnits: text('requiredStandardUnits'),
      capacityUtilizationBps: int.tryParse(text('capacityUtilizationBps')) ?? 0,
      houseCapacityRevenueUnits: text('houseCapacityRevenueUnits'),
      earthCapacityExpenseUnits: text('earthCapacityExpenseUnits'),
      capacityMarginUnits: text('capacityMarginUnits'),
      capacityStatus: text('capacityStatus', 'CURRENT'),
      treasuryUnits: text('treasuryUnits'),
      operationsUnits: text('operationsUnits'),
      reserveUnits: text('reserveUnits'),
      technologyCount: int.tryParse(text('technologyCount')) ?? 0,
      activeResearchCount: int.tryParse(text('activeResearchCount')) ?? 0,
      canJoin: json['canJoin'] == true,
      membershipState: text('membershipState', 'INELIGIBLE'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'admission_policy': admissionPolicy,
        'member_house_count': memberHouseCount,
        'income_tax_bps': incomeTaxBps,
        'sales_tax_bps': salesTaxBps,
        'corporate_tax_bps': corporateTaxBps,
        'property_tax_bps': propertyTaxBps,
        'house_capacity_base_rate_units': houseCapacityBaseRateUnits,
        'occupied_capacity_units': occupiedCapacityUnits,
        'standard_capacity_units': standardCapacityUnits,
        'required_standard_units': requiredStandardUnits,
        'capacity_utilization_bps': capacityUtilizationBps,
        'house_capacity_revenue_units': houseCapacityRevenueUnits,
        'earth_capacity_expense_units': earthCapacityExpenseUnits,
        'capacity_margin_units': capacityMarginUnits,
        'capacity_status': capacityStatus,
        'treasury_units': treasuryUnits,
        'operations_units': operationsUnits,
        'reserve_units': reserveUnits,
        'technology_count': technologyCount,
        'active_research_count': activeResearchCount,
        'can_join': canJoin,
        'membership_state': membershipState,
      };
}
