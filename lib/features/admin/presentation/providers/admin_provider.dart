import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/admin_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../trips/domain/models/viatico_model.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../domain/models/liquidacion_model.dart';
import '../../domain/models/company_config_model.dart';
import '../../domain/models/incidencia_model.dart';
import '../../../../core/utils/chilean_financial_calculator.dart';
import '../../domain/models/ziyu_models.dart';
import '../../domain/models/analytics_models.dart';

import '../../domain/services/tax_indicator_service.dart';
import '../../domain/services/ai_analytic_service.dart';

// Repositorio singleton del admin
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository();
});

final aiAnalyticServiceProvider = Provider((ref) => AIAnalyticService());

// ─── ESTADO DE ANÁLISIS IA ──────────────────────────────────────────────────

class AIAnalysisNotifier extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncValue.data(null);

  Future<void> runAnalysis(List<RouteProfitability> data) async {
    state = const AsyncValue.loading();
    try {
      final result = await ref.read(aiAnalyticServiceProvider).analyzeRouteProfitability(data);
      state = AsyncValue.data(result);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }
  
  void clear() => state = const AsyncValue.data(null);
}

final aiAnalysisResultProvider = NotifierProvider<AIAnalysisNotifier, AsyncValue<String?>>(() => AIAnalysisNotifier());

// ─── CHAT OPERATIVO IA ──────────────────────────────────────────────────────

class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;

  ChatMessage({required this.role, required this.content, required this.timestamp});
}

class OperationalChatNotifier extends Notifier<AsyncValue<List<ChatMessage>>> {
  @override
  AsyncValue<List<ChatMessage>> build() => const AsyncValue.data([]);

  Future<void> sendMessage(String text, List<RouteProfitability> data) async {
    final currentMessages = state.value ?? [];
    final newUserMessage = ChatMessage(role: 'user', content: text, timestamp: DateTime.now());
    
    state = AsyncValue.data([...currentMessages, newUserMessage]);

    try {
      // Preparar historial para la API
      final history = currentMessages.map((m) => {'role': m.role, 'content': m.content}).toList();
      
      final response = await ref.read(aiAnalyticServiceProvider).askOperationalAssistant(
        question: text,
        data: data,
        history: history,
      );

      final aiMessage = ChatMessage(role: 'assistant', content: response, timestamp: DateTime.now());
      state = AsyncValue.data([...state.value!, aiMessage]);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  void clear() => state = const AsyncValue.data([]);
}

final operationalChatProvider = NotifierProvider<OperationalChatNotifier, AsyncValue<List<ChatMessage>>>(() => OperationalChatNotifier());

final taxIndicatorServiceProvider = Provider((ref) => TaxIndicatorService());

/// Provider que vigila si el mes seleccionado tiene UTM.
/// Si no la tiene, gatilla la sincronización automática con la API.
final utmSyncProvider = FutureProvider<void>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  final config = ref.watch(companyConfigProvider).value;
  final user = ref.read(currentUserProfileProvider).value;
  
  if (user == null || config == null) return;
  
  final monthKey = "${month.year}-${month.month.toString().padLeft(2, '0')}";
  
  // Si no tenemos la UTM para este mes en el historial, sincronizamos el año completo
  if (!config.utmHistory.containsKey(monthKey)) {
    final history = await ref.read(taxIndicatorServiceProvider).fetchUtmYearlyHistory(month.year);
    if (history.isNotEmpty) {
      await ref.read(adminRepositoryProvider).syncUtmHistory(user.idEmpresa, history);
    }
  }
});

// ─── MES SELECCIONADO ────────────────────────────────────────────────────────

class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }
  void setMonth(DateTime month) => state = month;
}

final selectedMonthProvider = NotifierProvider<SelectedMonthNotifier, DateTime>(() => SelectedMonthNotifier());

// ─── VEHÍCULO SELECCIONADO ───────────────────────────────────────────────────

class SelectedVehicleNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setVehicle(String? id) => state = id;
}

final selectedVehicleProvider = NotifierProvider<SelectedVehicleNotifier, String?>(() => SelectedVehicleNotifier());

// ─── STREAMS DE DATOS BASE ───────────────────────────────────────────────────

final monthlyTripsProvider = StreamProvider<List<TripModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  final month = ref.watch(selectedMonthProvider);
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchMonthlyTrips(user.idEmpresa, month);
});

final monthlyExpensesProvider = StreamProvider<List<ExpenseModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  final month = ref.watch(selectedMonthProvider);
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchMonthlyExpenses(user.idEmpresa, month);
});

final allTripsProvider = StreamProvider<List<TripModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchAllTrips(user.idEmpresa);
});

final allExpensesProvider = StreamProvider<List<ExpenseModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchAllExpenses(user.idEmpresa);
});

