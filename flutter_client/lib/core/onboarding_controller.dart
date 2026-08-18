import 'package:flutter/material.dart';
import 'models/onboarding_state.dart';
import 'audio/earth_audio_engine.dart';

class OnboardingController extends ChangeNotifier {
  static final OnboardingController instance = OnboardingController._internal();

  OnboardingController._internal();

  OnboardingProgress _progress = const OnboardingProgress();

  OnboardingProgress get progress => _progress;
  int get currentStepIndex => _progress.currentStepIndex;
  OnboardingStep get currentStep => OnboardingStep.steps[_progress.currentStepIndex.clamp(0, OnboardingStep.steps.length - 1)];
  bool get isDismissed => _progress.isDismissed;
  bool get isCompleted => _progress.isCompleted;

  void completeStep(String stepId) {
    if (_progress.completedStepIds.contains(stepId)) return;

    final updatedSet = Set<String>.from(_progress.completedStepIds)..add(stepId);
    final allComplete = updatedSet.length >= OnboardingStep.steps.length;
    final nextIndex = (_progress.currentStepIndex + 1).clamp(0, OnboardingStep.steps.length - 1);

    _progress = _progress.copyWith(
      completedStepIds: updatedSet,
      currentStepIndex: allComplete ? _progress.currentStepIndex : nextIndex,
      isCompleted: allComplete,
    );

    EarthAudioEngine.instance.playChime();
    notifyListeners();
  }

  void nextStep() {
    if (_progress.currentStepIndex < OnboardingStep.steps.length - 1) {
      _progress = _progress.copyWith(currentStepIndex: _progress.currentStepIndex + 1);
      EarthAudioEngine.instance.playClick();
      notifyListeners();
    }
  }

  void previousStep() {
    if (_progress.currentStepIndex > 0) {
      _progress = _progress.copyWith(currentStepIndex: _progress.currentStepIndex - 1);
      EarthAudioEngine.instance.playClick();
      notifyListeners();
    }
  }

  void jumpToStep(int index) {
    if (index >= 0 && index < OnboardingStep.steps.length) {
      _progress = _progress.copyWith(currentStepIndex: index);
      EarthAudioEngine.instance.playClick();
      notifyListeners();
    }
  }

  void setDismissed(bool dismissed) {
    _progress = _progress.copyWith(isDismissed: dismissed);
    EarthAudioEngine.instance.playClick();
    notifyListeners();
  }

  void reset() {
    _progress = const OnboardingProgress();
    notifyListeners();
  }
}
