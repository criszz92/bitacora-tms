import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Modelo de Destino de Entrega (Puerto / Depósito / Terminal)
class DeliveryDestination {
  final String id;
  final String nombre;
  final String tipo; // 'puerto', 'deposito', 'planta'
  final String geocercaModoGps;
  final LatLng ubicacion;
  final String descripcion;

  const DeliveryDestination({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.geocercaModoGps,
    required this.ubicacion,
    required this.descripcion,
  });
}

/// Punto de muestreo topográfico detallado de una ruta
class ElevationProfilePoint {
  final double distanceKm;
  final double altitudeMeters;
  final double gradePercent;
  final LatLng position;

  const ElevationProfilePoint({
    required this.distanceKm,
    required this.altitudeMeters,
    required this.gradePercent,
    required this.position,
  });
}

/// Tramo o rampa crítica de esfuerzo (cuestas, pendientes sostenidas)
class CriticalGradientSegment {
  final double startKm;
  final double endKm;
  final double lengthKm;
  final double avgGradePercent;
  final double maxGradePercent;
  final double elevationGainMeters;
  final String label;

  const CriticalGradientSegment({
    required this.startKm,
    required this.endKm,
    required this.lengthKm,
    required this.avgGradePercent,
    required this.maxGradePercent,
    required this.elevationGainMeters,
    required this.label,
  });
}

/// Informe analítico topográfico completo punto a punto de una ruta
class RouteTopographyAnalysis {
  final double ascentMeters;
  final double descentMeters;
  final double minAltitude;
  final double maxAltitude;
  final double totalDistanceKm;
  final List<ElevationProfilePoint> points;
  final List<CriticalGradientSegment> criticalRamps;
  final double steepClimbKm; // km con pendiente > 3.5%
  final double moderateClimbKm; // km con pendiente 1.5% a 3.5%
  final double flatKm; // km planos -1.5% a +1.5%
  final double descentKm; // km con pendiente < -1.5%
  final String sourceDescription;

  const RouteTopographyAnalysis({
    required this.ascentMeters,
    required this.descentMeters,
    required this.minAltitude,
    required this.maxAltitude,
    required this.totalDistanceKm,
    required this.points,
    required this.criticalRamps,
    required this.steepClimbKm,
    required this.moderateClimbKm,
    required this.flatKm,
    required this.descentKm,
    required this.sourceDescription,
  });

  static RouteTopographyAnalysis empty() {
    return const RouteTopographyAnalysis(
      ascentMeters: 0,
      descentMeters: 0,
      minAltitude: 0,
      maxAltitude: 0,
      totalDistanceKm: 0,
      points: [],
      criticalRamps: [],
      steepClimbKm: 0,
      moderateClimbKm: 0,
      flatKm: 0,
      descentKm: 0,
      sourceDescription: 'Sin datos',
    );
  }
}

