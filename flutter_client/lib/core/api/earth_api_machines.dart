part of 'earth_api.dart';

extension EarthApiMachines on EarthApi {
  // --- Machines ---

  Future<EarthState> acquireMachine(String machineType) async {
    await _request('/api/machines/acquire', method: 'POST', body: {
      'machineType': machineType,
      'correlationId':
          'machine-acquisition-$machineType-${DateTime.now().microsecondsSinceEpoch}',
    });
    return world();
  }

  Future<EarthState> maintainMachine(String machineId) async {
    await _request('/api/machines/$machineId/maintenance',
        method: 'POST',
        body: {
          'amount': 10,
          'correlationId':
              'machine-maintenance-$machineId-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> decommissionMachine(String machineId,
      {String otp = ''}) async {
    await _request('/api/machines/$machineId/decommission',
        method: 'POST',
        body: {
          if (otp.isNotEmpty) 'otp': otp,
          'correlationId':
              'machine-recycle-$machineId-${DateTime.now().microsecondsSinceEpoch}',
        });
    return world();
  }

  Future<EarthState> setMachineUtilization(
      String machineId, int utilization) async {
    await _request('/api/machines/$machineId/utilization',
        method: 'POST', body: {'utilization': utilization});
    return world();
  }

  Future<EarthState> assignMachineToBusiness(String machineId, String? businessId) async {
    await _request('/api/machines/$machineId/workplace', method: 'POST', body: {'businessId': businessId});
    return world();
  }

  Future<EarthState> upgradeMachine(String machineId, {String otp = ''}) async {
    await _request('/api/machines/$machineId/upgrade', method: 'POST', body: {
      if (otp.isNotEmpty) 'otp': otp,
    });
    return world();
  }

  Future<EarthState> sellMachine(String machineId, String buyerId, double price,
      {String otp = ''}) async {
    await _request('/api/machines/$machineId/sell', method: 'POST', body: {
      'buyerId': buyerId.trim(),
      'price': price,
      if (otp.isNotEmpty) 'otp': otp,
    });
    return world();
  }

}
