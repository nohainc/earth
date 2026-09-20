part of 'earth_api.dart';

extension EarthApiHouse on EarthApi {
  Future<HouseProfile> houseProfile() async {
    final response = await _request('/api/house');
    if (response is Map<String, dynamic> && response['houseProfile'] is Map) {
      return HouseProfile.fromJson(
          Map<String, dynamic>.from(response['houseProfile'] as Map));
    }
    throw Exception('House profile unavailable');
  }

  Future<HouseProfile> registerHouseSuccessor(String name) async {
    final response = await _request('/api/house/succession',
        method: 'POST', body: {'name': name.trim()});
    if (response is Map<String, dynamic>) return houseProfile();
    throw Exception('Succession plan could not be saved');
  }

  Future<Map<String, dynamic>> listHousePolicies() async {
    final response = await _request('/api/house/policies');
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'ok': false, 'error': 'Policies unavailable'};
  }

  Future<Map<String, dynamic>> saveHousePolicy({
    required String policyType,
    required int effectiveFromGameDay,
    String operatingMode = 'BALANCED',
    String dailySpendCap = '0',
    Map<String, String> minimumReserve = const {},
    Map<String, String> sellAbove = const {},
    Map<String, String> maxInputPrice = const {},
    Map<String, String> minSalePrice = const {},
    Map<String, String> maxBuyQuantity = const {},
    Map<String, String> maxSellQuantity = const {},
  }) async {
    final response = await _request(
      '/api/house/policies',
      method: 'POST',
      body: {
        'policyType': policyType,
        'effectiveFromGameDay': effectiveFromGameDay,
        'operatingMode': operatingMode,
        'dailySpendCap': dailySpendCap,
        'minimumReserve': minimumReserve,
        'sellAbove': sellAbove,
        'maxInputPrice': maxInputPrice,
        'minSalePrice': minSalePrice,
        'maxBuyQuantity': maxBuyQuantity,
        'maxSellQuantity': maxSellQuantity,
        'correlationId': newClientCorrelationId('HOUSE-POLICY'),
      },
    );
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'ok': false, 'error': 'Policy could not be saved'};
  }

  Future<Map<String, dynamic>> saveHouseAutomation({
    int? effectiveFromGameDay,
    bool enabled = true,
    String dailySpendCap = '0',
    Map<String, String> minimumReserve = const {},
    Map<String, String> sellAbove = const {},
    Map<String, String> maxInputPrice = const {},
    Map<String, String> minSalePrice = const {},
    Map<String, String> maxBuyQuantity = const {},
    Map<String, String> maxSellQuantity = const {},
  }) async {
    final response =
        await _request('/api/house/automation', method: 'PUT', body: {
      if (effectiveFromGameDay != null)
        'effectiveFromGameDay': effectiveFromGameDay,
      'enabled': enabled,
      'dailySpendCap': dailySpendCap,
      'minimumReserve': minimumReserve,
      'sellAbove': sellAbove,
      'maxInputPrice': maxInputPrice,
      'minSalePrice': minSalePrice,
      'maxBuyQuantity': maxBuyQuantity,
      'maxSellQuantity': maxSellQuantity,
      'correlationId': newClientCorrelationId('HOUSE-AUTOMATION'),
    });
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{
            'ok': false,
            'error': 'Automation could not be saved'
          };
  }

  Future<Map<String, dynamic>> getHouseAutomation() async {
    final response = await _request('/api/house/automation');
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{
            'ok': false,
            'error': 'Automation configuration unavailable'
          };
  }

  Future<Map<String, dynamic>> previewHouseAutomation({
    bool enabled = true,
    String dailySpendCap = '0',
    Map<String, String> minimumReserve = const {},
    Map<String, String> sellAbove = const {},
    Map<String, String> maxInputPrice = const {},
    Map<String, String> minSalePrice = const {},
    Map<String, String> maxBuyQuantity = const {},
    Map<String, String> maxSellQuantity = const {},
  }) async {
    final response = await _request('/api/house/automation/preview', method: 'POST', body: {
      'enabled': enabled,
      'dailySpendCap': dailySpendCap,
      'minimumReserve': minimumReserve,
      'sellAbove': sellAbove,
      'maxInputPrice': maxInputPrice,
      'minSalePrice': minSalePrice,
      'maxBuyQuantity': maxBuyQuantity,
      'maxSellQuantity': maxSellQuantity,
    });
    return response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'ok': false, 'error': 'Automation preview unavailable'};
  }

  Future<Map<String, dynamic>> updateHouseProfile({
    required String motto,
    String? houseName,
  }) async {
    final response = await _request(
      '/api/house/profile',
      method: 'PATCH',
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
