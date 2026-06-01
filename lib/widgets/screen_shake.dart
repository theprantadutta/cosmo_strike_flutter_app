import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ShakeIntensity { light, medium, heavy, extreme }

class ScreenShakeController extends ChangeNotifier {
  bool _isShaking = false;
  double _intensity = 0.0;
  Duration _duration = Duration.zero;
  DateTime? _shakeStartTime;
  Offset _currentOffset = Offset.zero;

  bool get isShaking => _isShaking;
  Offset get offset => _currentOffset;
  double get intensity => _intensity;

  void shake({
    ShakeIntensity intensity = ShakeIntensity.medium,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    _intensity = _getIntensityValue(intensity);
    _duration = duration;
    _shakeStartTime = DateTime.now();
    _isShaking = true;
    _startShakeAnimation();
    notifyListeners();
  }

  double _getIntensityValue(ShakeIntensity intensity) {
    switch (intensity) {
      case ShakeIntensity.light:
        return 2.0;
      case ShakeIntensity.medium:
        return 4.0;
      case ShakeIntensity.heavy:
        return 8.0;
      case ShakeIntensity.extreme:
        return 12.0;
    }
  }

  void _startShakeAnimation() {
    if (!_isShaking || _shakeStartTime == null) return;

    final elapsed = DateTime.now().difference(_shakeStartTime!);
    if (elapsed > _duration) {
      _stopShake();
      return;
    }

    // Calculate shake progress (0.0 to 1.0)
    final progress = elapsed.inMilliseconds / _duration.inMilliseconds;
    final dampening = 1.0 - progress; // Fade out over time

    // Generate random shake offset
    final random = math.Random();
    final currentIntensity = _intensity * dampening;

    _currentOffset = Offset(
      (random.nextDouble() - 0.5) * 2 * currentIntensity,
      (random.nextDouble() - 0.5) * 2 * currentIntensity,
    );

    notifyListeners();

    // Schedule next frame
    Future.delayed(const Duration(milliseconds: 16), _startShakeAnimation);
  }

  void _stopShake() {
    _isShaking = false;
    _currentOffset = Offset.zero;
    _intensity = 0.0;
    _shakeStartTime = null;
    notifyListeners();
  }

  void stopShake() {
    _stopShake();
  }

  @override
  void dispose() {
    _stopShake();
    super.dispose();
  }
}

class ScreenShakeWidget extends StatefulWidget {
  final Widget child;
  final ScreenShakeController controller;

  const ScreenShakeWidget({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<ScreenShakeWidget> createState() => _ScreenShakeWidgetState();
}

class _ScreenShakeWidgetState extends State<ScreenShakeWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onShakeUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onShakeUpdate);
    super.dispose();
  }

  void _onShakeUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: widget.controller.offset,
      child: widget.child,
    );
  }
}

// Game Juice Effects Controller
class GameJuiceController extends ChangeNotifier {
  final ScreenShakeController shakeController = ScreenShakeController();
  final Map<String, AnimationController> _animationControllers = {};

  // Whether juice effects are enabled (controlled by settings)
  bool _shakeEnabled = true;
  bool get shakeEnabled => _shakeEnabled;
  set shakeEnabled(bool value) {
    _shakeEnabled = value;
    if (!value) {
      shakeController.stopShake(); // Stop any running shake
      // Also reset scale punch to stop its animation loop
      _scalePunchValue = 1.0;
      _scalePunchStartTime = null;
    }
  }

  // Scale punch effect for UI elements
  double _scalePunchValue = 1.0;
  Duration _scalePunchDuration = Duration.zero;
  DateTime? _scalePunchStartTime;

  double get scalePunch => _scalePunchValue;

  void addAnimationController(String key, AnimationController controller) {
    _animationControllers[key] = controller;
  }

  void removeAnimationController(String key) {
    _animationControllers.remove(key);
  }

