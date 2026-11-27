import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/admin/domain/models/company_config_model.dart';
import '../../features/auth/domain/models/user_model.dart';
import '../../features/trips/domain/models/expense_model.dart';
import '../../features/trips/domain/models/vehicle_model.dart';
import '../../features/trips/domain/models/trip_model.dart';

/// Columna Vertebral Única de Bitácora TMS (Single Source of Truth).
///
/// Centraliza la identidad de vehículos, formato canónico de rutas
/// (INICIO ➔ CLIENTE(S) ➔ DESTINO) y resolución dinámica de precios de diésel
/// y rendimiento real por camión/fecha, evitando cálculos divergentes por pantalla.
class TmsBackbone {
  /// Parsea de forma segura cualquier fecha proveniente de Firestore
  /// (Timestamp, String ISO-8601, DateTime o null) sin lanzar excepciones.
  static DateTime parseDate(dynamic val, {DateTime? fallback}) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String && val.trim().isNotEmpty) {
      return DateTime.tryParse(val.trim()) ?? (fallback ?? DateTime.now());
    }
    return fallback ?? DateTime.now();
  }

  /// Parsea una fecha nullable de Firestore de forma segura.
  static DateTime? parseNullableDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String && val.trim().isNotEmpty) {
      return DateTime.tryParse(val.trim());
    }
    return null;
  }

  /// Normaliza una patente o identificador quitando guiones/espacios en mayúsculas.
  static String normalizePlate(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  /// Normaliza el nombre de un punto/ubicación (colapsa espacios y unifica "//").
  /// Ej: "BASE //CASA" y "BASE//CASA" -> "BASE // CASA".
  static String normalizeLocation(String? raw) {
    if (raw == null) return '';
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'\s*//\s*'), ' // ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  /// Genera la ruta canónica única para TODO el proyecto:
  /// `INICIO ➔ CLIENTE(S) ➔ DESTINO`
  static String canonicalRoute(TripModel trip) {
    final start = normalizeLocation(trip.origin);
    final rawEnd = (trip.puntoDescarga != null && trip.puntoDescarga!.trim().isNotEmpty)
        ? trip.puntoDescarga!
        : trip.destination;
    final end = normalizeLocation(rawEnd);

    final List<String> intermediateClients = [];
    if (trip.paradasIntermedias != null && trip.paradasIntermedias!.isNotEmpty) {
      for (final stop in trip.paradasIntermedias!) {
        final sNorm = normalizeLocation(stop);
        if (sNorm.isNotEmpty && !intermediateClients.contains(sNorm)) {
          intermediateClients.add(sNorm);
        }
      }
    }

    final cNorm = normalizeLocation(trip.client);
    if (cNorm.isNotEmpty &&
        cNorm != 'RETIRO ANTICIPADO' &&
        cNorm != 'MANTENIMIENTO' &&
        cNorm != 'MOVIMIENTO INTERNO' &&
        cNorm != start &&
        cNorm != end &&
        !cNorm.contains('GENERICO') &&
        !cNorm.contains('GENÉRICO') &&
        !intermediateClients.contains(cNorm)) {
      intermediateClients.insert(0, cNorm);
    }

    final sLabel = start.isEmpty ? 'ORIGEN' : start;
    final eLabel = end.isEmpty ? 'DESTINO' : end;

    if (intermediateClients.isNotEmpty) {
      return '$sLabel ➔ ${intermediateClients.join(' / ')} ➔ $eLabel';
    }
    return '$sLabel ➔ $eLabel';
  }

  /// Resuelve un `vehicleId` o patente (ej. "VEH-..." o "JHBZ64" o "JH-BZ-64")
  /// al [VehicleModel] correspondiente, o null si no existe.
  static VehicleModel? findVehicle(String? idOrPlate, List<VehicleModel> vehicles) {
    if (idOrPlate == null || idOrPlate.trim().isEmpty) return null;
    final raw = idOrPlate.trim();
    final norm = normalizePlate(raw);

    for (final v in vehicles) {
      if (v.id == raw || normalizePlate(v.patente) == norm) {
        return v;
      }
    }
    return null;
  }

  /// Retorna el ID canónico del vehículo (`v.id`) para cruzar viajes y gastos
  /// sin importar si fueron guardados con `VEH-...` o con la patente.
  static String canonicalVehicleKey(String? idOrPlate, List<VehicleModel> vehicles) {
    final v = findVehicle(idOrPlate, vehicles);
    if (v != null) return v.id;
    final norm = normalizePlate(idOrPlate);
    return norm.isEmpty ? 'N/A' : norm;
  }

  /// Verifica si un `vehicleId` de viaje o gasto pertenece a un vehículo dado.
  static bool matchesVehicle(String? idOrPlate, VehicleModel vehicle) {
    if (idOrPlate == null || idOrPlate.trim().isEmpty) return false;
    final raw = idOrPlate.trim();
    return raw == vehicle.id || normalizePlate(raw) == normalizePlate(vehicle.patente);
  }

  /// Resuelve el precio neto vigente por litro de diésel para un vehículo en una fecha.
  ///
  /// Prioridad (de mayor a menor veracidad operativa):
  /// 1. Última carga real de combustible del mismo vehículo con `litros > 0` y `date <= refDate`.
  ///    Refleja el costo real del combustible que el camión lleva en el estanque esa semana.
  /// 2. Última carga real de combustible de la flota con `litros > 0` y `date <= refDate`.
  /// 3. Precio diésel neto configurado en [CompanyConfigModel] para el mes de [refDate].
  static double resolveDieselNetoPrice({
    required DateTime refDate,
    String? vehicleIdOrPlate,
    required List<VehicleModel> vehicles,
    required List<ExpenseModel> fuelExpenses,
    CompanyConfigModel? config,
  }) {
    final targetKey = vehicleIdOrPlate != null
        ? canonicalVehicleKey(vehicleIdOrPlate, vehicles)
        : null;

    final validCharges = fuelExpenses.where((e) {
      return e.type.toLowerCase() == 'combustible' &&
          (e.litros ?? 0) > 0 &&
          e.amount > 0 &&
          !e.date.isAfter(refDate);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    // 1. Carga más reciente del mismo vehículo antes o igual a la fecha del viaje
    if (targetKey != null && targetKey != 'N/A') {
      for (final e in validCharges) {
        if (canonicalVehicleKey(e.vehicleId, vehicles) == targetKey) {
          return _netPricePerLiter(e);
        }
      }
    }

    // 2. Carga más reciente de cualquier unidad de la empresa
    if (validCharges.isNotEmpty) {
      return _netPricePerLiter(validCharges.first);
    }

    // 3. Configuración histórica mensual / base de la empresa
    if (config != null) {
      final monthKey =
          '${refDate.year}-${refDate.month.toString().padLeft(2, '0')}';
      return config.getDieselManualForMonth(monthKey) ?? config.precioDieselNeto;
    }

    return 800.0;
  }

  static double _netPricePerLiter(ExpenseModel e) {
    final litros = e.litros!;
    final double netAmount;
    if (e.isExento) {
      netAmount = e.amount;
    } else if (e.customIva != null && e.customIva! > 0) {
      netAmount = (e.amount - e.customIva!).clamp(0.0, e.amount);
    } else {
      netAmount = e.amount / 1.19;
    }
    return netAmount / litros;
  }

  /// Resuelve el rendimiento real vigente (Km/L) de un vehículo.
  /// Prioriza el rendimiento real medido entre estanques llenos (`ultimoRendimientoReal`),
  /// luego el esperado del camión (`rendimientoKmPorLitro`).
  static double resolveVehicleEfficiency(VehicleModel? vehicle) {
    if (vehicle != null) {
      if (vehicle.ultimoRendimientoReal != null &&
          vehicle.ultimoRendimientoReal! > 0.5) {
        return vehicle.ultimoRendimientoReal!;
      }
      if (vehicle.rendimientoKmPorLitro > 0.5) {
        return vehicle.rendimientoKmPorLitro;
      }
    }
    return 2.5;
  }

  /// Monto comisionable único de un viaje:
  /// Solo viajes operativos; incluye valor base + extraCostos + sobreEstadia.
  static double tripCommissionableAmount(TripModel trip) {
    if (!trip.isOperativo) return 0.0;
    return trip.value + (trip.extraCostos ?? 0.0) + (trip.sobreEstadia ?? 0.0);
  }

  /// Costo de mantenimiento por KM único:
  /// Prioriza el override específico del camión, o suma las reglas globales de la empresa.
  static double resolveMaintenanceCostPerKm(
    VehicleModel? vehicle,
    CompanyConfigModel config,
  ) {
    if (vehicle?.costoMantenimientoPorKm != null &&
        vehicle!.costoMantenimientoPorKm! > 0) {
      return vehicle.costoMantenimientoPorKm!;
    }
    double total = 0.0;
    for (final rule in config.maintenanceRules) {
      final cost = (rule['cost'] as num?)?.toDouble() ?? 0.0;
      final km = (rule['km'] as num?)?.toDouble() ?? 0.0;
      if (km > 0) total += (cost / km);
    }
    return total;
  }

  /// Cálculo único de viáticos para un conjunto de viajes de un chofer.
  /// Soporta `POR_VIAJE` y `POR_JORNADA` sin duplicar lógica en 7 pantallas.
  static ({double total, Map<String, double> perTrip}) calculateTripsViaticos({
    required List<TripModel> trips,
    required UserModel driver,
    required CompanyConfigModel config,
  }) {
    final Map<String, double> perTrip = {};
    double total = 0.0;
    final largo = driver.montoViaticoLargo ?? 10000.0;
    final local = driver.montoViaticoLocal ?? 6500.0;
    final threshold = config.umbralKilometrosViatico;

    if (config.tipoViatico == 'POR_VIAJE') {
      for (final t in trips) {
        if (t.isOperativo) {
          final v = (t.totalKm ?? 0.0) >= threshold ? largo : local;
          perTrip[t.id] = v;
          total += v;
        } else {
          perTrip[t.id] = 0.0;
        }
      }
      return (total: total, perTrip: perTrip);
    }

    final Map<String, List<TripModel>> tripsByDay = {};
    for (final t in trips) {
      if (t.isOperativo) {
        final dayKey = '${t.startDate.year}-${t.startDate.month}-${t.startDate.day}';
        tripsByDay.putIfAbsent(dayKey, () => []).add(t);
      } else {
        perTrip[t.id] = 0.0;
      }
    }

    for (final dayTrips in tripsByDay.values) {
      final existsLongTrip = dayTrips.any((t) => (t.totalKm ?? 0.0) >= threshold);
      final dayV = existsLongTrip ? largo : local;
      total += dayV;
      for (final t in dayTrips) {
        perTrip[t.id] = dayV / dayTrips.length;
      }
    }

    return (total: total, perTrip: perTrip);
  }

  /// Calcula el Road Master Score real (0-100) basado en trazabilidad de hitos,
  /// rendimiento real de combustible vs esperado y cumplimiento de KM/documentos.
  static ({int total, int hitos, int combustible, int jornada}) calculateRoadMasterScore({
    required List<TripModel> driverTrips,
    VehicleModel? vehicle,
  }) {
    final finished = driverTrips.where((t) => t.status != 'En Ruta').toList();

    // 1. Hitos y cumplimiento (sobre 40)
    int hitosScore = 32;
    if (finished.isNotEmpty) {
      final withHitos = finished.where((t) => (t.hitos != null && t.hitos!.isNotEmpty) || (t.totalKm ?? 0) > 0).length;
      hitosScore = ((withHitos / finished.length) * 40).round().clamp(0, 40);
    }

    // 2. Eficiencia de combustible real vs esperada (sobre 30)
    int combScore = 25;
    if (vehicle != null && vehicle.ultimoRendimientoReal != null && vehicle.ultimoRendimientoReal! > 0) {
      final ratio = vehicle.ultimoRendimientoReal! / (vehicle.rendimientoKmPorLitro > 0 ? vehicle.rendimientoKmPorLitro : 2.5);
      if (ratio >= 0.95) {
        combScore = 30;
      } else if (ratio >= 0.85) {
        combScore = 24;
      } else {
        combScore = 16;
      }
    }

    // 3. Trazabilidad de jornada / documentos / KM (sobre 30)
    int jornadaScore = 25;
    final opTrips = finished.where((t) => t.isOperativo).toList();
    if (opTrips.isNotEmpty) {
      final traceable = opTrips.where((t) =>
          (t.totalKm ?? 0) > 0 &&
          ((t.guideNumber != null && t.guideNumber!.isNotEmpty) ||
           (t.containerNumber != null && t.containerNumber!.isNotEmpty))).length;
      jornadaScore = ((traceable / opTrips.length) * 30).round().clamp(0, 30);
    }

    return (
      total: (hitosScore + combScore + jornadaScore).clamp(0, 100),
      hitos: hitosScore,
      combustible: combScore,
      jornada: jornadaScore,
    );
  }
}

