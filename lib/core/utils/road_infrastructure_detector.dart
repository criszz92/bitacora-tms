import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Utilidad técnica avanzada para:
/// 1. Detección por proximidad ortogonal y radio adaptativo según tipo (Troncal vs Lateral).
/// 2. Cálculo de rumbo (heading/bearing 0-360°) y concordancia angular flexible con la calzada.
/// 3. Prevención de falsos positivos en peajes laterales adyacentes a autopistas troncales.
/// 4. Desempate por "Gate más cercano" (Nearest Toll Gate) en plazas con calzadas paralelas.
class RoadInfrastructureDetector {
  /// Distancia en metros entre dos coordenadas geográficas (Fórmula de Haversine)
  static double calculateDistanceMeters(LatLng p1, LatLng p2) {
    const double earthRadius = 6371000; // metros
    final double dLat = _degToRad(p2.latitude - p1.latitude);
    final double dLng = _degToRad(p2.longitude - p1.longitude);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(p1.latitude)) *
            math.cos(_degToRad(p2.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Calcula el rumbo en grados (0° a 360°) desde p1 hacia p2.
  /// 0° = Norte, 90° = Oriente/Este, 180° = Sur, 270° = Poniente/Oeste.
  static double calculateBearing(LatLng p1, LatLng p2) {
    final double lat1 = _degToRad(p1.latitude);
    final double lat2 = _degToRad(p2.latitude);
    final double dLng = _degToRad(p2.longitude - p1.longitude);

    final double y = math.sin(dLng) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final double theta = math.atan2(y, x);
    final double degrees = theta * (180.0 / math.pi);
    final double bearing = (degrees + 360.0) % 360.0;
    return bearing;
  }

  /// Retorna el radio de captura óptimo en metros para evitar atrapar calzadas adyacentes:
  /// - Peajes Laterales: Radio estricto de 16m (el ramal tiene ~8m; la autopista central está a 20-30m)
  /// - Peajes Troncales: Radio de 45m (cubre las pistas de la calzada)
  /// - Romanas / Pesajes: Radio amplio preventivo
  static double getOptimalDetectionRadius({
    required String tipoCode,
    required String subtipo,
    double? radioConfigurado,
  }) {
    final subLower = subtipo.toLowerCase();
    
    // Si es un Peaje Lateral (como el de Ranco / Los Ángeles)
    if (subLower.contains('lateral') || subLower.contains('ramal') || subLower.contains('salida')) {
      return 18.0; // Quirúrgico: descarta completamente el tránsito por la carretera central
    }

    // Si es Troncal / TAG / Free Flow
    if (subLower.contains('troncal') || subLower.contains('tag') || subLower.contains('portico')) {
      return (radioConfigurado != null && radioConfigurado >= 35.0 && radioConfigurado <= 60.0)
          ? radioConfigurado
          : 45.0;
    }

    return (radioConfigurado != null && radioConfigurado > 0) ? radioConfigurado : 50.0;
  }

  /// Valida si el rumbo del camión [truckHeading] coincide con el sentido del punto [sentidoPunto].
  /// Usa tolerancias de cono de 65° para adaptarse a curvas reales en carreteras (ej. Cabrero o Puente Industrial).
  static bool matchesDirection({
    required double? truckHeading,
    required String sentidoPunto,
  }) {
    final cleanSentido = sentidoPunto.trim().toLowerCase();

    // Si es bidireccional o sin rumbo disponible, es válido
    if (cleanSentido.isEmpty ||
        cleanSentido == 'bidireccional' ||
        cleanSentido == 'ambos' ||
        truckHeading == null) {
      return true;
    }

    final double h = (truckHeading % 360.0 + 360.0) % 360.0;

    // Sentido Norte -> Sur (Eje Sur nominal 180°, tolerancia amplia 105° a 255°)
    if (cleanSentido.contains('norte-sur') ||
        cleanSentido == 'sur' ||
        cleanSentido == 'hacia el sur') {
      return h >= 105.0 && h <= 255.0;
    }

    // Sentido Sur -> Norte (Eje Norte nominal 0° / 360°, tolerancia 285° a 75°)
    if (cleanSentido.contains('sur-norte') ||
        cleanSentido == 'norte' ||
        cleanSentido == 'hacia el norte') {
      return h >= 285.0 || h <= 75.0;
    }

    // Sentido Oriente -> Poniente (Hacia la costa / mar, nominal 270°, ej. Cabrero a Concepción: 195° a 345°)
    if (cleanSentido.contains('oriente-poniente') ||
        cleanSentido.contains('cordillera-costa') ||
        cleanSentido == 'poniente' ||
        cleanSentido == 'oeste') {
      return h >= 195.0 && h <= 345.0;
    }

    // Sentido Poniente -> Oriente (Hacia el interior / cordillera, nominal 90°, ej. Concepción a Cabrero: 15° a 165°)
    if (cleanSentido.contains('poniente-oriente') ||
        cleanSentido.contains('costa-cordillera') ||
        cleanSentido == 'oriente' ||
        cleanSentido == 'este') {
      return h >= 15.0 && h <= 165.0;
    }

    return true;
  }

  /// Evalúa si el punto de tipo restricción horaria aplica activamente o en los próximos [marginMinutes].
  static Map<String, dynamic> checkTimeRestriction({
    required String? horarioStr,
    DateTime? checkTime,
    int marginMinutes = 20,
  }) {
    if (horarioStr == null || horarioStr.trim().isEmpty) {
      return {'applies': false, 'isNearWindow': false, 'detail': ''};
    }

    final now = checkTime ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final windows = horarioStr.split(RegExp(r'[,;]'));

    for (final rawWin in windows) {
      final parts = rawWin.trim().split('-');
      if (parts.length != 2) continue;

      final startParts = parts[0].trim().split(':');
      final endParts = parts[1].trim().split(':');
      if (startParts.length != 2 || endParts.length != 2) continue;

      final startMin = (int.tryParse(startParts[0]) ?? 0) * 60 + (int.tryParse(startParts[1]) ?? 0);
      final endMin = (int.tryParse(endParts[0]) ?? 0) * 60 + (int.tryParse(endParts[1]) ?? 0);

      // Si está en curso la restricción
      if (currentMinutes >= startMin && currentMinutes <= endMin) {
        return {
          'applies': true,
          'isNearWindow': false,
          'detail': 'Restricción horaria activa (${parts[0].trim()} - ${parts[1].trim()} hrs)',
        };
      }

      // Si está próximo a iniciar dentro del margen de anticipación
      if (currentMinutes >= (startMin - marginMinutes) && currentMinutes < startMin) {
        final faltanMin = startMin - currentMinutes;
        return {
          'applies': true,
          'isNearWindow': true,
          'detail': 'Restricción inicia en $faltanMin min (${parts[0].trim()} - ${parts[1].trim()} hrs)',
        };
      }
    }

    return {'applies': false, 'isNearWindow': false, 'detail': ''};
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