final choferesProvider = StreamProvider<List<UserModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchChoferes(user.idEmpresa);
});

final adminVehiclesProvider = StreamProvider<List<VehicleModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchVehicles(user.idEmpresa);
});

final adminViaticosProvider = StreamProvider<List<ViaticoModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchAllViaticos(user.idEmpresa);
});

final adminIncidenciasProvider = StreamProvider<List<IncidenciaModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchIncidencias(user.idEmpresa);
});

// ─── CONFIGURACIÓN ───────────────────────────────────────────────────────────

final companyConfigProvider = StreamProvider<CompanyConfigModel?>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return Stream.value(null);
  return ref.read(adminRepositoryProvider).watchCompanyConfig(user.idEmpresa);
});

/// Indica si los gastos fijos del mes seleccionado ya fueron aplicados.
final gastosFijosAplicadosProvider = Provider<bool>((ref) {
  final config = ref.watch(companyConfigProvider).value;
  final month = ref.watch(selectedMonthProvider);
  if (config == null) return false;
  final monthKey = "${month.year}-${month.month.toString().padLeft(2, '0')}";
  return config.mesesGastosFijosAplicados.contains(monthKey);
});

// ─── KPIs Y FINANZAS ─────────────────────────────────────────────────────────

class KpiData {
  final int totalViajes;
  final Map<String, double> summary;

  double get totalIngresosNetos => summary['ingresosNetos'] ?? 0;
  double get totalGastosBrutos => summary['gastosBrutos'] ?? 0;
  double get totalPersonal => summary['costosPersonal'] ?? 0;
  double get resultadoOperacional => summary['resultadoOperacional'] ?? 0;
  double get margenOperacional => summary['margenOperacional'] ?? 0;
  double get ivaNetoPagar => summary['ivaNetoPagar'] ?? 0;
  double get flujoCajaReal => summary['flujoCajaReal'] ?? 0;
  double get margenNetoCaja => summary['margenNetoCaja'] ?? 0;
  
  // Para F29 detallado & Fuente de Verdad
  double get ivaDebito => summary['ivaDebito'] ?? 0;
  double get ivaCredito => summary['ivaCredito'] ?? 0;
  double get recuperacionDiesel => summary['recuperacionDiesel'] ?? 0;
  double get litrosDiesel => summary['litrosDiesel'] ?? 0;
  double get remanenteAnterior => summary['remanenteAnterior'] ?? 0;
  double get nuevoRemanenteFavor => summary['nuevoRemanenteFavor'] ?? 0;
  double get ppmObligatorio => summary['ppmObligatorio'] ?? 0;
  double get totalF29Pagar => summary['totalF29Pagar'] ?? 0;
  double get gastosNetos => summary['gastosNetos'] ?? 0;
  double get ingresosBrutos => summary['ingresosBrutos'] ?? 0;
  double get mantenimientoTeoricoKm => summary['mantenimientoTeoricoKm'] ?? 0;
  double get mantenimientoRealEjecutado => summary['mantenimientoRealEjecutado'] ?? 0;
  double get saldoFondoMantenimiento => summary['saldoFondoMantenimiento'] ?? 0;
  double get totalPeajesExentos => summary['totalPeajesExentos'] ?? 0;
  double get flujoCajaSinIva => summary['flujoCajaSinIva'] ?? 0;
  double get margenCajaSinIva => summary['margenCajaSinIva'] ?? 0;

  const KpiData({required this.totalViajes, required this.summary});
}

