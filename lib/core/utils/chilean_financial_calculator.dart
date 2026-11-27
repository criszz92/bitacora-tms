import '../../features/auth/domain/models/user_model.dart';
import '../../features/admin/domain/models/company_config_model.dart';
import '../../features/trips/domain/models/trip_model.dart';
import '../../features/admin/domain/models/analytics_models.dart';
import '../../features/trips/domain/models/expense_model.dart';
import '../../features/trips/domain/models/vehicle_model.dart';
import 'tms_backbone.dart';

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
      if (trip.idChofer == driver.uid && trip.isOperativo) {
        final facturable = trip.value + (trip.extraCostos ?? 0) + (trip.sobreEstadia ?? 0);
        comision += facturable * (config.porcentajeComision / 100);
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

    // 5. Viáticos (solo para viajes con ganancia/operativos)
    double viaticosTotales = 0;
    if (config.tipoViatico == 'POR_VIAJE') {
      for (final trip in monthlyTrips) {
        if (trip.idChofer == driver.uid && trip.isOperativo) {
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
        if (trip.idChofer == driver.uid && trip.isOperativo) {
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

    // 1. Comisión (incluye extraCostos y sobreEstadia)
    double comision = 0;
    for (final trip in monthlyTrips) {
      if (trip.idChofer == driver.uid) {
        comision += TmsBackbone.tripCommissionableAmount(trip) * (config.porcentajeComision / 100);
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
      final driverTrips = monthlyTrips.where((t) => t.idChofer == driver.uid).toList();
      viaticosTotales = TmsBackbone.calculateTripsViaticos(
        trips: driverTrips,
        driver: driver,
        config: config,
      ).total;
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

  /// Calcula el resumen financiero consolidado para la empresa con análisis tributario F29 y Fuente de Verdad.
  static Map<String, double> calculateCompanySummary({
    required List<UserModel> allDrivers,
    required List<TripModel> monthlyTrips,
    required List<dynamic> directExpenses,
    required CompanyConfigModel config,
    List<VehicleModel>? vehicles,
    double? customUtmValue,
    double? customDieselValue,
    double? customRemanenteAnterior,
  }) {
    // 1. Ingresos Operacionales Netos (Facturación pura de viajes, sin IVA)
    double totalIngresosNetos = 0;
    double totalKmFlota = 0;
    final Map<String, double> kmPorVehiculo = {};

    for (final trip in monthlyTrips) {
      if (trip.isOperativo) {
        totalIngresosNetos += trip.value + (trip.extraCostos ?? 0) + (trip.sobreEstadia ?? 0);
      }
      final km = (trip.totalKm ?? 0);
      totalKmFlota += km;
      if (trip.vehicleId != null) {
        kmPorVehiculo[trip.vehicleId!] = (kmPorVehiculo[trip.vehicleId!] ?? 0) + km;
      }
    }

    final double ivaDebito = totalIngresosNetos * 0.19;

    // 2. Mantenimiento Teórico según KM (Personalizado por camión o global)
    double costoGlobalMantenimientoPorKm = 0.0;
    for (var rule in config.maintenanceRules) {
      final cost = (rule['cost'] as num?)?.toDouble() ?? 0;
      final km = (rule['km'] as num?)?.toDouble() ?? 1;
      if (km > 0) costoGlobalMantenimientoPorKm += (cost / km);
    }

    double provisionMantenimientoTeorica = 0.0;
    if (vehicles != null && vehicles.isNotEmpty) {
      for (final v in vehicles) {
        final kmUnidad = kmPorVehiculo[v.id] ?? kmPorVehiculo[v.patente] ?? 0.0;
        final costoKm = v.costoMantenimientoPorKm ?? costoGlobalMantenimientoPorKm;
        provisionMantenimientoTeorica += (kmUnidad * costoKm);
      }
    } else {
      provisionMantenimientoTeorica = totalKmFlota * costoGlobalMantenimientoPorKm;
    }

    // 3. Gastos Reales Pagados y Desglose Tributario Quirúrgico
    double totalDesembolsoGastosBrutos = 0;
    double totalGastosOperativosNetos = 0;
    double totalIvaCreditoGastos = 0;
    double litrosDieselReales = 0;
    double totalGastosRealesMantenimiento = 0;
    double totalPeajesExentos = 0;

    for (final expense in directExpenses) {
      final amount = (expense.amount as num).toDouble();
      final typeLower = (expense.type as String).toLowerCase();
      final bool isExento = (expense.isExento as bool?) ?? (typeLower == 'peaje');
      final isMaintenance = typeLower.contains('manten') || typeLower.contains('taller') || typeLower.contains('repuesto');

      totalDesembolsoGastosBrutos += amount;

      if (isMaintenance) {
        totalGastosRealesMantenimiento += amount;
      }

      final isActivoFijo = typeLower.contains('activo') || typeLower.contains('inversión') || typeLower.contains('inversion') || typeLower.contains('equipo');

      if (isActivoFijo) {
        // ACTIVO FIJO (ej. Compra de Camión \):
        // NO destruye el resultado operacional/EBITDA mensual, pero aporta el 100% de su IVA Crédito al F29.
        if (!isExento) {
          final neto = amount / 1.19;
          final iva = amount - neto;
          totalIvaCreditoGastos += iva;
        }
      } else if (typeLower == 'peaje' || isExento) {
        totalGastosOperativosNetos += amount;
        if (typeLower == 'peaje') totalPeajesExentos += amount;
      } else if (typeLower == 'combustible') {
        final lts = (expense.litros as num?)?.toDouble() ?? 0.0;
        litrosDieselReales += lts;

        double ivaRealCombustible = (expense.customIva as num?)?.toDouble() ?? 0.0;
        if (ivaRealCombustible <= 0) {
          final netoEst = amount / 1.19;
          ivaRealCombustible = amount - netoEst;
          totalGastosOperativosNetos += netoEst;
        } else {
          totalGastosOperativosNetos += (amount - ivaRealCombustible);
        }
        totalIvaCreditoGastos += ivaRealCombustible;
      } else {
        final neto = amount / 1.19;
        final iva = amount - neto;
        totalGastosOperativosNetos += neto;
        totalIvaCreditoGastos += iva;
      }
    }

    // 4. Costos de Personal
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

    // 5. Ley 19.764: Beneficio Diésel
    final utmToUse = customUtmValue ?? config.valorUTM;
    final porcentajeRecup = config.porcentajeRecuperacionIepd > 0 ? (config.porcentajeRecuperacionIepd / 100.0) : 0.80;
    final recuperacionDiesel = litrosDieselReales * (1.5 * utmToUse / 1000.0) * porcentajeRecup;

    // 6. Liquidación Tributaria F29 (Fuente de Verdad SII)
    final double ppmObligatorio = totalIngresosNetos * (config.tasaPPM / 100.0);
    final double remanenteAnterior = customRemanenteAnterior ?? config.remanenteCreditoFiscalAcumulado;
    final double balanceIva = ivaDebito - totalIvaCreditoGastos - recuperacionDiesel - remanenteAnterior;

    double ivaAPagarFinal = 0.0;
    double nuevoRemanenteFavor = 0.0;

    if (balanceIva > 0) {
      ivaAPagarFinal = balanceIva;
      nuevoRemanenteFavor = 0.0;
    } else {
      ivaAPagarFinal = 0.0;
      nuevoRemanenteFavor = balanceIva.abs();
    }

    final double totalF29Pagar = ivaAPagarFinal + ppmObligatorio;

    // 7. Bloques Ejecutivos
    final double resultadoOperacionalNeto = totalIngresosNetos - totalGastosOperativosNetos - totalCostosPersonal;
    final double margenOperacionalPct = totalIngresosNetos > 0 ? (resultadoOperacionalNeto / totalIngresosNetos) * 100 : 0.0;

    final double totalIngresosBrutosCobrados = totalIngresosNetos * 1.19;
    // Caja con IVA (Bruta): Se cobra con IVA y se paga F29 (incluye el IVA débito neto y PPM)
    final double flujoCajaRealBolsillo = totalIngresosBrutosCobrados - totalDesembolsoGastosBrutos - totalCostosPersonal - totalF29Pagar;
    final double margenNetoCajaPct = totalIngresosBrutosCobrados > 0 ? (flujoCajaRealBolsillo / totalIngresosBrutosCobrados) * 100 : 0.0;

    // Caja SIN IVA (Pura Operación / Exenta de distorsión IVA):
    // Ingresos Netos - Gastos Operacionales Netos - Costos Personal - PPM
    final double flujoCajaSinIva = totalIngresosNetos - totalGastosOperativosNetos - totalCostosPersonal - ppmObligatorio;
    final double margenCajaSinIvaPct = totalIngresosNetos > 0 ? (flujoCajaSinIva / totalIngresosNetos) * 100 : 0.0;

    final double saldoFondoMantenimiento = provisionMantenimientoTeorica - totalGastosRealesMantenimiento;

    return {
      'ingresosNetos': totalIngresosNetos,
      'gastosNetos': totalGastosOperativosNetos,
      'costosPersonal': totalCostosPersonal,
      'resultadoOperacional': resultadoOperacionalNeto,
      'margenOperacional': margenOperacionalPct,
      'ivaDebito': ivaDebito,
      'ivaCredito': totalIvaCreditoGastos,
      'recuperacionDiesel': recuperacionDiesel,
      'remanenteAnterior': remanenteAnterior,
      'nuevoRemanenteFavor': nuevoRemanenteFavor,
      'ppmObligatorio': ppmObligatorio,
      'ivaNetoPagar': ivaAPagarFinal,
      'totalF29Pagar': totalF29Pagar,
      'ingresosBrutos': totalIngresosBrutosCobrados,
      'gastosBrutos': totalDesembolsoGastosBrutos,
      'flujoCajaReal': flujoCajaRealBolsillo,
      'margenNetoCaja': margenNetoCajaPct,
      'flujoCajaSinIva': flujoCajaSinIva,
      'margenCajaSinIva': margenCajaSinIvaPct,
      'mantenimientoTeoricoKm': provisionMantenimientoTeorica,
      'mantenimientoRealEjecutado': totalGastosRealesMantenimiento,
      'saldoFondoMantenimiento': saldoFondoMantenimiento,
      'costoMantenimientoPorKmGlobal': costoGlobalMantenimientoPorKm,
      'litrosDiesel': litrosDieselReales,
      'totalPeajesExentos': totalPeajesExentos,
      'totalKmFlota': totalKmFlota,
      'precioDieselNeto': customDieselValue ?? config.precioDieselNeto,
      'ingresos': totalIngresosNetos,
      'gastoTotalReal': totalDesembolsoGastosBrutos + totalCostosPersonal,
      'utilidadReal': resultadoOperacionalNeto,
    };
  }

  /// Calcula la rentabilidad desglosada por ruta con desglose quirúrgico de costos.
  static List<RouteProfitability> calculateRouteProfitability({
    required List<TripModel> allTrips,
    required List<ExpenseModel> allExpenses,
    required List<UserModel> allDrivers,
    required CompanyConfigModel config,
    List<VehicleModel> vehicles = const [],
  }) {
    if (allTrips.isEmpty) return [];

    final Map<String, double> vehicleTotalKm = {};
    final Map<String, double> vehicleDieselNetCost = {};
    final Map<String, double> vehicleGenericTollsCost = {}; 
    final Map<String, double> directTripTolls = {};

    for (final trip in allTrips) {
      final vid = TmsBackbone.canonicalVehicleKey(trip.vehicleId, vehicles);
      vehicleTotalKm[vid] = (vehicleTotalKm[vid] ?? 0) + (trip.totalKm ?? 0);
    }

    for (final exp in allExpenses) {
      final vid = TmsBackbone.canonicalVehicleKey(exp.vehicleId, vehicles);
      final typeLower = exp.type.toLowerCase();
      if (typeLower == 'combustible') {
        final double netAmount;
        if (exp.isExento) {
          netAmount = exp.amount;
        } else if (exp.customIva != null && exp.customIva! > 0) {
          netAmount = (exp.amount - exp.customIva!).clamp(0.0, exp.amount);
        } else {
          netAmount = exp.amount / 1.19;
        }
        vehicleDieselNetCost[vid] = (vehicleDieselNetCost[vid] ?? 0) + netAmount;
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
            if (t.isOperativo) {
              final v = ((t.totalKm ?? 0) >= config.umbralKilometrosViatico) ? (driver.montoViaticoLargo ?? 10000) : (driver.montoViaticoLocal ?? 6500);
              tripViaticos[t.id] = v;
              totalViaticos += v;
            } else {
              tripViaticos[t.id] = 0.0;
            }
          }
        } else {
          final Map<String, List<TripModel>> tripsByDay = {};
          for (final t in driverTrips) {
            if (t.isOperativo) {
              final dayKey = '${t.startDate.year}-${t.startDate.month}-${t.startDate.day}';
              tripsByDay.putIfAbsent(dayKey, () => []).add(t);
            } else {
              tripViaticos[t.id] = 0.0;
            }
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
          if (t.isOperativo) {
            final facturable = t.value + (t.extraCostos ?? 0) + (t.sobreEstadia ?? 0);
            totalComisiones += facturable * (config.porcentajeComision / 100);
          }
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
      final routeKey = TmsBackbone.canonicalRoute(trip);
      final vid = TmsBackbone.canonicalVehicleKey(trip.vehicleId, vehicles);
      final matchedVehicle = TmsBackbone.findVehicle(trip.vehicleId, vehicles);
      final tripKm = trip.totalKm ?? 0;
      
      final truckTotalKm = vehicleTotalKm[vid] ?? 0;
      double fuelNetCost = 0;
      if (truckTotalKm > 0) {
        fuelNetCost = ((vehicleDieselNetCost[vid] ?? 0) / truckTotalKm) * tripKm;
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

      // B) Costo Variable (Comisión por Facturación - 0 si no es operativo)
      final facturable = trip.isOperativo ? (trip.value + (trip.extraCostos ?? 0) + (trip.sobreEstadia ?? 0)) : 0.0;
      double commissionCost = facturable * (config.porcentajeComision / 100);

      // C) Viáticos (0 si no es operativo)
      double viatico = tripViaticos[trip.id] ?? 0.0;

      double personalCost = baseSalaryCost + commissionCost;
      final effectiveMaintPerKm = matchedVehicle?.costoMantenimientoPorKm ?? costoMantenimientoPorKm;
      double maintenanceCost = tripKm * effectiveMaintPerKm;

      final facturableTotal = trip.isOperativo ? (trip.value + (trip.extraCostos ?? 0) + (trip.sobreEstadia ?? 0)) : 0.0;
      routeStats.putIfAbsent(routeKey, () => []).add({
        'income': facturableTotal,
        'fuel': fuelNetCost,
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

  /// Calcula en tiempo real si un servicio de transporte propuesto es rentable,
  /// mostrando un desglose quirúrgico de costos y el margen neto real "al bolsillo".
  static Map<String, double> calculateTripQuote({
    required UserModel driver,
    required VehicleModel vehicle,
    required CompanyConfigModel config,
    required double kmPosicionamiento,
    required double kmRuta,
    required double tarifaPropuesta,
    required double precioDieselNeto,
    required double peajes,
    required double viaticoManual,
    required int diasViaje,
    required double margenObjetivo, // porcentaje, ej. 25.0
    bool idaYVuelta = false,
    double? customUtmValue,
  }) {
    // 1. KM total
    final double kmRutaEfectivo = idaYVuelta ? (kmRuta * 2) : kmRuta;
    final double kmTotal = kmPosicionamiento + kmRutaEfectivo;

    // Peajes efectivos
    final double peajesEfectivo = idaYVuelta ? (peajes * 2) : peajes;

    // 2. Combustible
    final double rendimiento = vehicle.rendimientoKmPorLitro;
    final double litrosConsumidos = rendimiento > 0 ? (kmTotal / rendimiento) : 0;
    final double combustibleNeto = litrosConsumidos * precioDieselNeto;
    final double combustibleBruto = combustibleNeto * 1.19;
    final double creditoIvaCombustible = combustibleBruto - combustibleNeto;

    // 3. IVA Débito sobre la tarifa
    final double ivaDebito = tarifaPropuesta * 0.19;

    // 4. Comisión del chofer
    final double comision = tarifaPropuesta * (config.porcentajeComision / 100);

    // 5. Mantenimiento (Usa el costo personalizado del camión si existe, sino el global)
    double costoMantenimientoPorKm = vehicle.costoMantenimientoPorKm ?? 0.0;
    if (costoMantenimientoPorKm <= 0) {
      for (var rule in config.maintenanceRules) {
        final cost = (rule['cost'] as num?)?.toDouble() ?? 0;
        final km = (rule['km'] as num?)?.toDouble() ?? 1;
        if (km > 0) costoMantenimientoPorKm += (cost / km);
      }
    }
    final double mantenimiento = kmTotal * costoMantenimientoPorKm;

    // 6. Costo fijo del chofer (prorrateo diario)
    final double costoMensualFijo = calculateMonthlyEmployerCost(
      driver: driver,
      config: config,
      monthlyTrips: [],
    );
    final double costoFijoDiario = config.diasLaboralesMes > 0 
        ? costoMensualFijo / config.diasLaboralesMes 
        : 0;
    final double costoFijoChofer = costoFijoDiario * diasViaje;

    // 7. Recuperación Ley 19.764 (Aplica el porcentaje de recuperación legal según tramo anual de ventas en UTM)
    final double utmToUse = customUtmValue ?? config.valorUTM;
    final double pctRecup = (config.porcentajeRecuperacionIepd > 0) 
        ? (config.porcentajeRecuperacionIepd / 100.0) 
        : 0.80;
    final double recuperacionLey19764 = litrosConsumidos * (1.5 * utmToUse / 1000.0) * pctRecup;

    // 8. Costo total real (suma de todos los costos operativos)
    final double costoTotalReal = combustibleNeto +
        peajesEfectivo +
        comision +
        viaticoManual +
        mantenimiento +
        costoFijoChofer;

    // 9. Margen Neto Real (El crédito tributario Ley 19.764 alivia directamente la caja fiscal de combustible)
    final double costoEfectivoCombustible = (combustibleNeto - recuperacionLey19764).clamp(0.0, double.infinity);
    final double costoOperativoEfectivo = costoEfectivoCombustible +
        peajesEfectivo +
        comision +
        viaticoManual +
        mantenimiento +
        costoFijoChofer;
    final double margenNetoReal = tarifaPropuesta - costoOperativoEfectivo;

    // 10. Indicadores
    final double margenPorcentaje = tarifaPropuesta > 0 
        ? (margenNetoReal / tarifaPropuesta) * 100 
        : 0;
    final double cpk = kmTotal > 0 ? (tarifaPropuesta / kmTotal) : 0;

    // 11. Tarifa mínima sugerida para alcanzar el margen objetivo
    final double tarifaMinimaSugerida = (margenObjetivo < 100)
        ? costoTotalReal / (1 - margenObjetivo / 100)
        : costoTotalReal;

    return {
      'kmTotal': kmTotal,
      'litrosConsumidos': litrosConsumidos,
      'combustibleNeto': combustibleNeto,
      'combustibleBruto': combustibleBruto,
      'creditoIvaCombustible': creditoIvaCombustible,
      'ivaDebito': ivaDebito,
      'comision': comision,
      'mantenimiento': mantenimiento,
      'costoFijoChofer': costoFijoChofer,
      'recuperacionLey19764': recuperacionLey19764,
      'costoTotalReal': costoTotalReal,
      'margenNetoReal': margenNetoReal,
      'margenPorcentaje': margenPorcentaje,
      'cpk': cpk,
      'tarifaMinimaSugerida': tarifaMinimaSugerida,
    };
  }
}
