part of 'earth_api.dart';

extension EarthApiHouse on EarthApi {
  Future<Map<String, dynamic>> houseOverview() async {
    final response = await _request('/api/house');
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> unlockHousePerk(String perkKey) async {
    final response = await _request(
      '/api/house/perks/unlock',
      method: 'POST',
      body: {'perkKey': perkKey},
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> equipHouseHeirloom(String heirloomId) async {
    final response = await _request(
      '/api/house/heirlooms/equip',
      method: 'POST',
      body: {'heirloomId': heirloomId},
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> forgeHouseHeirloom({
    required String name,
    required String heirloomType,
    required String inscription,
    required String statBuff,
  }) async {
    final response = await _request(
      '/api/house/heirlooms/forge',
      method: 'POST',
      body: {
        'name': name,
        'heirloomType': heirloomType,
        'inscription': inscription,
        'statBuff': statBuff,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> updateHouseMotto({
    required String motto,
    String? houseName,
  }) async {
    final response = await _request(
      '/api/house/motto',
      method: 'POST',
      body: {
        'motto': motto,
        if (houseName != null) 'houseName': houseName,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

}
