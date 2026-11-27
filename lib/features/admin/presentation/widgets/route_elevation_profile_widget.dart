import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../trips/domain/services/route_mission_service.dart';

/// Widget de Perfil de Elevación Interactivo Punto a Punto
/// Muestra el gráfico continuo de altitud, cotas msnm, pendientes % y rampas críticas.
class RouteElevationProfileWidget extends StatefulWidget {
  final RouteTopographyAnalysis analysis;
  final String routeTitle;
  final Color primaryColor;
  final Function(ElevationProfilePoint?)? onPointHover;

  const RouteElevationProfileWidget({
    super.key,
    required this.analysis,
    this.routeTitle = 'Perfil Topográfico de Ruta',
    this.primaryColor = Colors.cyanAccent,
    this.onPointHover,
  });

  @override
  State<RouteElevationProfileWidget> createState() => _RouteElevationProfileWidgetState();
}

class _RouteElevationProfileWidgetState extends State<RouteElevationProfileWidget> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final pts = widget.analysis.points;
    if (pts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'Sin puntos de elevación disponibles para graficar',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      );
    }

    final hoveredPoint = (_hoveredIndex != null && _hoveredIndex! >= 0 && _hoveredIndex! < pts.length)
        ? pts[_hoveredIndex!]
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera del gráfico
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.show_chart, color: widget.primaryColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    widget.routeTitle,
                    style: TextStyle(
                      color: widget.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Text(
                '${widget.analysis.totalDistanceKm.toStringAsFixed(1)} km • Cotas: ${widget.analysis.minAltitude.toStringAsFixed(0)}m - ${widget.analysis.maxAltitude.toStringAsFixed(0)}m',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Información interactiva del punto seleccionado al pasar el mouse/tocar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin_drop, size: 14, color: Colors.white54),
                    const SizedBox(width: 6),
                    Text(
                      hoveredPoint != null
                          ? 'Km ${hoveredPoint.distanceKm.toStringAsFixed(1)}'
                          : 'Pasa el cursor sobre el gráfico para ver el detalle punto a punto',
                      style: TextStyle(
                        color: hoveredPoint != null ? Colors.white : Colors.white54,
                        fontSize: 11,
                        fontWeight: hoveredPoint != null ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (hoveredPoint != null) ...[
                  Row(
                    children: [
                      const Text('Altitud: ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text(
                        '${hoveredPoint.altitudeMeters.toStringAsFixed(0)} msnm',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      const Text('Pendiente: ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text(
                        '${hoveredPoint.gradePercent >= 0 ? "+" : ""}${hoveredPoint.gradePercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: hoveredPoint.gradePercent > 3.5
                              ? Colors.redAccent
                              : (hoveredPoint.gradePercent < -3.5 ? Colors.orangeAccent : Colors.greenAccent),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Lienzo del gráfico de altitud continuo
          SizedBox(
            height: 130,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanDown: (details) => _updateHover(details.localPosition, constraints.maxWidth, pts.length),
                  onPanUpdate: (details) => _updateHover(details.localPosition, constraints.maxWidth, pts.length),
                  child: MouseRegion(
                    onHover: (event) => _updateHover(event.localPosition, constraints.maxWidth, pts.length),
                    onExit: (_) {
                      setState(() => _hoveredIndex = null);
                      widget.onPointHover?.call(null);
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, 130),
                      painter: _ElevationCurvePainter(
                        points: pts,
                        minAlt: widget.analysis.minAltitude,
                        maxAlt: widget.analysis.maxAltitude,
                        primaryColor: widget.primaryColor,
                        hoveredIndex: _hoveredIndex,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Desglose de Esfuerzo de Motor por Kilómetros
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DESGLOSE DE PENDIENTES & CONDICIÓN DE MARCHA',
                  style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildGradePill(
                      label: 'Subida Fuerte (>3.5%)',
                      km: widget.analysis.steepClimbKm,
                      color: Colors.redAccent,
                      totalKm: widget.analysis.totalDistanceKm,
                    ),
                    const SizedBox(width: 8),
                    _buildGradePill(
                      label: 'Subida Moderada (1.5% - 3.5%)',
                      km: widget.analysis.moderateClimbKm,
                      color: Colors.amberAccent,
                      totalKm: widget.analysis.totalDistanceKm,
                    ),
                    const SizedBox(width: 8),
                    _buildGradePill(
                      label: 'Plano (-1.5% a +1.5%)',
                      km: widget.analysis.flatKm,
                      color: Colors.greenAccent,
                      totalKm: widget.analysis.totalDistanceKm,
                    ),
                    const SizedBox(width: 8),
                    _buildGradePill(
                      label: 'Bajadas / Retención',
                      km: widget.analysis.descentKm,
                      color: Colors.blueAccent,
                      totalKm: widget.analysis.totalDistanceKm,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Rampas Críticas Detectadas
          if (widget.analysis.criticalRamps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Text(
                        'SECTORES CRÍTICOS DE TREPADA (${widget.analysis.criticalRamps.length} CUESTAS / RAMPAS)',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...widget.analysis.criticalRamps.map((ramp) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '• ${ramp.label} (${ramp.lengthKm.toStringAsFixed(1)} km)',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                          Text(
                            '+${ramp.elevationGainMeters.toStringAsFixed(0)}m  (Pend. máx: ${ramp.maxGradePercent.toStringAsFixed(1)}%)',
                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGradePill({
    required String label,
    required double km,
    required Color color,
    required double totalKm,
  }) {
    final pct = totalKm > 0 ? (km / totalKm * 100).toStringAsFixed(0) : '0';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              '${km.toStringAsFixed(1)} km ($pct%)',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _updateHover(Offset localPos, double width, int pointCount) {
    if (width <= 0 || pointCount == 0) return;
    final ratio = (localPos.dx / width).clamp(0.0, 1.0);
    final idx = (ratio * (pointCount - 1)).round();
    setState(() {
      _hoveredIndex = idx;
    });
    if (idx >= 0 && idx < widget.analysis.points.length) {
      widget.onPointHover?.call(widget.analysis.points[idx]);
    }
  }
}

/// CustomPainter para renderizar la curva topográfica continua con relleno gradiente
class _ElevationCurvePainter extends CustomPainter {
  final List<ElevationProfilePoint> points;
  final double minAlt;
  final double maxAlt;
  final Color primaryColor;
  final int? hoveredIndex;

  _ElevationCurvePainter({
    required this.points,
    required this.minAlt,
    required this.maxAlt,
    required this.primaryColor,
    required this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final altRange = math.max(15.0, maxAlt - minAlt);
    final effectiveMin = minAlt - (altRange * 0.08);
    final effectiveMax = maxAlt + (altRange * 0.08);
    final effectiveRange = effectiveMax - effectiveMin;

    final path = Path();
    final fillPath = Path();

    Offset getPointOffset(int i) {
      final denom = points.length > 1 ? (points.length - 1) : 1;
      final x = (i / denom) * size.width;
      final normalizedAlt = (points[i].altitudeMeters - effectiveMin) / effectiveRange;
      final y = size.height - (normalizedAlt * size.height);
      return Offset(x, y.clamp(2.0, size.height - 2.0));
    }

    final first = getPointOffset(0);
    path.moveTo(first.dx, first.dy);
    fillPath.moveTo(first.dx, size.height);
    fillPath.lineTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final prev = getPointOffset(i - 1);
      final curr = getPointOffset(i);
      final controlX = (prev.dx + curr.dx) / 2;
      path.cubicTo(controlX, prev.dy, controlX, curr.dy, curr.dx, curr.dy);
      fillPath.cubicTo(controlX, prev.dy, controlX, curr.dy, curr.dx, curr.dy);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Relleno degradado bajo la curva
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          primaryColor.withValues(alpha: 0.35),
          primaryColor.withValues(alpha: 0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Línea de la curva
    final strokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);

    // Resaltar rampas críticas con línea roja sobre la curva
    for (int i = 1; i < points.length; i++) {
      if (points[i].gradePercent > 3.5) {
        final prev = getPointOffset(i - 1);
        final curr = getPointOffset(i);
        final rampPaint = Paint()
          ..color = Colors.redAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(prev, curr, rampPaint);
      }
    }

    // Línea de cursor vertical si hay hover
    if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < points.length) {
      final hoverOffset = getPointOffset(hoveredIndex!);
      final cursorPaint = Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawLine(Offset(hoverOffset.dx, 0), Offset(hoverOffset.dx, size.height), cursorPaint);

      // Círculo en el punto
      final circlePaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;
      final borderCircle = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(hoverOffset, 4.5, circlePaint);
      canvas.drawCircle(hoverOffset, 4.5, borderCircle);
    }
  }

  @override
  bool shouldRepaint(covariant _ElevationCurvePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.hoveredIndex != hoveredIndex;
  }
}

