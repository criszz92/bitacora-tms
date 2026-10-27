import 'package:bitacora/features/trips/domain/models/vehicle_model.dart';
import 'package:bitacora/features/trips/domain/models/expense_model.dart';

/// Resultado del estado del estanque digital de un vehículo o equipo
class TankState {
  final String vehicleId;
  final String patente;
  final bool isCalibrated;
  final double capacityLitros;
  final double currentLitros;
  final double percentage;
  final double estimatedAutonomyKm;
  final bool isLowFuelAlert;
  final double? lastRealRendimiento;
  final double expectedRendimiento;
  final double fuelValueClp; // Dinero a favor valorizado al precio neto

  // Estado del generador / Thermo King auxiliar (si aplica)
  final bool hasAuxiliary;
  final String? auxIdentifier;
  final double auxCapacityLitros;
  final double auxCurrentLitros;
  final double auxPercentage;
  final double auxAutonomyHours;
  final bool auxLowFuelAlert;

  TankState({
    required this.vehicleId,
    required this.patente,
    required this.isCalibrated,
    required this.capacityLitros,
    required this.currentLitros,
    required this.percentage,
    required this.estimatedAutonomyKm,
    required this.isLowFuelAlert,
    this.lastRealRendimiento,
    required this.expectedRendimiento,
    required this.fuelValueClp,
    this.hasAuxiliary = false,
    this.auxIdentifier,
    this.auxCapacityLitros = 0.0,
    this.auxCurrentLitros = 0.0,
    this.auxPercentage = 0.0,
    this.auxAutonomyHours = 0.0,
    this.auxLowFuelAlert = false,
  });
}

/// Estado global de combustible para toda la flota
class FleetFuelSummary {
  final int totalVehicles;
  final int calibratedVehicles;
  final double totalFleetCapacityLitros;
  final double totalFleetCurrentLitros;
  final double fleetAveragePercentage;
  final double totalMoneyInTanksClp; // Dinero a favor en la calle (Lts * Precio Neto)
  final double litersToFullFleet;    // Cuántos litros faltan para tener la flota al 100%
  final double moneyNeededToFullClp; // Presupuesto necesario para llenar la flota
  final int lowFuelAlertsCount;

  FleetFuelSummary({
    required this.totalVehicles,
    required this.calibratedVehicles,
    required this.totalFleetCapacityLitros,
    required this.totalFleetCurrentLitros,
    required this.fleetAveragePercentage,
    required this.totalMoneyInTanksClp,
    required this.litersToFullFleet,
    required this.moneyNeededToFullClp,
    required this.lowFuelAlertsCount,
  });
}