final financialSummaryProvider = Provider<AsyncValue<Map<String, double>>>((ref) {
  final trips = ref.watch(monthlyTripsProvider).value ?? [];
  final expenses = ref.watch(monthlyExpensesProvider).value ?? [];
  final choferes = ref.watch(choferesProvider).value ?? [];
  final config = ref.watch(companyConfigProvider).value ?? CompanyConfigModel(idEmpresa: '');
  final selectedVehicleId = ref.watch(selectedVehicleProvider);
  final month = ref.watch(selectedMonthProvider);
  
  // Gatillamos la sincronización en segundo plano (si falta la UTM)
  ref.watch(utmSyncProvider);

  final vehicles = ref.watch(adminVehiclesProvider).value ?? [];

  // Normalización bidireccional de camión para métricas financieras
  final matchedVehicleObj = vehicles.where((v) => v.id == selectedVehicleId || v.patente == selectedVehicleId).firstOrNull;
  final filterPlate = matchedVehicleObj?.patente.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  final filterId = matchedVehicleObj?.id ?? selectedVehicleId;

  bool matchesVehicle(String? vId) {
    if (selectedVehicleId == null) return true;
    if (vId == null || vId.isEmpty) return false;
    return vId == filterId || (filterPlate != null && vId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase() == filterPlate);
  }

  final filteredTrips = selectedVehicleId == null ? trips : trips.where((t) => matchesVehicle(t.vehicleId)).toList();
  final filteredExpenses = selectedVehicleId == null ? expenses : expenses.where((e) => matchesVehicle(e.vehicleId)).toList();

  // Obtenemos los valores específicos para este mes del historial
  final monthKey = "${month.year}-${month.month.toString().padLeft(2, '0')}";
  final utmValue = config.utmHistory[monthKey];
  final dieselValue = config.getDieselManualForMonth(monthKey);

  
  // === CALCULO DE REMANENTE ACUMULADO DINAMICO HISTORICO ===
  // Si hay compras o saldo anterior en meses previos, calculamos cuanto remanente llega a este mes
  final allTrips = ref.watch(allTripsProvider).value ?? [];
  final allExpenses = ref.watch(allExpensesProvider).value ?? [];

  final startOfCurrentMonth = DateTime(month.year, month.month, 1);
  final previousExpenses = allExpenses.where((e) => e.date.isBefore(startOfCurrentMonth)).toList();
  final previousTrips = allTrips.where((t) => t.startDate.isBefore(startOfCurrentMonth)).toList();

  double remanenteAcumuladoMes = config.remanenteCreditoFiscalAcumulado;

  if (previousExpenses.isNotEmpty || previousTrips.isNotEmpty) {
    final Set<String> previousMonthKeys = {};
    for (final e in previousExpenses) {
      final m = e.date.month.toString().padLeft(2, '0');
      previousMonthKeys.add('${e.date.year}-$m');
    }
    for (final t in previousTrips) {
      final m = t.startDate.month.toString().padLeft(2, '0');
      previousMonthKeys.add('${t.startDate.year}-$m');
    }

    final sortedPreviousMonths = previousMonthKeys.toList()..sort();

    for (final pKey in sortedPreviousMonths) {
      final parts = pKey.split('-');
      final pYear = int.parse(parts[0]);
      final pMonth = int.parse(parts[1]);
      final pMonthStart = DateTime(pYear, pMonth, 1);
      final pMonthEnd = DateTime(pYear, pMonth + 1, 1);

      final mTrips = previousTrips.where((t) => t.startDate.isAfter(pMonthStart.subtract(const Duration(seconds: 1))) && t.startDate.isBefore(pMonthEnd)).toList();
      final mExpenses = previousExpenses.where((e) => e.date.isAfter(pMonthStart.subtract(const Duration(seconds: 1))) && e.date.isBefore(pMonthEnd)).toList();

      final pUtm = config.utmHistory[pKey] ?? config.valorUTM;
      final pDiesel = config.dieselHistory[pKey] ?? config.precioDieselNeto;

      final mSummary = ChileanFinancialCalculator.calculateCompanySummary(
        allDrivers: choferes,
        monthlyTrips: mTrips,
        directExpenses: mExpenses,
        config: config,
        vehicles: vehicles,
        customUtmValue: pUtm,
        customDieselValue: pDiesel,
        customRemanenteAnterior: remanenteAcumuladoMes,
      );

      remanenteAcumuladoMes = mSummary['nuevoRemanenteFavor'] ?? 0.0;
    }
  }

  final summary = ChileanFinancialCalculator.calculateCompanySummary(
    allDrivers: choferes,
    monthlyTrips: filteredTrips,
    directExpenses: filteredExpenses,
    config: config,
    vehicles: vehicles,
    customUtmValue: utmValue,
    customDieselValue: dieselValue,
    customRemanenteAnterior: remanenteAcumuladoMes,
  );
  return AsyncValue.data(summary);
});

final kpiProvider = Provider<AsyncValue<KpiData>>((ref) {
  final summaryAsync = ref.watch(financialSummaryProvider);
  final tripsAsync = ref.watch(monthlyTripsProvider);
  return summaryAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (summary) => AsyncValue.data(KpiData(totalViajes: (tripsAsync.value ?? []).length, summary: summary)),
  );
});

// ─── ANALÍTICA Y TENDENCIAS ───────────────────────────────────────────────────

final expenseBreakdownProvider = Provider<AsyncValue<Map<String, double>>>((ref) {
  final summary = ref.watch(financialSummaryProvider).value ?? {};
  final expenses = ref.watch(monthlyExpensesProvider).value ?? [];
  final Map<String, double> breakdown = {};
  for (final e in expenses) { 
    double netAmount = e.amount;
    if (e.type.toLowerCase() != 'peaje') {
      netAmount = e.amount / 1.19;
    }
    breakdown[e.type] = (breakdown[e.type] ?? 0) + netAmount; 
  }
  final personalCost = summary['costosPersonal'] ?? 0;
  if (personalCost > 0) breakdown['Personal/Sueldos'] = personalCost;
  return AsyncValue.data(breakdown);
});

