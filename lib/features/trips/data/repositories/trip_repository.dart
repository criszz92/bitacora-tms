import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/models/expense_model.dart';
import '../../domain/models/shift_model.dart';
import '../../domain/models/vehicle_model.dart';
import '../../domain/models/viatico_model.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../admin/domain/models/service_request_model.dart';
import '../../../admin/domain/models/incidencia_model.dart';
import '../../../../core/models/audit_log_model.dart';
import '../../../../core/utils/security_utils.dart';

class TripRepository {
  final FirebaseFirestore _firestore;
  final UserModel? currentUser;

  TripRepository({FirebaseFirestore? firestore, this.currentUser}) 
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // Extraemos el candado de seguridad directamente del perfil conectado
  String get currentEmpresaId => currentUser?.idEmpresa ?? '';
  String get currentChoferId => currentUser?.uid ?? '';

  // ================= JORNADA (SHIFT) =================
  
  // Observa si el chofer tiene un turno de trabajo abierto hoy
  Stream<ShiftModel?> watchActiveShift() {
    return _firestore
        .collection('jornadas')
        .where('idEmpresa', isEqualTo: currentEmpresaId)
        .where('idChofer', isEqualTo: currentChoferId)
        .where('status', isEqualTo: 'Activa')
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return ShiftModel.fromMap(doc.data(), doc.id);
    });
  }

  Future<void> startShift(ShiftModel shift) async {
    await _firestore.collection('jornadas').doc(shift.id).set(shift.toMap());
  }

  Future<void> endShift(String shiftId, int endOdometer) async {
    await _firestore.collection('jornadas').doc(shiftId).update({
      'endTime': DateTime.now().toIso8601String(),
      'endOdometer': endOdometer,
      'status': 'Cerrada',
    });

    await _logAction(
      accion: 'CIERRE_JORNADA',
      coleccion: 'jornadas',
      documentoId: shiftId,
      detalles: {'endOdometer': endOdometer},
    );
  }

  // ================= VIAJES Y GASTOS =================

  // Escucha en TIEMPO REAL los viajes activos del chofer en su empresa
  Stream<List<TripModel>> watchActiveTrips() {
    return _firestore
        .collection('viajes')
        .where('idEmpresa', isEqualTo: currentEmpresaId)
        .where('idChofer', isEqualTo: currentChoferId)
        .where('status', isEqualTo: 'En Ruta')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => TripModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Obtiene los viajes de un chofer en un rango de fechas para rendición de viáticos
  Future<List<TripModel>> getTripsByDateRange(DateTime start, DateTime end) async {
    final snapshot = await _firestore
        .collection('viajes')
        .where('idEmpresa', isEqualTo: currentEmpresaId)
        .where('idChofer', isEqualTo: currentChoferId)
        .get(const GetOptions(source: Source.server));

    final trips = snapshot.docs.map((doc) => TripModel.fromMap(doc.data(), doc.id)).toList();
    
    // Filtrado local para evitar requerir Composite Indexes en Firestore tempranamente
    return trips.where((t) {
      return t.startDate.isAfter(start.subtract(const Duration(days: 1))) && 
             t.startDate.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }

  // Escucha en TIEMPO REAL los gastos recientes
  Stream<List<ExpenseModel>> watchRecentExpenses() {
    return _firestore
        .collection('gastos')
        .where('idEmpresa', isEqualTo: currentEmpresaId)
        .where('idChofer', isEqualTo: currentChoferId)
        .orderBy('date', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ExpenseModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Guarda un gasto directamente en Firestore
  Future<void> addExpense(ExpenseModel expense) async {
    await _firestore.collection('gastos').doc(expense.id).set(expense.toMap());
  }

  // Inicia un nuevo viaje
  Future<void> startTrip(TripModel trip) async {
    // Sanitizar campos de texto
    final sanitizedTrip = trip.copyWith(
      origin: SecurityUtils.sanitizeText(trip.origin),
      destination: SecurityUtils.sanitizeText(trip.destination),
      comments: SecurityUtils.sanitizeText(trip.comments),
    );
    await _firestore.collection('viajes').doc(sanitizedTrip.id).set(sanitizedTrip.toMap());
  }

  // Finaliza un viaje en ruta
  Future<void> endTrip(String tripId, {double? totalKm}) async {
    await _firestore.collection('viajes').doc(tripId).update({
      'status': 'Finalizado',
      'endTime': DateTime.now().toIso8601String(),
      ...(totalKm != null ? {'totalKm': totalKm} : {}),
    });
  }

  // Finaliza un viaje y guarda el número de guía obtenido al cerrar la carga
  Future<void> endTripWithGuide(String tripId, String? guideNumber, {double? totalKm}) async {
    final sanitizedGuide = guideNumber != null ? SecurityUtils.sanitizeText(guideNumber) : null;
    
    await _firestore.collection('viajes').doc(tripId).update({
      'status': 'Finalizado',
      'endTime': DateTime.now().toIso8601String(),
      ...(sanitizedGuide != null ? {'guideNumber': sanitizedGuide} : {}),
      ...(totalKm != null ? {'totalKm': totalKm} : {}),
    });

    await _logAction(
      accion: 'CIERRE_VIAJE',
      coleccion: 'viajes',
      documentoId: tripId,
      detalles: {
        'guideNumber': sanitizedGuide,
        'totalKm': totalKm,
      },
    );
  }

  // ================= VEHÍCULOS =================

  /// Escucha en tiempo real la lista de camiones registrados para esta empresa.
  Stream<List<VehicleModel>> watchVehicles() {
    return _firestore
        .collection('vehiculos')
        .where('idEmpresa', isEqualTo: currentEmpresaId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => VehicleModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  /// Registra un nuevo camión en la empresa.
  Future<void> addVehicle(VehicleModel vehicle) async {
    await _firestore.collection('vehiculos').doc(vehicle.id).set(vehicle.toMap());
  }

  /// Elimina un camión de la empresa.
  Future<void> deleteVehicle(String vehicleId) async {
    await _firestore.collection('vehiculos').doc(vehicleId).delete();
  }

  // ================= VIÁTICOS =================

  /// Guarda una rendición de viáticos en Firestore con estado 'pendiente'.
  Future<void> saveViatico(ViaticoModel viatico) async {
    await _firestore.collection('viaticos').doc(viatico.id).set(viatico.toMap());
  }

  /// Elimina una rendición de viáticos pendiente de Firestore.
  Future<void> deleteViatico(String viaticoId) async {
    await _firestore.collection('viaticos').doc(viaticoId).delete();
  }


  /// Escucha en tiempo real las rendiciones del chofer para pintar el calendario.
  Stream<List<ViaticoModel>> watchViaticos() {
    return _firestore
        .collection('viaticos')
        .where('idChofer', isEqualTo: currentChoferId)
        .where('idEmpresa', isEqualTo: currentEmpresaId)
        .orderBy('creadoEn', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ViaticoModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ================= INCIDENCIAS =================

  Future<void> reportIncidencia(IncidenciaModel incidencia) async {
    final sanitized = incidencia.copyWith(
      descripcion: SecurityUtils.sanitizeText(incidencia.descripcion),
    );
    await _firestore.collection('incidencias').doc(sanitized.id).set(sanitized.toMap());

    await _logAction(
      accion: 'REPORTE_INCIDENCIA',
      coleccion: 'incidencias',
      documentoId: sanitized.id,
      detalles: {'tipo': sanitized.tipo},
    );
  }

  // ================= ASIGNACIONES INTELIGENTES =================
  
  /// Escucha solicitudes asignadas a este chofer específico
  Stream<List<ServiceRequest>> watchAssignedRequests() {
    return _firestore
        .collection('service_requests')
        .where('assignedTo', isEqualTo: currentChoferId)
        .where('status', isEqualTo: 'assigned')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => ServiceRequest.fromFirestore(doc)).toList());
  }

  Future<void> updateServiceRequestStatus(String requestId, String status) async {
    await _firestore.collection('service_requests').doc(requestId).update({'status': status});
  }

  // ================= AUXILIARES DE SEGURIDAD =================

  Future<void> _logAction({
    required String accion,
    required String coleccion,
    required String documentoId,
    required Map<String, dynamic> detalles,
  }) async {
    try {
      final log = AuditLogModel(
        id: const Uuid().v4(),
        idUsuario: currentChoferId,
        nombreUsuario: currentUser?.nombre ?? 'Desconocido',
        idEmpresa: currentEmpresaId,
        accion: accion,
        coleccion: coleccion,
        documentoId: documentoId,
        detalles: detalles,
        fecha: DateTime.now(),
      );

      await _firestore.collection('auditoria').doc(log.id).set(log.toMap());
    } catch (e) {
      // Fallo silencioso de auditoría para no bloquear la operación principal
      debugPrint('Error al guardar log de auditoría: $e');
    }
  }
}