class FuelPerformanceService {
  /// Calcula el estado dinámico del estanque de un camión en memoria (costo cero en Firebase)
  static TankState calculateVehicleTankState({
    required VehicleModel vehicle,
    required List<ExpenseModel> vehicleExpenses,
    required double currentOdometer,
    required double currentDieselNeto,
  }) {
    final capacity = vehicle.capacidadEstanqueLitros > 0 ? vehicle.capacidadEstanqueLitros : 600.0;
    final expectedRendimiento = vehicle.rendimientoKmPorLitro > 0 ? vehicle.rendimientoKmPorLitro : 2.5;

    // Si nunca se ha realizado una calibración "Full Tank"
    if (!vehicle.tanqueCalibrado || vehicle.ultimoLlenadoKm == null) {
      return TankState(
        vehicleId: vehicle.id,
        patente: vehicle.patente,
        isCalibrated: false,
        capacityLitros: capacity,
        currentLitros: 0.0,
        percentage: 0.0,
        estimatedAutonomyKm: 0.0,
        isLowFuelAlert: false,
        expectedRendimiento: expectedRendimiento,
        fuelValueClp: 0.0,
        hasAuxiliary: vehicle.tieneEquipoAuxiliar,
        auxIdentifier: vehicle.identificadorAuxiliar,
      );
    }

    // 1. Filtrar gastos de combustible del camión posteriores al último Full Tank
    final baseKm = vehicle.ultimoLlenadoKm!;
    final baseFecha = vehicle.ultimoLlenadoFecha ?? DateTime(2020);

    // Cargas parciales (no full) realizadas después del último full
    double cargasParcialesLitros = 0.0;
    double? ultimoRendimientoReal;

    // Buscamos gastos de combustible asociados al camión
    final fuelExpenses = vehicleExpenses
        .where((e) =>
            e.type.toLowerCase() == 'combustible' &&
            (e.destinoCombustible == 'CAMION' || e.destinoCombustible == null))
        .toList();

    fuelExpenses.sort((a, b) => b.date.compareTo(a.date));

    // Si hay cargas con rendimiento calculado, tomamos el más reciente
    for (final exp in fuelExpenses) {
      if (exp.rendimientoTramo != null && exp.rendimientoTramo! > 0) {
        ultimoRendimientoReal = exp.rendimientoTramo;
        break;
      }
    }

    for (final exp in fuelExpenses) {
      if (exp.date.isAfter(baseFecha) && !exp.isFullTank) {
        cargasParcialesLitros += (exp.litros ?? 0.0);
      }
    }

    // 2. Kilómetros recorridos desde el último Full Tank
    final kmRecorridos = (currentOdometer >= baseKm) ? (currentOdometer - baseKm) : 0.0;

    // Rendimiento a utilizar (si tenemos rendimiento real medido reciente, lo ponderamos)
    final rendimientoEfectivo = (ultimoRendimientoReal != null && ultimoRendimientoReal > 0)
        ? (ultimoRendimientoReal * 0.7 + expectedRendimiento * 0.3)
        : expectedRendimiento;

    final litrosConsumidos = kmRecorridos / rendimientoEfectivo;
    
    // Litros actuales = Capacidad a tope + Cargas intermedias - Consumo
    double litrosActuales = (capacity + cargasParcialesLitros) - litrosConsumidos;
    if (litrosActuales < 0) litrosActuales = 0;
    if (litrosActuales > capacity) litrosActuales = capacity;

    final percentage = (litrosActuales / capacity) * 100.0;
    final autonomyKm = litrosActuales * rendimientoEfectivo;
    final isLowFuel = litrosActuales <= vehicle.litrosReservaAlerta;
    final fuelValue = litrosActuales * currentDieselNeto;

    // 3. Cálculo de Generador Auxiliar (Reefer / Thermo King)
    bool auxLow = false;
    double auxCap = vehicle.capacidadEstanqueAuxiliar ?? 200.0;
    double auxCur = auxCap;
    double auxPct = 100.0;
    double auxAutonomy = 0.0;

    if (vehicle.tieneEquipoAuxiliar) {
      final consumoHr = vehicle.consumoHoraAuxiliar > 0 ? vehicle.consumoHoraAuxiliar : 2.5;
      final ultHorometro = vehicle.ultimoLlenadoHorometroAux ?? 0.0;
      final curHorometro = vehicle.horometroActualAuxiliar ?? ultHorometro;
      final horasUso = (curHorometro >= ultHorometro) ? (curHorometro - ultHorometro) : 0.0;

      // Cargas auxiliares
      final auxExpenses = vehicleExpenses
          .where((e) => e.type.toLowerCase() == 'combustible' && e.destinoCombustible == 'AUXILIAR')
          .toList();
      double auxCargas = 0.0;
      for (final exp in auxExpenses) {
        if (exp.date.isAfter(baseFecha) && !exp.isFullTank) {
          auxCargas += (exp.litros ?? 0.0);
        }
      }

      final auxConsumo = horasUso * consumoHr;
      auxCur = (auxCap + auxCargas) - auxConsumo;
      if (auxCur < 0) auxCur = 0;
      if (auxCur > auxCap) auxCur = auxCap;
      auxPct = auxCap > 0 ? (auxCur / auxCap) * 100.0 : 0.0;
      auxAutonomy = consumoHr > 0 ? (auxCur / consumoHr) : 0.0;
      auxLow = auxCur <= (auxCap * 0.2); // Alerta si queda menos del 20%
    }

    return TankState(
      vehicleId: vehicle.id,
      patente: vehicle.patente,
      isCalibrated: true,
      capacityLitros: capacity,
      currentLitros: litrosActuales,
      percentage: percentage,
      estimatedAutonomyKm: autonomyKm,
      isLowFuelAlert: isLowFuel,
      lastRealRendimiento: ultimoRendimientoReal,
      expectedRendimiento: expectedRendimiento,
      fuelValueClp: fuelValue,
      hasAuxiliary: vehicle.tieneEquipoAuxiliar,
      auxIdentifier: vehicle.identificadorAuxiliar,
      auxCapacityLitros: auxCap,
      auxCurrentLitros: auxCur,
      auxPercentage: auxPct,
      auxAutonomyHours: auxAutonomy,
      auxLowFuelAlert: auxLow,
    );
  }

  /// Calcula el consolidado macro de combustible para toda la flota
  static FleetFuelSummary calculateFleetSummary({
    required List<VehicleModel> vehicles,
    required List<ExpenseModel> allExpenses,
    required double currentDieselNeto,
  }) {
    int totalVehicles = vehicles.length;
    int calibratedCount = 0;
    double totalCap = 0;
    double totalCur = 0;
    int lowFuelAlerts = 0;

    for (final v in vehicles) {
      final vExpenses = allExpenses.where((e) => e.vehicleId == v.id || e.vehicleId == v.patente).toList();
      final state = calculateVehicleTankState(
        vehicle: v,
        vehicleExpenses: vExpenses,
        currentOdometer: v.currentOdometer,
        currentDieselNeto: currentDieselNeto,
      );

      totalCap += state.capacityLitros;
      if (state.hasAuxiliary) {
        totalCap += state.auxCapacityLitros;
      }

      if (state.isCalibrated) {
        calibratedCount++;
        totalCur += state.currentLitros;
        if (state.hasAuxiliary) {
          totalCur += state.auxCurrentLitros;
        }
        if (state.isLowFuelAlert || state.auxLowFuelAlert) {
          lowFuelAlerts++;
        }
      }
    }

    final avgPercentage = totalCap > 0 ? (totalCur / totalCap) * 100.0 : 0.0;
    final moneyInTanks = totalCur * currentDieselNeto;
    final litersToFull = (totalCap - totalCur).clamp(0.0, double.infinity);
    final moneyToFull = litersToFull * currentDieselNeto;

    return FleetFuelSummary(
      totalVehicles: totalVehicles,
      calibratedVehicles: calibratedCount,
      totalFleetCapacityLitros: totalCap,
      totalFleetCurrentLitros: totalCur,
      fleetAveragePercentage: avgPercentage,
      totalMoneyInTanksClp: moneyInTanks,
      litersToFullFleet: litersToFull,
      moneyNeededToFullClp: moneyToFull,
      lowFuelAlertsCount: lowFuelAlerts,
    );
  }
}

