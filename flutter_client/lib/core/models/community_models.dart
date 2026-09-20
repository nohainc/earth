const _communityRoles = {'OWNER', 'MODERATOR', 'MEMBER'};

String normalizeCommunityRole(Object? raw) {
  final role = raw?.toString().toUpperCase();
  return _communityRoles.contains(role) ? role! : '';
}

class CommunityViewerPermissions {
  final String? membershipStatus;
  final String? role;
  final String? requestStatus;
  final String? requestId;
  final bool canJoin;
  final bool canLeave;
  final bool canEdit;
  final bool canManageMembers;
  final bool canApproveRequests;
  final bool canChangeRoles;
  final bool canDisband;
  final bool canTransferOwnership;
  final bool canCancelRequest;
  final CommunityViewerCapabilities capabilities;

  const CommunityViewerPermissions({
    required this.membershipStatus,
    required this.role,
    required this.requestStatus,
    required this.requestId,
    required this.canJoin,
    required this.canLeave,
    required this.canEdit,
    required this.canManageMembers,
    required this.canApproveRequests,
    required this.canChangeRoles,
    required this.canDisband,
    required this.canTransferOwnership,
    required this.canCancelRequest,
    required this.capabilities,
  });

  factory CommunityViewerPermissions.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'] is Map
        ? Map<String, dynamic>.from(json['capabilities'] as Map)
        : json;
    final capabilities = CommunityViewerCapabilities.fromJson(rawCapabilities);
    return CommunityViewerPermissions(
      membershipStatus: json['membershipStatus']?.toString(),
      role: (() {
        final role = normalizeCommunityRole(json['role']);
        return role.isEmpty ? null : role;
      })(),
      requestStatus: json['requestStatus']?.toString(),
      requestId: json['requestId']?.toString(),
      canJoin: json['canJoin'] == true,
      canLeave: json['canLeave'] == true,
      canEdit: json['canEdit'] == true,
      canManageMembers: json['canManageMembers'] == true,
      canApproveRequests: json['canApproveRequests'] == true,
      canChangeRoles: json['canChangeRoles'] == true,
      canDisband: json['canDisband'] == true,
      canTransferOwnership: capabilities.canTransferOwnership,
      canCancelRequest: capabilities.canCancelRequest,
      capabilities: capabilities,
    );
  }
}

class CommunityViewerCapabilities {
  final bool canJoin;
  final bool canLeave;
  final bool canEdit;
  final bool canManageMembers;
  final bool canApproveRequests;
  final bool canChangeRoles;
  final bool canDisband;
  final bool canTransferOwnership;
  final bool canCancelRequest;

  const CommunityViewerCapabilities({
    required this.canJoin,
    required this.canLeave,
    required this.canEdit,
    required this.canManageMembers,
    required this.canApproveRequests,
    required this.canChangeRoles,
    required this.canDisband,
    required this.canTransferOwnership,
    required this.canCancelRequest,
  });

  factory CommunityViewerCapabilities.fromJson(Map<String, dynamic> json) =>
      CommunityViewerCapabilities(
        canJoin: json['canJoin'] == true,
        canLeave: json['canLeave'] == true,
        canEdit: json['canEdit'] == true,
        canManageMembers: json['canManageMembers'] == true,
        canApproveRequests: json['canApproveRequests'] == true,
        canChangeRoles: json['canChangeRoles'] == true,
        canDisband: json['canDisband'] == true,
        canTransferOwnership: json['canTransferOwnership'] == true,
        canCancelRequest: json['canCancelRequest'] == true,
      );
}

typedef CommunityCapabilityMatrix = CommunityViewerCapabilities;

class CommunitySummary {
  final String id;
  final String name;
  final String description;
  final String visibility;
  final String joinPolicy;
  final String status;
  final String founderHouseId;
  final String? founderHouseName;
  final int memberCount;
  final CommunityViewerPermissions viewer;

  const CommunitySummary({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.joinPolicy,
    required this.status,
    required this.founderHouseId,
    required this.founderHouseName,
    required this.memberCount,
    required this.viewer,
  });

  factory CommunitySummary.fromJson(Map<String, dynamic> json) {
    final viewer = json['viewer'] is Map
        ? Map<String, dynamic>.from(json['viewer'] as Map)
        : const <String, dynamic>{};
    return CommunitySummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      visibility: json['visibility']?.toString() ?? 'PUBLIC',
      joinPolicy: json['join_policy']?.toString() ?? 'OPEN',
      status: json['status']?.toString() ?? 'ACTIVE',
      founderHouseId: json['founder_house_id']?.toString() ?? '',
      founderHouseName: json['founder_house_name']?.toString(),
      memberCount: _int(json['member_count']),
      viewer: CommunityViewerPermissions.fromJson(viewer),
    );
  }
}

