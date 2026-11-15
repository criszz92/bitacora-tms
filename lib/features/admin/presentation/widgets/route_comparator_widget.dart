import 'package:flutter/material.dart';
import '../../../trips/domain/services/route_mission_service.dart';
import 'route_elevation_profile_widget.dart';

/// Modelo de datos para una ruta seleccionada en el comparador
class ComparedRouteData {
  final String label; // "Ruta 1 (Vía Itata)"
  final String plate;
  final DateTime date;
  final double distanceKm;
  final double avgSpeed;
  final double maxSpeed;
  final Duration totalDuration;
  final double estimatedLiters;
  final RouteTopographyAnalysis topography;
  final Color color;

  const ComparedRouteData({
    required this.label,
    required this.plate,
    required this.date,
    required this.distanceKm,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.totalDuration,
    required this.estimatedLiters,
    required this.topography,
    required this.color,
  });
}

/// Widget Comparador de Rutas y Corredores Alternativos
/// Muestra tabla de contraste, métricas energéticas, esfuerzo mecánico y veredicto analítico.
class RouteComparatorWidget extends StatelessWidget {
  final ComparedRouteData routeA;
  final ComparedRouteData? routeB;
  final VoidCallback onClearRouteB;
  final Function(ElevationProfilePoint?)? onPointHoverA;
  final Function(ElevationProfilePoint?)? onPointHoverB;

