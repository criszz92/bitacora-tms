import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/models/expense_model.dart';
import '../../domain/models/shift_model.dart';
import '../../domain/models/vehicle_model.dart';
import '../../domain/models/viatico_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// Provides the repository instance, re-creándose si el usuario cambia
final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final userProfile = ref.watch(currentUserProfileProvider).value;
  return TripRepository(currentUser: userProfile);
});

// Escucha en tiempo real si hay una jornada abierta (Inició el día)
final activeShiftProvider = StreamProvider<ShiftModel?>((ref) {
  final repo = ref.watch(tripRepositoryProvider);
  return repo.watchActiveShift();
});

// Escucha en tiempo real (Stream) los viajes activos de Firestore
final activeTripsProvider = StreamProvider<List<TripModel>>((ref) {
  final repo = ref.watch(tripRepositoryProvider);
  return repo.watchActiveTrips();
});

// Escucha en tiempo real (Stream) los gastos de Firestore
final expensesProvider = StreamProvider<List<ExpenseModel>>((ref) {
  final repo = ref.watch(tripRepositoryProvider);
  return repo.watchRecentExpenses();
});

// Calcula el total de gastos basado únicamente en la JORNADA ACTIVA
final totalExpensesProvider = Provider<AsyncValue<double>>((ref) {
  final expensesState = ref.watch(expensesProvider);
  final activeShiftState = ref.watch(activeShiftProvider);

  if (activeShiftState.value == null) {
    return const AsyncValue.data(0.0);
  }

  return expensesState.whenData((expenses) {
    final shiftExpenses = expenses.where((e) => e.idJornada == activeShiftState.value!.id);
    return shiftExpenses.fold<double>(0.0, (sum, item) => sum + item.amount);
  });
});

// Escucha en tiempo real los camiones registrados en la empresa (para ShiftStartScreen)
final vehiclesProvider = StreamProvider<List<VehicleModel>>((ref) {
  final repo = ref.watch(tripRepositoryProvider);
  return repo.watchVehicles();
});

// Escucha en tiempo real las rendiciones de viáticos del chofer (para pintar el calendario)
final viaticosProvider = StreamProvider<List<ViaticoModel>>((ref) {
  final repo = ref.watch(tripRepositoryProvider);
  return repo.watchViaticos();
});
// Escucha el camión específico que el conductor está operando en su jornada actual
final currentVehicleProvider = Provider<AsyncValue<VehicleModel?>>((ref) {
  final shift = ref.watch(activeShiftProvider).value;
  final vehicles = ref.watch(vehiclesProvider).value ?? [];
  
  if (shift == null) return const AsyncValue.data(null);
  
  try {
    final vehicle = vehicles.firstWhere((v) => v.patente == shift.patenteCamion);
    return AsyncValue.data(vehicle);
  } catch (_) {
    return const AsyncValue.data(null);
  }
});
