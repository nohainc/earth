import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/earth_state.dart';
import '../../shared/widgets/format_helpers.dart';

class ClientSimulationEngine extends ChangeNotifier {
  EarthState? _baseState;
  DateTime _lastSyncTime = DateTime.now();
  Timer? _ticker;

  EarthState? get state => _baseState;
  DateTime get lastSyncTime => _lastSyncTime;

  ClientSimulationEngine({EarthState? initialState}) {
    if (initialState != null) {
      updateBaseState(initialState);
    }
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  void updateBaseState(EarthState newState) {
    _baseState = newState;
    _lastSyncTime = DateTime.now();
    notifyListeners();
  }

  double get elapsedSeconds {
    return DateTime.now().difference(_lastSyncTime).inMilliseconds / 1000.0;
  }

  /// Calculates interpolated continuous resource quantity.
  double getResourceAmount(String resourceName) {
    if (_baseState == null) return 0.0;
    final baseAmount = asDoubleOr(_baseState!.resources[resourceName], 0.0);
    final flows = _baseState!.json['resourceFlows'];
    final flowMap = flows is Map ? flows : const {};
    final resourceFlow = flowMap[resourceName];
    final netPerSec = asDoubleOr(resourceFlow is Map ? resourceFlow['netPerSecond'] : null, 0.0);
    final calculated = baseAmount + (netPerSec * elapsedSeconds);
    return calculated < 0 ? 0.0 : calculated;
  }

  /// Calculates continuous credit balance.
  double getCreditsAmount() {
    if (_baseState == null) return 0.0;
    final baseCredits = asDoubleOr(_baseState!.human['credits'], 0.0);
    final flows = _baseState!.json['resourceFlows'];
    final flowMap = flows is Map ? flows : const {};
    final creditFlow = flowMap['credits'];
    final netPerSec = asDoubleOr(creditFlow is Map ? creditFlow['netPerSecond'] : null, 0.0);
    final calculated = baseCredits + (netPerSec * elapsedSeconds);
    return calculated < 0 ? 0.0 : calculated;
  }

  /// Calculates flow rate per second for a commodity.
  double getNetRatePerSecond(String resourceName) {
    if (_baseState == null) return 0.0;
    final flows = _baseState!.json['resourceFlows'];
    final flowMap = flows is Map ? flows : const {};
    final resourceFlow = flowMap[resourceName];
    return asDoubleOr(resourceFlow is Map ? resourceFlow['netPerSecond'] : null, 0.0);
  }

  /// Calculates continuous machine condition.
  double getMachineCondition(String machineId, double baseCondition, double utilization) {
    if (utilization <= 0) return baseCondition;
    // Condition drops ~0.0001 per sec at 100% utilization
    final wear = (utilization * 0.0001 / 60.0) * elapsedSeconds;
    final res = baseCondition - wear;
    return res < 0 ? 0.0 : res;
  }

  /// Calculates continuous research progress (0..100).
  double getResearchProgress(double baseProgress, double budget) {
    if (budget <= 0) return baseProgress;
    // Daily rate = min(10, budget / 100), per second = dailyRate / 1440
    final ratePerSec = (budget / 100.0).clamp(1.0, 10.0) / 1440.0;
    final progress = baseProgress + (ratePerSec * elapsedSeconds);
    return progress > 100.0 ? 100.0 : progress;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
