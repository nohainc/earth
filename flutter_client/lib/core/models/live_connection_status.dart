import 'package:flutter/material.dart';
import '../../app/theme.dart';

enum LiveConnectionStatus {
  live,
  reconnecting,
  polling,
  offline,
}

extension LiveConnectionStatusX on LiveConnectionStatus {
  String get label {
    switch (this) {
      case LiveConnectionStatus.live:
        return 'LIVE STREAM ACTIVE';
      case LiveConnectionStatus.reconnecting:
        return 'RECONNECTING / REPLAYING...';
      case LiveConnectionStatus.polling:
        return 'POLLING MODE (PERIODIC SYNC)';
      case LiveConnectionStatus.offline:
        return 'OFFLINE / STALE DATA';
    }
  }

  String get shortLabel {
    switch (this) {
      case LiveConnectionStatus.live:
        return 'LIVE';
      case LiveConnectionStatus.reconnecting:
        return 'RECONNECTING';
      case LiveConnectionStatus.polling:
        return 'POLLING';
      case LiveConnectionStatus.offline:
        return 'OFFLINE';
    }
  }

  String get description {
    switch (this) {
      case LiveConnectionStatus.live:
        return 'Real-time WebSocket telemetry channel active.';
      case LiveConnectionStatus.reconnecting:
        return 'Re-establishing WebSocket telemetry connection...';
      case LiveConnectionStatus.polling:
        return 'WebSocket stream disconnected. Periodic polling active (updates every 8s). Simulation data may be slightly delayed.';
      case LiveConnectionStatus.offline:
        return 'Network connection unreachable. Displaying cached simulation snapshot.';
    }
  }

  Color get color {
    switch (this) {
      case LiveConnectionStatus.live:
        return const Color(0xFF00E676);
      case LiveConnectionStatus.reconnecting:
        return const Color(0xFFFF9100);
      case LiveConnectionStatus.polling:
        return const Color(0xFFFFD600);
      case LiveConnectionStatus.offline:
        return const Color(0xFFFF5252);
    }
  }

  IconData get icon {
    switch (this) {
      case LiveConnectionStatus.live:
        return Icons.bolt;
      case LiveConnectionStatus.reconnecting:
        return Icons.sync;
      case LiveConnectionStatus.polling:
        return Icons.timer_outlined;
      case LiveConnectionStatus.offline:
        return Icons.cloud_off_outlined;
    }
  }
}