  const RouteComparatorWidget({
    super.key,
    required this.routeA,
    required this.routeB,
    required this.onClearRouteB,
    this.onPointHoverA,
    this.onPointHoverB,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner explicativo superior
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1E3A8A).withValues(alpha: 0.4),
                  const Color(0xFF161B22),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMPARADOR ANALÍTICO DE RUTAS & CORREDORES',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Inspección punto a punto de distancia, topografía satelital, esfuerzo motriz en cuestas y consumo real.',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (routeB != null)
                  IconButton(
                    onPressed: onClearRouteB,
                    tooltip: 'Quitar Ruta B (Comparativa)',
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── TABLA COMPARATIVA DIRECTA (A vs B) ──────────────────
          if (routeB != null) ...[
            _buildSideBySideComparisonTable(routeA, routeB!),
            const SizedBox(height: 16),
            _buildVerdictCard(routeA, routeB!),
            const SizedBox(height: 20),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ruta 1 cargada. Para comparar contra otra alternativa, selecciona otra fecha/camión y presiona "Fijar como Ruta 2 (Comparar)".',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── PERFIL TOPOGRÁFICO CONTINUO: RUTA A ──────────────────
          RouteElevationProfileWidget(
            analysis: routeA.topography,
            routeTitle: 'Ruta 1 (Base): ${routeA.label}',
            primaryColor: routeA.color,
            onPointHover: onPointHoverA,
          ),

          // ── PERFIL TOPOGRÁFICO CONTINUO: RUTA B ──────────────────
          if (routeB != null) ...[
            const SizedBox(height: 16),
            RouteElevationProfileWidget(
              analysis: routeB!.topography,
              routeTitle: 'Ruta 2 (Alternativa): ${routeB!.label}',
              primaryColor: routeB!.color,
              onPointHover: onPointHoverB,
            ),
          ],
        ],
      ),
    );
  }

  /// Tabla de Contraste Cara a Cara
  Widget _buildSideBySideComparisonTable(ComparedRouteData a, ComparedRouteData b) {
    final distDiff = (b.distanceKm - a.distanceKm);
    final timeDiffMin = b.totalDuration.inMinutes - a.totalDuration.inMinutes;
    final climbDiff = (b.topography.ascentMeters - a.topography.ascentMeters);
    final steepDiff = (b.topography.steepClimbKm - a.topography.steepClimbKm);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          // Encabezado de columnas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('MÉTRICA / FACTOR', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: a.color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          a.label,
                          style: TextStyle(color: a.color, fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: b.color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          b.label,
                          style: TextStyle(color: b.color, fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text('DIFERENCIA (B vs A)', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // Filas
          _buildMetricRow('Distancia Total', '${a.distanceKm.toStringAsFixed(1)} km', '${b.distanceKm.toStringAsFixed(1)} km',
              '${distDiff >= 0 ? "+" : ""}${distDiff.toStringAsFixed(1)} km', distDiff <= 0),
          _buildMetricRow('Tiempo de Viaje', _formatDuration(a.totalDuration), _formatDuration(b.totalDuration),
              '${timeDiffMin >= 0 ? "+" : ""}$timeDiffMin min', timeDiffMin <= 0),
          _buildMetricRow('Velocidad Promedio', '${a.avgSpeed.toStringAsFixed(0)} km/h', '${b.avgSpeed.toStringAsFixed(0)} km/h',
              '${(b.avgSpeed - a.avgSpeed) >= 0 ? "+" : ""}${(b.avgSpeed - a.avgSpeed).toStringAsFixed(0)} km/h', b.avgSpeed >= a.avgSpeed),
          _buildMetricRow('Desnivel Subida (+Δz)', '+${a.topography.ascentMeters.toStringAsFixed(0)} m', '+${b.topography.ascentMeters.toStringAsFixed(0)} m',
              '${climbDiff >= 0 ? "+" : ""}${climbDiff.toStringAsFixed(0)} m', climbDiff <= 0),
          _buildMetricRow('Km en Subida Fuerte (>3.5%)', '${a.topography.steepClimbKm.toStringAsFixed(1)} km', '${b.topography.steepClimbKm.toStringAsFixed(1)} km',
              '${steepDiff >= 0 ? "+" : ""}${steepDiff.toStringAsFixed(1)} km', steepDiff <= 0),
          _buildMetricRow('Rampas Críticas (Cuestas)', '${a.topography.criticalRamps.length} cuestas', '${b.topography.criticalRamps.length} cuestas',
              '${b.topography.criticalRamps.length - a.topography.criticalRamps.length} cuestas', b.topography.criticalRamps.length <= a.topography.criticalRamps.length),
          _buildMetricRow('Consumo Est. Diésel', '${a.estimatedLiters.toStringAsFixed(1)} Lts', '${b.estimatedLiters.toStringAsFixed(1)} Lts',
              '${(b.estimatedLiters - a.estimatedLiters) >= 0 ? "+" : ""}${(b.estimatedLiters - a.estimatedLiters).toStringAsFixed(1)} Lts', (b.estimatedLiters - a.estimatedLiters) <= 0),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String title, String valA, String valB, String diff, bool isGoodForB) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11))),
          Expanded(flex: 3, child: Text(valA, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text(valB, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isGoodForB ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                diff,
                style: TextStyle(
                  color: isGoodForB ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta de Veredicto Operacional
  Widget _buildVerdictCard(ComparedRouteData a, ComparedRouteData b) {
    final distDiff = (b.distanceKm - a.distanceKm).abs();
    final climbDiff = (b.topography.ascentMeters - a.topography.ascentMeters).abs();
    final isAShorter = a.distanceKm < b.distanceKm;
    final isAFlatter = a.topography.ascentMeters < b.topography.ascentMeters;

    String recommendation = '';
    if (isAShorter && isAFlatter) {
      recommendation = '🏆 La Ruta 1 (${a.label}) es objetivamente superior en todos los aspectos: es $distDiff km más corta y acumula $climbDiff m menos de subida.';
    } else if (!isAShorter && !isAFlatter) {
      recommendation = '🏆 La Ruta 2 (${b.label}) es objetivamente superior en todos los aspectos: es $distDiff km más corta y acumula $climbDiff m menos de subida.';
    } else {
      final shorterRoute = isAShorter ? 'Ruta 1 (${a.label})' : 'Ruta 2 (${b.label})';
      final flatterRoute = isAFlatter ? 'Ruta 1 (${a.label})' : 'Ruta 2 (${b.label})';
      recommendation = '⚖️ Compromiso Topográfico vs Distancia: $shorterRoute ahorra $distDiff km en odómetro, pero $flatterRoute tiene $climbDiff m menos de esfuerzo en cuestas. Para camión CARGADO (45 ton) conviene $flatterRoute para evitar sobreconsumo de inyección en subida; para camión VACÍO conviene $shorterRoute por menor desgaste kilométrico.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2818),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology, color: Colors.greenAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'VEREDICTO ANALÍTICO DE DECISIÓN',
                style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            recommendation,
            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    return '${d.inMinutes}m';
  }
}

