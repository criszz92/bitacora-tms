import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Contenedor estilizado con efecto Glassmorphism e instrumentación automotriz pesada.
/// Implementa desenfoque de fondo (BackdropFilter), tono carbón translúcido
/// y borde con micro-gradiente de luz o resplandor ámbar cuando está activo.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double blur;
  final Color? backgroundColor;
  final double backgroundOpacity;
  final bool isActive;
  final VoidCallback? onTap;
  final double borderWidth;
  final List<BoxShadow>? customShadows;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.blur = 14.0,
    this.backgroundColor,
    this.backgroundOpacity = 0.65,
    this.isActive = false,
    this.onTap,
    this.borderWidth = 1.0,
    this.customShadows,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(20.0);
    final effectiveBgColor = (backgroundColor ?? AppColors.surface).withValues(
      alpha: isActive ? 0.75 : backgroundOpacity,
    );

    // Gradiente del borde: reflejo de luz superior o resplandor ámbar activo
    final borderGradient = isActive
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.55),
              AppColors.primaryWarm.withValues(alpha: 0.20),
            ],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.14),
              Colors.white.withValues(alpha: 0.03),
            ],
          );

    final shadows = customShadows ?? [
      if (isActive)
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.16),
          blurRadius: 18,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        )
      else
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
    ];

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: effectiveRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: _GlassBorderPainter(
              borderRadius: effectiveRadius,
              borderWidth: borderWidth,
              gradient: borderGradient,
            ),
            child: Container(
              color: effectiveBgColor,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassBorderPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final double borderWidth;
  final Gradient gradient;

  _GlassBorderPainter({
    required this.borderRadius,
    required this.borderWidth,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (borderWidth <= 0) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(borderWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassBorderPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.gradient != gradient;
  }
}

