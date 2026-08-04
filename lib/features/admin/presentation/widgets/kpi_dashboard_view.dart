import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import 'package:intl/intl.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../../core/utils/number_utils.dart';

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

    final trips = (tripsAsync.value ?? []).where((t) => selectedVehicleId == null || t.vehicleId == selectedVehicleId).toList();
    final expenses = (expensesAsync.value ?? []).where((e) => selectedVehicleId == null || e.vehicleId == selectedVehicleId).toList();
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
                _buildTaxAnalysisPanel(kpi, utmUsed, dieselUsed),
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

  Widget _buildTaxAnalysisPanel(KpiData kpi, double utmUsed, double dieselUsed) {
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
              const Icon(Icons.analytics_outlined, color: Colors.orange, size: 22),
              const SizedBox(width: 12),
              const Text('Análisis Tributario F29 & Flujo de Caja Real',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              _infoBadge('Diesel Neto: \$${dieselUsed.toStringAsFixed(0)}', Colors.blueAccent),
              const SizedBox(width: 8),
              _infoBadge('UTM Mes: ${_fmt(utmUsed)}', Colors.orange),
              const SizedBox(width: 8),
              _infoBadge('Recuperación Diésel Activa', Colors.greenAccent),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _taxSubSection(
                  title: 'DETALLE IVA MES',
                  items: [
                    _taxRow('IVA Débito (Ventas)', kpi.ivaDebito, isNegative: false),
                    _taxRow('IVA Crédito (Gastos)', -kpi.ivaCredito, isNegative: true),
                    _taxRow('Ley 19.764 (Diésel)', -kpi.recuperacionDiesel, isNegative: true, isHighlight: true),
                    const Divider(color: Colors.white10, height: 24),
                    _taxRow('ESTIMADO F29 A PAGAR', kpi.ivaNetoPagar, isBold: true, 
                        customColor: kpi.ivaNetoPagar > 0 ? Colors.orange : Colors.greenAccent),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                flex: 1,
                child: _taxSubSection(
                  title: 'INDICADORES LEY 19.764',
                  items: [
                    _infoRow('Lts Reales Mes', '${kpi.litrosDiesel.toStringAsFixed(1)} Lts'),
                    _infoRow('Total Beneficio', _fmt(kpi.recuperacionDiesel)),
                    const SizedBox(height: 12),
                    const Text('Datos basados en cargas reales.', style: TextStyle(color: Colors.white24, fontSize: 9)),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    children: [
                      const Text('DINERO REAL EN BOLSILLO', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(_fmt(kpi.flujoCajaReal), 
                          style: TextStyle(color: kpi.flujoCajaReal >= 0 ? Colors.white : Colors.redAccent, fontSize: 32, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Margen Neto: ${kpi.margenNetoCaja.toStringAsFixed(1)}%', 
                          style: TextStyle(color: kpi.margenNetoCaja >= 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
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

  Widget _infoRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))]));

  Widget _infoBadge(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.2))), child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)));

  Widget _buildVehicleSelector(WidgetRef ref, List<VehicleModel> vehicles) => Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)), child: DropdownButtonHideUnderline(child: DropdownButton<String?>(value: ref.watch(selectedVehicleProvider), dropdownColor: const Color(0xFF1E1E1E), icon: const Icon(Icons.local_shipping, color: Colors.orange, size: 18), hint: const Text('Toda la Flota', style: TextStyle(color: Colors.white, fontSize: 13)), items: [const DropdownMenuItem(value: null, child: Text('Toda la Flota', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente, style: const TextStyle(color: Colors.white))))], onChanged: (val) => ref.read(selectedVehicleProvider.notifier).setVehicle(val))));

  Widget _buildMonthSelector(WidgetRef ref, DateTime selected, bool isCurrentMonth, List<String> months) => Container(decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)), child: Row(children: [IconButton(icon: const Icon(Icons.chevron_left, color: Colors.grey, size: 18), onPressed: () => ref.read(selectedMonthProvider.notifier).setMonth(DateTime(selected.year, selected.month - 1, 1))), Text('${months[selected.month]} ${selected.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), IconButton(icon: Icon(Icons.chevron_right, color: isCurrentMonth ? Colors.white24 : Colors.grey, size: 18), onPressed: isCurrentMonth ? null : () => ref.read(selectedMonthProvider.notifier).setMonth(DateTime(selected.year, selected.month + 1, 1)))]));

  // --- LISTAS Y DIÁLOGOS DE MÁXIMA ESTABILIDAD Y SEGURIDAD NUMÉRICA ---

  Widget _buildTripsList(List trips, BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    return Column(children: trips.map<Widget>((t) {
      final vehicle = vehicles.firstWhere(
        (v) => v.id == t.vehicleId || v.patente == t.vehicleId, 
        orElse: () => VehicleModel(id: '', patente: t.vehicleId ?? 'S/P', idEmpresa: '')
      );
      return InkWell(
        onTap: () => _showEditTripDialog(context, ref, t, vehicles),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: (t.billingType ?? '') == 'OS' ? Colors.white38 : Colors.orange, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text('${t.origin ?? ""} → ${t.destination ?? ""}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)), const SizedBox(width: 8), Text(vehicle.patente, style: const TextStyle(color: Colors.white38, fontSize: 10))]),
              Text('[${DateFormat('dd/MM').format(t.startDate)}] ${t.client ?? ""} | ${(t.containerNumber != null && t.containerNumber!.isNotEmpty) ? t.containerNumber : (t.guideNumber ?? "S/ID")}', 
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ])),
            Text(_fmt((t.value ?? 0) + (t.extraCostos ?? 0) + (t.sobreEstadia ?? 0)), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          linkedRoute = '${trip.origin} → ${trip.destination}';
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
                    DropdownButtonFormField<String>(initialValue: type, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Tipo de Gasto', labelStyle: TextStyle(color: Colors.grey)), items: ['Combustible', 'Peaje', 'Mantención', 'Seguro', 'Sueldo', 'Otros'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (val) => setDialogState(() => type = val!)),
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
                  final expense = ExpenseModel(id: '', idEmpresa: profile?.idEmpresa ?? '', idChofer: profile?.uid ?? 'ADMIN', idJornada: 'ADMIN', amount: NumberUtils.tryParseDouble(montoCtrl.text) ?? 0, type: type, litros: NumberUtils.tryParseDouble(litrosCtrl.text), date: selectedDate, description: descCtrl.text, status: 'Pagado', vehicleId: selectedVehicle, tripId: selectedTripId);
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
              const Text('Editar Viaje', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              TextButton(onPressed: () async {
                final confirm = await _showDeleteConfirm(context, 'viaje');
                if (confirm) { await ref.read(adminRepositoryProvider).deleteTrip(t.id); if (ctx.mounted) Navigator.pop(ctx); }
              }, child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent))),
            ]),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
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
                    Row(children: [
                      const Icon(Icons.local_shipping, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: DropdownButtonFormField<String>(initialValue: selectedVehicle, dropdownColor: const Color(0xFF1A1A1A), style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Vehículo', labelStyle: TextStyle(color: Colors.grey, fontSize: 12), border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))), items: [const DropdownMenuItem(value: null, child: Text('No asignado')), ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente)))], onChanged: (val) => setDialogState(() => selectedVehicle = val))),
                    ]),
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
}
