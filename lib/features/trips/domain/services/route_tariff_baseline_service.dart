import '../models/trip_model.dart';

enum AnomalySeverity { normal, warning, critical }

/// Estadísticas históricas consolidadas para una ruta específica (ORIGEN ➔ CLIENTE ➔ DESTINO)
class RouteTariffStats {
  final String routeKey;
  final int totalTrips;
  final double avgTariff;
  final double minTariff;
  final double maxTariff;
  final double suggestedTariff;

  const RouteTariffStats({
    required this.routeKey,
    required this.totalTrips,
    required this.avgTariff,
    required this.minTariff,
    required this.maxTariff,
    required this.suggestedTariff,
  });
}

/// Diagnóstico de anomalía o desviación de tarifa contra el histórico del transportista
class RouteTariffAnomaly {
  final bool isAnomaly;
  final dynamic severity; // String o AnomalySeverity
  final double deviationPercent;
  final double historicalAvg;
  final double inputTariff;
  final String message;

  const RouteTariffAnomaly({
    required this.isAnomaly,
    required this.severity,
    required this.deviationPercent,
    required this.historicalAvg,
    required this.inputTariff,
    required this.message,
  });

  String get reason => message;
  bool get isCritical => severity == 'fraude_sospecha' || severity == AnomalySeverity.critical;
  bool get isWarning => severity == 'advertencia' || severity == AnomalySeverity.warning;

  static const normal = RouteTariffAnomaly(
    isAnomaly: false,
    severity: 'normal',
    deviationPercent: 0.0,
    historicalAvg: 0.0,
    inputTariff: 0.0,
    message: 'Tarifa dentro del rango histórico esperado.',
  );
}

/// Extensión fluida para interactuar con la línea base desde vistas y controladores
extension RouteTariffBaselineExt on Map<String, RouteTariffStats> {
  RouteTariffAnomaly evaluateTariff({
    required String origin,
    required String client,
    required String destination,
    required double enteredValue,
  }) {
    final routeKey = '${origin.trim().toUpperCase()} ➔ ${client.trim().toUpperCase()} ➔ ${destination.trim().toUpperCase()}';
    return RouteTariffBaselineService.evaluateTariff(
      routeKey: routeKey,
      enteredValue: enteredValue,
      baseline: this,
    );
  }

  double? getSuggestedTariff({
    required String origin,
    required String client,
    required String destination,
  }) {
    return RouteTariffBaselineService.getSuggestedTariff(
      origin: origin,
      client: client,
      destination: destination,
      baseline: this,
    );
  }
}

/// Servicio inteligente de Línea Base de Tarifas y Radar de Fraude por Ruta
class RouteTariffBaselineService {
  /// Construye la línea base histórica a partir de todos los viajes registrados por la empresa
  static Map<String, RouteTariffStats> buildRouteBaseline(List<TripModel> trips) {
    final Map<String, List<double>> tariffsByRoute = {};

    for (final trip in trips) {
      // Solo considerar viajes operativos con valor comercial mayor a cero (excluyendo retiros vacíos $0)
      if (!trip.isOperativo || trip.value <= 0 || trip.isRetiroAnticipado) continue;

      final key = trip.displayRoute3Steps.trim().toUpperCase();
      tariffsByRoute.putIfAbsent(key, () => []).add(trip.value);
    }

    final Map<String, RouteTariffStats> baseline = {};

    tariffsByRoute.forEach((route, values) {
      if (values.isEmpty) return;
      values.sort();

      final total = values.length;
      final sum = values.fold<double>(0.0, (acc, v) => acc + v);
      final avg = sum / total;
      final min = values.first;
      final max = values.last;

      // Mediana para mitigar valores atípicos
      final median = total % 2 == 1
          ? values[total ~/ 2]
          : (values[(total ~/ 2) - 1] + values[total ~/ 2]) / 2.0;

      baseline[route] = RouteTariffStats(
        routeKey: route,
        totalTrips: total,
        avgTariff: avg,
        minTariff: min,
        maxTariff: max,
        suggestedTariff: median,
      );
    });

    return baseline;
  }

  /// Evalúa si el valor ingresado para un viaje presenta una desviación anómala o sospecha de fraude
  static RouteTariffAnomaly evaluateTariff({
    required String routeKey,
    required double enteredValue,
    required Map<String, RouteTariffStats> baseline,
    double tolerancePercent = 25.0, // Umbral configurable (por defecto 25%)
  }) {
    // Si no tiene valor o es retiro anticipado ($0), es normal
    if (enteredValue <= 0) return RouteTariffAnomaly.normal;

    final cleanKey = routeKey.trim().toUpperCase();
    final stats = baseline[cleanKey];

    // Si es una ruta totalmente nueva (sin histórico suficiente)
    if (stats == null || stats.totalTrips < 2) {
      return RouteTariffAnomaly(
        isAnomaly: false,
        severity: 'normal',
        deviationPercent: 0.0,
        historicalAvg: stats?.avgTariff ?? enteredValue,
        inputTariff: enteredValue,
        message: 'Ruta nueva o con pocos registros previos. Sin anomalías detectables.',
      );
    }

    final avg = stats.avgTariff;
    final diff = enteredValue - avg;
    final deviation = (diff / avg) * 100.0;
    final absDeviation = deviation.abs();

    if (absDeviation <= tolerancePercent) {
      return RouteTariffAnomaly(
        isAnomaly: false,
        severity: 'normal',
        deviationPercent: deviation,
        historicalAvg: avg,
        inputTariff: enteredValue,
        message: 'Tarifa consistente con el promedio histórico (\$${avg.toInt()}).',
      );
    }

    if (absDeviation > 50.0) {
      final direction = deviation > 0 ? 'superior' : 'inferior';
      return RouteTariffAnomaly(
        isAnomaly: true,
        severity: 'fraude_sospecha',
        deviationPercent: deviation,
        historicalAvg: avg,
        inputTariff: enteredValue,
        message: 'ALERTA CRÍTICA: Tarifa un ${absDeviation.toStringAsFixed(1)}% $direction al promedio (\$${avg.toInt()}). Requiere validación de administración.',
      );
    }

    final direction = deviation > 0 ? 'sobre' : 'bajo';
    return RouteTariffAnomaly(
      isAnomaly: true,
      severity: 'advertencia',
      deviationPercent: deviation,
      historicalAvg: avg,
      inputTariff: enteredValue,
      message: 'Aviso: Tarifa un ${absDeviation.toStringAsFixed(1)}% $direction el promedio histórico (\$${avg.toInt()}).',
    );
  }

  /// Sugiere la tarifa más probable al seleccionar una ruta en el formulario
  static double? getSuggestedTariff({
    required String origin,
    required String client,
    required String destination,
    required Map<String, RouteTariffStats> baseline,
  }) {
    final o = origin.trim().toUpperCase();
    final c = client.trim().toUpperCase();
    final d = destination.trim().toUpperCase();

    // 1. Coincidencia exacta con paradas
    final fullKey = '$o ➔ $c ➔ $d';
    if (baseline.containsKey(fullKey)) {
      return baseline[fullKey]!.suggestedTariff;
    }

    // 2. Coincidencia sin intermedias
    final directKey = '$o ➔ DIRECTO ➔ $d';
    if (baseline.containsKey(directKey)) {
      return baseline[directKey]!.suggestedTariff;
    }

    // 3. Búsqueda por similitud de extremos
    for (final entry in baseline.entries) {
      if (entry.key.startsWith(o) && entry.key.endsWith(d)) {
        return entry.value.suggestedTariff;
      }
    }

    return null;
  }
}