  // Screen shake for impacts
  void shakeScreen({
    ShakeIntensity intensity = ShakeIntensity.medium,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    // Skip shake animation if disabled - prevents background animation loop
    if (!_shakeEnabled) return;
    shakeController.shake(intensity: intensity, duration: duration);
  }

  // Scale punch for UI feedback
  void triggerScalePunch({
    double intensity = 0.1,
    Duration duration = const Duration(milliseconds: 150),
  }) {
    // Skip scale punch animation if effects are disabled
    if (!_shakeEnabled) return;
    _scalePunchValue = 1.0 + intensity;
    _scalePunchDuration = duration;
    _scalePunchStartTime = DateTime.now();
    _startScalePunchAnimation();
    notifyListeners();
  }

  void _startScalePunchAnimation() {
    if (_scalePunchStartTime == null) return;

    final elapsed = DateTime.now().difference(_scalePunchStartTime!);
    if (elapsed > _scalePunchDuration) {
      _scalePunchValue = 1.0;
      _scalePunchStartTime = null;
      notifyListeners();
      return;
    }

    // Calculate scale using a punch curve (quick scale up, then down)
    final progress =
        elapsed.inMilliseconds / _scalePunchDuration.inMilliseconds;
    final punchCurve = math.sin(progress * math.pi);

    _scalePunchValue = 1.0 + (0.1 * punchCurve);
    notifyListeners();

    // Schedule next frame
    Future.delayed(const Duration(milliseconds: 16), _startScalePunchAnimation);
  }

  // Specific game event effects
  void foodEaten() {
    shakeScreen(
      intensity: ShakeIntensity.light,
      duration: const Duration(milliseconds: 100),
    );
    triggerScalePunch(intensity: 0.05);
  }

  void bonusFoodEaten() {
    shakeScreen(
      intensity: ShakeIntensity.medium,
      duration: const Duration(milliseconds: 200),
    );
    triggerScalePunch(intensity: 0.08);
  }

  void specialFoodEaten() {
    shakeScreen(
      intensity: ShakeIntensity.heavy,
      duration: const Duration(milliseconds: 300),
    );
    triggerScalePunch(intensity: 0.12);
  }

  void powerUpCollected() {
    shakeScreen(
      intensity: ShakeIntensity.medium,
      duration: const Duration(milliseconds: 250),
    );
    triggerScalePunch(intensity: 0.1);
  }

  void gameOver() {
    shakeScreen(
      intensity: ShakeIntensity.extreme,
      duration: const Duration(milliseconds: 500),
    );
  }

  void levelUp() {
    shakeScreen(
      intensity: ShakeIntensity.light,
      duration: const Duration(milliseconds: 150),
    );
    triggerScalePunch(intensity: 0.06);
  }

  void wallHit() {
    shakeScreen(
      intensity: ShakeIntensity.heavy,
      duration: const Duration(milliseconds: 400),
    );
  }

  void selfCollision() {
    shakeScreen(
      intensity: ShakeIntensity.heavy,
      duration: const Duration(milliseconds: 350),
    );
  }

  void buttonPress() {
    triggerScalePunch(
      intensity: 0.03,
      duration: const Duration(milliseconds: 100),
    );
  }

  void achievementUnlocked() {
    shakeScreen(
      intensity: ShakeIntensity.light,
      duration: const Duration(milliseconds: 200),
    );
    triggerScalePunch(intensity: 0.08);
  }

  @override
  void dispose() {
    shakeController.dispose();
    _animationControllers.clear();
    super.dispose();
  }
}

// Scale punch widget for UI elements
class ScalePunchWidget extends StatefulWidget {
  final Widget child;
  final GameJuiceController controller;

  const ScalePunchWidget({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<ScalePunchWidget> createState() => _ScalePunchWidgetState();
}

class _ScalePunchWidgetState extends State<ScalePunchWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: widget.controller.scalePunch,
      child: widget.child,
    );
  }
}

// Combined juice widget that applies both shake and scale effects
class GameJuiceWidget extends StatelessWidget {
  final Widget child;
  final GameJuiceController controller;
  final bool applyShake;
  final bool applyScale;

  const GameJuiceWidget({
    super.key,
    required this.child,
    required this.controller,
    this.applyShake = true,
    this.applyScale = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    if (applyScale) {
      result = ScalePunchWidget(controller: controller, child: result);
    }

    if (applyShake) {
      result = ScreenShakeWidget(
        controller: controller.shakeController,
        child: result,
      );
    }

    return result;
  }
}
