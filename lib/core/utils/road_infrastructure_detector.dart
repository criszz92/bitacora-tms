import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Utilidad técnica para:
/// 1. Calcular rumbo (heading/bearing 0-360°) entre coordenadas o evaluar el `course` del GPS del camión.
/// 2. Validar si el sentido del camión coincide con el sentido asignado al punto de infraestructura.
/// 3. Validar si una restricción horaria aplica en el momento proyectado de cruce.
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

  /// Valida si el rumbo del camión [truckHeading] coincide con el sentido del punto [sentidoPunto].
  static bool matchesDirection({
    required double? truckHeading,
    required String sentidoPunto,
  }) {
    final cleanSentido = sentidoPunto.trim().toLowerCase();

    // Si es bidireccional o desconocido, no se discrimina por rumbo
    if (cleanSentido.isEmpty ||
        cleanSentido == 'bidireccional' ||
        cleanSentido == 'ambos' ||
        truckHeading == null) {
      return true;
    }

    final double h = (truckHeading % 360.0 + 360.0) % 360.0;

    // Sentido Norte -> Sur
    if (cleanSentido.contains('norte-sur') ||
        cleanSentido == 'sur' ||
        cleanSentido == 'hacia el sur') {
      return h >= 110.0 && h <= 250.0;
    }

    // Sentido Sur -> Norte
    if (cleanSentido.contains('sur-norte') ||
        cleanSentido == 'norte' ||
        cleanSentido == 'hacia el norte') {
      return h >= 290.0 || h <= 70.0;
    }

    // Sentido Oriente -> Poniente (Hacia la costa / mar)
    if (cleanSentido.contains('oriente-poniente') ||
        cleanSentido.contains('cordillera-costa') ||
        cleanSentido == 'poniente' ||
        cleanSentido == 'oeste') {
      return h >= 200.0 && h <= 340.0;
    }

    // Sentido Poniente -> Oriente (Hacia el interior / cordillera)
    if (cleanSentido.contains('poniente-oriente') ||
        cleanSentido.contains('costa-cordillera') ||
        cleanSentido == 'oriente' ||
        cleanSentido == 'este') {
      return h >= 20.0 && h <= 160.0;
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
