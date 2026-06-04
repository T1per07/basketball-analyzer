import 'package:flutter/material.dart';

class AnimatedButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color? color;
  final Color? hoverColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool isLoading;

  const AnimatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color,
    this.hoverColor,
    this.borderRadius = 12,
    this.padding,
    this.isLoading = false,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? const Color(0xFFFF6B2B);
    final hoverColor = widget.hoverColor ?? const Color(0xFFFF9800);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onPressed?.call();
        },
        onTapCancel: () => _controller.reverse(),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: widget.padding ??
                    const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                decoration: BoxDecoration(
                  color: _isHovered ? hoverColor : color,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: (_isHovered ? hoverColor : color).withOpacity(0.4),
                      blurRadius: _isHovered ? 20 : 10,
                      offset: Offset(0, _isHovered ? 4 : 2),
                    ),
                  ],
                ),
                child: widget.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : widget.child,
              ),
            );
          },
        ),
      ),
    );
  }
}

class GlowButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color color;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const GlowButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color = const Color(0xFFFF6B2B),
    this.borderRadius = 12,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: -2,
          ),
        ],
      ),
      child: AnimatedButton(
        onPressed: onPressed,
        color: color,
        borderRadius: borderRadius,
        padding: padding,
        child: child,
      ),
    );
  }
}
