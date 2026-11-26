import '../../features/admin/domain/models/company_config_model.dart';
import '../../features/trips/domain/models/expense_model.dart';
import '../../features/trips/domain/models/vehicle_model.dart';
import '../../features/trips/domain/models/trip_model.dart';

/// Columna Vertebral Única de Bitácora TMS (Single Source of Truth).
///
/// Centraliza la identidad de vehículos, formato canónico de rutas
/// (INICIO ➔ CLIENTE(S) ➔ DESTINO) y resolución dinámica de precios de diésel
/// y rendimiento real por camión/fecha, evitando cálculos divergentes por pantalla.
class TmsBackbone {
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
}

