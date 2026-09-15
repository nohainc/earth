class OrganizationCharter {
  const OrganizationCharter({
    required this.membershipModel,
    required this.ownershipModel,
    required this.votingMethod,
    required this.authorityLimits,
    required this.surplusPolicy,
    required this.capabilities,
    required this.dissolutionPolicy,
  });

  final String membershipModel;
  final String ownershipModel;
  final String votingMethod;
  final Map<String, dynamic> authorityLimits;
  final String surplusPolicy;
  final List<String> capabilities;
  final String dissolutionPolicy;

  factory OrganizationCharter.fromJson(Map<String, dynamic> json) => OrganizationCharter(
    membershipModel: json['membershipModel'] as String,
    ownershipModel: json['ownershipModel'] as String,
    votingMethod: json['votingMethod'] as String,
    authorityLimits: Map<String, dynamic>.from(json['authorityLimits'] as Map),
    surplusPolicy: json['surplusPolicy'] as String,
    capabilities: (json['capabilities'] as List).cast<String>(),
    dissolutionPolicy: json['dissolutionPolicy'] as String,
  );

  Map<String, dynamic> toJson() => {
    'membershipModel': membershipModel,
    'ownershipModel': ownershipModel,
    'votingMethod': votingMethod,
    'authorityLimits': authorityLimits,
    'surplusPolicy': surplusPolicy,
    'capabilities': capabilities,
    'dissolutionPolicy': dissolutionPolicy,
  };
}
