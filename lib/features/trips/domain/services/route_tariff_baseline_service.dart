import 'package:intl/intl.dart';
import '../models/trip_model.dart';

enum AnomalySeverity { normal, warning, critical }

/// Estadísticas históricas consolidadas para una ruta o corredor comercial específico
class RouteTariffStats {
  final String routeKey;
  final int totalTrips;
  final double avgTariff;
  final double minTariff;
  final double maxTariff;
  final double suggestedTariff; // Tarifa Maestra / Moda Ponderada
  final int frequencyCount;     // Cuántas veces se repite la tarifa maestra
  final double confidenceScore; // % de viajes que coinciden con esta tarifa (0.0 a 1.0)
  final double? avgKm;          // Distancia promedio en km para este corredor

  const RouteTariffStats({
    required this.routeKey,
    required this.totalTrips,
    required this.avgTariff,
    required this.minTariff,
    required this.maxTariff,
    required this.suggestedTariff,
    this.frequencyCount = 1,
    this.confidenceScore = 1.0,
    this.avgKm,
  });
}

/// Diagnóstico de anomalía o desviación de tarifa contra el histórico real del transportista
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
    String? mandante,
    required String origin,
    required String client,
    required String destination,
    required double enteredValue,
  }) {
    return RouteTariffBaselineService.evaluateTariff(
      mandante: mandante,
      origin: origin,
      client: client,
      destination: destination,
      enteredValue: enteredValue,
      baseline: this,
    );
  }

  double? getSuggestedTariff({
    String? mandante,
    required String origin,
    required String client,
    required String destination,
  }) {
    return RouteTariffBaselineService.getSuggestedTariff(
      mandante: mandante,
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
  /// Indexa por corredor comercial exacto (Mandante + Cliente + Destino), por corredor operativo
  /// (Cliente + Destino) y por cliente histórico.
  /// Implementa selección por MODA PONDERADA (Tarifa que más veces se repite, con regla si >= 3-4 veces)
  static Map<String, RouteTariffStats> buildRouteBaseline(List<TripModel> trips) {
    final Map<String, List<double>> tariffsByRoute = {};
    final Map<String, List<double>> kmsByRoute = {};

    void addTariff(String key, double val, double? km) {
      final clean = key.trim().toUpperCase();
      if (clean.isEmpty) return;
      tariffsByRoute.putIfAbsent(clean, () => []).add(val);
      if (km != null && km > 0) {
        kmsByRoute.putIfAbsent(clean, () => []).add(km);
      }
    }

    for (final trip in trips) {
      // Solo considerar viajes operativos con valor comercial mayor a cero (excluyendo retiros vacíos $0)
      if (!trip.isOperativo || trip.value <= 0 || trip.isRetiroAnticipado) continue;

      final m = trip.mandante.trim().toUpperCase();
      final c = trip.client.trim().toUpperCase();
      final o = trip.origin.trim().toUpperCase();
      final d = (trip.puntoDescarga != null && trip.puntoDescarga!.trim().isNotEmpty
              ? trip.puntoDescarga!
              : trip.destination)
          .trim()
          .toUpperCase();
      final km = trip.totalKm;

      // 1. Clave compuesta comercial exacta: MANDANTE + CLIENTE + DESTINO
      if (m.isNotEmpty && c.isNotEmpty && d.isNotEmpty) {
        addTariff('MANDANTE:$m|CLIENTE:$c|DESTINO:$d', trip.value, km);
      }

      // 2. Corredor Operativo: CLIENTE + DESTINO
      if (c.isNotEmpty && d.isNotEmpty) {
        addTariff('CLIENTE:$c|DESTINO:$d', trip.value, km);
      }

      // 3. Histórico por Cliente
      if (c.isNotEmpty && c != 'RETIRO ANTICIPADO' && c != 'MANTENIMIENTO') {
        addTariff('CLIENTE:$c', trip.value, km);
      }

      // 4. Clave 3 Pasos Tradicional
      final route3Steps = trip.displayRoute3Steps.trim().toUpperCase();
      addTariff(route3Steps, trip.value, km);
      if (o.isNotEmpty && c.isNotEmpty && d.isNotEmpty) {
        addTariff('$o ➔ $c ➔ $d', trip.value, km);
      }
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

      // ── ALGORITMO DE MODA PONDERADA (Frecuencia de Repetición) ──
      // Agrupamos tarifas dentro de una pequeña tolerancia (~$500 pesos por redondeos)
      final Map<double, int> frequencies = {};
      for (final val in values) {
        // Redondear a la decena más cercana para unificar pequeñas variaciones
        final rounded = (val / 100.0).roundToDouble() * 100.0;
        frequencies[rounded] = (frequencies[rounded] ?? 0) + 1;
      }

      // Encontrar la tarifa con mayor frecuencia de repetición
      double modeTariff = values.first;
      int maxFreq = 0;
      frequencies.forEach((tariffVal, count) {
        if (count > maxFreq) {
          maxFreq = count;
          modeTariff = tariffVal;
        }
      });

      // Si la moda tiene una frecuencia significativa (>= 3 repeticiones o >= 30% del volumen),
      // esa es la REGLA MAESTRA. De lo contrario, usamos la mediana como fallback.
      double suggested;
      if (maxFreq >= 3 || (total >= 4 && (maxFreq / total) >= 0.4)) {
        suggested = modeTariff;
      } else {
        // Mediana como fallback si no hay una moda clara
        suggested = total % 2 == 1
            ? values[total ~/ 2]
            : (values[(total ~/ 2) - 1] + values[total ~/ 2]) / 2.0;
      }

      // Cálculo de Km promedio si existe
      double? avgKm;
      final kmList = kmsByRoute[route];
      if (kmList != null && kmList.isNotEmpty) {
        avgKm = kmList.fold<double>(0.0, (acc, k) => acc + k) / kmList.length;
      }

      baseline[route] = RouteTariffStats(
        routeKey: route,
        totalTrips: total,
        avgTariff: avg,
        minTariff: min,
        maxTariff: max,
        suggestedTariff: suggested,
        frequencyCount: maxFreq,
        confidenceScore: total > 0 ? (maxFreq / total) : 1.0,
        avgKm: avgKm,
      );
    });

    return baseline;
  }

  /// Evalúa si el valor ingresado para un viaje presenta una desviación anómala o sospecha de fraude
  static RouteTariffAnomaly evaluateTariff({
    String? mandante,
    required String origin,
    required String client,
    required String destination,
    required double enteredValue,
    required Map<String, RouteTariffStats> baseline,
    double tolerancePercent = 25.0, // Umbral configurable (por defecto 25%)
  }) {
    // Si no tiene valor o es retiro anticipado ($0), es normal
    if (enteredValue <= 0) return RouteTariffAnomaly.normal;

    // Si el usuario está recién ingresando números iniciales (< 10.000)
    if (enteredValue < 10000) {
      return const RouteTariffAnomaly(
        isAnomaly: false,
        severity: 'incompleto',
        deviationPercent: 0.0,
        historicalAvg: 0.0,
        inputTariff: 0.0,
        message: 'Ingresa el monto del flete completo en pesos.',
      );
    }

    final cleanClient = client.trim().toUpperCase();
    if (cleanClient.isEmpty || cleanClient == 'RETIRO ANTICIPADO' || cleanClient == 'MANTENIMIENTO') {
      return RouteTariffAnomaly.normal;
    }

    final suggested = getSuggestedTariff(
      mandante: mandante,
      origin: origin,
      client: client,
      destination: destination,
      baseline: baseline,
    );

    // Si no hay histórico específico para este cliente/ruta
    if (suggested == null || suggested <= 0) {
      return RouteTariffAnomaly(
        isAnomaly: false,
        severity: 'nuevo',
        deviationPercent: 0.0,
        historicalAvg: enteredValue,
        inputTariff: enteredValue,
        message: 'Ruta o cliente sin registros históricos suficientes para contraste.',
      );
    }

    final diff = enteredValue - suggested;
    final deviation = (diff / suggested) * 100.0;
    final absDeviation = deviation.abs();

    if (absDeviation <= tolerancePercent) {
      return RouteTariffAnomaly(
        isAnomaly: false,
        severity: 'normal',
        deviationPercent: deviation,
        historicalAvg: suggested,
        inputTariff: enteredValue,
        message: 'Tarifa consistente con el histórico para $client (\$${NumberFormat('#,###', 'es_CL').format(suggested.toInt())}).',
      );
    }

    if (absDeviation > 50.0) {
      final direction = deviation > 0 ? 'superior' : 'inferior';
      return RouteTariffAnomaly(
        isAnomaly: true,
        severity: 'fraude_sospecha',
        deviationPercent: deviation,
        historicalAvg: suggested,
        inputTariff: enteredValue,
        message: 'ALERTA: Tarifa un ${absDeviation.toStringAsFixed(1)}% $direction a lo registrado para $client (\$${NumberFormat('#,###', 'es_CL').format(suggested.toInt())}).',
      );
    }

    final direction = deviation > 0 ? 'sobre' : 'bajo';
    return RouteTariffAnomaly(
      isAnomaly: true,
      severity: 'advertencia',
      deviationPercent: deviation,
      historicalAvg: suggested,
      inputTariff: enteredValue,
      message: 'Aviso: Tarifa un ${absDeviation.toStringAsFixed(1)}% $direction el histórico de $client (\$${NumberFormat('#,###', 'es_CL').format(suggested.toInt())}).',
    );
  }

  /// Retorna las estadísticas completas del mejor corredor o cliente disponible
  static RouteTariffStats? getSuggestedStats({
    String? mandante,
    required String origin,
    required String client,
    required String destination,
    required Map<String, RouteTariffStats> baseline,
  }) {
    final m = (mandante ?? '').trim().toUpperCase();
    final c = client.trim().toUpperCase();
    final d = destination.trim().toUpperCase();
    final o = origin.trim().toUpperCase();

    if (c.isEmpty || c == 'RETIRO ANTICIPADO' || c == 'MANTENIMIENTO') {
      return null;
    }

    if (m.isNotEmpty && d.isNotEmpty) {
      final keyExact = 'MANDANTE:$m|CLIENTE:$c|DESTINO:$d';
      if (baseline.containsKey(keyExact)) return baseline[keyExact];
    }

    if (d.isNotEmpty) {
      final keyCorredor = 'CLIENTE:$c|DESTINO:$d';
      if (baseline.containsKey(keyCorredor)) return baseline[keyCorredor];
    }

    if (o.isNotEmpty && d.isNotEmpty) {
      final key3Steps = '$o ➔ $c ➔ $d';
      if (baseline.containsKey(key3Steps)) return baseline[key3Steps];
    }

    final keyClient = 'CLIENTE:$c';
    if (baseline.containsKey(keyClient)) return baseline[keyClient];

    for (final entry in baseline.entries) {
      if (entry.key.startsWith('CLIENTE:')) {
        final clientInKey = entry.key.replaceFirst('CLIENTE:', '').split('|').first;
        if (clientInKey == c || (c.length >= 4 && (clientInKey.contains(c) || c.contains(clientInKey)))) {
          return entry.value;
        }
      }
    }

    return null;
  }

  /// Sugiere la tarifa más probable al seleccionar una ruta en el formulario
  static double? getSuggestedTariff({
    String? mandante,
    required String origin,
    required String client,
    required String destination,
    required Map<String, RouteTariffStats> baseline,
  }) {
    final stats = getSuggestedStats(
      mandante: mandante,
      origin: origin,
      client: client,
      destination: destination,
      baseline: baseline,
    );
    return stats?.suggestedTariff;
  }
}
