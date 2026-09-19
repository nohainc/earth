class HouseFinanceOverview {
  final String houseId;
  final HouseLiquidity liquidity;
  final HouseObligations obligations;
  final HouseBankSummary bank;
  final HouseCashflow cashflow;

  const HouseFinanceOverview({
    required this.houseId,
    required this.liquidity,
    required this.obligations,
    required this.bank,
    required this.cashflow,
  });

  factory HouseFinanceOverview.fromJson(Map<String, dynamic> json) {
    return HouseFinanceOverview(
      houseId: json['houseId']?.toString() ?? '',
      liquidity: HouseLiquidity.fromJson(_map(json['liquidity'])),
      obligations: HouseObligations.fromJson(_map(json['obligations'])),
      bank: HouseBankSummary.fromJson(_map(json['bank'])),
      cashflow: HouseCashflow.fromJson(_map(json['cashflow'])),
    );
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
}

class HouseLiquidity {
  final BigInt? availableToSpendUnits;
  final int? nextSettlementGameDay;
  const HouseLiquidity({this.availableToSpendUnits, this.nextSettlementGameDay});

  factory HouseLiquidity.fromJson(Map<String, dynamic> json) => HouseLiquidity(
        availableToSpendUnits: _units(json['availableToSpendUnits']),
        nextSettlementGameDay: int.tryParse('${json['nextSettlementGameDay'] ?? ''}'),
      );
}

class HouseObligations {
  final HouseObligationSection capacity;
  final HouseObligationSection taxes;
  final HouseObligationSection loans;
  final HouseObligationSection other;
  final Map<String, dynamic> dailyNeeds;
  const HouseObligations({required this.capacity, required this.taxes, required this.loans, required this.other, required this.dailyNeeds});

  factory HouseObligations.fromJson(Map<String, dynamic> json) => HouseObligations(
        capacity: HouseObligationSection.fromJson(_map(json['capacity'])),
        taxes: HouseObligationSection.fromJson(_map(json['taxes'])),
        loans: HouseObligationSection.fromJson(_map(json['loans'])),
        other: HouseObligationSection.fromJson(_map(json['other'])),
        dailyNeeds: _map(json['dailyNeeds']),
      );
}

class HouseObligationSection {
  final String status;
  final BigInt totalRemainingUnits;
  final List<HouseObligationClaim> claims;
  const HouseObligationSection({required this.status, required this.totalRemainingUnits, required this.claims});

  factory HouseObligationSection.fromJson(Map<String, dynamic> json) => HouseObligationSection(
        status: json['status']?.toString() ?? 'CURRENT',
        totalRemainingUnits: _units(json['totalRemainingUnits']) ?? BigInt.zero,
        claims: (json['claims'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => HouseObligationClaim.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );
}

class HouseObligationClaim {
  final String id;
  final String status;
  final int? dueGameDay;
  final BigInt remainingUnits;
  const HouseObligationClaim({required this.id, required this.status, this.dueGameDay, required this.remainingUnits});

  factory HouseObligationClaim.fromJson(Map<String, dynamic> json) => HouseObligationClaim(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString() ?? 'CURRENT',
        dueGameDay: int.tryParse('${json['dueGameDay'] ?? ''}'),
        remainingUnits: _units(json['remainingUnits']) ?? BigInt.zero,
      );
}

class HouseBankSummary {
  final List<HouseDeposit> deposits;
  final List<HouseLoan> loans;
  final BigInt depositPrincipalUnits;
  final BigInt loanOutstandingUnits;
  const HouseBankSummary({required this.deposits, required this.loans, required this.depositPrincipalUnits, required this.loanOutstandingUnits});

  factory HouseBankSummary.fromJson(Map<String, dynamic> json) => HouseBankSummary(
        deposits: (json['deposits'] as List? ?? const []).whereType<Map>().map((x) => HouseDeposit.fromJson(Map<String, dynamic>.from(x))).toList(growable: false),
        loans: (json['loans'] as List? ?? const []).whereType<Map>().map((x) => HouseLoan.fromJson(Map<String, dynamic>.from(x))).toList(growable: false),
        depositPrincipalUnits: _units(json['summary'] is Map ? (json['summary'] as Map)['depositPrincipalUnits'] : null) ?? BigInt.zero,
        loanOutstandingUnits: _units(json['summary'] is Map ? (json['summary'] as Map)['loanOutstandingUnits'] : null) ?? BigInt.zero,
      );
}

class HouseDeposit {
  final String id;
  final String status;
  final BigInt principalUnits;
  final BigInt accruedInterestUnits;
  final int? startGameDay;
  final int? startGameMinute;
  final int? maturityGameDay;
  final int? maturityGameMinute;
  const HouseDeposit({required this.id, required this.status, required this.principalUnits, required this.accruedInterestUnits, this.startGameDay, this.startGameMinute, this.maturityGameDay, this.maturityGameMinute});

  factory HouseDeposit.fromJson(Map<String, dynamic> json) => HouseDeposit(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString().toUpperCase() ?? 'UNKNOWN',
        principalUnits: _units(json['principal_units'] ?? json['principalUnits']) ?? BigInt.zero,
        accruedInterestUnits: _units(json['accrued_interest_units'] ?? json['accruedInterestUnits']) ?? BigInt.zero,
        startGameDay: int.tryParse('${json['start_game_day'] ?? ''}'),
        startGameMinute: int.tryParse('${json['start_game_minute'] ?? ''}'),
        maturityGameDay: int.tryParse('${json['maturity_game_day'] ?? json['maturityGameDay'] ?? ''}'),
        maturityGameMinute: int.tryParse('${json['maturity_game_minute'] ?? ''}'),
      );
}

class HouseLoan {
  final String id;
  final String status;
  final BigInt outstandingPrincipalUnits;
  final BigInt accruedInterestUnits;
  final int? maturityGameDay;
  final int? nextPaymentGameDay;
  const HouseLoan({required this.id, required this.status, required this.outstandingPrincipalUnits, required this.accruedInterestUnits, this.maturityGameDay, this.nextPaymentGameDay});

  factory HouseLoan.fromJson(Map<String, dynamic> json) => HouseLoan(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString().toUpperCase() ?? 'UNKNOWN',
        outstandingPrincipalUnits: _units(json['outstanding_principal_units']) ?? BigInt.zero,
        accruedInterestUnits: _units(json['accrued_interest_units']) ?? BigInt.zero,
        maturityGameDay: int.tryParse('${json['maturity_game_day'] ?? ''}'),
        nextPaymentGameDay: int.tryParse('${json['next_payment_game_day'] ?? ''}'),
      );
}

class HouseCashflow {
  final Map<String, dynamic> historical;
  final Map<String, dynamic> nextSettlement;
  final List<Map<String, dynamic>> recentTransactions;
  const HouseCashflow({required this.historical, required this.nextSettlement, required this.recentTransactions});

  factory HouseCashflow.fromJson(Map<String, dynamic> json) => HouseCashflow(
        historical: _map(json['historical']),
        nextSettlement: _map(json['nextSettlement']),
        recentTransactions: (json['recentTransactions'] as List? ?? const []).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList(growable: false),
      );
}

BigInt? _units(dynamic value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  return BigInt.tryParse(value.toString());
}

Map<String, dynamic> _map(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : const <String, dynamic>{};
