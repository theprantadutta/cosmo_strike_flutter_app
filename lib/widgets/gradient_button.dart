import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';

class GradientButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String text;
  final Color primaryColor;
  final Color secondaryColor;
  final IconData? icon;
  final double width;
  final double height;
  final bool outlined;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.text,
    required this.primaryColor,
    required this.secondaryColor,
    this.icon,
    this.width = 160,
    this.height = 56,
    this.outlined = false,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onPressed != null
          ? () {
              HapticFeedback.lightImpact();
              AudioService().playSound('button_click');
              widget.onPressed!();
            }
          : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: widget.outlined
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [widget.primaryColor, widget.secondaryColor],
                      ),
                border: widget.outlined
                    ? Border.all(color: widget.primaryColor, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: widget.primaryColor.withValues(
                      alpha: 0.3 + (_glowAnimation.value * 0.2),
                    ),
                    blurRadius: 8 + (_glowAnimation.value * 4),
                    spreadRadius: 1 + (_glowAnimation.value * 2),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          color: widget.outlined
                              ? widget.primaryColor
                              : Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.text,
                          style: TextStyle(
                            color: widget.outlined
                                ? widget.primaryColor
                                : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
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
