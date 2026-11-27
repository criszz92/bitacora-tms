import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/cotizacion_model.dart';
import 'admin_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../../core/utils/chilean_financial_calculator.dart';

// Stream de historial de cotizaciones para la empresa actual
final cotizacionesProvider = StreamProvider<List<CotizacionModel>>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  if (user == null || user.idEmpresa.isEmpty) return Stream.value([]);
  return ref.read(adminRepositoryProvider).watchCotizaciones(user.idEmpresa);
});

// Estado para el formulario del cotizador
class CotizadorFormState {
  final String? editandoId; // Si no es null, estamos editando esta cotización
  final String origen;
  final String destino;
  final String clienteNombre;
  final String clienteRut;
  final String clienteContacto;
  final VehicleModel? vehicle;
  final UserModel? driver;
  final double kmPosicionamiento;
  final double kmRuta;
  final double tarifaPropuesta;
  final double? precioDieselNetoManual; // null means use config default
  final double peajes;
  final double viaticoManual;
  final int diasViaje;
  final double? margenObjetivoManual; // null means use config default

  final bool idaYVuelta; // Nuevo campo

  CotizadorFormState({
    this.editandoId,
    this.origen = '',
    this.destino = '',
    this.clienteNombre = '',
    this.clienteRut = '',
    this.clienteContacto = '',
    this.vehicle,
    this.driver,
    this.kmPosicionamiento = 0.0,
    this.kmRuta = 0.0,
    this.tarifaPropuesta = 0.0,
    this.precioDieselNetoManual,
    this.peajes = 0.0,
    this.viaticoManual = 0.0,
    this.diasViaje = 1,
    this.margenObjetivoManual,
    this.idaYVuelta = false,
  });

  CotizadorFormState copyWith({
    String? editandoId,
    bool clearEditandoId = false,
    String? origen,
    String? destino,
    String? clienteNombre,
    String? clienteRut,
    String? clienteContacto,
    VehicleModel? vehicle,
    UserModel? driver,
    double? kmPosicionamiento,
    double? kmRuta,
    double? tarifaPropuesta,
    double? precioDieselNetoManual,
    bool clearPrecioDieselManual = false,
    double? peajes,
    double? viaticoManual,
    int? diasViaje,
    double? margenObjetivoManual,
    bool clearMargenManual = false,
    bool? idaYVuelta,
  }) {
    return CotizadorFormState(
      editandoId: clearEditandoId ? null : (editandoId ?? this.editandoId),
      origen: origen ?? this.origen,
      destino: destino ?? this.destino,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      clienteRut: clienteRut ?? this.clienteRut,
      clienteContacto: clienteContacto ?? this.clienteContacto,
      vehicle: vehicle ?? this.vehicle,
      driver: driver ?? this.driver,
      kmPosicionamiento: kmPosicionamiento ?? this.kmPosicionamiento,
      kmRuta: kmRuta ?? this.kmRuta,
      tarifaPropuesta: tarifaPropuesta ?? this.tarifaPropuesta,
      precioDieselNetoManual: clearPrecioDieselManual ? null : (precioDieselNetoManual ?? this.precioDieselNetoManual),
      peajes: peajes ?? this.peajes,
      viaticoManual: viaticoManual ?? this.viaticoManual,
      diasViaje: diasViaje ?? this.diasViaje,
      margenObjetivoManual: clearMargenManual ? null : (margenObjetivoManual ?? this.margenObjetivoManual),
      idaYVuelta: idaYVuelta ?? this.idaYVuelta,
    );
  }
}

class CotizadorFormNotifier extends Notifier<CotizadorFormState> {
  @override
  CotizadorFormState build() {
    return CotizadorFormState();
  }

  void updateField({
    String? editandoId,
    String? origen,
    String? destino,
    String? clienteNombre,
    String? clienteRut,
    String? clienteContacto,
    VehicleModel? vehicle,
    UserModel? driver,
    double? kmPosicionamiento,
    double? kmRuta,
    double? tarifaPropuesta,
    double? precioDieselNetoManual,
    double? peajes,
    double? viaticoManual,
    int? diasViaje,
    double? margenObjetivoManual,
    bool? idaYVuelta,
  }) {
    state = state.copyWith(
      editandoId: editandoId,
      origen: origen,
      destino: destino,
      clienteNombre: clienteNombre,
      clienteRut: clienteRut,
      clienteContacto: clienteContacto,
      vehicle: vehicle,
      driver: driver,
      kmPosicionamiento: kmPosicionamiento,
      kmRuta: kmRuta,
      tarifaPropuesta: tarifaPropuesta,
      precioDieselNetoManual: precioDieselNetoManual,
      peajes: peajes,
      viaticoManual: viaticoManual,
      diasViaje: diasViaje,
      margenObjetivoManual: margenObjetivoManual,
      idaYVuelta: idaYVuelta,
    );
  }

  void reset() {
    state = CotizadorFormState();
  }

  void loadCotizacionParaEdicion(CotizacionModel c, List<VehicleModel> vehicles, List<UserModel> choferes) {
    state = CotizadorFormState(
      editandoId: c.id,
      origen: c.origen,
      destino: c.destino,
      clienteNombre: c.clienteNombre,
      clienteRut: c.clienteRut,
      clienteContacto: c.clienteContacto,
      vehicle: vehicles.where((v) => v.id == c.vehicleId).firstOrNull,
      driver: choferes.where((d) => d.uid == c.idChofer).firstOrNull,
      kmPosicionamiento: c.kmPosicionamiento,
      kmRuta: c.kmRuta,
      tarifaPropuesta: c.tarifaPropuesta,
      precioDieselNetoManual: c.precioDieselNeto,
      peajes: c.peajes,
      viaticoManual: c.viaticoManual,
      diasViaje: c.diasViaje,
      margenObjetivoManual: c.margenObjetivo,
      idaYVuelta: c.idaYVuelta,
    );
  }
}

final cotizadorFormProvider = NotifierProvider<CotizadorFormNotifier, CotizadorFormState>(() {
  return CotizadorFormNotifier();
});

// Provider derivado que calcula reactivamente los resultados en base al state y a la config global
final cotizadorResultProvider = Provider<Map<String, double>?>((ref) {
  final formState = ref.watch(cotizadorFormProvider);
  final configAsync = ref.watch(companyConfigProvider);

  if (formState.driver == null || formState.vehicle == null || configAsync.value == null) {
    return null; // Faltan datos esenciales para calcular
  }

  final config = configAsync.value!;

  final precioDiesel = formState.precioDieselNetoManual ?? config.precioDieselNeto;
  final margenObj = formState.margenObjetivoManual ?? config.margenObjetivoCotizacion;

  return ChileanFinancialCalculator.calculateTripQuote(
    driver: formState.driver!,
    vehicle: formState.vehicle!,
    config: config,
    kmPosicionamiento: formState.kmPosicionamiento,
    kmRuta: formState.kmRuta,
    tarifaPropuesta: formState.tarifaPropuesta,
    precioDieselNeto: precioDiesel,
    peajes: formState.peajes,
    viaticoManual: formState.viaticoManual,
    diasViaje: formState.diasViaje,
    margenObjetivo: margenObj,
    idaYVuelta: formState.idaYVuelta,
  );
});