/// Servicio que gestiona la arquitectura de Misión, Tramos, Geocercas y Corredores
class RouteMissionService {
  /// Catálogo oficial de Puertos y Depósitos de la Región del Biobío y Ñuble
  static const List<DeliveryDestination> deliveryCatalog = [
    // ─── PUERTOS MARÍTIMOS ───────────────────────────────────────────────
    DeliveryDestination(
      id: 'puerto_coronel',
      nombre: 'Puerto Coronel',
      tipo: 'puerto',
      geocercaModoGps: 'PUERTO_CORONEL',
      ubicacion: LatLng(-37.034519, -73.146822),
      descripcion: 'Terminal marítimo principal Bahía de Coronel',
    ),
    DeliveryDestination(
      id: 'puerto_lirquen',
      nombre: 'DP World Lirquén',
      tipo: 'puerto',
      geocercaModoGps: 'PUERTO_LIRQUEN',
      ubicacion: LatLng(-36.712759, -72.979223),
      descripcion: 'Terminal portuario DP World Bahía de Concepción',
    ),
    DeliveryDestination(
      id: 'puerto_svti',
      nombre: 'Puerto SVTI (San Vicente)',
      tipo: 'puerto',
      geocercaModoGps: 'PUERTO_SVTI',
      ubicacion: LatLng(-36.729008, -73.137884),
      descripcion: 'San Vicente Terminal Internacional (Talcahuano)',
    ),

    // ─── DEPÓSITOS DE CONTENEDORES Y EXTRAPORTUARIOS ────────────────────
    DeliveryDestination(
      id: 'medlog_coronel',
      nombre: 'Medlog Coronel',
      tipo: 'deposito',
      geocercaModoGps: 'MEDLOG_CORONEL',
      ubicacion: LatLng(-36.983189, -73.176747),
      descripcion: 'Depósito de contenedores vacíos MSC / Medlog',
    ),
    DeliveryDestination(
      id: 'dyc_svti',
      nombre: 'D&C San Vicente',
      tipo: 'deposito',
      geocercaModoGps: 'DYC_SVTI',
      ubicacion: LatLng(-36.726791, -73.120529),
      descripcion: 'Depósito y contenedores D&C Talcahuano',
    ),
    DeliveryDestination(
      id: 'contopsa_svti',
      nombre: 'Contopsa San Vicente',
      tipo: 'deposito',
      geocercaModoGps: 'CONTOPSA_SVTI',
      ubicacion: LatLng(-36.729345, -73.113880),
      descripcion: 'Depósito extraportuario Contopsa',
    ),
    DeliveryDestination(
      id: 'sitrans_svti',
      nombre: 'Sitrans San Vicente',
      tipo: 'deposito',
      geocercaModoGps: 'ISLA_ROCUANT',
      ubicacion: LatLng(-36.728232, -73.102344),
      descripcion: 'Terminal extraportuario Sitrans / Rocuant',
    ),
    DeliveryDestination(
      id: 'compac_coronel',
      nombre: 'Compac Coronel',
      tipo: 'deposito',
      geocercaModoGps: 'COMPAC_CORONEL',
      ubicacion: LatLng(-36.983575, -73.172252),
      descripcion: 'Parque industrial Escuadrón Coronel',
    ),
    DeliveryDestination(
      id: 'emergent_svti',
      nombre: 'Emergent Cold SVTI',
      tipo: 'deposito',
      geocercaModoGps: 'EMERGENCOLD_SVTI',
      ubicacion: LatLng(-36.727494, -73.122120),
      descripcion: 'Frigorífico y depósito refrigerado Talcahuano',
    ),
    DeliveryDestination(
      id: 'emergent_sanpedro',
      nombre: 'Emergent Cold San Pedro',
      tipo: 'deposito',
      geocercaModoGps: 'EMERCOLD_SANPEDRO',
      ubicacion: LatLng(-36.866638, -73.145928),
      descripcion: 'Frigorífico San Pedro de la Paz',
    ),
    DeliveryDestination(
      id: 'agunsa_svti',
      nombre: 'Agunsa San Vicente',
      tipo: 'deposito',
      geocercaModoGps: 'AGUNSA_SVTI',
      ubicacion: LatLng(-36.719728, -73.122830),
      descripcion: 'Depósito Agunsa Talcahuano',
    ),
    DeliveryDestination(
      id: 'logistica_escuadron',
      nombre: 'Logística Escuadrón',
      tipo: 'deposito',
      geocercaModoGps: 'LOGISTICA_ESCUADRON',
      ubicacion: LatLng(-36.955293, -73.159276),
      descripcion: 'Centro de acopio Parque Escuadrón Coronel',
    ),
  ];

  /// Asocia un nombre de cliente comercial con su geocerca configurada en ModoGPS
  static String? findGeofenceForClient(String clientName) {
    final clean = clientName.toUpperCase().trim();
    if (clean.contains('FORSAC')) return 'FORSAC_CHILLAN';
    if (clean.contains('MASISA')) return 'MASISA_SANPEDRO';
    if (clean.contains('PROMASA')) return 'PROMASA_LOS_ANGELES';
    if (clean.contains('INTERGLOBO')) return 'INTERGLOBO_CHILE';
    if (clean.contains('ORIZON')) return 'ORIZON_CNL';
    if (clean.contains('FIORDO')) return 'FIORDO_AUSTRAL_CASA_MATRIZ';
    if (clean.contains('TERRAMAR')) return 'TERRAMAR';
    if (clean.contains('NORAMCO')) return 'NORAMCO';
    if (clean.contains('BASE') || clean.contains('CASA')) return 'CASA-Base';
    return null;
  }

