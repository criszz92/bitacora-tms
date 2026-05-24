import '../../features/auth/domain/models/user_model.dart';
import '../../features/admin/domain/models/company_config_model.dart';
import '../../features/trips/domain/models/trip_model.dart';
import '../../features/admin/domain/models/analytics_models.dart';
import '../../features/trips/domain/models/expense_model.dart';

class ChileanFinancialCalculator {
  /// Calcula el costo total para el empleador de un conductor específico en un mes.
  static double calculateMonthlyEmployerCost({
    required UserModel driver,
    required CompanyConfigModel config,
    required List<TripModel> monthlyTrips,
  }) {
    if (driver.rol != 'CHOFER') return 0;

    final sueldoBase = driver.sueldoBase ?? config.sueldoMinimo;
    final toggles = driver.configuracionPagos ?? {};

    // 1. Comisión por Facturación
    double comision = 0;
    for (final trip in monthlyTrips) {
      if (trip.idChofer == driver.uid) {
        comision += trip.value * (config.porcentajeComision / 100);
      }
    }

    // 2. Gratificación Legal
    double gratificacion = 0;
    if (toggles['Gratificación'] ?? true) {
      final topeGratificacion = (config.sueldoMinimo * 4.75) / 12;
      gratificacion = ((sueldoBase + comision) * 0.25).clamp(0, topeGratificacion);
    }

    final totalImponible = sueldoBase + comision + gratificacion;
    
    // Base sobre la que se calculan leyes sociales (configurable por el cliente)
    final baseParaLeyesSociales = driver.baseImponible == 'Sueldo Base' 
        ? sueldoBase 
        : totalImponible;

    // 2. SIS
    double sis = 0;
    if (toggles['SIS'] ?? true) {
      sis = baseParaLeyesSociales * (config.tasaSIS / 100);
    }

    // 3. Mutual
    double mutual = 0;
    if (toggles['Mutual'] ?? true) {
      mutual = baseParaLeyesSociales * (config.tasaMutual / 100);
    }

    // 4. Seguro de Cesantía (Aporte Patronal)
    double cesantia = 0;
    if (toggles['Seguro Cesantía'] ?? true) {
      final tasa = driver.tipoContrato == 'Plazo Fijo' ? 0.03 : 0.024;
      cesantia = baseParaLeyesSociales * tasa;
    }

    // 5. Viáticos
    double viaticosTotales = 0;
    if (config.tipoViatico == 'POR_VIAJE') {
      for (final trip in monthlyTrips) {
        if (trip.idChofer == driver.uid) {
          final threshold = config.umbralKilometrosViatico;
          final isLongTrip = (trip.totalKm ?? 0) >= threshold;
          viaticosTotales += isLongTrip 
              ? (driver.montoViaticoLargo ?? 10000) 
              : (driver.montoViaticoLocal ?? 6500);
        }
      }
    } else {
      final Map<String, List<TripModel>> tripsByDay = {};
      for (final trip in monthlyTrips) {
        if (trip.idChofer == driver.uid) {
          final dayKey = '${trip.startDate.year}-${trip.startDate.month}-${trip.startDate.day}';
          tripsByDay.putIfAbsent(dayKey, () => []).add(trip);
        }
      }
      for (final dayTrips in tripsByDay.values) {
        bool existsLongTrip = dayTrips.any((t) => (t.totalKm ?? 0.0) >= config.umbralKilometrosViatico);
        viaticosTotales += existsLongTrip 
            ? (driver.montoViaticoLargo ?? 10000) 
            : (driver.montoViaticoLocal ?? 6500);
      }
    }

    // 6. Costo Adicional si la Empresa Asume Leyes Sociales del Trabajador (Sueldo Líquido Pactado)
    double costoLeyesAsumidas = 0;
    if (driver.empresaAsumeLeyes == true) {
      double descuentoAFP = 0;
      if (toggles['AFP'] ?? true) {
        descuentoAFP = baseParaLeyesSociales * ((driver.tasaAFP ?? 10.58) / 100);
      }
      double descuentoSalud = 0;
      if (toggles['Salud'] ?? true) {
        descuentoSalud = baseParaLeyesSociales * ((driver.tasaSalud ?? 7.0) / 100);
      }
      double descuentoCesantiaTrabajador = 0;
      if (toggles['Seguro Cesantía'] ?? true) {
        if (driver.tipoContrato != 'Plazo Fijo') {
          descuentoCesantiaTrabajador = baseParaLeyesSociales * 0.006;
        }
      }
      costoLeyesAsumidas = descuentoAFP + descuentoSalud + descuentoCesantiaTrabajador;
    }

    return totalImponible + sis + mutual + cesantia + viaticosTotales + costoLeyesAsumidas;
  }

