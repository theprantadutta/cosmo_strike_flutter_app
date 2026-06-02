import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

class AnimatedShipLogo extends StatefulWidget {
  final GameTheme theme;
  final AnimationController controller;
  final double size;
  final bool useTextLogo; // New parameter to choose between logos

  const AnimatedShipLogo({
    super.key,
    required this.theme,
    required this.controller,
    this.size = 120,
    this.useTextLogo = false, // Default to transparent logo
  });

  @override
  State<AnimatedShipLogo> createState() => _AnimatedShipLogoState();
}

class _AnimatedShipLogoState extends State<AnimatedShipLogo>
    with SingleTickerProviderStateMixin {
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: widget.controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _pulseAnimation =
        Tween<double>(
          begin: 1.0,
          end: 1.05, // Subtle pulse effect
        ).animate(
          CurvedAnimation(
            parent: widget.controller,
            curve: const Interval(0.6, 1.0, curve: Curves.easeInOut),
          ),
        );

    _rotationAnimation =
        Tween<double>(
          begin: 0.0,
          end: 0.1, // Subtle rotation effect
        ).animate(
          CurvedAnimation(
            parent: widget.controller,
            curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value * _pulseAnimation.value,
            child: Transform.rotate(
              angle: _rotationAnimation.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.theme.accentColor.withValues(alpha: 0.1),
                      widget.theme.backgroundColor.withValues(alpha: 0.3),
                    ],
                  ),
                  border: Border.all(
                    color: widget.theme.accentColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.theme.accentColor.withValues(alpha: 0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    widget.size * 0.05,
                  ), // Minimal padding for better fit
                  child: Image.asset(
                    widget.useTextLogo
                        ? 'assets/images/cosmo_strike_logo.png'
                        : 'assets/images/cosmo_strike_transparent.png',
                    fit: BoxFit.contain, // Keep aspect ratio
                    width: widget.size,
                    height: widget.size,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to a simple icon if image fails to load
                      return Icon(
                        Icons.games,
                        size: widget.size * 0.6,
                        color: widget.theme.accentColor,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
