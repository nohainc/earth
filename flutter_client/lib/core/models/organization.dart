class EarthOrganization {
  final String id;
  final String name;
  final String archetype;
  final String joinPolicy;
  final bool isMember;
  final int memberCount;
  final List<String> capabilities;

  const EarthOrganization({
    required this.id,
    required this.name,
    required this.archetype,
    required this.joinPolicy,
    required this.isMember,
    required this.memberCount,
    required this.capabilities,
  });

  factory EarthOrganization.fromJson(Map<String, dynamic> json) {
    return EarthOrganization(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      archetype: '${json['archetype'] ?? ''}',
      joinPolicy: '${json['join_policy'] ?? json['joinPolicy'] ?? 'OPEN'}',
      isMember: json['is_member'] == true || json['isMember'] == true,
      memberCount: (json['member_count'] as num?)?.toInt() ?? (json['memberCount'] as num?)?.toInt() ?? 0,
      capabilities: ((json['capabilities'] as List?) ?? const []).map((value) => '$value').toList(growable: false),
    );
  }
}
