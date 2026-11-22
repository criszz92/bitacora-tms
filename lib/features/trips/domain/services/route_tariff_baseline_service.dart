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
  static Map<String, RouteTariffStats> buildRouteBaseline(List<TripModel> trips) {
    final Map<String, List<double>> tariffsByRoute = {};

    void addTariff(String key, double val) {
      final clean = key.trim().toUpperCase();
      if (clean.isEmpty) return;
      tariffsByRoute.putIfAbsent(clean, () => []).add(val);
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

      // 1. Clave compuesta comercial exacta: MANDANTE + CLIENTE + DESTINO
      if (m.isNotEmpty && c.isNotEmpty && d.isNotEmpty) {
        addTariff('MANDANTE:$m|CLIENTE:$c|DESTINO:$d', trip.value);
      }

      // 2. Corredor Operativo: CLIENTE + DESTINO
      if (c.isNotEmpty && d.isNotEmpty) {
        addTariff('CLIENTE:$c|DESTINO:$d', trip.value);
      }

      // 3. Histórico por Cliente
      if (c.isNotEmpty && c != 'RETIRO ANTICIPADO' && c != 'MANTENIMIENTO') {
        addTariff('CLIENTE:$c', trip.value);
      }

      // 4. Clave 3 Pasos Tradicional
      final route3Steps = trip.displayRoute3Steps.trim().toUpperCase();
      addTariff(route3Steps, trip.value);
      if (o.isNotEmpty && c.isNotEmpty && d.isNotEmpty) {
        addTariff('$o ➔ $c ➔ $d', trip.value);
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

  /// Sugiere la tarifa más probable al seleccionar una ruta en el formulario
  static double? getSuggestedTariff({
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

    // Si no hay cliente, no podemos inferir una tarifa seria
    if (c.isEmpty || c == 'RETIRO ANTICIPADO' || c == 'MANTENIMIENTO') {
      return null;
    }

    // Nivel 1: Coincidencia comercial exacta (Mandante + Cliente + Destino)
    if (m.isNotEmpty && d.isNotEmpty) {
      final keyExact = 'MANDANTE:$m|CLIENTE:$c|DESTINO:$d';
      if (baseline.containsKey(keyExact)) {
        return baseline[keyExact]!.suggestedTariff;
      }
    }

    // Nivel 2: Corredor de transporte (Cliente + Destino)
    if (d.isNotEmpty) {
      final keyCorredor = 'CLIENTE:$c|DESTINO:$d';
      if (baseline.containsKey(keyCorredor)) {
        return baseline[keyCorredor]!.suggestedTariff;
      }
    }

    // Nivel 3: Ruta de 3 pasos (Origen + Cliente + Destino)
    if (o.isNotEmpty && d.isNotEmpty) {
      final key3Steps = '$o ➔ $c ➔ $d';
      if (baseline.containsKey(key3Steps)) {
        return baseline[key3Steps]!.suggestedTariff;
      }
    }

    // Nivel 4: Histórico consolidado del Cliente
    final keyClient = 'CLIENTE:$c';
    if (baseline.containsKey(keyClient)) {
      return baseline[keyClient]!.suggestedTariff;
    }

    // Nivel 5: Búsqueda difusa por coincidencia de nombre de Cliente
    for (final entry in baseline.entries) {
      if (entry.key.startsWith('CLIENTE:')) {
        final clientInKey = entry.key.replaceFirst('CLIENTE:', '').split('|').first;
        if (clientInKey == c || (c.length >= 4 && (clientInKey.contains(c) || c.contains(clientInKey)))) {
          return entry.value.suggestedTariff;
        }
      }
    }

    // Si el cliente no tiene registros, NUNCA prestar tarifa de otro cliente
    return null;
  }
}
