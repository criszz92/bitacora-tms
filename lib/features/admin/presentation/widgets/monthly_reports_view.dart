import '../../../auth/domain/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/admin_provider.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../domain/models/incidencia_model.dart';
import '../../domain/models/company_config_model.dart';
import '../../../../core/utils/chilean_holidays.dart';
import '../../../../core/utils/chilean_financial_calculator.dart';
import 'monthly_report_exporter.dart';
import 'create_incidencia_dialog.dart';

class MonthlyReportsView extends ConsumerStatefulWidget {
  const MonthlyReportsView({super.key});

  @override
  ConsumerState<MonthlyReportsView> createState() => _MonthlyReportsViewState();
}

class _MonthlyReportsViewState extends ConsumerState<MonthlyReportsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _filterVehicleId; // null = Toda la flota

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(num? val) => NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0).format(val ?? 0);

  @override
  Widget build(BuildContext context) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final configAsync = ref.watch(companyConfigProvider);
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final tripsAsync = ref.watch(monthlyTripsProvider);
    final expensesAsync = ref.watch(monthlyExpensesProvider);
    final incidenciasAsync = ref.watch(adminIncidenciasProvider);
    final driversAsync = ref.watch(choferesProvider);
    final summaryAsync = ref.watch(financialSummaryProvider);

    final allTrips = ref.watch(allTripsProvider).value ?? [];
    final allExpenses = ref.watch(allExpensesProvider).value ?? [];

    final config = configAsync.value ?? CompanyConfigModel(idEmpresa: '');
    final vehicles = vehiclesAsync.value ?? [];
    final trips = tripsAsync.value ?? [];
    final expenses = expensesAsync.value ?? [];
    final incidencias = incidenciasAsync.value ?? [];
    final drivers = driversAsync.value ?? [];
    final summary = summaryAsync.value ?? {};

    // Filtrado por unidad si se selecciona una específica
    final filteredTrips = _filterVehicleId == null
        ? trips
        : trips.where((t) => t.vehicleId == _filterVehicleId).toList();
    final filteredExpenses = _filterVehicleId == null
        ? expenses
        : expenses.where((e) => e.vehicleId == _filterVehicleId).toList();

    // ─── CÁLCULO DE HISTORIAL DE 3 MESES PARA COMPARATIVAS ───
    final List<Map<String, dynamic>> history3Months = _calculate3MonthsHistory(
      selectedMonth,
      allTrips,
      allExpenses,
      drivers,
      vehicles,
      config,
    );

    // ─── CÁLCULO DE ESTADÍSTICAS POR UNIDAD (FLOTA) ───
    final List<Map<String, dynamic>> vehicleStats = _calculateVehicleStats(
      selectedMonth,
      vehicles,
      trips,
      expenses,
      incidencias,
      config,
    );

    // ─── CÁLCULO DE MATRIZ DE RUTAS ───
    final List<Map<String, dynamic>> routeStats = _calculateRouteStats(filteredTrips, filteredExpenses);

    final monthName = DateFormat('MMMM yyyy', 'es_CL').format(selectedMonth).toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── ENCABEZADO SUPERIOR Y SELECTORES ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Informes & Auditoría Mensual',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Periodo: $monthName | Fuente de Verdad SII y Conciliación Bancaria',
                        style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
                Row(
                  children: [
                    // Selector de Vehículo
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _filterVehicleId,
                          dropdownColor: const Color(0xFF1E1E1E),
                          icon: const Icon(Icons.local_shipping, color: Colors.orange, size: 18),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Toda la Flota', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                            ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente, style: const TextStyle(color: Colors.white)))),
                          ],
                          onChanged: (val) => setState(() => _filterVehicleId = val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Selector de Mes
                    _buildMonthSelector(ref, selectedMonth),
                    const SizedBox(width: 16),

                    // Botón Exportar PDF
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('Exportar PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => MonthlyReportExporter.exportMonthlyReportPdf(
                        selectedMonth: selectedMonth,
                        config: config,
                        summary: summary,
                        monthlyTrips: trips,
                        monthlyExpenses: expenses,
                        vehicles: vehicles,
                        incidencias: incidencias,
                        drivers: drivers,
                        routeStats: routeStats,
                        vehicleStats: vehicleStats,
                        history3Months: history3Months,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Botón Exportar Excel
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.table_view, size: 18),
                      label: const Text('Exportar Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => MonthlyReportExporter.exportMonthlyReportExcel(
                        selectedMonth: selectedMonth,
                        config: config,
                        summary: summary,
                        monthlyTrips: trips,
                        monthlyExpenses: expenses,
                        vehicles: vehicles,
                        incidencias: incidencias,
                        drivers: drivers,
                        routeStats: routeStats,
                        vehicleStats: vehicleStats,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ─── PESTAÑAS ───
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.orange,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.orange,
                indicatorWeight: 3,
                tabs: const [
                  Tab(icon: Icon(Icons.analytics_outlined), text: 'Resumen & Comparativa (3 Meses)'),
                  Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Radiografía por Unidad'),
                  Tab(icon: Icon(Icons.route_outlined), text: 'Matriz de Rutas'),
                  Tab(icon: Icon(Icons.build_outlined), text: 'Incidencias & Taller'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ─── CONTENIDO DE PESTAÑAS ───
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabResumenYComparativa(summary, history3Months),
                  _buildTabRadiografiaPorUnidad(vehicleStats),
                  _buildTabMatrizRutas(routeStats),
                  _buildTabIncidenciasYTaller(incidencias, selectedMonth, vehicles),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── PESTAÑA 1: RESUMEN Y COMPARATIVA TRIMESTRAL ───
  Widget _buildTabResumenYComparativa(Map<String, double> summary, List<Map<String, dynamic>> history) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tarjetas Clave de Operación
          Row(
            children: [
              _metricCard('Facturación Neta', _fmt(summary['ingresosNetos']), Colors.blueAccent, Icons.receipt_long),
              const SizedBox(width: 14),
              _metricCard('Gastos Operativos', _fmt(summary['gastosNetos']), Colors.orangeAccent, Icons.trending_down),
              const SizedBox(width: 14),
              _metricCard('EBITDA Operacional', _fmt(summary['resultadoOperacional']), Colors.greenAccent, Icons.check_circle_outline,
                  subtitle: 'Margen: ${(summary['margenOperacional'] ?? 0).toStringAsFixed(1)}%'),
              const SizedBox(width: 14),
              _metricCard('F29 a Pagar (Día 20)', _fmt(summary['totalF29Pagar']), Colors.purpleAccent, Icons.account_balance,
                  subtitle: (summary['nuevoRemanenteFavor'] ?? 0) > 0 ? 'Remanente mes sig: ${_fmt(summary['nuevoRemanenteFavor'])}' : null),
              const SizedBox(width: 14),
              _metricCard('Caja Libre (Con IVA)', _fmt(summary['flujoCajaReal']), Colors.cyanAccent, Icons.savings_outlined,
                  subtitle: 'Sin IVA: ${_fmt(summary['flujoCajaSinIva'])}'),
            ],
          ),

          const SizedBox(height: 24),

          // Gráfico / Tabla Comparativa de 3 Meses
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Comparativa Trimestral de Rendimiento (Hasta 3 Meses)',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Tendencia Operativa', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Visualizador en Barras Comparativas
                Row(
                  children: history.map((h) {
                    final isCurrent = h['isCurrent'] == true;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCurrent ? Colors.orange.withValues(alpha: 0.08) : Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isCurrent ? Colors.orange : Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(h['mesLabel'], style: TextStyle(color: isCurrent ? Colors.orange : Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('${h['viajes']} viajes', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                            const Divider(color: Colors.white12, height: 16),
                            _dataRow('Facturación:', _fmt(h['ingresosNetos'])),
                            _dataRow('Gastos Totales:', _fmt(h['gastosBrutos'])),
                            _dataRow('Margen EBITDA:', _fmt(h['resultadoOperacional']), isBold: true, color: Colors.greenAccent),
                            _dataRow('F29 Pagado:', _fmt(h['f29'])),
                            _dataRow('Caja en Banco:', _fmt(h['flujoCajaReal']), isBold: true, color: Colors.cyanAccent),
                          ],
                        ),
                      ),
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

  // ─── PESTAÑA 2: RADIOGRAFÍA POR UNIDAD ───
  Widget _buildTabRadiografiaPorUnidad(List<Map<String, dynamic>> vehicleStats) {
    if (vehicleStats.isEmpty) {
      return const Center(child: Text('No hay vehículos registrados en la flota', style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      itemCount: vehicleStats.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final v = vehicleStats[index];
        final bool fondoPositivo = (v['saldoMantenimiento'] as double) >= 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text(v['patente'], style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      Text('${v['marca']} ${v['modelo']} (${v['anio']})', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (v['tasaDisponibilidad'] as double) >= 90 ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Disponibilidad: ${(v['tasaDisponibilidad'] as double).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: (v['tasaDisponibilidad'] as double) >= 90 ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Métricas de la Unidad
              Row(
                children: [
                  _subMetric('KM Recorridos', '${NumberFormat.decimalPattern('es_CL').format(v['km'])} KM'),
                  _subMetric('Viajes Mes', '${v['viajes']}'),
                  _subMetric('Diésel Cargado', '${(v['litros'] as double).toStringAsFixed(0)} Lts'),
                  _subMetric('Rendimiento', '${(v['rendimiento'] as double).toStringAsFixed(2)} Km/L'),
                  _subMetric('Días en Taller', '${v['diasTaller']} días (Lun-Sáb)'),
                  _subMetric('Facturas Taller Real', _fmt(v['gastoTallerReal'])),
                  _subMetric('Desgaste Presupuestado', _fmt(v['desgasteTeorico'])),
                  _subMetric(
                    fondoPositivo ? 'Reserva a Favor' : 'Sobregasto Taller',
                    _fmt((v['saldoMantenimiento'] as double).abs()),
                    color: fondoPositivo ? Colors.greenAccent : Colors.redAccent,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── PESTAÑA 3: MATRIZ DE RUTAS ───
  Widget _buildTabMatrizRutas(List<Map<String, dynamic>> routeStats) {
    if (routeStats.isEmpty) {
      return const Center(child: Text('No hay rutas realizadas en el mes seleccionado', style: TextStyle(color: Colors.grey)));
    }

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rentabilidad Desglosada por Trayecto y Frecuencia',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.5),
                3: FlexColumnWidth(1.5),
                4: FlexColumnWidth(1.5),
                5: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24))),
                  children: [
                    _th('Ruta (Origen -> Destino)'),
                    _th('Vueltas'),
                    _th('Facturación Neta'),
                    _th('Costo Directo'),
                    _th('Margen Bruto'),
                    _th('Rentabilidad %'),
                  ],
                ),
                ...routeStats.map((r) => TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                  children: [
                    _td(r['ruta'], isBold: true),
                    _td('${r['frecuencia']}'),
                    _td(_fmt(r['ingreso'])),
                    _td(_fmt(r['costo'])),
                    _td(_fmt(r['margen']), color: (r['margen'] as double) >= 0 ? Colors.greenAccent : Colors.redAccent),
                    _td('${(r['rentabilidad'] as double).toStringAsFixed(1)}%',
                        color: (r['rentabilidad'] as double) >= 25 ? Colors.greenAccent : Colors.orangeAccent),
                  ],
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── PESTAÑA 4: INCIDENCIAS Y TALLER ───
  Widget _buildTabIncidenciasYTaller(List<IncidenciaModel> incidencias, DateTime selectedMonth, List<VehicleModel> vehicles) {
    final monthIncidencias = incidencias.where((i) {
      final d = i.fecha;
      return d.year == selectedMonth.year && d.month == selectedMonth.month;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Registro de Incidencias y Días Detenido (${monthIncidencias.length})',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Ingresar Mantención / Taller', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => showCreateIncidenciaDialog(context, ref, vehicles),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (monthIncidencias.isEmpty)
          const Expanded(child: Center(child: Text('No hay incidencias ni mantenciones reportadas en este mes', style: TextStyle(color: Colors.grey))))
        else
          Expanded(
            child: ListView.separated(
              itemCount: monthIncidencias.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final inc = monthIncidencias[index];
                final dias = ChileanHolidays.getDiasDetenidosHabiles(inc.fechaIngresoTaller ?? inc.fecha, inc.fechaResolucion);

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: inc.estado == 'Solucionado' ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          inc.estado == 'Solucionado' ? Icons.check_circle_outline : Icons.build_circle_outlined,
                          color: inc.estado == 'Solucionado' ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(inc.vehiclePatente, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                                  child: Text(inc.tipo, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                ),
                                const SizedBox(width: 8),
                                Text('• ${DateFormat('dd/MM/yyyy').format(inc.fecha)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(inc.descripcion, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            if (inc.tallerProveedor != null) ...[
                              const SizedBox(height: 2),
                              Text('Taller: ${inc.tallerProveedor} | Factura: ${inc.numeroFactura ?? "S/F"}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Text('$dias días hábiles detenido', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 4),
                          Text(inc.costoReparacion != null ? _fmt(inc.costoReparacion) : 'Sin costo',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ─── MÉTODOS AUXILIARES DE CÁLCULO VERÍDICO ───

  List<Map<String, dynamic>> _calculate3MonthsHistory(
    DateTime currentMonth,
    List<TripModel> allTrips,
    List<ExpenseModel> allExpenses,
    List<UserModel> drivers,
    List<VehicleModel> vehicles,
    CompanyConfigModel config,
  ) {
    final List<DateTime> months = [];
    for (int i = 2; i >= 0; i--) {
      months.add(DateTime(currentMonth.year, currentMonth.month - i, 1));
    }

    double remanenteArrastre = config.remanenteCreditoFiscalAcumulado;

    return months.map((m) {
      final mKey = "${m.year}-${m.month.toString().padLeft(2, '0')}";
      final mStart = DateTime(m.year, m.month, 1);
      final mEnd = DateTime(m.year, m.month + 1, 1);

      final mTrips = allTrips.where((t) => t.startDate.isAfter(mStart.subtract(const Duration(seconds: 1))) && t.startDate.isBefore(mEnd)).toList();
      final mExpenses = allExpenses.where((e) => e.date.isAfter(mStart.subtract(const Duration(seconds: 1))) && e.date.isBefore(mEnd)).toList();

      final mUtm = config.utmHistory[mKey] ?? config.valorUTM;
      final mDiesel = config.dieselHistory[mKey] ?? config.precioDieselNeto;

      final mSummary = ChileanFinancialCalculator.calculateCompanySummary(
        allDrivers: drivers,
        monthlyTrips: mTrips,
        directExpenses: mExpenses,
        config: config,
        vehicles: vehicles,
        customUtmValue: mUtm,
        customDieselValue: mDiesel,
        customRemanenteAnterior: remanenteArrastre,
      );

      remanenteArrastre = mSummary['nuevoRemanenteFavor'] ?? 0.0;

      return {
        'mesLabel': DateFormat('MMM yyyy', 'es_CL').format(m).toUpperCase(),
        'isCurrent': m.year == currentMonth.year && m.month == currentMonth.month,
        'viajes': mTrips.length,
        'ingresosNetos': mSummary['ingresosNetos'] ?? 0.0,
        'gastosBrutos': mSummary['gastosBrutos'] ?? 0.0,
        'resultadoOperacional': mSummary['resultadoOperacional'] ?? 0.0,
        'f29': mSummary['totalF29Pagar'] ?? 0.0,
        'flujoCajaReal': mSummary['flujoCajaReal'] ?? 0.0,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _calculateVehicleStats(
    DateTime selectedMonth,
    List<VehicleModel> vehicles,
    List<TripModel> trips,
    List<ExpenseModel> expenses,
    List<IncidenciaModel> incidencias,
    CompanyConfigModel config,
  ) {
    final diasHabilesTotalesMes = ChileanHolidays.getDiasHabilesMes(selectedMonth.year, selectedMonth.month);

    return vehicles.map((v) {
      final vTrips = trips.where((t) => t.vehicleId == v.id || t.vehicleId == v.patente).toList();
      final vExpenses = expenses.where((e) => e.vehicleId == v.id || e.vehicleId == v.patente).toList();

      double km = 0;
      for (final t in vTrips) {
        km += (t.totalKm ?? 0);
      }

      double litros = 0;
      double gastoTallerReal = 0;
      for (final e in vExpenses) {
        final tLower = e.type.toLowerCase();
        if (tLower == 'combustible') {
          litros += (e.litros ?? 0);
        } else if (tLower.contains('manten') || tLower.contains('taller') || tLower.contains('repuesto')) {
          gastoTallerReal += e.amount;
        }
      }

      final rendimiento = (litros > 0 && km > 0) ? (km / litros) : 0.0;

      // Días en Taller calculados por incidencias del mes
      final vIncidencias = incidencias.where((i) {
        final matchesVehicle = i.vehicleId == v.id || i.vehiclePatente == v.patente;
        final d = i.fecha;
        return matchesVehicle && d.year == selectedMonth.year && d.month == selectedMonth.month;
      }).toList();

      int diasTaller = 0;
      for (final inc in vIncidencias) {
        diasTaller += ChileanHolidays.getDiasDetenidosHabiles(inc.fechaIngresoTaller ?? inc.fecha, inc.fechaResolucion);
      }

      final diasOperativos = (diasHabilesTotalesMes - diasTaller).clamp(0, diasHabilesTotalesMes);
      final tasaDisponibilidad = diasHabilesTotalesMes > 0 ? (diasOperativos / diasHabilesTotalesMes) * 100 : 100.0;

      final costoKm = v.costoMantenimientoPorKm ?? 49.0;
      final desgasteTeorico = km * costoKm;
      final saldoMantenimiento = desgasteTeorico - gastoTallerReal;

      return {
        'patente': v.patente,
        'marca': v.marca ?? 'Camión',
        'modelo': v.modelo ?? '',
        'anio': v.anio ?? '',
        'km': km,
        'viajes': vTrips.length,
        'litros': litros,
        'rendimiento': rendimiento,
        'diasTaller': diasTaller,
        'diasOperativos': diasOperativos,
        'tasaDisponibilidad': tasaDisponibilidad,
        'gastoTallerReal': gastoTallerReal,
        'desgasteTeorico': desgasteTeorico,
        'saldoMantenimiento': saldoMantenimiento,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _calculateRouteStats(List<TripModel> trips, List<ExpenseModel> expenses) {
    final Map<String, List<TripModel>> grouped = {};
    for (final t in trips) {
      final key = '${t.origin} -> ${t.destination}';
      grouped.putIfAbsent(key, () => []).add(t);
    }

    return grouped.entries.map((e) {
      final routeKey = e.key;
      final rTrips = e.value;
      double ingresoTotal = 0;
      double kmTotal = 0;

      for (final t in rTrips) {
        ingresoTotal += t.value + (t.extraCostos ?? 0) + (t.sobreEstadia ?? 0);
        kmTotal += (t.totalKm ?? 0);
      }

      // Costo directo estimado por KM promedio
      final costoDirecto = kmTotal * 650.0; // Diésel + Peajes promedio
      final margen = ingresoTotal - costoDirecto;
      final rentabilidad = ingresoTotal > 0 ? (margen / ingresoTotal) * 100 : 0.0;

      return {
        'ruta': routeKey,
        'frecuencia': rTrips.length,
        'ingreso': ingresoTotal,
        'costo': costoDirecto,
        'margen': margen,
        'rentabilidad': rentabilidad,
      };
    }).toList();
  }

  Widget _buildMonthSelector(WidgetRef ref, DateTime selected) {
    final months = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final now = DateTime.now();
    final isCurrent = selected.year == now.year && selected.month == now.month;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.grey, size: 18),
            onPressed: () => ref.read(selectedMonthProvider.notifier).setMonth(DateTime(selected.year, selected.month - 1, 1)),
          ),
          Text('${months[selected.month]} ${selected.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          IconButton(
            icon: Icon(Icons.chevron_right, color: isCurrent ? Colors.white24 : Colors.grey, size: 18),
            onPressed: isCurrent ? null : () => ref.read(selectedMonthProvider.notifier).setMonth(DateTime(selected.year, selected.month + 1, 1)),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String val, Color color, IconData icon, {String? subtitle}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Text(val, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subMetric(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _dataRow(String label, String val, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(val, style: TextStyle(color: color ?? Colors.white, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _th(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(text, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _td(String text, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(text, style: TextStyle(color: color ?? Colors.white, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
    );
  }
}