  /// Asocia un nombre de puerto o depósito con su geocerca configurada en ModoGPS
  static String? findGeofenceForDestination(String destinationName) {
    final clean = destinationName.toUpperCase().trim();
    for (final dest in deliveryCatalog) {
      if (clean.contains(dest.nombre.toUpperCase()) || clean.contains(dest.geocercaModoGps)) {
        return dest.geocercaModoGps;
      }
    }
    if (clean.contains('CORONEL')) return 'PUERTO_CORONEL';
    if (clean.contains('LIRQUEN') || clean.contains('LIRQUÉN')) return 'PUERTO_LIRQUEN';
    if (clean.contains('SVTI') || clean.contains('SAN VICENTE')) return 'PUERTO_SVTI';
    if (clean.contains('MEDLOG')) return 'MEDLOG_CORONEL';
    if (clean.contains('SITRANS')) return 'ISLA_ROCUANT';
    if (clean.contains('DYC') || clean.contains('D&C')) return 'DYC_SVTI';
    if (clean.contains('CONTOPSA')) return 'CONTOPSA_SVTI';
    return null;
  }

  /// Construye los tramos iniciales de la misión predictiva
  static List<Map<String, dynamic>> buildMissionLegs({
    required String origin,
    required String client,
    required String puntoDescarga,
    List<String>? paradasIntermedias,
  }) {
    final legs = <Map<String, dynamic>>[];
    final nowStr = DateTime.now().toIso8601String();

    // Tramo 1: Posicionamiento en Vacío (Desde Origen / Base hacia la Planta/Cliente)
    legs.add({
      'id': 'tramo_1',
      'tipo': 'posicionamiento_vacio',
      'nombre': 'Tramo 1: Posicionamiento a Planta (Vacío)',
      'origen': origin,
      'destino': client,
      'geocercaDestino': findGeofenceForClient(client),
      'estado': 'en_ruta', // Arranca de inmediato al iniciar viaje
      'horaInicio': nowStr,
      'horaFin': null,
      'kmGps': null,
      'desnivelPositivoM': 0.0,
      'desnivelNegativoM': 0.0,
      'corredorDetectado': null,
    });

    int legIndex = 2;

    // Tramos Intermedios (Si el chofer agregó multi-paradas)
    if (paradasIntermedias != null && paradasIntermedias.isNotEmpty) {
      String prevStop = client;
      for (final stop in paradasIntermedias) {
        legs.add({
          'id': 'tramo_$legIndex',
          'tipo': 'parada_intermedia',
          'nombre': 'Tramo $legIndex: Parada Intermedia ($stop)',
          'origen': prevStop,
          'destino': stop,
          'geocercaDestino': findGeofenceForClient(stop) ?? findGeofenceForDestination(stop),
          'estado': 'pendiente',
          'horaInicio': null,
          'horaFin': null,
          'kmGps': null,
          'desnivelPositivoM': 0.0,
          'desnivelNegativoM': 0.0,
          'corredorDetectado': null,
        });
        prevStop = stop;
        legIndex++;
      }
    }

    // Tramo Final: Con Carga hacia Puerto o Depósito
    final prevOrigin = paradasIntermedias != null && paradasIntermedias.isNotEmpty
        ? paradasIntermedias.last
        : client;

    legs.add({
      'id': 'tramo_$legIndex',
      'tipo': 'cargado',
      'nombre': 'Tramo $legIndex: Traslado a Destino (Cargado)',
      'origen': prevOrigin,
      'destino': puntoDescarga,
      'geocercaDestino': findGeofenceForDestination(puntoDescarga),
      'estado': 'pendiente',
      'horaInicio': null,
      'horaFin': null,
      'kmGps': null,
      'desnivelPositivoM': 0.0,
      'desnivelNegativoM': 0.0,
      'corredorDetectado': null,
    });

    return legs;
  }

