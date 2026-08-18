part of 'earth_api.dart';

extension EarthApiDynasty on EarthApi {
  Future<Map<String, dynamic>> dynastyOverview() async {
    final response = await _request('/api/dynasty');
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> unlockDynastyPerk(String perkKey) async {
    final response = await _request(
      '/api/dynasty/perks/unlock',
      method: 'POST',
      body: {'perkKey': perkKey},
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> equipDynastyHeirloom(String heirloomId) async {
    final response = await _request(
      '/api/dynasty/heirlooms/equip',
      method: 'POST',
      body: {'heirloomId': heirloomId},
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> forgeDynastyHeirloom({
    required String name,
    required String heirloomType,
    required String inscription,
    required String statBuff,
  }) async {
    final response = await _request(
      '/api/dynasty/heirlooms/forge',
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

  Future<Map<String, dynamic>> updateDynastyMotto({
    required String motto,
    String? dynastyName,
  }) async {
    final response = await _request(
      '/api/dynasty/motto',
      method: 'POST',
      body: {
        'motto': motto,
        if (dynastyName != null) 'dynastyName': dynastyName,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'ok': true};
  }
}
