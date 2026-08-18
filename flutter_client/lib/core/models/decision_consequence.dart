import 'package:flutter/material.dart';

class DecisionConsequence {
  final String actionTitle;
  final String actionCategory;
  final String immediateCost;
  final String expectedBenefit;
  final String risk;
  final List<String> affectedEntities;
  final bool isPermanent;
  final String impactHorizon;
  final String confirmLabel;
  final IconData icon;

  const DecisionConsequence({
    required this.actionTitle,
    required this.actionCategory,
    required this.immediateCost,
    required this.expectedBenefit,
    required this.risk,
    required this.affectedEntities,
    required this.isPermanent,
    required this.impactHorizon,
    this.confirmLabel = 'CONFIRM & EXECUTE DECISION',
    this.icon = Icons.bolt_outlined,
  });

  Map<String, dynamic> toJson() => {
        'actionTitle': actionTitle,
        'actionCategory': actionCategory,
        'immediateCost': immediateCost,
        'expectedBenefit': expectedBenefit,
        'risk': risk,
        'affectedEntities': affectedEntities,
        'isPermanent': isPermanent,
        'impactHorizon': impactHorizon,
        'confirmLabel': confirmLabel,
      };

  factory DecisionConsequence.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['affectedEntities'] as List<dynamic>? ?? [];
    return DecisionConsequence(
      actionTitle: json['actionTitle']?.toString() ?? '',
      actionCategory: json['actionCategory']?.toString() ?? 'OPERATIONAL ACTION',
      immediateCost: json['immediateCost']?.toString() ?? '0.00 CR',
      expectedBenefit: json['expectedBenefit']?.toString() ?? 'No projected yield',
      risk: json['risk']?.toString() ?? 'Low operational risk',
      affectedEntities: rawEntities.map((e) => e.toString()).toList(),
      isPermanent: json['isPermanent'] == true || json['isPermanent'] == 'true',
      impactHorizon: json['impactHorizon']?.toString() ?? 'Immediate (Day 185)',
      confirmLabel: json['confirmLabel']?.toString() ?? 'CONFIRM & EXECUTE DECISION',
    );
  }

  // Factory Presets for key gameplay decisions
  static DecisionConsequence machineAcquisition({
    required String machineName,
    required double costCredits,
    required String outputYield,
    required String businessName,
  }) {
    return DecisionConsequence(
      actionTitle: 'Acquire Industrial Machine: $machineName',
      actionCategory: 'INDUSTRIAL ASSET ACQUISITION',
      immediateCost: '${costCredits.toStringAsFixed(2)} CR + Initial Power Draw',
      expectedBenefit: '+$outputYield / Simulation Day (+18% Corporate Revenue Capacity)',
      risk: '2.5% daily wear; requires periodic overhaul to prevent breakdowns',
      affectedEntities: [businessName, 'Local Commodity Grid'],
      isPermanent: true,
      impactHorizon: 'Active upon settlement • Recurring Daily',
      confirmLabel: 'AUTHORIZE MACHINE ACQUISITION',
      icon: Icons.precision_manufacturing,
    );
  }

  static DecisionConsequence dividendDistribution({
    required String businessName,
    required double totalAmount,
    required int shareholderCount,
  }) {
    return DecisionConsequence(
      actionTitle: 'Declare Corporate Dividend: $businessName',
      actionCategory: 'EQUITY CAPITAL ALLOCATION',
      immediateCost: '${totalAmount.toStringAsFixed(2)} CR debited from corporate treasury',
      expectedBenefit: 'Pro-rata cash distributions to $shareholderCount equity partners; boosts shareholder confidence',
      risk: 'Reduces operational cash cushion for machine repairs and supply contracts',
      affectedEntities: [businessName, '$shareholderCount Shareholders', 'Municipal Revenue Office'],
      isPermanent: true,
      impactHorizon: 'Immediate ledger settlement (Day 185)',
      confirmLabel: 'EXECUTE DIVIDEND DISTRIBUTION',
      icon: Icons.payments_outlined,
    );
  }

  static DecisionConsequence researchFunding({
    required String projectName,
    required double computeAllocated,
    required String unlockYield,
  }) {
    return DecisionConsequence(
      actionTitle: 'Fund Technological Research: $projectName',
      actionCategory: 'RESEARCH & SCIENTIFIC ADVANCEMENT',
      immediateCost: '${computeAllocated.toStringAsFixed(0)} Compute Nodes Committed',
      expectedBenefit: unlockYield,
      risk: 'Compute capacity is locked for the duration of the research cycle',
      affectedEntities: ['Enterprise Compute Pool', 'Federation Tech Registry'],
      isPermanent: true,
      impactHorizon: '3-Day Research Horizon (Est. Completion Day 188)',
      confirmLabel: 'PLEDGE RESEARCH COMPUTE',
      icon: Icons.science_outlined,
    );
  }

  static DecisionConsequence municipalTaxAdjustment({
    required String cityName,
    required double oldRatePct,
    required double newRatePct,
  }) {
    final isIncrease = newRatePct > oldRatePct;
    return DecisionConsequence(
      actionTitle: 'Amend Municipal Tax Charter: $cityName',
      actionCategory: 'MUNICIPAL CIVIC GOVERNANCE',
      immediateCost: '500.00 CR Civic Proposal Filing Fee',
      expectedBenefit: isIncrease
          ? '+${((newRatePct - oldRatePct) * 1200).toStringAsFixed(0)} CR / Day Municipal Treasury Budget'
          : 'Lowers business overhead by ${(oldRatePct - newRatePct).toStringAsFixed(1)}%, boosting commercial activity',
      risk: isIncrease
          ? 'May cause corporate migration or civic unrest if capacity pressures exist'
          : 'Reduces municipal treasury funding for public infrastructure subsidies',
      affectedEntities: ['$cityName Residents', '$cityName Commercial Enterprises', 'Municipal Senate'],
      isPermanent: false,
      impactHorizon: 'Enacted on Next Game Day Advance',
      confirmLabel: 'RATIFY TAX CHARTER AMENDMENT',
      icon: Icons.account_balance,
    );
  }

  static DecisionConsequence governanceVote({
    required String proposalTitle,
    required String voteType, // 'YES' or 'NO'
    required double votingPower,
  }) {
    return DecisionConsequence(
      actionTitle: 'Cast Senate Ballot: $proposalTitle',
      actionCategory: 'SOVEREIGN SENATE GOVERNANCE',
      immediateCost: '1 Sovereign Ballot (${votingPower.toStringAsFixed(1)} Weighted Votes)',
      expectedBenefit: voteType == 'YES'
          ? 'Advances statutory ratification and policy enactment across the Federation'
          : 'Blocks legislative enactment and protects existing status quo',
      risk: 'Irrevocable ballot; constitutional challenges require supreme court appeal',
      affectedEntities: ['United Corporations Senate', 'Planetary Federation'],
      isPermanent: true,
      impactHorizon: 'Tallied at Voting Cycle Close',
      confirmLabel: 'CAST SOVEREIGN BALLOT ($voteType)',
      icon: Icons.how_to_vote_outlined,
    );
  }
}
