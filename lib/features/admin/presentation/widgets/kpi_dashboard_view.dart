import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import 'package:intl/intl.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../domain/models/recurring_expense_model.dart';
import '../../domain/models/company_config_model.dart';
import '../../../../core/utils/number_utils.dart';
import '../../domain/services/modogps_service.dart';
import '../../../trips/domain/services/route_tariff_baseline_service.dart';

class KpiDashboardView extends ConsumerWidget {
  const KpiDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(kpiProvider);
    final tripsAsync = ref.watch(monthlyTripsProvider);
    final expensesAsync = ref.watch(monthlyExpensesProvider);
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final selectedVehicleId = ref.watch(selectedVehicleProvider);
    final configAsync = ref.watch(companyConfigProvider);
    final config = configAsync.value;
    final selectedMonth = ref.watch(selectedMonthProvider);
    final monthKey = "${selectedMonth.year}-${selectedMonth.month.toString().padLeft(2, '0')}";
    final utmUsed = config?.getUtmForMonth(monthKey) ?? 65000.0;
    final vehicles = vehiclesAsync.value ?? [];
    
    final summaryAsync = ref.watch(financialSummaryProvider);
    final summary = summaryAsync.value ?? {};
    final dieselUsed = summary['precioDieselNeto'] ?? config?.precioDieselNeto ?? 800.0;

    // Normalización bidireccional (ID interno vs Patente física)
    final selectedVehicleObj = vehicles.where((v) => v.id == selectedVehicleId || v.patente == selectedVehicleId).firstOrNull;
    final targetPlate = selectedVehicleObj?.patente;
    final targetId = selectedVehicleObj?.id ?? selectedVehicleId;

    bool matchesVehicle(String? entityVehicleId) {
      if (selectedVehicleId == null) return true;
      if (entityVehicleId == null || entityVehicleId.isEmpty) return false;
      return entityVehicleId == targetId || 
             (targetPlate != null && entityVehicleId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase() == targetPlate.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase());
    }

