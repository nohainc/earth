part of 'earth_api.dart';

extension EarthApiSupplyContracts on EarthApi {
  Future<List<dynamic>> supplyContracts() async {
    final response = await _request('/api/contracts/supply');
    if (response is Map<String, dynamic>) {
      return (response['supplyContracts'] as List<dynamic>?) ?? const [];
    }
    return const [];
  }

  Future<Map<String, dynamic>> proposeSupplyContract({
    required String counterpartyId,
    String proposerRole = 'buyer',
    String resourceType = 'energy',
    required double dailyQuantity,
    required double unitPrice,
    required int totalDays,
    double penaltyPerDefault = 0.0,
    String? title,
    String? correlationId,
  }) async {
    final response = await _request(
      '/api/contracts/supply/propose',
      method: 'POST',
      body: {
        'counterpartyId': counterpartyId,
        'proposerRole': proposerRole,
        'resourceType': resourceType,
        'dailyQuantity': dailyQuantity,
        'unitPrice': unitPrice,
        'totalDays': totalDays,
        'penaltyPerDefault': penaltyPerDefault,
        if (title != null && title.isNotEmpty) 'title': title,
        if (correlationId != null) 'correlationId': correlationId,
      },
    );
    return response is Map<String, dynamic> ? response : {'ok': true};
  }

  Future<List<dynamic>> contractDeliveryTicks(String contractId) async {
    final response = await _request('/api/contracts/$contractId/ticks');
    if (response is Map<String, dynamic>) {
      return (response['ticks'] as List<dynamic>?) ?? const [];
    }
    return const [];
  }
}
