part of 'earth_api.dart';

extension EarthApiPersonalFinance on EarthApi {
  Future<Map<String, dynamic>> personalFinance() async {
    final response = await _request('/api/finance/personal');
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<EarthState> declareInsolvencyRestructuring({String? reason, String? otp}) async {
    final body = <String, dynamic>{
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (otp != null && otp.trim().isNotEmpty) 'otp': otp.trim(),
    };
    await _request('/api/finance/personal/declare', method: 'POST', body: body);
    return world();
  }

  Future<EarthState> settlePersonalTax(double taxableAmount) async {
    await _request('/api/taxes/settle', method: 'POST', body: {
      'taxableAmount': taxableAmount,
    });
    return world();
  }
}
