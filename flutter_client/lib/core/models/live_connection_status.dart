import 'package:flutter/material.dart';

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
        return 'RETRY';
      case LiveConnectionStatus.polling:
        return 'POLL';
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
        return 'WebSocket stream disconnected. Periodic polling active (updates every 8s). World data may be slightly delayed.';
      case LiveConnectionStatus.offline:
        return 'Network connection unreachable. Displaying the cached World snapshot.';
    }
  }

  Color get color {
    switch (this) {
      case LiveConnectionStatus.live:
        return const Color(0xFF10B981);
      case LiveConnectionStatus.reconnecting:
        return const Color(0xFFF59E0B);
      case LiveConnectionStatus.polling:
        return const Color(0xFFFBBF24);
      case LiveConnectionStatus.offline:
        return const Color(0xFFEF4444);
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