  /// Calcula la estructura de liquidación de sueldo chilena real para el trabajador.
  static Map<String, dynamic> calculateDriverPayslip({
    required UserModel driver,
    required CompanyConfigModel config,
    required List<TripModel> monthlyTrips,
    double? viaticosYaPagados,
  }) {
    if (driver.rol != 'CHOFER') return {};

    final sueldoBase = driver.sueldoBase ?? config.sueldoMinimo;
    final toggles = driver.configuracionPagos ?? {};

    // 1. Comisión
    double comision = 0;
    for (final trip in monthlyTrips) {
      if (trip.idChofer == driver.uid) {
        comision += trip.value * (config.porcentajeComision / 100);
      }
    }

    // 2. Gratificación
    double gratificacion = 0;
    if (toggles['Gratificación'] ?? true) {
      final topeGratificacion = (config.sueldoMinimo * 4.75) / 12;
      gratificacion = ((sueldoBase + comision) * 0.25).clamp(0, topeGratificacion);
    }

    final totalImponible = sueldoBase + comision + gratificacion;
    final baseParaLeyesSociales = driver.baseImponible == 'Sueldo Base' 
        ? sueldoBase 
        : totalImponible;

    // 3. Viáticos (No Imponibles)
    // Si se pasa viaticosYaPagados (proveniente de las rendiciones reales), se usa ese valor.
    // De lo contrario, se calcula teóricamente usando los viajes del mes.
    double viaticosTotales = 0;
    if (viaticosYaPagados != null) {
      viaticosTotales = viaticosYaPagados;
    } else {
      if (config.tipoViatico == 'POR_VIAJE') {
        for (final trip in monthlyTrips) {
          if (trip.idChofer == driver.uid) {
            final threshold = config.umbralKilometrosViatico;
            final isLongTrip = (trip.totalKm ?? 0) >= threshold;
            viaticosTotales += isLongTrip 
                ? (driver.montoViaticoLargo ?? 10000) 
                : (driver.montoViaticoLocal ?? 6500);
          }
        }
      } else {
        final Map<String, List<TripModel>> tripsByDay = {};
        for (final trip in monthlyTrips) {
          if (trip.idChofer == driver.uid) {
            final dayKey = '${trip.startDate.year}-${trip.startDate.month}-${trip.startDate.day}';
            tripsByDay.putIfAbsent(dayKey, () => []).add(trip);
          }
        }
        for (final dayTrips in tripsByDay.values) {
          bool existsLongTrip = dayTrips.any((t) => (t.totalKm ?? 0.0) >= config.umbralKilometrosViatico);
          viaticosTotales += existsLongTrip 
              ? (driver.montoViaticoLargo ?? 10000) 
              : (driver.montoViaticoLocal ?? 6500);
        }
      }
    }

    final totalHaberes = totalImponible + viaticosTotales;

    // 4. Descuentos Legales (Trabajador)
    double descuentoAFP = 0;
    if (toggles['AFP'] ?? true) {
      descuentoAFP = baseParaLeyesSociales * ((driver.tasaAFP ?? 10.58) / 100);
    }

    double descuentoSalud = 0;
    if (toggles['Salud'] ?? true) {
      descuentoSalud = baseParaLeyesSociales * ((driver.tasaSalud ?? 7.0) / 100);
    }

    double descuentoCesantia = 0;
    if (toggles['Seguro Cesantía'] ?? true) {
      if (driver.tipoContrato != 'Plazo Fijo') {
        descuentoCesantia = baseParaLeyesSociales * 0.006;
      }
    }

    final totalDescuentos = descuentoAFP + descuentoSalud + descuentoCesantia;
    
    // Si la empresa asume los descuentos, no se le restan al bolsillo del trabajador
    final liquidoAPago = driver.empresaAsumeLeyes == true 
        ? totalHaberes 
        : totalHaberes - totalDescuentos;

    return {
      'Sueldo Base': sueldoBase,
      'Comisiones': comision,
      'Gratificación Legal': gratificacion,
      'Total Imponible': totalImponible,
      'Viáticos (No Imponible)': viaticosTotales,
      'Total Haberes': totalHaberes,
      'AFP': descuentoAFP,
      'Salud': descuentoSalud,
      'Seguro Cesantía (Trabajador)': descuentoCesantia,
      'Total Descuentos': totalDescuentos,
      'Sueldo Líquido': liquidoAPago,
      'Base Imponible Usada': baseParaLeyesSociales,
    };
  }