  /// Detecta si el punto actual o la trayectoria corresponde a uno de los corredores principales
  /// (Ruta 152 Itata vs Ruta 146 Cabrero vs Ruta 5 Sur)
  static String? detectCorridor(double lat, double lng) {
    // 1. Corredor Autopista del Itata (Ruta 152):
    // Conecta Chillán con Concepción entre lat -36.60 y -36.75, lng -72.60 y -72.95
    if (lat >= -36.78 && lat <= -36.58 && lng >= -72.95 && lng <= -72.30) {
      // Diferenciamos si está más al norte (Ruta 152 Itata)
      if (lat < -36.65) {
        return 'Ruta 152 (Autopista del Itata)';
      }
    }

    // 2. Corredor Autopista Concepción - Cabrero (Ruta 146):
    // Cruza desde Cabrero (-37.03, -72.40) hacia Concepción (-36.82, -73.05)
    if (lat >= -37.10 && lat <= -36.80 && lng >= -72.95 && lng <= -72.40) {
      return 'Ruta 146 (Autopista Cabrero)';
    }

    // 3. Corredor Ruta 5 Sur (Eje Longitudinal):
    // Entre Chillán y Los Ángeles alrededor de longitud -72.30 a -72.10
    if (lat >= -37.45 && lat <= -36.45 && lng >= -72.40 && lng <= -72.05) {
      return 'Ruta 5 Sur';
    }

    return null;
  }

  /// Calcula el desnivel topográfico acumulado (metros subidos vs metros bajados)
  /// a partir de la secuencia de altitudes en metros ('pos.z')
  static Map<String, double> computeElevationProfile(List<double> altitudes) {
    if (altitudes.length < 2) {
      return {'ascentMeters': 0.0, 'descentMeters': 0.0};
    }

    double ascent = 0.0;
    double descent = 0.0;

    for (int i = 1; i < altitudes.length; i++) {
      final diff = altitudes[i] - altitudes[i - 1];
      // Ignorar fluctuaciones de ruido satelital menores a 2 metros
      if (diff > 2.0) {
        ascent += diff;
      } else if (diff < -2.0) {
        descent += diff.abs();
      }
    }

    return {
      'ascentMeters': double.parse(ascent.toStringAsFixed(1)),
      'descentMeters': double.parse(descent.toStringAsFixed(1)),
    };
  }

  /// Genera un análisis topográfico completo y riguroso punto a punto de la ruta.
  /// Si el GPS físico trajo altitudes válidas las utiliza; de lo contrario consulta el modelo SRTM satelital.
  static Future<RouteTopographyAnalysis> analyzeDetailedTopography({
    required List<LatLng> coordinates,
    List<double?>? rawHardwareAltitudes,
  }) async {
    if (coordinates.length < 2) return RouteTopographyAnalysis.empty();

    // 1. Calcular distancias acumuladas punto a punto
    final distancePoints = <double>[0.0];
    const distanceCalc = Distance();
    double totalDistKm = 0.0;

    for (int i = 1; i < coordinates.length; i++) {
      final meters = distanceCalc.as(LengthUnit.Meter, coordinates[i - 1], coordinates[i]);
      totalDistKm += (meters / 1000.0);
      distancePoints.add(totalDistKm);
    }

    // 2. Determinar altitudes (Hardware GPS o SRTM Satelital)
    List<double> altitudes = [];
    String sourceDesc = 'ModoGPS Telemetría pos.z';

    final hasHardware = rawHardwareAltitudes != null &&
        rawHardwareAltitudes.length == coordinates.length &&
        rawHardwareAltitudes.whereType<double>().any((a) => a > 0);

    if (hasHardware) {
      altitudes = rawHardwareAltitudes.map((a) => (a ?? 0.0)).toList();
    } else {
      // Muestrear ordenadamente entre 40 y 60 puntos
      sourceDesc = 'Modelo Digital de Elevación SRTM (Open-Meteo DEM)';
      final step = math.max(1, coordinates.length ~/ 50);
      final sampledIndices = <int>[];
      for (int i = 0; i < coordinates.length; i += step) {
        sampledIndices.add(i);
        if (sampledIndices.length >= 50) break;
      }
      if (sampledIndices.last != coordinates.length - 1) {
        sampledIndices.add(coordinates.length - 1);
      }

      final sampledCoords = sampledIndices.map((idx) => coordinates[idx]).toList();
      final lats = sampledCoords.map((p) => p.latitude.toStringAsFixed(4)).join(',');
      final lngs = sampledCoords.map((p) => p.longitude.toStringAsFixed(4)).join(',');

      try {
        final uri = Uri.parse('https://api.open-meteo.com/v1/elevation?latitude=$lats&longitude=$lngs');
        final res = await http.get(uri).timeout(const Duration(seconds: 7));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map;
          final rawElev = (data['elevation'] as List?)?.map((e) => (e as num).toDouble()).toList();
          if (rawElev != null && rawElev.isNotEmpty) {
            // Interpolar linealmente para tener altura en cada punto de coordenada
            altitudes = List.generate(coordinates.length, (i) {
              // Buscar índice sampled más cercano
              int bestSample = 0;
              int minDiff = 999999;
              for (int s = 0; s < sampledIndices.length; s++) {
                final diff = (sampledIndices[s] - i).abs();
                if (diff < minDiff) {
                  minDiff = diff;
                  bestSample = s;
                }
              }
              return bestSample < rawElev.length ? rawElev[bestSample] : 0.0;
            });
          }
        }
      } catch (_) {}
    }

