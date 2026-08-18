import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/audio/earth_audio_engine.dart';

void main() {
  test('EarthAudioEngine volume controls, mute and sound triggers work correctly', () {
    final engine = EarthAudioEngine.instance;
    final dispatched = <String>[];

    engine.customSynthesizer = (type, volume) {
      dispatched.add('$type:${volume.toStringAsFixed(1)}');
    };

    engine.setMuted(false);
    engine.setMasterVolume(1.0);
    engine.setSfxVolume(1.0);

    engine.playClick();
    expect(dispatched.contains('click:1.0'), isTrue);

    engine.playChime();
    expect(dispatched.contains('chime:1.0'), isTrue);

    engine.playTradeExecution();
    expect(dispatched.contains('trade_executed:1.0'), isTrue);

    engine.playGavel();
    expect(dispatched.contains('gavel:1.0'), isTrue);

    engine.playAlert();
    expect(dispatched.contains('alert:1.0'), isTrue);

    engine.playCash();
    expect(dispatched.contains('cash:1.0'), isTrue);

    // Test mute toggle
    engine.toggleMute();
    expect(engine.isMuted, isTrue);

    dispatched.clear();
    engine.playClick();
    expect(dispatched.isEmpty, isTrue);

    engine.setMuted(false);
    expect(engine.isMuted, isFalse);

    // Test ambient control
    engine.startAmbient();
    expect(engine.isAmbientPlaying, isTrue);

    engine.stopAmbient();
    expect(engine.isAmbientPlaying, isFalse);
  });
}