    final trips = (tripsAsync.value ?? []).where((t) => matchesVehicle(t.vehicleId)).toList();
    final expenses = (expensesAsync.value ?? []).where((e) => matchesVehicle(e.vehicleId)).toList();
    final allMonthlyTrips = tripsAsync.value ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref, vehicles),
          const SizedBox(height: 32),
          kpiAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFFFFF))),
            error: (e, s) => Text('Error cargando KPIs: $e', style: const TextStyle(color: Colors.red)),
            data: (kpi) => Column(
              children: [
                _buildOperationalKpis(kpi),
                const SizedBox(height: 24),
                _buildTaxAnalysisPanel(kpi, utmUsed, dieselUsed, config),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Viajes del Mes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('${trips.length} registros', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          tripsAsync.when(
            loading: () => const LinearProgressIndicator(color: Color(0xFFFFFFFF)),
            error: (e, s) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
            data: (_) => trips.isEmpty
                ? _emptyState('No hay viajes registrados.')
                : _buildTripsList(trips, context, ref, vehicles),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gastos del Mes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('${expenses.length} registros', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          expensesAsync.when(
            loading: () => const LinearProgressIndicator(color: Colors.orange),
            error: (e, s) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
            data: (_) => expenses.isEmpty
                ? _emptyState('No hay gastos registrados.')
                : _buildExpensesList(expenses, allMonthlyTrips, context, ref, vehicles),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    final months = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final selected = ref.watch(selectedMonthProvider);
    final now = DateTime.now();
    final isCurrentMonth = selected.year == now.year && selected.month == now.month;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dashboard Ejecutivo',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 2),
                const Text('Módulo de Análisis Tributario F29 Activo', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _showAddTripDialog(context, ref, vehicles),
          icon: const Icon(Icons.add_road, size: 18),
          label: const Text('Registrar Viaje'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _showAddExpenseDialog(context, ref, vehicles),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Registrar Gasto'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        const SizedBox(width: 8),
        // ─── BOTÓN APLICAR GASTOS FIJOS ───────────────────────────
        Builder(
          builder: (context) {
            final config = ref.watch(companyConfigProvider).value;
            final gastosFijos = config?.gastosRecurrentes.where((g) => g.activo).toList() ?? [];
            final yaAplicados = ref.watch(gastosFijosAplicadosProvider);
            
            if (gastosFijos.isEmpty) return const SizedBox.shrink();
            
            return ElevatedButton.icon(
              onPressed: yaAplicados ? null : () => _showApplyRecurringExpensesDialog(context, ref, gastosFijos, vehicles),
              icon: Icon(yaAplicados ? Icons.check_circle_outline : Icons.repeat, size: 18),
              label: Text(yaAplicados ? 'Gastos Fijos ✓' : 'Aplicar Gastos Fijos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: yaAplicados ? Colors.green.withValues(alpha: 0.2) : Colors.deepPurple,
                foregroundColor: yaAplicados ? Colors.green : Colors.white,
                disabledBackgroundColor: Colors.green.withValues(alpha: 0.15),
                disabledForegroundColor: Colors.green.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            );
          },
        ),
        const SizedBox(width: 16),
        _buildVehicleSelector(ref, vehicles),
        const SizedBox(width: 16),
        _buildMonthSelector(ref, selected, isCurrentMonth, months),
      ],
    );
  }

  Widget _buildOperationalKpis(KpiData kpi) {
    return Row(
      children: [
        _miniKpiCard('Viajes', '${kpi.totalViajes}', Icons.local_shipping_outlined, Colors.blue),
        const SizedBox(width: 12),
        _miniKpiCard('Ingreso Neto', _fmt(kpi.totalIngresosNetos), Icons.trending_up, Colors.green),
        const SizedBox(width: 12),
        _miniKpiCard('Gasto Bruto', _fmt(kpi.totalGastosBrutos), Icons.trending_down, Colors.orange),
        const SizedBox(width: 12),
        _miniKpiCard('Costo Personal', _fmt(kpi.totalPersonal), Icons.people_outline, Colors.purple),
        const SizedBox(width: 12),
        _miniKpiCard('Margen Op.', '${kpi.margenOperacional.toStringAsFixed(1)}%', Icons.pie_chart_outline, kpi.margenOperacional >= 0 ? Colors.greenAccent : Colors.redAccent),
      ],
    );
  }

  Widget _buildTaxAnalysisPanel(KpiData kpi, double utmUsed, double dieselUsed, CompanyConfigModel? config) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_outlined, color: Colors.greenAccent, size: 24),
              const SizedBox(width: 12),
              const Text('Análisis Financiero, F29 & Fuente de Verdad',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              _infoBadge('Diesel Neto: \$${dieselUsed.toStringAsFixed(0)}', Colors.blueAccent),
              const SizedBox(width: 8),
              _infoBadge('UTM Mes: ${_fmt(utmUsed)}', Colors.orange),
              const SizedBox(width: 8),
              _infoBadge('Recuperación IEPD ${(config?.porcentajeRecuperacionIepd ?? 80.0).toStringAsFixed(0)}% Activa', Colors.greenAccent),
            ],
          ),
          const SizedBox(height: 28),

          // ─── 3 BLOQUES EJECUTIVOS CONEXOS ───
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // BLOQUE 1: P&L OPERACIONAL NETO
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: _taxSubSection(
                    title: '1. RESULTADO OPERATIVO (P&L NETO)',
                    items: [
                      _taxRow('Facturación Fletes (Neto)', kpi.totalIngresosNetos, isBold: true),
                      _taxRow('(-) Gastos Operativos (Netos)', -kpi.gastosNetos, isNegative: true),
                      if (kpi.totalPeajesExentos > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 4),
                          child: Text('• Incluye Peajes Exentos: ${_fmt(kpi.totalPeajesExentos)}',
                              style: const TextStyle(color: Colors.grey, fontSize: 10)),
                        ),
                      _taxRow('(-) Costos de Personal (Haberes+SIS)', -kpi.totalPersonal, isNegative: true),
                      const Divider(color: Colors.white12, height: 20),
                      _taxRow('MARGEN OPERATIVO (EBITDA)', kpi.resultadoOperacional,
                          isBold: true, customColor: kpi.resultadoOperacional >= 0 ? Colors.greenAccent : Colors.redAccent),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Rentabilidad Op: ${kpi.margenOperacional.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: kpi.margenOperacional >= 0 ? Colors.greenAccent : Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // BLOQUE 2: RADIOGRAFÍA DEL F29
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: _taxSubSection(
                    title: '2. RADIOGRAFÍA TRIBUTARIA F29',
                    items: [
                      _taxRow('IVA Débito Fiscal (19%)', kpi.ivaDebito),
                      _taxRow('(-) IVA Crédito (Compras/Diésel)', -kpi.ivaCredito, isNegative: true),
                      _taxRow('(-) Beneficio Ley 19.764', -kpi.recuperacionDiesel, isNegative: true, isHighlight: true),
                      if (kpi.remanenteAnterior > 0)
                        _taxRow('(-) Remanente IVA Anterior', -kpi.remanenteAnterior, isNegative: true, isHighlight: true),
                      _taxRow('(+) PPM Obligatorio (${(config?.tasaPPM ?? 1.5).toStringAsFixed(1)}%)', kpi.ppmObligatorio, isHighlight: true),
                      const Divider(color: Colors.white12, height: 20),
                      if (kpi.nuevoRemanenteFavor > 0) ...[
                        _taxRow('IVA NETO A PAGAR', 0.0, isBold: true, customColor: Colors.greenAccent),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('⭐ Remanente a Favor Mes Sig:',
                                  style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                              Text(_fmt(kpi.nuevoRemanenteFavor),
                                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ] else ...[
                        _taxRow('IVA NETO A PAGAR', kpi.ivaNetoPagar, isBold: true, customColor: Colors.orangeAccent),
                      ],
                      _taxRow('TOTAL A PAGAR F29 (DÍA 20)', kpi.totalF29Pagar,
                          isBold: true, customColor: kpi.totalF29Pagar > 0 ? Colors.orange : Colors.greenAccent),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // BLOQUE 3: FLUJO DE CAJA LIBRE EN BANCO
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    children: [
                      _taxSubSection(
                        title: '3. CAJA BANCARIA ("EN BOLSILLO")',
                        items: [
                          _taxRow('Cobrado Clientes (Bruto)', kpi.ingresosBrutos),
                          _taxRow('(-) Gastos Desembolsados', -kpi.totalGastosBrutos, isNegative: true),
                          _taxRow('(-) Sueldos y Leyes Sociales', -kpi.totalPersonal, isNegative: true),
                          _taxRow('(-) Cargo F29 día 20', -kpi.totalF29Pagar, isNegative: true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // TARJETA 1: DISPONIBLE CON RECUPERACIÓN DE IVA (CAJA BRUTA)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: kpi.flujoCajaReal >= 0
                                    ? Colors.greenAccent.withValues(alpha: 0.06)
                                    : Colors.redAccent.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: kpi.flujoCajaReal >= 0
                                      ? Colors.greenAccent.withValues(alpha: 0.25)
                                      : Colors.redAccent.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text('DISP. CON IVA',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(_fmt(kpi.flujoCajaReal),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: kpi.flujoCajaReal >= 0 ? Colors.white : Colors.redAccent,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text('Margen: ${kpi.margenNetoCaja.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                          color: kpi.margenNetoCaja >= 0 ? Colors.greenAccent : Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // TARJETA 2: DISPONIBLE SIN IVA (OPERACIÓN PURA)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: kpi.flujoCajaSinIva >= 0
                                    ? Colors.amberAccent.withValues(alpha: 0.06)
                                    : Colors.redAccent.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: kpi.flujoCajaSinIva >= 0
                                      ? Colors.amberAccent.withValues(alpha: 0.25)
                                      : Colors.redAccent.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text('DISP. SIN IVA',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(_fmt(kpi.flujoCajaSinIva),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: kpi.flujoCajaSinIva >= 0 ? Colors.white : Colors.redAccent,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text('Margen: ${kpi.margenCajaSinIva.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                          color: kpi.margenCajaSinIva >= 0 ? Colors.amberAccent : Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ─── BLOQUE 4: COMPARADOR DE MANTENIMIENTO: TEÓRICO SEGÚN KM vs. FACTURAS TALLER ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                const Icon(Icons.build_circle_outlined, color: Colors.amberAccent, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CONTROL DE MANTENIMIENTO: DESGASTE TEÓRICO vs. GASTO EJECUTADO EN TALLER',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(
                        'Desgaste presupuestado por KM recorridos: ${_fmt(kpi.mantenimientoTeoricoKm)}  |  Facturas reales pagadas en taller: ${_fmt(kpi.mantenimientoRealEjecutado)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: kpi.saldoFondoMantenimiento >= 0
                        ? Colors.greenAccent.withValues(alpha: 0.1)
                        : Colors.orangeAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: kpi.saldoFondoMantenimiento >= 0 ? Colors.greenAccent : Colors.orangeAccent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        kpi.saldoFondoMantenimiento >= 0 ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        color: kpi.saldoFondoMantenimiento >= 0 ? Colors.greenAccent : Colors.orangeAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (kpi.saldoFondoMantenimiento >= 0 ? 'Fondo Reserva: +' : 'Sobregasto Taller: ') +
                            _fmt(kpi.saldoFondoMantenimiento),
                        style: TextStyle(
                          color: kpi.saldoFondoMantenimiento >= 0 ? Colors.greenAccent : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _miniKpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: color.withValues(alpha: 0.5), size: 14), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10))]),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _taxSubSection({required String title, required List<Widget> items}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)), const SizedBox(height: 16), ...items]);

  Widget _taxRow(String label, double value, {bool isNegative = false, bool isHighlight = false, bool isBold = false, Color? customColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: isHighlight ? Colors.orange : Colors.grey, fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
      Text(_fmt(value), style: TextStyle(color: customColor ?? (isNegative ? Colors.redAccent : Colors.white), fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
    ]),
  );



  Widget _infoBadge(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.2))), child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)));

  Widget _buildVehicleSelector(WidgetRef ref, List<VehicleModel> vehicles) => Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)), child: DropdownButtonHideUnderline(child: DropdownButton<String?>(value: ref.watch(selectedVehicleProvider), dropdownColor: const Color(0xFF1E1E1E), icon: const Icon(Icons.local_shipping, color: Colors.orange, size: 18), hint: const Text('Toda la Flota', style: TextStyle(color: Colors.white, fontSize: 13)), items: [const DropdownMenuItem(value: null, child: Text('Toda la Flota', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente, style: const TextStyle(color: Colors.white))))], onChanged: (val) => ref.read(selectedVehicleProvider.notifier).setVehicle(val))));

  Widget _buildMonthSelector(WidgetRef ref, DateTime selected, bool isCurrentMonth, List<String> months) => Container(decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)), child: Row(children: [IconButton(icon: const Icon(Icons.chevron_left, color: Colors.grey, size: 18), onPressed: () => ref.read(selectedMonthProvider.notifier).setMonth(DateTime(selected.year, selected.month - 1, 1))), Text('${months[selected.month]} ${selected.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), IconButton(icon: Icon(Icons.chevron_right, color: isCurrentMonth ? Colors.white24 : Colors.grey, size: 18), onPressed: isCurrentMonth ? null : () => ref.read(selectedMonthProvider.notifier).setMonth(DateTime(selected.year, selected.month + 1, 1)))]));

  // --- LISTAS Y DIÁLOGOS DE MÁXIMA ESTABILIDAD Y SEGURIDAD NUMÉRICA ---

  Widget _buildTripsList(List<TripModel> trips, BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    final baseline = ref.watch(routeTariffBaselineProvider);
    return Column(children: trips.map<Widget>((t) {
      final vehicle = vehicles.firstWhere(
        (v) => v.id == t.vehicleId || v.patente == t.vehicleId, 
        orElse: () => VehicleModel(id: '', patente: t.vehicleId ?? 'S/P', idEmpresa: '')
      );
      final anomaly = baseline.evaluateTariff(
        origin: t.origin,
        client: t.client,
        destination: t.destination,
        enteredValue: t.value,
      );
      return InkWell(
        onTap: () => _showEditTripDialog(context, ref, t, vehicles),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: t.billingType == 'OS' ? Colors.white38 : Colors.orange, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t.displayRoute3Steps, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13), overflow: TextOverflow.ellipsis)), 
                const SizedBox(width: 8), 
                Text(vehicle.patente, style: const TextStyle(color: Colors.white38, fontSize: 10))
              ]),
              Row(children: [
                Expanded(
                  child: Text(
                    '[${DateFormat('dd/MM').format(t.startDate)}] ${t.client} | ${(t.containerNumber != null && t.containerNumber!.isNotEmpty) ? t.containerNumber! : (t.guideNumber ?? "S/ID")}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (anomaly.isAnomaly) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: anomaly.reason,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: anomaly.isCritical 
                            ? Colors.redAccent.withValues(alpha: 0.15) 
                            : Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: anomaly.isCritical 
                              ? Colors.redAccent 
                              : Colors.amber, 
                          width: 0.8
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded, 
                            size: 11, 
                            color: anomaly.isCritical 
                                ? Colors.redAccent 
                                : Colors.amber
                          ),
                          const SizedBox(width: 3),
                          Text(
                            anomaly.isCritical ? 'Tarifa Anómala' : 'Revisar Tarifa',
                            style: TextStyle(
                              fontSize: 9, 
                              fontWeight: FontWeight.bold,
                              color: anomaly.isCritical 
                                  ? Colors.redAccent 
                                  : Colors.amber
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ]),
            ])),
            const SizedBox(width: 8),
            Text(_fmt(t.value + (t.extraCostos ?? 0) + (t.sobreEstadia ?? 0)), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
      );
    }).toList());
  }

  Widget _buildExpensesList(List<ExpenseModel> expenses, List<TripModel> trips, BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    return Column(children: expenses.map((e) {
      // Buscar el nombre del viaje vinculado
      String? linkedRoute;
      if (e.tripId != null && e.tripId!.isNotEmpty) {
        try {
          final trip = trips.firstWhere((t) => t.id == e.tripId);
          linkedRoute = trip.displayRoute3Steps;
        } catch (_) {
          linkedRoute = 'Viaje no encontrado';
        }
      }

      return InkWell(
        onTap: () => _showEditExpenseDialog(context, ref, e, vehicles),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(e.type.toLowerCase() == 'combustible' ? Icons.local_gas_station : Icons.receipt_long, color: Colors.orange, size: 16),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.description.isEmpty ? 'Gasto sin descripción' : e.description, style: const TextStyle(fontSize: 13)), 
              Row(children: [
                Text(e.type, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                if (linkedRoute != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.link, size: 10, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(linkedRoute, style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                ]
              ])
            ])),
            Text(_fmt(e.amount), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ]),
        ),
      );
    }).toList());
  }

  void _showAddExpenseDialog(BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    final montoCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final litrosCtrl = TextEditingController();
    
    final dashboardMonth = ref.read(selectedMonthProvider);
    final now = DateTime.now();
    DateTime selectedDate = (dashboardMonth.year == now.year && dashboardMonth.month == now.month) 
        ? now : DateTime(dashboardMonth.year, dashboardMonth.month, 1);

    String type = 'Otros';
    bool isExento = false;
    String? selectedVehicle;
    String? selectedTripId;
    final trips = ref.read(monthlyTripsProvider).value ?? [];

    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 450,
        constraints: const BoxConstraints(maxHeight: 750),
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Registrar Gasto', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (d != null) setDialogState(() => selectedDate = d);
                      },
                      child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.calendar_today, color: Colors.orange, size: 16), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Fecha del Gasto', style: TextStyle(color: Colors.grey, fontSize: 10)), Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])])),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(initialValue: type, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Tipo de Gasto', labelStyle: TextStyle(color: Colors.grey)), items: [
                      'Combustible',
                      'Peaje',
                      'Mantención',
                      'Seguro',
                      'Sueldo',
                      'Compra Activo / Camión',
                      'Otros'
                    ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        type = val!;
                        if (type.toLowerCase() == 'peaje') isExento = true;
                      });
                    }),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isExento ? 'Documento Exento de IVA' : 'Factura con IVA Recuperable (19%)',
                        style: TextStyle(
                          color: isExento ? Colors.grey : Colors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        isExento
                            ? 'El total pagado va 100% al costo (Peajes, contratos s/IVA).'
                            : 'El IVA (19%) se separa automáticamente para el F29.',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      value: isExento,
                      activeTrackColor: Colors.grey,
                      onChanged: (val) => setDialogState(() => isExento = val),
                    ),
                    const SizedBox(height: 16),
                    if (type.toLowerCase() == 'combustible') ...[ _buildNumericField(litrosCtrl, 'Litros Reales'), const SizedBox(height: 16)],
                    DropdownButtonFormField<String>(initialValue: selectedVehicle, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Vehículo', labelStyle: TextStyle(color: Colors.grey)), items: [const DropdownMenuItem(value: null, child: Text('General')), ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente)))], onChanged: (val) => setDialogState(() => selectedVehicle = val)),
                    const SizedBox(height: 16),
                    if (type.toLowerCase() == 'peaje') ...[
                      DropdownButtonFormField<String>(initialValue: selectedTripId, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white, fontSize: 13), decoration: const InputDecoration(labelText: 'Vincular a Viaje (Opcional)', labelStyle: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)), items: [const DropdownMenuItem(value: null, child: Text('Gasto General (Prorrateado)')), ...trips.where((t) => selectedVehicle == null || t.vehicleId == selectedVehicle).map((t) => DropdownMenuItem(value: t.id, child: Text('${t.origin} -> ${t.destination} (${t.guideNumber ?? "S/G"})', style: const TextStyle(fontSize: 12))))], onChanged: (val) {
                        setDialogState(() {
                          selectedTripId = val;
                          if (val != null) {
                            final trip = trips.firstWhere((t) => t.id == val);
                            selectedDate = trip.startDate; // Actualizar fecha automáticamente
                          }
                        });
                      }),
                      const SizedBox(height: 16),
                    ],
                    _buildNumericField(montoCtrl, 'Monto Total (\$)'),
                    const SizedBox(height: 16),
                    _buildField(descCtrl, 'Descripción'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: () async {
                  final profile = ref.read(currentUserProfileProvider).value;
                  final expense = ExpenseModel(id: '', idEmpresa: profile?.idEmpresa ?? '', idChofer: profile?.uid ?? 'ADMIN', idJornada: 'ADMIN', amount: NumberUtils.tryParseDouble(montoCtrl.text) ?? 0, type: type, litros: NumberUtils.tryParseDouble(litrosCtrl.text), date: selectedDate, description: descCtrl.text, status: 'Pagado', vehicleId: selectedVehicle, tripId: selectedTripId, isExento: isExento);
                  await ref.read(adminRepositoryProvider).saveExpense(expense);
                  if (ctx.mounted) Navigator.pop(ctx);
              }, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)), child: const Text('Guardar')),
            ])
          ],
        )),
      ),
    ));
  }

  void _showAddTripDialog(BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    final originCtrl = TextEditingController();
    final destCtrl = TextEditingController();
    final clientCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final extraCtrl = TextEditingController();
    final sobreEstadiaCtrl = TextEditingController();
    final containerCtrl = TextEditingController();
    final guideCtrl = TextEditingController();
    final kmCtrl = TextEditingController();
    
    final dashboardMonth = ref.read(selectedMonthProvider);
    final now = DateTime.now();
    DateTime selectedDate = (dashboardMonth.year == now.year && dashboardMonth.month == now.month) 
        ? now : DateTime(dashboardMonth.year, dashboardMonth.month, 1);
        
    String? selectedVehicle;
    String? selectedDriverId;
    final drivers = ref.read(choferesProvider).value ?? [];

    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 450,
        constraints: const BoxConstraints(maxHeight: 750),
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Registrar Viaje', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (d != null) setDialogState(() => selectedDate = d);
                      },
                      child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.calendar_today, color: Colors.blueAccent, size: 16), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Fecha del Viaje', style: TextStyle(color: Colors.grey, fontSize: 10)), Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])])),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(initialValue: selectedDriverId, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Chofer (Requerido)', labelStyle: TextStyle(color: Colors.grey)), items: drivers.map((d) => DropdownMenuItem(value: d.uid, child: Text(d.nombre))).toList(), onChanged: (val) => setDialogState(() => selectedDriverId = val)),
                    const SizedBox(height: 16),
                    _buildField(originCtrl, 'Origen'),
                    const SizedBox(height: 16),
                    _buildField(destCtrl, 'Destino'),
                    const SizedBox(height: 16),
                    _buildField(clientCtrl, 'Cliente'),
                    const SizedBox(height: 16),
                    _buildNumericField(valueCtrl, 'Valor Base (\$)'),
                    const SizedBox(height: 16),
                    _buildNumericField(extraCtrl, 'Extra Costos (\$)'),
                    const SizedBox(height: 16),
                    _buildNumericField(sobreEstadiaCtrl, 'Sobre Estadía (\$)'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(initialValue: selectedVehicle, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Vehículo', labelStyle: TextStyle(color: Colors.grey)), items: [const DropdownMenuItem(value: null, child: Text('No asignado')), ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente)))], onChanged: (val) => setDialogState(() => selectedVehicle = val)),
                    const SizedBox(height: 16),
                    _buildField(containerCtrl, 'Nº Contenedor'),
                    const SizedBox(height: 16),
                    _buildField(guideCtrl, 'Nº Guía'),
                    const SizedBox(height: 16),
                    _buildNumericField(kmCtrl, 'Kilómetros Recorridos'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: () async {
                if (selectedDriverId == null) return;
                try {
                  final profile = ref.read(currentUserProfileProvider).value;
                  final newTrip = TripModel(
                    id: '',
                    idEmpresa: profile?.idEmpresa ?? '',
                    idChofer: selectedDriverId!,
                    idJornada: 'ADMIN',
                    startDate: selectedDate,
                    endDate: selectedDate,
                    origin: originCtrl.text,
                    destination: destCtrl.text,
                    status: 'Finalizado',
                    cargoType: 'Carga General',
                    client: clientCtrl.text,
                    mandante: clientCtrl.text,
                    value: NumberUtils.tryParseDouble(valueCtrl.text) ?? 0.0,
                    billingType: 'OT',
                    extraCostos: NumberUtils.tryParseDouble(extraCtrl.text) ?? 0.0,
                    sobreEstadia: NumberUtils.tryParseDouble(sobreEstadiaCtrl.text) ?? 0.0,
                    containerNumber: containerCtrl.text,
                    guideNumber: guideCtrl.text,
                    vehicleId: selectedVehicle,
                    totalKm: NumberUtils.tryParseDouble(kmCtrl.text) ?? 0.0,
                    comments: 'Registrado manualmente por ADMIN',
                  );
                  await ref.read(adminRepositoryProvider).saveTrip(newTrip);
                } catch (e) { /* Error silenciado */ }
                if (ctx.mounted) Navigator.pop(ctx);
              }, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)), child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
          ],
        )),
      ),
    ));
  }

  void _showEditTripDialog(BuildContext context, WidgetRef ref, dynamic t, List<VehicleModel> vehicles) {
    final originCtrl = TextEditingController(text: (t.origin ?? "").toString());
    final destCtrl = TextEditingController(text: (t.destination ?? "").toString());
    final clientCtrl = TextEditingController(text: (t.client ?? "").toString());
    final valueCtrl = TextEditingController(text: (t.value ?? 0).toStringAsFixed(0));
    final extraCtrl = TextEditingController(text: (t.extraCostos ?? 0).toStringAsFixed(0));
    final sobreEstadiaCtrl = TextEditingController(text: (t.sobreEstadia ?? 0).toStringAsFixed(0));
    final containerCtrl = TextEditingController(text: (t.containerNumber ?? "").toString());
    final guideCtrl = TextEditingController(text: (t.guideNumber ?? "").toString());
    final kmCtrl = TextEditingController(text: (t.totalKm ?? 0).toStringAsFixed(1));
    final matchedVehicle = vehicles.where((v) => v.id == t.vehicleId || v.patente == t.vehicleId).firstOrNull;
    String? selectedVehicle = matchedVehicle?.id;

    final targetPlate = matchedVehicle?.patente ?? t.vehicleId ?? '';
    final modoGps = ref.read(modoGpsServiceProvider);
    final startTime = t.startDate;
    final endTime = t.endDate ?? DateTime.now();
    final timeFmt = DateFormat('HH:mm');

    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 950,
        constraints: const BoxConstraints(maxHeight: 780),
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note, color: Colors.blueAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text('Editar Viaje', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              TextButton(onPressed: () async {
                final confirm = await _showDeleteConfirm(context, 'viaje');
                if (confirm) { await ref.read(adminRepositoryProvider).deleteTrip(t.id); if (ctx.mounted) Navigator.pop(ctx); }
              }, child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent))),
            ]),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── COLUMNA IZQUIERDA: FORMULARIO COMERCIAL ──
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('DATOS DEL VIAJE', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 12),
                          _buildField(originCtrl, 'Origen'),
                          const SizedBox(height: 14),
                          _buildField(destCtrl, 'Destino'),
                          const SizedBox(height: 14),
                          _buildField(clientCtrl, 'Cliente'),
                          const SizedBox(height: 14),
                          _buildNumericField(valueCtrl, 'Valor Base (\$)'),
                          Builder(builder: (_) {
                            final baseline = ref.read(routeTariffBaselineProvider);
                            final anomaly = baseline.evaluateTariff(
                              origin: originCtrl.text,
                              client: clientCtrl.text,
                              destination: destCtrl.text,
                              enteredValue: NumberUtils.tryParseDouble(valueCtrl.text) ?? 0,
                            );
                            final suggested = baseline.getSuggestedTariff(
                              origin: originCtrl.text,
                              client: clientCtrl.text,
                              destination: destCtrl.text,
                            );
                            if (anomaly.isAnomaly) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 8),
                                child: Text(
                                  anomaly.reason,
                                  style: TextStyle(
                                    color: anomaly.isCritical ? Colors.redAccent : Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }
                            if (suggested != null) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 8),
                                child: Text(
                                  '✓ En rango histórico (Promedio: ${_fmt(suggested)})',
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }),
                          const SizedBox(height: 14),
                          _buildNumericField(extraCtrl, 'Extra Costos (\$)'),
                          const SizedBox(height: 14),
                          _buildNumericField(sobreEstadiaCtrl, 'Sobre Estadía (\$)'),
                          const SizedBox(height: 14),
                          Row(children: [
                            const Icon(Icons.local_shipping, color: Colors.white, size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: DropdownButtonFormField<String>(initialValue: selectedVehicle, dropdownColor: const Color(0xFF161B22), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Vehículo', labelStyle: TextStyle(color: Colors.grey, fontSize: 12), border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))), items: [const DropdownMenuItem(value: null, child: Text('No asignado')), ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente)))], onChanged: (val) => setDialogState(() => selectedVehicle = val))),
                          ]),
                          const SizedBox(height: 14),
                          _buildField(containerCtrl, 'Nº Contenedor'),
                          const SizedBox(height: 14),
                          _buildField(guideCtrl, 'Nº Guía'),
                          const SizedBox(height: 14),
                          _buildNumericField(kmCtrl, 'Kilómetros Recorridos'),
                        ],
                      ),
                    ),
                  ),

                  // ── SEPARADOR VERTICAL ──
                  const VerticalDivider(color: Colors.white12, width: 24),

                  // ── COLUMNA DERECHA: RESUMEN GPS, HITOS Y ESTIMACIÓN DE COMBUSTIBLE ──
                  Expanded(
                    flex: 6,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: FutureBuilder<GpsHistoricalTrip?>(
                        future: targetPlate.isEmpty
                            ? Future.value(null)
                            : modoGps.fetchTripInterval(
                                plate: targetPlate,
                                startTime: startTime,
                                endTime: endTime,
                              ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Colors.blueAccent),
                                  SizedBox(height: 14),
                                  Text('Cargando telemetría e hitos de ModoGPS...', style: TextStyle(color: Colors.white60, fontSize: 12)),
                                ],
                              ),
                            );
                          }

                          final hTrip = snapshot.data;
                          final double kmCalculados = hTrip?.totalDistanceKm ?? t.totalKm ?? 0.0;
                          // Estimación: Camión cargado rinde aprox 2.4 a 2.6 km/l
                          final double litrosEstimados = kmCalculados > 0 ? (kmCalculados / 2.5) : 0.0;
                          final double costoCombustibleEstimado = litrosEstimados * 850.0; // Precio aprox CLP neto

                          return SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.satellite_alt, color: Colors.blueAccent, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('TELEMETRÍA E HITOS DE RUTA', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        (hTrip?.journeyStart != null && hTrip?.journeyEnd != null)
                                            ? '${timeFmt.format(hTrip!.journeyStart!.determinedStartTime)} - ${timeFmt.format(hTrip.journeyEnd!.determinedEndTime)}'
                                            : '${timeFmt.format(startTime)} - ${timeFmt.format(endTime)}',
                                        style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Métricas rápidas
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Distancia GPS', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                            const SizedBox(height: 4),
                                            Text('${kmCalculados.toStringAsFixed(1)} KM', style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Diesel Estimado', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                            const SizedBox(height: 4),
                                            Text('${litrosEstimados.toStringAsFixed(1)} Lts', style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Costo Combustible', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                            const SizedBox(height: 4),
                                            Text('\$${costoCombustibleEstimado.toStringAsFixed(0)}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                if (hTrip != null && (hTrip.totalDistanceKm > 0) && (t.totalKm == null || t.totalKm! <= 0)) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.greenAccent.withValues(alpha: 0.15),
                                        foregroundColor: Colors.greenAccent,
                                        side: const BorderSide(color: Colors.greenAccent, width: 0.8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          kmCtrl.text = hTrip.totalDistanceKm.toStringAsFixed(1);
                                        });
                                      },
                                      icon: const Icon(Icons.auto_fix_high, size: 16),
                                      label: const Text('Aplicar KM Calculados por GPS al Viaje', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // ── JORNADA INTELIGENTE DETECTADA POR MODOGPS ──
                                if (hTrip != null && (hTrip.journeyStart != null || hTrip.journeyEnd != null)) ...[
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (hTrip.journeyStart != null)
                                        Expanded(
                                          child: _buildDashboardJourneyStartCard(hTrip.journeyStart!, timeFmt),
                                        ),
                                      if (hTrip.journeyStart != null && hTrip.journeyEnd != null)
                                        const SizedBox(width: 8),
                                      if (hTrip.journeyEnd != null)
                                        Expanded(
                                          child: _buildDashboardJourneyEndCard(hTrip.journeyEnd!, timeFmt),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // Lista de Hitos Operativos Registrados
                                const Text('Hitos Registrados por Conductor:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                if (t.hitos == null || t.hitos!.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                                    child: Text(
                                      t.hitoActual != null ? 'Hito actual: ${t.hitoActual}' : 'Sin hitos registrados manualmente aún.',
                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                    ),
                                  )
                                else
                                  ...t.hitos!.map((h) => Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.flag, size: 14, color: Colors.amber),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(h['nombre']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                        Text(
                                          h['timestamp'] != null ? DateFormat('HH:mm').format(DateTime.parse(h['timestamp'])) : '',
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  )),
                                const SizedBox(height: 16),

                                // Detenciones en Geocercas de ModoGPS
                                const Text('Permanencia en Geocercas GPS (Espera / Faena):', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                if (hTrip == null || hTrip.stays.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                                    child: const Text('No se detectaron detenciones en geocercas registradas para este tramo.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                  )
                                else
                                  ...hTrip.stays.map((stay) => Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on, size: 14, color: Colors.blueAccent),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(stay.geofenceName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                        Text(
                                          '${timeFmt.format(stay.entryTime)} - ${timeFmt.format(stay.exitTime)} (${stay.durationMinutes} min)',
                                          style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  )),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: () async {
                try {
                  final map = (t as dynamic).toMap();
                  map['origin'] = originCtrl.text; map['destination'] = destCtrl.text; map['client'] = clientCtrl.text;
                  map['value'] = NumberUtils.tryParseDouble(valueCtrl.text) ?? 0.0; 
                  map['extraCostos'] = NumberUtils.tryParseDouble(extraCtrl.text) ?? 0.0;
                  map['sobreEstadia'] = NumberUtils.tryParseDouble(sobreEstadiaCtrl.text) ?? 0.0;
                  map['containerNumber'] = containerCtrl.text;
                  map['guideNumber'] = guideCtrl.text; 
                  map['vehicleId'] = selectedVehicle;
                  map['totalKm'] = NumberUtils.tryParseDouble(kmCtrl.text) ?? 0.0;
                  await ref.read(adminRepositoryProvider).updateTripMap(t.id, map);
                } catch (e) { /* Error silenciado */ }
                if (ctx.mounted) Navigator.pop(ctx);
              }, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)), child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
          ],
        )),
      ),
    ));
  }

  void _showEditExpenseDialog(BuildContext context, WidgetRef ref, ExpenseModel e, List<VehicleModel> vehicles) {
    final montoCtrl = TextEditingController(text: e.amount.toStringAsFixed(0));
    final descCtrl = TextEditingController(text: e.description);
    final litrosCtrl = TextEditingController(text: e.litros?.toString() ?? '');
    
    DateTime selectedDate = e.date;
    String type = e.type;
    final matchedVehicle = vehicles.where((v) => v.id == e.vehicleId || v.patente == e.vehicleId).firstOrNull;
    String? selectedVehicle = matchedVehicle?.id;
    String? selectedTripId = e.tripId;
    final trips = ref.read(monthlyTripsProvider).value ?? [];

    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 450,
        constraints: const BoxConstraints(maxHeight: 750),
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Editar Gasto', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              TextButton(onPressed: () async {
                final confirm = await _showDeleteConfirm(context, 'gasto');
                if (confirm) { await ref.read(adminRepositoryProvider).deleteExpense(e.id); if (ctx.mounted) Navigator.pop(ctx); }
              }, child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent))),
            ]),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (d != null) setDialogState(() => selectedDate = d);
                      },
                      child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.calendar_today, color: Colors.orange, size: 16), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Fecha del Gasto', style: TextStyle(color: Colors.grey, fontSize: 10)), Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])])),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(initialValue: type, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Tipo', labelStyle: TextStyle(color: Colors.grey)), items: ['Combustible', 'Peaje', 'Mantención', 'Seguro', 'Sueldo', 'Otros'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (val) => setDialogState(() => type = val!)),
                    const SizedBox(height: 16),
                    if (type.toLowerCase() == 'combustible') ...[ _buildNumericField(litrosCtrl, 'Litros Reales'), const SizedBox(height: 16)],
                    DropdownButtonFormField<String>(initialValue: selectedVehicle, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Vehículo', labelStyle: TextStyle(color: Colors.grey)), items: [const DropdownMenuItem(value: null, child: Text('General')), ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente)))], onChanged: (val) => setDialogState(() => selectedVehicle = val)),
                    const SizedBox(height: 16),
                    if (type.toLowerCase() == 'peaje') ...[
                      DropdownButtonFormField<String>(initialValue: selectedTripId, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white, fontSize: 13), decoration: const InputDecoration(labelText: 'Vincular a Viaje (Opcional)', labelStyle: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)), items: [const DropdownMenuItem(value: null, child: Text('Gasto General (Prorrateado)')), ...trips.where((t) => selectedVehicle == null || t.vehicleId == selectedVehicle).map((t) => DropdownMenuItem(value: t.id, child: Text('${t.origin} -> ${t.destination} (${t.guideNumber ?? "S/G"})', style: const TextStyle(fontSize: 12))))], onChanged: (val) {
                        setDialogState(() {
                          selectedTripId = val;
                          if (val != null) {
                            try {
                              final trip = trips.firstWhere((t) => t.id == val);
                              selectedDate = trip.startDate;
                            } catch (_) {}
                          }
                        });
                      }),
                      const SizedBox(height: 16),
                    ],
                    _buildNumericField(montoCtrl, 'Monto (\$)'),
                    const SizedBox(height: 16),
                    _buildField(descCtrl, 'Descripción'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: () async {
                final updated = ExpenseModel(id: e.id, idEmpresa: e.idEmpresa, idChofer: e.idChofer, idJornada: e.idJornada, amount: NumberUtils.tryParseDouble(montoCtrl.text) ?? 0, type: type, description: descCtrl.text, vehicleId: selectedVehicle, tripId: selectedTripId, litros: NumberUtils.tryParseDouble(litrosCtrl.text), date: selectedDate, status: e.status);
                await ref.read(adminRepositoryProvider).saveExpense(updated);
                if (ctx.mounted) Navigator.pop(ctx);
              }, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)), child: const Text('Guardar')),
            ]),
          ],
        )),
      ),
    ));
  }

  void _showApplyRecurringExpensesDialog(BuildContext context, WidgetRef ref, List<RecurringExpenseModel> gastosFijos, List<VehicleModel> vehicles) {
    final months = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final selectedMonth = ref.read(selectedMonthProvider);
    final monthName = '${months[selectedMonth.month]} ${selectedMonth.year}';
    final total = gastosFijos.fold<double>(0, (sum, g) => sum + g.monto);
    bool isApplying = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.repeat, color: Colors.deepPurple, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Aplicar Gastos Fijos', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          Text(monthName, style: const TextStyle(color: Colors.deepPurple, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Los siguientes gastos se crearán como registros del mes seleccionado:',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: gastosFijos.map((g) {
                        final vehicleName = g.vehicleId != null
                            ? vehicles.where((v) => v.id == g.vehicleId).firstOrNull?.patente ?? 'Vehículo'
                            : 'General';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.receipt_long, color: Colors.orange, size: 18),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(g.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                                          child: Text(g.tipo, style: const TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(g.vehicleId != null ? Icons.local_shipping : Icons.business, size: 11, color: Colors.white30),
                                        const SizedBox(width: 4),
                                        Text(vehicleName, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(_fmt(g.monto), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${gastosFijos.length} gastos fijos', style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w500, fontSize: 13)),
                      Text('Total: ${_fmt(total)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: isApplying ? null : () async {
                        setDialogState(() => isApplying = true);
                        try {
                          final profile = ref.read(currentUserProfileProvider).value;
                          if (profile == null) return;
                          
                          final count = await ref.read(adminRepositoryProvider).applyRecurringExpenses(
                            idEmpresa: profile.idEmpresa,
                            adminUid: profile.uid,
                            month: selectedMonth,
                            gastosRecurrentes: gastosFijos,
                          );
                          
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✓ Se aplicaron $count gastos fijos para $monthName'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isApplying = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      icon: isApplying
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 18),
                      label: Text(isApplying ? 'Aplicando...' : 'Confirmar y Aplicar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildNumericField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [DecimalTextInputFormatter()],
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Future<bool> _showDeleteConfirm(BuildContext context, String tipo) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: Text('Eliminar $tipo', style: const TextStyle(color: Colors.redAccent)), content: Text('¿Estás seguro de eliminar este $tipo?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar'))])) ?? false;
  }

  String _fmt(double amount) { final isNeg = amount < 0; final abs = amount.abs(); final parts = abs.toStringAsFixed(0).split(''); final buf = StringBuffer(isNeg ? '-\$' : '\$'); for (int i = 0; i < parts.length; i++) { if (i > 0 && (parts.length - i) % 3 == 0) buf.write('.'); buf.write(parts[i]); } return buf.toString(); }

  Widget _emptyState(String message) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.inbox_outlined, size: 40, color: Colors.white10), const SizedBox(height: 12), Text(message, style: const TextStyle(color: Colors.grey, fontSize: 12))]));

  Widget _buildDashboardJourneyStartCard(GpsJourneyStart start, DateFormat timeFmt) {
    final determinedTime = start.determinedStartTime;
    final timeStr = timeFmt.format(determinedTime);

    final String confidence;
    final Color confidenceColor;
    if (start.firstMotionTime != null && start.engineOnAtStart) {
      confidence = 'ALTA';
      confidenceColor = Colors.greenAccent;
    } else if (start.firstMotionTime != null) {
      confidence = 'MEDIA';
      confidenceColor = Colors.amberAccent;
    } else {
      confidence = 'BAJA';
      confidenceColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2137),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.play_circle_fill, color: Colors.blueAccent, size: 13),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'INICIO JORNADA',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: confidenceColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'CONF. $confidence',
                  style: TextStyle(color: confidenceColor, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      start.firstMotionTime != null ? 'Primer movimiento' : 'Primer GPS',
                      style: const TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                    if (start.startGeofenceName != null)
                      Text(
                        start.startGeofenceName!,
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 6),
          _buildJourneyMiniRow(Icons.gps_fixed, '1er GPS:', timeFmt.format(start.firstGpsTime), Colors.cyanAccent),
          const SizedBox(height: 3),
          _buildJourneyMiniRow(
            Icons.directions_car,
            'Movimiento:',
            start.firstMotionTime != null ? timeFmt.format(start.firstMotionTime!) : 'S/D',
            Colors.greenAccent,
          ),
          const SizedBox(height: 3),
          _buildJourneyMiniRow(
            Icons.power,
            'Motor:',
            start.engineOnAtStart ? 'Encendido ✓' : 'Sin datos',
            start.engineOnAtStart ? Colors.greenAccent : Colors.white38,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardJourneyEndCard(GpsJourneyEnd end, DateFormat timeFmt) {
    final determinedTime = end.determinedEndTime;
    final timeStr = timeFmt.format(determinedTime);
    final dur = end.totalDuration;
    final durStr = dur.inHours > 0 ? '${dur.inHours}h ${dur.inMinutes % 60}m' : '${dur.inMinutes}m';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF20132A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.stop_circle, color: Colors.purpleAccent, size: 13),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'TÉRMINO JORNADA',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  durStr,
                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      end.isStopped ? 'Vehículo detenido' : 'En movimiento',
                      style: const TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                    if (end.endGeofenceName != null)
                      Text(
                        end.endGeofenceName!,
                        style: const TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 6),
          _buildJourneyMiniRow(Icons.flag, 'Último GPS:', timeStr, Colors.purpleAccent),
          const SizedBox(height: 3),
          _buildJourneyMiniRow(
            Icons.pause_circle_outline,
            'Estado:',
            end.isStopped ? 'Detenido (0 km/h)' : '${end.lastSpeed.toStringAsFixed(0)} km/h',
            end.isStopped ? Colors.greenAccent : Colors.amberAccent,
          ),
          const SizedBox(height: 3),
          _buildJourneyMiniRow(Icons.timelapse, 'Duración:', durStr, Colors.amberAccent),
        ],
      ),
    );
  }

  Widget _buildJourneyMiniRow(IconData icon, String label, String value, Color valColor) {
    return Row(
      children: [
        Icon(icon, size: 10, color: Colors.white38),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: valColor, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