  /// Calcula el resumen financiero consolidado para la empresa con análisis tributario F29.
  static Map<String, double> calculateCompanySummary({
    required List<UserModel> allDrivers,
    required List<TripModel> monthlyTrips,
    required List<dynamic> directExpenses,
    required CompanyConfigModel config,
    double? customUtmValue,
    double? customDieselValue,
  }) {
    double totalMontoDieselBruto = 0;
    double litrosDieselTotal = 0;
    for (final expense in directExpenses) {
      if (expense.type.toLowerCase() == 'combustible') {
        totalMontoDieselBruto += expense.amount;
        litrosDieselTotal += (expense.litros ?? 0.0);
      }
    }
    
    double precioDieselNetoCalculado = litrosDieselTotal > 0 
        ? (totalMontoDieselBruto / 1.19) / litrosDieselTotal 
        : config.precioDieselNeto;

    final precioDieselNetoFinal = customDieselValue ?? precioDieselNetoCalculado;

    double totalIngresosNetos = 0;
    double totalKmFlota = 0;
    for (final trip in monthlyTrips) {
      totalIngresosNetos += trip.value;
      totalKmFlota += (trip.totalKm ?? 0);
    }
    double ivaDebito = totalIngresosNetos * 0.19;

    double costoMantenimientoPorKm = 0.0;
    for (var rule in config.maintenanceRules) {
      final cost = (rule['cost'] as num?)?.toDouble() ?? 0;
      final km = (rule['km'] as num?)?.toDouble() ?? 1;
      if (km > 0) costoMantenimientoPorKm += (cost / km);
    }
    double provisionMantenimiento = totalKmFlota * costoMantenimientoPorKm;

    double totalGastosBrutos = 0;
    double totalGastosNetos = 0;
    double totalIvaCredito = 0;
    double litrosDieselReales = 0;

    for (final expense in directExpenses) {
      final typeLower = expense.type.toLowerCase();
      final isMaintenance = typeLower.contains('manten');

      double neto = expense.amount / 1.19;
      double iva = expense.amount - neto;
      
      if (typeLower == 'peaje') {
        neto = expense.amount;
        iva = 0;
      }
      
      // El IVA siempre se recupera, sin importar si es mantención real o no.
      totalIvaCredito += iva;

      // Solo los gastos NO relacionados a mantenimiento suman al flujo operativo directo, 
      // porque el mantenimiento se manejará por provisión.
      if (!isMaintenance) {
        totalGastosBrutos += expense.amount;
        totalGastosNetos += neto;
      }

      if (typeLower == 'combustible') {
        litrosDieselReales += (expense.litros ?? 0.0);
      }
    }

    // Integramos la Provisión de Mantenimiento al Gasto Operativo (Ahorro Inconsciente)
    totalGastosNetos += provisionMantenimiento;
    totalGastosBrutos += provisionMantenimiento;

    double totalCostosPersonal = 0;
    for (final driver in allDrivers) {
      if (driver.rol == 'CHOFER') {
        final driverTrips = monthlyTrips.where((t) => t.idChofer == driver.uid).toList();
        totalCostosPersonal += calculateMonthlyEmployerCost(
          driver: driver,
          config: config,
          monthlyTrips: driverTrips,
        );
      }
    }

    final utmToUse = customUtmValue ?? config.valorUTM;
    final recuperacionDiesel = litrosDieselReales * (1.5 * utmToUse / 1000);

    final ivaNetoPagar = ivaDebito - totalIvaCredito - recuperacionDiesel;

    final resultadoOperacional = totalIngresosNetos - totalGastosNetos - totalCostosPersonal;
    final flujoCajaReal = resultadoOperacional - ivaNetoPagar;
    final margenOperacional = totalIngresosNetos > 0 ? (resultadoOperacional / totalIngresosNetos) * 100 : 0.0;
    final margenNetoCaja = totalIngresosNetos > 0 ? (flujoCajaReal / totalIngresosNetos) * 100 : 0.0;

    return {
      'ingresosNetos': totalIngresosNetos,
      'ivaDebito': ivaDebito,
      'gastosBrutos': totalGastosBrutos,
      'gastosNetos': totalGastosNetos,
      'ivaCredito': totalIvaCredito,
      'litrosDiesel': litrosDieselReales,
      'recuperacionDiesel': recuperacionDiesel,
      'costosPersonal': totalCostosPersonal,
      'ivaNetoPagar': ivaNetoPagar,
      'resultadoOperacional': resultadoOperacional,
      'flujoCajaReal': flujoCajaReal,
      'margenOperacional': margenOperacional,
      'margenNetoCaja': margenNetoCaja,
      'precioDieselNeto': precioDieselNetoFinal,
      'precioDieselCalculado': precioDieselNetoCalculado,
      'ingresos': totalIngresosNetos,
      'gastoTotalReal': totalGastosBrutos + totalCostosPersonal,
      'utilidadReal': resultadoOperacional,
    };
  }

