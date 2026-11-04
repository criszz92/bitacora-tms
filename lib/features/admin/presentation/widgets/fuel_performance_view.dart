import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bitacora/features/admin/presentation/providers/admin_provider.dart';
import 'package:bitacora/features/trips/domain/models/vehicle_model.dart';
import 'package:bitacora/features/trips/domain/models/expense_model.dart';
import 'package:bitacora/features/admin/domain/services/fuel_performance_service.dart';
import 'package:bitacora/core/utils/number_utils.dart';

class FuelPerformanceView extends ConsumerStatefulWidget {
  const FuelPerformanceView({super.key});

  @override
  ConsumerState<FuelPerformanceView> createState() => _FuelPerformanceViewState();
}

class _FuelPerformanceViewState extends ConsumerState<FuelPerformanceView> {
  String? _selectedVehicleId; // null = Flota Completa

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final expensesAsync = ref.watch(monthlyExpensesProvider);
    final configAsync = ref.watch(companyConfigProvider);

    final vehicles = vehiclesAsync.value ?? [];
    final allExpenses = expensesAsync.value ?? [];
    final config = configAsync.value;
    final dieselPrice = config?.precioDieselNeto ?? 1050.0;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER & SELECTOR DE UNIDAD / FLOTA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_gas_station, color: Colors.greenAccent, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'Rendimiento & Estanque Digital',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Monitoreo quirúrgico de combustible, autonomía y equipos de refrigeración auxiliar.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
                // Selector Unidad vs Flota
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedVehicleId,
                      dropdownColor: const Color(0xFF1E1E1E),
                      hint: const Text('🌟 Toda la Flota (Consolidado)', style: TextStyle(color: Colors.white)),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('🌟 Toda la Flota (Consolidado)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        ...vehicles.map((v) => DropdownMenuItem<String?>(
                              value: v.id,
                              child: Text('${v.patente} · ${v.marca ?? ''} ${v.modelo ?? ''}', style: const TextStyle(color: Colors.white)),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedVehicleId = val);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // CONTENIDO PRINCIPAL
            Expanded(
              child: _selectedVehicleId == null
                  ? _buildFleetSummaryView(vehicles, allExpenses, dieselPrice)
                  : _buildSingleVehicleView(
                      vehicles.firstWhere((v) => v.id == _selectedVehicleId, orElse: () => vehicles.first),
                      allExpenses,
                      dieselPrice,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// VISTA 1: TODA LA FLOTA CONSOLIDADA
  Widget _buildFleetSummaryView(
    List<VehicleModel> vehicles,
    List<ExpenseModel> allExpenses,
    double dieselPrice,
  ) {
    final summary = FuelPerformanceService.calculateFleetSummary(
      vehicles: vehicles,
      allExpenses: allExpenses,
      currentDieselNeto: dieselPrice,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TARJETAS KPIS SUPERIORES
          Row(
            children: [
              _buildKpiCard(
                title: 'PETRÓLEO EN ESTANQUES',
                value: '\$ ${NumberUtils.formatCurrency(summary.totalMoneyInTanksClp)}',
                subtitle: '${summary.totalFleetCurrentLitros.toStringAsFixed(0)} Litros activos en la calle',
                icon: Icons.savings_outlined,
                color: Colors.greenAccent,
              ),
              const SizedBox(width: 16),
              _buildKpiCard(
                title: 'NIVEL PROMEDIO FLOTA',
                value: '${summary.fleetAveragePercentage.toStringAsFixed(1)}%',
                subtitle: 'Capacidad total: ${summary.totalFleetCapacityLitros.toStringAsFixed(0)} Lts',
                icon: Icons.speed,
                color: summary.fleetAveragePercentage < 30 ? Colors.redAccent : Colors.cyanAccent,
              ),
              const SizedBox(width: 16),
              _buildKpiCard(
                title: 'DÉFICIT PARA 100% FLOTA',
                value: '\$ ${NumberUtils.formatCurrency(summary.moneyNeededToFullClp)}',
                subtitle: 'Faltan ${summary.litersToFullFleet.toStringAsFixed(0)} Lts para llenar todo',
                icon: Icons.local_gas_station,
                color: Colors.orangeAccent,
              ),
              const SizedBox(width: 16),
              _buildKpiCard(
                title: 'ALERTAS DE RESERVA',
                value: '${summary.lowFuelAlertsCount}',
                subtitle: summary.lowFuelAlertsCount > 0 ? 'Unidades en zona de riesgo' : 'Flota con combustible óptimo',
                icon: Icons.warning_amber_rounded,
                color: summary.lowFuelAlertsCount > 0 ? Colors.redAccent : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // TABLA RESUMEN POR CAMIÓN
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estado del Estanque por Unidad & Auxiliares',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: vehicles.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                  itemBuilder: (ctx, i) {
                    final v = vehicles[i];
                    final vExpenses = allExpenses.where((e) => e.vehicleId == v.id || e.vehicleId == v.patente).toList();
                    final tank = FuelPerformanceService.calculateVehicleTankState(
                      vehicle: v,
                      vehicleExpenses: vExpenses,
                      currentOdometer: v.currentOdometer,
                      currentDieselNeto: dieselPrice,
                    );

                    return InkWell(
                      onTap: () => setState(() => _selectedVehicleId = v.id),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                v.patente,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${v.marca ?? ''} ${v.modelo ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                  Text(
                                    v.tieneEquipoAuxiliar
                                        ? '❄️ Aux: ${v.identificadorAuxiliar ?? 'Thermo'} | Ralentí: ${v.consumoRalentiLitrosHora.toStringAsFixed(1)} L/h'
                                        : 'Ralentí: ${v.consumoRalentiLitrosHora.toStringAsFixed(1)} L/h (Alerta >${v.maxMinutosRalentiAlerta}m)',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        tank.isCalibrated
                                            ? '${tank.currentLitros.toStringAsFixed(0)} / ${tank.capacityLitros.toStringAsFixed(0)} Lts'
                                            : 'Requiere Calibración',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: tank.isCalibrated ? Colors.white : Colors.orangeAccent,
                                        ),
                                      ),
                                      if (tank.isCalibrated)
                                        Text('${tank.percentage.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: tank.isCalibrated ? (tank.percentage / 100.0).clamp(0.0, 1.0) : 0.05,
                                      backgroundColor: Colors.white12,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        !tank.isCalibrated
                                            ? Colors.orangeAccent
                                            : tank.percentage < 25
                                                ? Colors.redAccent
                                                : tank.percentage < 50
                                                    ? Colors.amber
                                                    : Colors.greenAccent,
                                      ),
                                      minHeight: 8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    tank.isCalibrated ? '~${tank.estimatedAutonomyKm.toStringAsFixed(0)} KM' : '--',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent, fontSize: 15),
                                  ),
                                  const Text('Autonomía Est.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Icon(Icons.chevron_right, color: Colors.white24),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// VISTA 2: DETALLE QUIRÚRGICO DE UN CAMIÓN ESPECÍFICO
  Widget _buildSingleVehicleView(
    VehicleModel vehicle,
    List<ExpenseModel> allExpenses,
    double dieselPrice,
  ) {
    final vExpenses = allExpenses.where((e) => e.vehicleId == vehicle.id || e.vehicleId == vehicle.patente).toList();
    final tank = FuelPerformanceService.calculateVehicleTankState(
      vehicle: vehicle,
      vehicleExpenses: vExpenses,
      currentOdometer: vehicle.currentOdometer,
      currentDieselNeto: dieselPrice,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ESTANQUE DIGITAL PRINCIPAL
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.local_shipping, color: Colors.white, size: 24),
                              const SizedBox(width: 10),
                              Text(
                                'Estanque Camión (${vehicle.patente})',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: tank.isCalibrated ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tank.isCalibrated ? 'CALIBRADO AL TOPE' : 'PENDIENTE CALIBRACIÓN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: tank.isCalibrated ? Colors.greenAccent : Colors.orangeAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // MEDIDOR DIGITAL DE NIVEL
                      Center(
                        child: Column(
                          children: [
                            Text(
                              tank.isCalibrated ? '${tank.currentLitros.toStringAsFixed(0)} L' : '--',
                              style: TextStyle(
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                color: tank.percentage < 25 ? Colors.redAccent : Colors.white,
                              ),
                            ),
                            Text(
                              tank.isCalibrated
                                  ? 'de ${tank.capacityLitros.toStringAsFixed(0)} Litros (${tank.percentage.toStringAsFixed(0)}%)'
                                  : 'Capacidad nominal: ${tank.capacityLitros.toStringAsFixed(0)} Litros',
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // BARRA DE NIVEL
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: tank.isCalibrated ? (tank.percentage / 100.0).clamp(0.0, 1.0) : 0.05,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            !tank.isCalibrated
                                ? Colors.orangeAccent
                                : tank.percentage < 25
                                    ? Colors.redAccent
                                    : tank.percentage < 50
                                        ? Colors.amber
                                        : Colors.greenAccent,
                          ),
                          minHeight: 16,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // SUB-MÉTRICAS
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSubMetric('Autonomía Estimada', '~${tank.estimatedAutonomyKm.toStringAsFixed(0)} KM', Colors.cyanAccent),
                          _buildSubMetric('Rendimiento Usado', '${tank.expectedRendimiento.toStringAsFixed(2)} km/L', Colors.white),
                          _buildSubMetric('Consumo Ralentí', '${vehicle.consumoRalentiLitrosHora.toStringAsFixed(1)} L/h (Max ${vehicle.maxMinutosRalentiAlerta}m)', Colors.orangeAccent),
                          _buildSubMetric('Dinero en Estanque', '\$ ${NumberUtils.formatCurrency(tank.fuelValueClp)}', Colors.greenAccent),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ESTANQUE AUXILIAR (THERMO KING / GENSET) SI CORRESPONDE
              if (vehicle.tieneEquipoAuxiliar) ...[
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.ac_unit, color: Colors.cyanAccent, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                vehicle.identificadorAuxiliar ?? 'Thermo King / Reefer',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                '${tank.auxCurrentLitros.toStringAsFixed(0)} L',
                                style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Colors.cyanAccent),
                              ),
                              Text(
                                'de ${tank.auxCapacityLitros.toStringAsFixed(0)} Litros (${tank.auxPercentage.toStringAsFixed(0)}%)',
                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (tank.auxPercentage / 100.0).clamp(0.0, 1.0),
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                            minHeight: 16,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSubMetric('Autonomía Frío', '~${tank.auxAutonomyHours.toStringAsFixed(1)} Horas', Colors.cyanAccent),
                            _buildSubMetric('Consumo Teórico', '${vehicle.consumoHoraAuxiliar.toStringAsFixed(1)} L/h', Colors.white),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),

          // HISTORIAL DE CARGAS DE ESTA UNIDAD
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Historial de Cargas & Rendimiento Real Registrado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                if (vExpenses.where((e) => e.type.toLowerCase() == 'combustible').isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text('No hay cargas de combustible registradas para este vehículo.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('Fecha', style: TextStyle(color: Colors.grey))),
                      DataColumn(label: Text('Destino', style: TextStyle(color: Colors.grey))),
                      DataColumn(label: Text('Litros', style: TextStyle(color: Colors.grey))),
                      DataColumn(label: Text('Monto Bruto', style: TextStyle(color: Colors.grey))),
                      DataColumn(label: Text('Odómetro / Horas', style: TextStyle(color: Colors.grey))),
                      DataColumn(label: Text('Tipo Carga', style: TextStyle(color: Colors.grey))),
                      DataColumn(label: Text('Rendimiento Tramo', style: TextStyle(color: Colors.grey))),
                    ],
                    rows: vExpenses.where((e) => e.type.toLowerCase() == 'combustible').map((exp) {
                      return DataRow(
                        cells: [
                          DataCell(Text('${exp.date.day}/${exp.date.month}/${exp.date.year}')),
                          DataCell(Text(exp.destinoCombustible == 'AUXILIAR' ? '❄️ Auxiliar' : '🚛 Camión')),
                          DataCell(Text('${exp.litros?.toStringAsFixed(1) ?? '--'} L')),
                          DataCell(Text('\$ ${NumberUtils.formatCurrency(exp.amount)}')),
                          DataCell(Text(exp.destinoCombustible == 'AUXILIAR'
                              ? '${exp.horometroAtFill?.toStringAsFixed(1) ?? '--'} hrs'
                              : '${exp.odometerAtFill?.toStringAsFixed(0) ?? '--'} km')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: exp.isFullTank ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                exp.isFullTank ? 'FULL TANK' : 'Parcial',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: exp.isFullTank ? Colors.greenAccent : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            exp.rendimientoTramo != null
                                ? Text('${exp.rendimientoTramo} km/L', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent))
                                : const Text('--', style: TextStyle(color: Colors.grey)),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

