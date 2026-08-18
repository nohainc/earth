import 'package:flutter/foundation.dart';

typedef AudioSynthesizerFn = void Function(String soundType, double volume);

class EarthAudioEngine {
  static final EarthAudioEngine instance = EarthAudioEngine._();

  EarthAudioEngine._();

  bool _isMuted = false;
  double _masterVolume = 0.8;
  double _sfxVolume = 0.9;
  double _ambientVolume = 0.5;
  bool _ambientPlaying = false;

  AudioSynthesizerFn? customSynthesizer;

  bool get isMuted => _isMuted;
  double get masterVolume => _masterVolume;
  double get sfxVolume => _sfxVolume;
  double get ambientVolume => _ambientVolume;
  bool get isAmbientPlaying => _ambientPlaying;

  void setMuted(bool muted) {
    _isMuted = muted;
    if (_isMuted) {
      stopAmbient();
    }
  }

  void toggleMute() {
    setMuted(!_isMuted);
  }

  void setMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
  }

  void setSfxVolume(double volume) {
    _sfxVolume = volume.clamp(0.0, 1.0);
  }

  void setAmbientVolume(double volume) {
    _ambientVolume = volume.clamp(0.0, 1.0);
  }

  void startAmbient() {
    if (_isMuted) return;
    _ambientPlaying = true;
    _dispatch('ambient', _masterVolume * _ambientVolume);
  }

  void stopAmbient() {
    _ambientPlaying = false;
    _dispatch('stop_ambient', 0.0);
  }

  void playClick() {
    _playSfx('click');
  }

  void playChime() {
    _playSfx('chime');
  }

  void playTradeExecution() {
    _playSfx('trade_executed');
  }

  void playGavel() {
    _playSfx('gavel');
  }

  void playAlert() {
    _playSfx('alert');
  }

  void playCash() {
    _playSfx('cash');
  }

  void _playSfx(String type) {
    if (_isMuted || _masterVolume <= 0.001 || _sfxVolume <= 0.001) return;
    final effectiveVol = (_masterVolume * _sfxVolume).clamp(0.0, 1.0);
    _dispatch(type, effectiveVol);
  }

  void _dispatch(String type, double volume) {
    if (customSynthesizer != null) {
      customSynthesizer!(type, volume);
      return;
    }
    // In production web client or test runner, gracefully dispatch
    debugPrint('[EarthAudio] Sound dispatched: $type at volume ${volume.toStringAsFixed(2)}');
  }
}
