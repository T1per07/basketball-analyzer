import 'package:flutter/material.dart';

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient? gradient;

  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => (gradient ??
              const LinearGradient(
                colors: [
                  Color(0xFFFF6B2B),
                  Color(0xFFFF9800),
                  Color(0xFF00E5FF),
                ],
              ))
          .createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        style: style,
      ),
    );
  }
}

class AnimatedGradientText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final List<Color> colors;
  final Duration duration;

  const AnimatedGradientText(
    this.text, {
    super.key,
    this.style,
    this.colors = const [
      Color(0xFFFF6B2B),
      Color(0xFFFF9800),
      Color(0xFF00E5FF),
      Color(0xFFFF6B2B),
    ],
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedGradientText> createState() => _AnimatedGradientTextState();
}

class _AnimatedGradientTextState extends State<AnimatedGradientText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: widget.colors,
              transform: GradientRotation(_controller.value * 2 * 3.14159),
            ).createShader(
              Rect.fromLTWH(0, 0, bounds.width, bounds.height),
            );
          },
          child: Text(
            widget.text,
            style: widget.style,
          ),
        );
      },
    );
  }
}