  /// Calcula la rentabilidad desglosada por ruta con desglose quirúrgico de costos.
  static List<RouteProfitability> calculateRouteProfitability({
    required List<TripModel> allTrips,
    required List<ExpenseModel> allExpenses,
    required List<UserModel> allDrivers,
    required CompanyConfigModel config,
  }) {
    if (allTrips.isEmpty) return [];

    final Map<String, double> vehicleTotalKm = {};
    final Map<String, double> vehicleDieselCost = {};
    final Map<String, double> vehicleGenericTollsCost = {}; 
    final Map<String, double> directTripTolls = {};

    for (final trip in allTrips) {
      final vid = trip.vehicleId ?? 'N/A';
      vehicleTotalKm[vid] = (vehicleTotalKm[vid] ?? 0) + (trip.totalKm ?? 0);
    }

    for (final exp in allExpenses) {
      final vid = exp.vehicleId ?? 'N/A';
      final typeLower = exp.type.toLowerCase();
      if (typeLower == 'combustible') {
        vehicleDieselCost[vid] = (vehicleDieselCost[vid] ?? 0) + exp.amount;
      } else if (typeLower == 'peaje') {
        if (exp.tripId != null && exp.tripId!.isNotEmpty) {
          directTripTolls[exp.tripId!] = (directTripTolls[exp.tripId!] ?? 0) + exp.amount;
        } else {
          vehicleGenericTollsCost[vid] = (vehicleGenericTollsCost[vid] ?? 0) + exp.amount;
        }
      }
    }

    final Map<String, double> driverDailyValue = {};
    final Map<String, int> tripsPerDriverDay = {};
    final Map<String, double> tripViaticos = {};

    for (final driver in allDrivers) {
      if (driver.rol == 'CHOFER') {
        final driverTrips = allTrips.where((t) => t.idChofer == driver.uid).toList();
        
        final Set<String> uniqueDays = {};
        for (final t in driverTrips) {
          DateTime current = t.startDate;
          while (true) {
            final dayKey = "${driver.uid}_${current.year}-${current.month}-${current.day}";
            uniqueDays.add(dayKey);
            tripsPerDriverDay[dayKey] = (tripsPerDriverDay[dayKey] ?? 0) + 1;
            
            final endD = t.endDate ?? t.startDate;
            if (current.year == endD.year && current.month == endD.month && current.day == endD.day) break;
            current = current.add(const Duration(days: 1));
          }
        }
        
        double totalViaticos = 0;
        if (config.tipoViatico == 'POR_VIAJE') {
          for (final t in driverTrips) {
            final v = ((t.totalKm ?? 0) >= config.umbralKilometrosViatico) ? (driver.montoViaticoLargo ?? 10000) : (driver.montoViaticoLocal ?? 6500);
            tripViaticos[t.id] = v;
            totalViaticos += v;
          }
        } else {
          final Map<String, List<TripModel>> tripsByDay = {};
          for (final t in driverTrips) {
            final dayKey = '${t.startDate.year}-${t.startDate.month}-${t.startDate.day}';
            tripsByDay.putIfAbsent(dayKey, () => []).add(t);
          }
          for (final dayTrips in tripsByDay.values) {
            bool existsLongTrip = dayTrips.any((t) => (t.totalKm ?? 0.0) >= config.umbralKilometrosViatico);
            final dayV = existsLongTrip ? (driver.montoViaticoLargo ?? 10000) : (driver.montoViaticoLocal ?? 6500);
            totalViaticos += dayV;
            for (final t in dayTrips) {
               tripViaticos[t.id] = dayV / dayTrips.length;
            }
          }
        }
        
        final totalUniqueDays = uniqueDays.length;
        final dMonthlyCost = calculateMonthlyEmployerCost(driver: driver, config: config, monthlyTrips: driverTrips);
        
        double totalComisiones = 0;
        for (final t in driverTrips) {
          totalComisiones += t.value * (config.porcentajeComision / 100);
        }
        
        double fixedCost = dMonthlyCost - totalComisiones - totalViaticos;
        
        driverDailyValue[driver.uid] = totalUniqueDays > 0 ? (fixedCost / totalUniqueDays) : fixedCost;
      }
    }

    double costoMantenimientoPorKm = 0.0;
    for (var rule in config.maintenanceRules) {
      final cost = (rule['cost'] as num?)?.toDouble() ?? 0;
      final km = (rule['km'] as num?)?.toDouble() ?? 1;
      if (km > 0) costoMantenimientoPorKm += (cost / km);
    }

    final Map<String, List<Map<String, double>>> routeStats = {};

    for (final trip in allTrips) {
      final routeKey = '${trip.origin} -> ${trip.destination}';
      final vid = trip.vehicleId ?? 'N/A';
      final tripKm = trip.totalKm ?? 0;
      
      final truckTotalKm = vehicleTotalKm[vid] ?? 0;
      double fuelCost = 0;
      if (truckTotalKm > 0) {
        fuelCost = ((vehicleDieselCost[vid] ?? 0) / truckTotalKm) * tripKm;
      }

      double tollsCost = 0;
      tollsCost += (directTripTolls[trip.id] ?? 0);
      if (truckTotalKm > 0) {
        tollsCost += ((vehicleGenericTollsCost[vid] ?? 0) / truckTotalKm) * tripKm;
      }

      // A) Costo Fijo (Valor Día Exacto)
      double baseSalaryCost = 0;
      DateTime current = trip.startDate;
      while (true) {
        final dayKey = "${trip.idChofer}_${current.year}-${current.month}-${current.day}";
        final tripsOnThisDay = tripsPerDriverDay[dayKey] ?? 1;
        baseSalaryCost += (driverDailyValue[trip.idChofer] ?? 0) / tripsOnThisDay;
        
        final endD = trip.endDate ?? trip.startDate;
        if (current.year == endD.year && current.month == endD.month && current.day == endD.day) break;
        current = current.add(const Duration(days: 1));
      }

      // B) Costo Variable (Comisión por Facturación)
      double commissionCost = trip.value * (config.porcentajeComision / 100);

      // C) Viáticos
      double viatico = tripViaticos[trip.id] ?? 0.0;

      double personalCost = baseSalaryCost + commissionCost;
      double maintenanceCost = tripKm * costoMantenimientoPorKm;

      routeStats.putIfAbsent(routeKey, () => []).add({
        'income': trip.value,
        'fuel': fuelCost / 1.19,
        'tolls': tollsCost,
        'viatico': viatico,
        'personal': personalCost,
        'maintenance': maintenanceCost,
        'km': tripKm,
      });
    }

    final List<RouteProfitability> results = [];
    routeStats.forEach((route, trips) {
      double totalIncome = 0;
      double totalFuel = 0;
      double totalTolls = 0;
      double totalViaticos = 0;
      double totalPersonal = 0;
      double totalMaintenance = 0;
      double totalKm = 0;

      for (final t in trips) {
        totalIncome += t['income']!;
        totalFuel += t['fuel']!;
        totalTolls += t['tolls']!;
        totalViaticos += t['viatico']!;
        totalPersonal += t['personal']!;
        totalMaintenance += t['maintenance']!;
        totalKm += t['km'] ?? 0;
      }

      final netMargin = totalIncome - totalFuel - totalTolls - totalViaticos - totalPersonal - totalMaintenance;
      final marginPct = totalIncome > 0 ? (netMargin / totalIncome) * 100 : 0.0;

      results.add(RouteProfitability(
        route: route,
        tripCount: trips.length,
        totalKm: totalKm,
        totalIncome: totalIncome,
        totalFuelCost: totalFuel,
        totalTolls: totalTolls,
        totalViaticos: totalViaticos,
        totalPersonal: totalPersonal,
        totalMaintenance: totalMaintenance,
        netMargin: netMargin,
        marginPercentage: marginPct,
      ));
    });

    results.sort((a, b) => b.netMargin.compareTo(a.netMargin));
    return results;
  }
}