final topClientsProvider = Provider<AsyncValue<List<MapEntry<String, double>>>>((ref) {
  final trips = ref.watch(monthlyTripsProvider).value ?? [];
  final Map<String, double> clientMap = {};
  for (final t in trips) { clientMap[t.client.isEmpty ? 'Sin cliente' : t.client] = (clientMap[t.client] ?? 0) + t.value; }
  final sorted = clientMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return AsyncValue.data(sorted.take(5).toList());
});

final topRoutesProvider = Provider<AsyncValue<List<MapEntry<String, int>>>>((ref) {
  final trips = ref.watch(monthlyTripsProvider).value ?? [];
  final Map<String, int> routeMap = {};
  for (final t in trips) { final r = '${t.origin} → ${t.destination}'; routeMap[r] = (routeMap[r] ?? 0) + 1; }
  final sorted = routeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return AsyncValue.data(sorted.take(5).toList());
});

final routeProfitabilityProvider = Provider<AsyncValue<List<RouteProfitability>>>((ref) {
  final trips = ref.watch(monthlyTripsProvider).value ?? [];
  final expenses = ref.watch(monthlyExpensesProvider).value ?? [];
  final choferes = ref.watch(choferesProvider).value ?? [];
  final config = ref.watch(companyConfigProvider).value ?? CompanyConfigModel(idEmpresa: '');
  
  final results = ChileanFinancialCalculator.calculateRouteProfitability(
    allTrips: trips,
    allExpenses: expenses,
    allDrivers: choferes,
    config: config,
  );
  
  return AsyncValue.data(results);
});

final trendProvider = FutureProvider<List<TrendData>>((ref) async {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null) return [];
  final repo = ref.read(adminRepositoryProvider);
  final now = DateTime.now();
  final results = <TrendData>[];
  final choferes = ref.read(choferesProvider).value ?? [];
  final config = ref.read(companyConfigProvider).value ?? CompanyConfigModel(idEmpresa: user.idEmpresa);
  final months = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];

  for (int i = 5; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i, 1);
    final trips = await repo.getTripsForMonth(user.idEmpresa, month);
    final expenses = await repo.getExpensesForMonth(user.idEmpresa, month);
    final monthKey = "${month.year}-${month.month.toString().padLeft(2, '0')}";
    final utmValue = config.utmHistory[monthKey];
    final dieselValue = config.getDieselManualForMonth(monthKey);

    final summary = ChileanFinancialCalculator.calculateCompanySummary(
      allDrivers: choferes, 
      monthlyTrips: trips, 
      directExpenses: expenses, 
      config: config,
      customUtmValue: utmValue,
      customDieselValue: dieselValue,
    );
    
    results.add(TrendData(
      label: months[month.month - 1], 
      ingresos: summary['ingresosNetos'] ?? 0, 
      gastos: summary['gastosBrutos'] ?? 0,
      margen: summary['resultadoOperacional'] ?? 0,
    ));
  }
  return results;
});

// ─── LIQUIDACIONES ──────────────────────────────────────────────────────────

final liquidacionesProvider = StreamProvider.autoDispose<List<LiquidacionModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  final month = ref.watch(selectedMonthProvider);
  final vehicleId = ref.watch(selectedVehicleProvider);
  if (user == null) return const Stream.empty();
  return ref.read(adminRepositoryProvider).watchLiquidaciones(user.idEmpresa, month: month, vehicleId: vehicleId);
});

// ─── CONCILIACIÓN ZIYU ───────────────────────────────────────────────────────

class ZiyuConciliationState {
  final String? fileName;
  final bool isProcessing;
  final List<ReconciliationResult>? results;
  final Map<String, int>? summary;

  ZiyuConciliationState({this.fileName, this.isProcessing = false, this.results, this.summary});

  ZiyuConciliationState copyWith({String? fileName, bool? isProcessing, List<ReconciliationResult>? results, Map<String, int>? summary}) {
    return ZiyuConciliationState(
      fileName: fileName ?? this.fileName,
      isProcessing: isProcessing ?? this.isProcessing,
      results: results ?? this.results,
      summary: summary ?? this.summary,
    );
  }
}

class ZiyuConciliationNotifier extends Notifier<ZiyuConciliationState> {
  @override
  ZiyuConciliationState build() => ZiyuConciliationState();
  void setProcessing(bool value) => state = state.copyWith(isProcessing: value);
  void setResults(String fileName, List<ReconciliationResult> results, Map<String, int> summary) {
    state = ZiyuConciliationState(fileName: fileName, results: results, summary: summary, isProcessing: false);
  }
  void clear() => state = ZiyuConciliationState();
}

final ziyuConciliationProvider = NotifierProvider<ZiyuConciliationNotifier, ZiyuConciliationState>(() => ZiyuConciliationNotifier());