class CommunityDetail extends CommunitySummary {
  final List<CommunityMember> members;
  final List<CommunityMembershipRequest> requests;

  const CommunityDetail({
    required super.id,
    required super.name,
    required super.description,
    required super.visibility,
    required super.joinPolicy,
    required super.status,
    required super.founderHouseId,
    required super.founderHouseName,
    required super.memberCount,
    required super.viewer,
    this.members = const [],
    this.requests = const [],
  });

  factory CommunityDetail.fromJson(Map<String, dynamic> json) {
    final summary = CommunitySummary.fromJson(json);
    final members = (json['members'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => CommunityMember.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    final requests = (json['requests'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => CommunityMembershipRequest.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
    return CommunityDetail(
      id: summary.id,
      name: summary.name,
      description: summary.description,
      visibility: summary.visibility,
      joinPolicy: summary.joinPolicy,
      status: summary.status,
      founderHouseId: summary.founderHouseId,
      founderHouseName: summary.founderHouseName,
      memberCount: summary.memberCount,
      viewer: summary.viewer,
      members: members,
      requests: requests,
    );
  }
}

class CommunityWorkspace extends CommunityDetail {
  final int pendingRequestCount;
  final List<CommunityMember> memberPreview;
  final String? memberNextCursor;
  final String? requestNextCursor;

  const CommunityWorkspace({
    required super.id,
    required super.name,
    required super.description,
    required super.visibility,
    required super.joinPolicy,
    required super.status,
    required super.founderHouseId,
    required super.founderHouseName,
    required super.memberCount,
    required super.viewer,
    super.members,
    super.requests,
    required this.pendingRequestCount,
    required this.memberPreview,
    required this.memberNextCursor,
    required this.requestNextCursor,
  });

  factory CommunityWorkspace.fromJson(Map<String, dynamic> json) {
    final detail = CommunityDetail.fromJson(json);
    final preview = (json['member_preview'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => CommunityMember.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return CommunityWorkspace(
      id: detail.id,
      name: detail.name,
      description: detail.description,
      visibility: detail.visibility,
      joinPolicy: detail.joinPolicy,
      status: detail.status,
      founderHouseId: detail.founderHouseId,
      founderHouseName: detail.founderHouseName,
      memberCount: detail.memberCount,
      viewer: detail.viewer,
      members: detail.members,
      requests: detail.requests,
      pendingRequestCount: _int(json['pending_request_count']),
      memberPreview: preview,
      memberNextCursor: json['member_next_cursor']?.toString(),
      requestNextCursor: json['request_next_cursor']?.toString(),
    );
  }
}

class CommunityMember {
  final String houseId;
  final String houseName;
  final String? currentHumanId;
  final String? currentHumanName;
  final String role;
  final String status;
  final int joinedGameDay;
  final int joinedGameMinute;
  final String? joinedAt;
  final String? leftAt;

  const CommunityMember({
    required this.houseId,
    required this.houseName,
    required this.currentHumanId,
    required this.currentHumanName,
    required this.role,
    required this.status,
    required this.joinedGameDay,
    required this.joinedGameMinute,
    required this.joinedAt,
    required this.leftAt,
  });

  factory CommunityMember.fromJson(Map<String, dynamic> json) =>
      CommunityMember(
        houseId: json['house_id']?.toString() ?? '',
        houseName: json['house_name']?.toString() ?? '',
        currentHumanId: json['current_human_id']?.toString(),
        currentHumanName: json['current_human_name']?.toString(),
        role: normalizeCommunityRole(json['role']),
        status: json['status']?.toString() ?? 'ACTIVE',
        joinedGameDay: _int(json['joined_game_day']),
        joinedGameMinute: _int(json['joined_game_minute']),
        joinedAt: json['joined_at']?.toString(),
        leftAt: json['left_at']?.toString(),
      );
}

typedef CommunityMemberRosterEntry = CommunityMember;

class CommunityMembershipRequest {
  final String id;
  final String communityId;
  final String houseId;
  final String houseName;
  final String? currentHumanId;
  final String? currentHumanName;
  final String applicationMessage;
  final String? decisionNote;
  final String status;
  final int requestedGameDay;
  final int requestedGameMinute;
  final String? createdAt;
  final String? decidedAt;

  const CommunityMembershipRequest({
    required this.id,
    required this.communityId,
    required this.houseId,
    required this.houseName,
    required this.currentHumanId,
    required this.currentHumanName,
    required this.applicationMessage,
    required this.decisionNote,
    required this.status,
    required this.requestedGameDay,
    required this.requestedGameMinute,
    required this.createdAt,
    required this.decidedAt,
  });

  factory CommunityMembershipRequest.fromJson(Map<String, dynamic> json) =>
      CommunityMembershipRequest(
        id: json['id']?.toString() ?? '',
        communityId: json['community_id']?.toString() ?? '',
        houseId: json['house_id']?.toString() ?? '',
        houseName: json['house_name']?.toString() ?? '',
        currentHumanId: json['current_human_id']?.toString(),
        currentHumanName: json['current_human_name']?.toString(),
        applicationMessage: json['application_message']?.toString() ?? '',
        decisionNote: json['decision_note']?.toString(),
        status: json['status']?.toString() ?? 'PENDING',
        requestedGameDay: _int(json['requested_game_day']),
        requestedGameMinute: _int(json['requested_game_minute']),
        createdAt: json['created_at']?.toString(),
        decidedAt: json['decided_at']?.toString(),
      );
}

class CommunityMembersResponse {
  final List<CommunityMember> members;
  final int totalCount;
  final bool hasMore;
  final String? nextCursor;
  const CommunityMembersResponse(this.members,
      {this.totalCount = 0, this.hasMore = false, this.nextCursor});

  factory CommunityMembersResponse.fromJson(Map<String, dynamic> json) =>
      CommunityMembersResponse(
        (json['members'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) =>
                CommunityMember.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: false),
        totalCount: _int(json['totalCount']),
        hasMore: json['hasMore'] == true,
        nextCursor: json['nextCursor']?.toString(),
      );
}

class CommunityMembershipRequestsResponse {
  final List<CommunityMembershipRequest> requests;
  final int totalCount;
  final bool hasMore;
  final String? nextCursor;
  const CommunityMembershipRequestsResponse(this.requests,
      {this.totalCount = 0, this.hasMore = false, this.nextCursor});

  factory CommunityMembershipRequestsResponse.fromJson(
          Map<String, dynamic> json) =>
      CommunityMembershipRequestsResponse(
        (json['requests'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => CommunityMembershipRequest.fromJson(
                Map<String, dynamic>.from(row)))
            .toList(growable: false),
        totalCount: _int(json['totalCount']),
        hasMore: json['hasMore'] == true,
        nextCursor: json['nextCursor']?.toString(),
      );
}

class CommunityMutationResult {
  final String? status;
  final CommunitySummary? community;
  final CommunityMember? member;
  final List<CommunityMember> members;
  final CommunityMembershipRequest? request;

  const CommunityMutationResult({
    this.status,
    this.community,
    this.member,
    this.members = const [],
    this.request,
  });

  factory CommunityMutationResult.fromJson(Map<String, dynamic> json) {
    final community = json['community'] is Map
        ? CommunitySummary.fromJson(
            Map<String, dynamic>.from(json['community'] as Map))
        : null;
    final member = json['member'] is Map
        ? CommunityMember.fromJson(
            Map<String, dynamic>.from(json['member'] as Map))
        : null;
    final request = json['request'] is Map
        ? CommunityMembershipRequest.fromJson(
            Map<String, dynamic>.from(json['request'] as Map))
        : null;
    final members = (json['members'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => CommunityMember.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return CommunityMutationResult(
      status: json['status']?.toString(),
      community: community,
      member: member,
      members: members,
      request: request,
    );
  }
}

class CommunityDirectoryResponse {
  final List<CommunitySummary> communities;
  final int totalCount;
  final bool hasMore;
  final String? nextCursor;

  const CommunityDirectoryResponse({
    required this.communities,
    required this.totalCount,
    required this.hasMore,
    required this.nextCursor,
  });

  factory CommunityDirectoryResponse.fromJson(Map<String, dynamic> json) =>
      CommunityDirectoryResponse(
        communities: (json['communities'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) =>
                CommunitySummary.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: false),
        totalCount: _int(json['totalCount']),
        hasMore: json['hasMore'] == true,
        nextCursor: json['nextCursor']?.toString(),
      );
}

int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