    if (altitudes.isEmpty || altitudes.length != coordinates.length) {
      return RouteTopographyAnalysis.empty();
    }

    // 3. Análisis punto a punto: Pendientes, Desniveles y Categorización
    final profilePoints = <ElevationProfilePoint>[];
    double totalAscent = 0.0;
    double totalDescent = 0.0;
    double minAlt = altitudes.first;
    double maxAlt = altitudes.first;

    double steepClimbKm = 0.0;
    double moderateClimbKm = 0.0;
    double flatKm = 0.0;
    double descentKm = 0.0;

    // Segmentos críticos de esfuerzo
    final criticalRamps = <CriticalGradientSegment>[];
    double currentRampStartKm = -1;
    double currentRampElevGain = 0;
    double currentRampMaxGrade = 0;
    double currentRampSumGrade = 0;
    int currentRampCount = 0;

    for (int i = 0; i < coordinates.length; i++) {
      final alt = altitudes[i];
      if (alt < minAlt) minAlt = alt;
      if (alt > maxAlt) maxAlt = alt;

      double gradePercent = 0.0;
      double segmentDistKm = 0.0;

      if (i > 0) {
        segmentDistKm = distancePoints[i] - distancePoints[i - 1];
        final distMeters = segmentDistKm * 1000.0;
        final deltaH = alt - altitudes[i - 1];

        if (distMeters > 5.0) {
          gradePercent = (deltaH / distMeters) * 100.0;
          // Limitar valores anómalos de GPS
          gradePercent = gradePercent.clamp(-18.0, 18.0);
        }

        if (deltaH > 1.5) {
          totalAscent += deltaH;
        } else if (deltaH < -1.5) {
          totalDescent += deltaH.abs();
        }

        // Categorizar km de marcha
        if (gradePercent > 3.5) {
          steepClimbKm += segmentDistKm;
          // Acumular rampa crítica
          if (currentRampStartKm < 0) {
            currentRampStartKm = distancePoints[i - 1];
            currentRampElevGain = 0;
            currentRampMaxGrade = gradePercent;
            currentRampSumGrade = gradePercent;
            currentRampCount = 1;
          } else {
            if (deltaH > 0) currentRampElevGain += deltaH;
            if (gradePercent > currentRampMaxGrade) currentRampMaxGrade = gradePercent;
            currentRampSumGrade += gradePercent;
            currentRampCount++;
          }
        } else {
          if (currentRampStartKm >= 0) {
            final rampLen = distancePoints[i] - currentRampStartKm;
            if (rampLen >= 0.4 && currentRampElevGain >= 12.0) {
              criticalRamps.add(CriticalGradientSegment(
                startKm: currentRampStartKm,
                endKm: distancePoints[i],
                lengthKm: rampLen,
                avgGradePercent: currentRampCount > 0 ? (currentRampSumGrade / currentRampCount) : 3.5,
                maxGradePercent: currentRampMaxGrade,
                elevationGainMeters: currentRampElevGain,
                label: 'Cuesta / Rampa Km ${currentRampStartKm.toStringAsFixed(1)} - ${distancePoints[i].toStringAsFixed(1)}',
              ));
            }
            currentRampStartKm = -1;
          }

          if (gradePercent >= 1.5 && gradePercent <= 3.5) {
            moderateClimbKm += segmentDistKm;
          } else if (gradePercent >= -1.5 && gradePercent < 1.5) {
            flatKm += segmentDistKm;
          } else {
            descentKm += segmentDistKm;
          }
        }
      }

      profilePoints.add(ElevationProfilePoint(
        distanceKm: distancePoints[i],
        altitudeMeters: alt,
        gradePercent: gradePercent,
        position: coordinates[i],
      ));
    }

    // Cerrar rampa si terminó al final de la ruta
    if (currentRampStartKm >= 0) {
      final rampLen = totalDistKm - currentRampStartKm;
      if (rampLen >= 0.4 && currentRampElevGain >= 12.0) {
        criticalRamps.add(CriticalGradientSegment(
          startKm: currentRampStartKm,
          endKm: totalDistKm,
          lengthKm: rampLen,
          avgGradePercent: currentRampCount > 0 ? (currentRampSumGrade / currentRampCount) : 3.5,
          maxGradePercent: currentRampMaxGrade,
          elevationGainMeters: currentRampElevGain,
          label: 'Rampa de Llegada Km ${currentRampStartKm.toStringAsFixed(1)}',
        ));
      }
    }

    return RouteTopographyAnalysis(
      ascentMeters: double.parse(totalAscent.toStringAsFixed(0)),
      descentMeters: double.parse(totalDescent.toStringAsFixed(0)),
      minAltitude: double.parse(minAlt.toStringAsFixed(0)),
      maxAltitude: double.parse(maxAlt.toStringAsFixed(0)),
      totalDistanceKm: double.parse(totalDistKm.toStringAsFixed(1)),
      points: profilePoints,
      criticalRamps: criticalRamps,
      steepClimbKm: double.parse(steepClimbKm.toStringAsFixed(1)),
      moderateClimbKm: double.parse(moderateClimbKm.toStringAsFixed(1)),
      flatKm: double.parse(flatKm.toStringAsFixed(1)),
      descentKm: double.parse(descentKm.toStringAsFixed(1)),
      sourceDescription: sourceDesc,
    );
  }

  /// Obtiene el perfil de elevación real (SRTM / DEM Satelital) consultando
  /// la API abierta y gratuita de Open-Meteo para las coordenadas del recorrido
  static Future<Map<String, double>> fetchDemElevationProfile(List<LatLng> points) async {
    if (points.length < 2) {
      return {'ascentMeters': 0.0, 'descentMeters': 0.0, 'minAltitude': 0.0, 'maxAltitude': 0.0};
    }

    try {
      // Tomar una muestra representativa de 35 a 45 puntos para no sobrecargar el URL
      final step = math.max(1, points.length ~/ 40);
      final sampled = <LatLng>[];
      for (int i = 0; i < points.length; i += step) {
        sampled.add(points[i]);
        if (sampled.length >= 45) break;
      }
      if (sampled.last != points.last) {
        sampled.add(points.last);
      }

      final lats = sampled.map((p) => p.latitude.toStringAsFixed(4)).join(',');
      final lngs = sampled.map((p) => p.longitude.toStringAsFixed(4)).join(',');

      final uri = Uri.parse('https://api.open-meteo.com/v1/elevation?latitude=$lats&longitude=$lngs');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map;
        final rawElev = data['elevation'] as List?;
        if (rawElev != null && rawElev.isNotEmpty) {
          final elevations = rawElev.map((e) => (e as num).toDouble()).toList();
          
          double ascent = 0.0;
          double descent = 0.0;
          double minAlt = elevations.first;
          double maxAlt = elevations.first;

          for (int i = 0; i < elevations.length; i++) {
            final e = elevations[i];
            if (e < minAlt) minAlt = e;
            if (e > maxAlt) maxAlt = e;

            if (i > 0) {
              final diff = e - elevations[i - 1];
              if (diff > 3.0) {
                ascent += diff;
              } else if (diff < -3.0) {
                descent += diff.abs();
              }
            }
          }

          return {
            'ascentMeters': double.parse(ascent.toStringAsFixed(0)),
            'descentMeters': double.parse(descent.toStringAsFixed(0)),
            'minAltitude': double.parse(minAlt.toStringAsFixed(0)),
            'maxAltitude': double.parse(maxAlt.toStringAsFixed(0)),
          };
        }
      }
    } catch (_) {}

    return {'ascentMeters': 0.0, 'descentMeters': 0.0, 'minAltitude': 0.0, 'maxAltitude': 0.0};
  }
}

