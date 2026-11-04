import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../trips/domain/models/viatico_model.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../domain/models/liquidacion_model.dart';
import '../../domain/models/company_config_model.dart';
import '../../domain/models/incidencia_model.dart';
import '../../domain/models/recurring_expense_model.dart';
import '../../domain/models/cotizacion_model.dart';

/// Repositorio exclusivo del Admin.
/// A diferencia del TripRepository (scoped al chofer actual),
/// este lee datos de toda la empresa usando idEmpresa como filtro.
class AdminRepository {
  final FirebaseFirestore _db;
  AdminRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  // ─── VIAJES (KPIs) ─────────────────────────────────────────────────────────

  /// Escucha TODOS los viajes de la empresa (para cálculo histórico y acumulado de F29)
  Stream<List<TripModel>> watchAllTrips(String idEmpresa) {
    return _db
        .collection('viajes')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .snapshots()
        .map((s) => s.docs.map((d) => TripModel.fromMap(d.data(), d.id)).toList());
  }

  /// Escucha TODOS los gastos de la empresa (para cálculo histórico y acumulado de F29)
  Stream<List<ExpenseModel>> watchAllExpenses(String idEmpresa) {
    return _db
        .collection('gastos')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .snapshots()
        .map((s) => s.docs.map((d) => ExpenseModel.fromMap(d.data(), d.id)).toList());
  }

  /// Retorna todos los viajes del mes indicado para la empresa.
  Stream<List<TripModel>> watchMonthlyTrips(String idEmpresa, DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1).toIso8601String();
    final monthEnd = DateTime(month.year, month.month + 1, 1).toIso8601String();

    return _db
        .collection('viajes')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('startDate', isGreaterThanOrEqualTo: monthStart)
        .where('startDate', isLessThan: monthEnd)
        .snapshots()
        .map((s) => s.docs.map((d) => TripModel.fromMap(d.data(), d.id)).toList());
  }

  Future<void> saveTrip(TripModel trip) async {
    if (trip.id.isEmpty) {
      final docRef = _db.collection('viajes').doc();
      final newTrip = trip.copyWith(id: docRef.id);
      await docRef.set(newTrip.toMap());
    } else {
      await _db.collection('viajes').doc(trip.id).update(trip.toMap());
    }
  }

  Future<void> updateTripMap(String tripId, Map<String, dynamic> data) async {
    await _db.collection('viajes').doc(tripId).update(data);
  }

  Future<void> deleteTrip(String tripId) async {
    await _db.collection('viajes').doc(tripId).delete();
  }

  /// Retorna los viajes OS pendientes de liquidar (que no estén Liquidados ni en Ruta)
  Future<List<TripModel>> getTripsForConciliation(String idEmpresa) async {
    final snapshot = await _db
        .collection('viajes')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('billingType', isEqualTo: 'OS')
        .where('status', isEqualTo: 'Finalizado')
        .get();
        
    return snapshot.docs.map((d) => TripModel.fromMap(d.data(), d.id)).toList();
  }

  /// Retorna todos los gastos del mes indicado para la empresa.
  Stream<List<ExpenseModel>> watchMonthlyExpenses(String idEmpresa, DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1).toIso8601String();
    final monthEnd = DateTime(month.year, month.month + 1, 1).toIso8601String();

    return _db
        .collection('gastos')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('date', isGreaterThanOrEqualTo: monthStart)
        .where('date', isLessThan: monthEnd)
        .snapshots()
        .map((s) => s.docs.map((d) => ExpenseModel.fromMap(d.data(), d.id)).toList());
  }

  /// Versión Future (para analítica de tendencia histórica)
  Future<List<TripModel>> getTripsForMonth(String idEmpresa, DateTime month) async {
    final monthStart = DateTime(month.year, month.month, 1).toIso8601String();
    final monthEnd = DateTime(month.year, month.month + 1, 1).toIso8601String();

    final snap = await _db
        .collection('viajes')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('startDate', isGreaterThanOrEqualTo: monthStart)
        .where('startDate', isLessThan: monthEnd)
        .get();

    return snap.docs.map((d) => TripModel.fromMap(d.data(), d.id)).toList();
  }

  /// Obtiene el último odómetro real registrado para un vehículo consultando sus jornadas
  Future<double?> getLatestOdometerForVehicle(String idEmpresa, String patente) async {
    try {
      final snapshot = await _db
          .collection('jornadas')
          .where('idEmpresa', isEqualTo: idEmpresa)
          .where('patenteCamion', isEqualTo: patente)
          .orderBy('startTime', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      
      final data = snapshot.docs.first.data();
      final endOdometer = data['endOdometer'];
      final startOdometer = data['startOdometer'];
      
      if (endOdometer != null) {
        return (endOdometer as num).toDouble();
      } else if (startOdometer != null) {
        return (startOdometer as num).toDouble();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<ExpenseModel>> getExpensesForMonth(String idEmpresa, DateTime month) async {
    final monthStart = DateTime(month.year, month.month, 1).toIso8601String();
    final monthEnd = DateTime(month.year, month.month + 1, 1).toIso8601String();
    final snap = await _db
        .collection('gastos')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('date', isGreaterThanOrEqualTo: monthStart)
        .where('date', isLessThan: monthEnd)
        .get();
    return snap.docs.map((d) => ExpenseModel.fromMap(d.data(), d.id)).toList();
  }

  Future<void> saveExpense(ExpenseModel expense) async {
    if (expense.id.isEmpty) {
      await _db.collection('gastos').add(expense.toMap());
    } else {
      await _db.collection('gastos').doc(expense.id).update(expense.toMap());
    }
  }

  Future<void> deleteExpense(String expenseId) async {
    await _db.collection('gastos').doc(expenseId).delete();
  }

  // ─── GASTOS FIJOS RECURRENTES ───────────────────────────────────────────────

  /// Aplica los gastos fijos recurrentes al mes indicado.
  /// Crea un documento de gasto real por cada gasto recurrente activo.
  /// Marca el mes como aplicado en la configuración para no duplicar.
  Future<int> applyRecurringExpenses({
    required String idEmpresa,
    required String adminUid,
    required DateTime month,
    required List<RecurringExpenseModel> gastosRecurrentes,
  }) async {
    final batch = _db.batch();
    final monthKey = "${month.year}-${month.month.toString().padLeft(2, '0')}";
    // Fecha: primer día del mes
    final expenseDate = DateTime(month.year, month.month, 15);
    int count = 0;

    for (final gasto in gastosRecurrentes) {
      if (!gasto.activo) continue;

      final docRef = _db.collection('gastos').doc();
      final expense = ExpenseModel(
        id: docRef.id,
        idEmpresa: idEmpresa,
        idChofer: adminUid,
        idJornada: 'GASTO_FIJO',
        amount: gasto.monto,
        type: gasto.tipo,
        date: expenseDate,
        description: '[Gasto Fijo] ${gasto.nombre}',
        status: 'Pagado',
        vehicleId: gasto.vehicleId,
      );
      batch.set(docRef, expense.toMap());
      count++;
    }

    // Marcar mes como aplicado
    final configRef = _db.collection('configuraciones_empresa').doc(idEmpresa);
    batch.update(configRef, {
      'mesesGastosFijosAplicados': FieldValue.arrayUnion([monthKey]),
    });

    await batch.commit();
    return count;
  }

  // ─── VIÁTICOS (Admin panel) ─────────────────────────────────────────────────

  /// Todas las rendiciones de la empresa ordenadas por fecha.
  Stream<List<ViaticoModel>> watchAllViaticos(String idEmpresa) {
    return _db
        .collection('viaticos')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .orderBy('creadoEn', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => ViaticoModel.fromMap(d.data(), d.id)).toList());
  }

  /// Marca una rendición como pagada. El stream del conductor se actualiza en tiempo real.
  Future<void> markViaticoPaid(String viaticoId, double montoTotal) async {
    await _db.collection('viaticos').doc(viaticoId).update({
      'estado': 'pagado',
      'montoTotal': montoTotal,
      'fechaPago': DateTime.now().toIso8601String(),
    });
  }

  /// Elimina una rendición de viáticos pendiente de Firestore (Modo Admin).
  Future<void> deleteViatico(String viaticoId) async {
    await _db.collection('viaticos').doc(viaticoId).delete();
  }

  /// Obtiene los viajes asociados a un chofer en un rango de fechas.
  Future<List<TripModel>> getTripsForViatico(String idEmpresa, String idChofer, DateTime start, DateTime end) async {
    final snapshot = await _db
        .collection('viajes')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('idChofer', isEqualTo: idChofer)
        .get();

    final trips = snapshot.docs.map((doc) => TripModel.fromMap(doc.data(), doc.id)).toList();
    
    // Filtrado local para coincidir exactamente con el rango (igual que en TripRepository)
    return trips.where((t) {
      return t.startDate.isAfter(start.subtract(const Duration(days: 1))) && 
             t.startDate.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }

  // ─── LIQUIDACIONES (Facturación y Pagos) ───────────────────────────────────

  Stream<List<LiquidacionModel>> watchLiquidaciones(String idEmpresa, {DateTime? month, String? vehicleId}) {
    Query query = _db.collection('liquidaciones').where('idEmpresa', isEqualTo: idEmpresa);

    // Si hay mes, filtramos por el rango de ese mes
    if (month != null) {
      final start = Timestamp.fromDate(DateTime(month.year, month.month, 1));
      final end = Timestamp.fromDate(DateTime(month.year, month.month + 1, 1));
      query = query.where('fechaCreacion', isGreaterThanOrEqualTo: start).where('fechaCreacion', isLessThan: end);
    }

    return query.snapshots().map((s) {
      final list = s.docs.map((d) => LiquidacionModel.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
      
      // Filtrado local por vehículo si es necesario (ya que el vehicleId está dentro de detalleCruce o tripIds)
      if (vehicleId != null) {
        return list.where((liq) {
          return liq.detalleCruce?.any((d) => d['vehicleId'] == vehicleId) ?? false;
        }).toList();
      }
      
      return list;
    });
  }

  /// Genera una liquidación atómicamente y marca los viajes como "Liquidada"
  Future<void> createLiquidacion(LiquidacionModel liq) async {
    final batch = _db.batch();

    // Guardar liquidación
    final liqRef = _db.collection('liquidaciones').doc(liq.id);
    batch.set(liqRef, liq.toMap());

    // Actualizar estado de los viajes a 'Liquidada'
    for (final tripId in liq.tripIds) {
      final tripRef = _db.collection('viajes').doc(tripId);
      batch.update(tripRef, {
        'status': 'Liquidada',
        'liquidacionId': liq.id, // Referencia inversa
      });
    }

    await batch.commit();
  }

  /// Elimina una liquidación y devuelve los viajes a su estado anterior
  Future<void> deleteLiquidacion(String liqId, List<String> tripIds) async {
    final batch = _db.batch();

    // 1. Eliminar documento de liquidación
    batch.delete(_db.collection('liquidaciones').doc(liqId));

    // 2. Revertir viajes a estado 'Finalizado' y limpiar referencia de liquidación
    for (final id in tripIds) {
      batch.update(_db.collection('viajes').doc(id), {
        'status': 'Finalizado',
        'liquidacionId': FieldValue.delete(),
      });
    }

    await batch.commit();
  }

  /// Vincula una factura a la liquidación y la marca como 'facturada'
  Future<void> linkFactura(String liqId, String nroFactura, List<String> tripIds) async {
    final batch = _db.batch();
    
    batch.update(_db.collection('liquidaciones').doc(liqId), {
      'estado': 'facturada',
      'nroFactura': nroFactura,
    });

    for (final tripId in tripIds) {
      batch.update(_db.collection('viajes').doc(tripId), {'status': 'Facturada'});
    }

    await batch.commit();
  }

  /// Marca la liquidación y todos sus viajes como 'Pagada'
  Future<void> markLiquidacionPaid(String liqId, List<String> tripIds) async {
    final batch = _db.batch();
    
    batch.update(_db.collection('liquidaciones').doc(liqId), {
      'estado': 'pagada',
      'fechaPago': DateTime.now().toIso8601String(),
    });

    for (final tripId in tripIds) {
      batch.update(_db.collection('viajes').doc(tripId), {'status': 'Pagada'});
    }

    await batch.commit();
  }

  // ─── FLOTA (Vehículos) ─────────────────────────────────────────────────────

  Stream<List<VehicleModel>> watchVehicles(String idEmpresa) {
    return _db
        .collection('vehiculos')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .snapshots()
        .map((s) => s.docs.map((d) => VehicleModel.fromMap(d.data(), d.id)).toList());
  }

  Future<void> addVehicle(VehicleModel v) async {
    await _db.collection('vehiculos').doc(v.id).set(v.toMap());
  }

  Future<void> updateVehicle(VehicleModel v) async {
    await _db.collection('vehiculos').doc(v.id).update(v.toMap());
  }

  // ─── INCIDENCIAS (Reportes de Choferes) ─────────────────────────────────────

  Stream<List<IncidenciaModel>> watchIncidencias(String idEmpresa) {
    return _db
        .collection('incidencias')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .orderBy('fecha', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => IncidenciaModel.fromMap(d.data(), d.id)).toList());
  }

  Future<void> updateIncidenciaEstado(String id, String nuevoEstado) async {
    await _db.collection('incidencias').doc(id).update({'estado': nuevoEstado});
  }

  Future<void> convertIncidenciaToExpense(IncidenciaModel incidencia, double amount) async {
    final docRef = _db.collection('gastos').doc();
    final expense = ExpenseModel(
      id: docRef.id,
      idEmpresa: incidencia.idEmpresa,
      idChofer: incidencia.idChofer,
      idJornada: 'ReporteAdmin',
      amount: amount,
      type: 'Mantenimiento',
      date: DateTime.now(),
      description: '[Incidencia] ${incidencia.descripcion}',
      status: 'Pagado',
      vehicleId: incidencia.vehiclePatente,
    );

    final batch = _db.batch();
    batch.set(docRef, expense.toMap());
    batch.update(_db.collection('incidencias').doc(incidencia.id), {'estado': 'Solucionado'});
    await batch.commit();
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _db.collection('vehiculos').doc(vehicleId).delete();
  }

  // ─── CONDUCTORES ────────────────────────────────────────────────────────────

  /// Todos los usuarios con rol CHOFER en la empresa.
  Stream<List<UserModel>> watchChoferes(String idEmpresa) {
    return _db
        .collection('usuarios')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('rol', isEqualTo: 'CHOFER')
        .snapshots()
        .map((s) => s.docs.map((d) => UserModel.fromMap(d.data(), d.id)).toList());
  }

  /// Actualiza los datos extendidos de un chofer (RUT, Licencias, Sueldo, etc.)
  Future<void> updateChoferProfile(UserModel user) async {
    await _db.collection('usuarios').doc(user.uid).update(user.toMap());
  }

  /// Obtiene todos los viajes hasta una fecha final (para cálculo de remanente acumulado)
  Future<List<TripModel>> getTripsUntil(String idEmpresa, DateTime until) async {
    final untilStr = until.toIso8601String();
    final snap = await _db
        .collection('viajes')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('startDate', isLessThan: untilStr)
        .get();
    return snap.docs.map((d) => TripModel.fromMap(d.data(), d.id)).toList();
  }

  /// Obtiene todos los gastos hasta una fecha final (para cálculo de remanente acumulado)
  Future<List<ExpenseModel>> getExpensesUntil(String idEmpresa, DateTime until) async {
    final untilStr = until.toIso8601String();
    final snap = await _db
        .collection('gastos')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('date', isLessThan: untilStr)
        .get();
    return snap.docs.map((d) => ExpenseModel.fromMap(d.data(), d.id)).toList();
  }

  // ─── CONFIGURACIÓN DE EMPRESA ──────────────────────────────────────────────

  /// Obtiene la configuración global de la empresa (Sueldo mínimo, Umbral KM, etc.)
  Stream<CompanyConfigModel?> watchCompanyConfig(String idEmpresa) {
    return _db
        .collection('configuraciones_empresa')
        .doc(idEmpresa)
        .snapshots()
        .map((doc) => doc.exists ? CompanyConfigModel.fromMap(doc.data()!, doc.id) : null);
  }

  /// Guarda o actualiza la configuración de la empresa.
  Future<void> updateCompanyConfig(CompanyConfigModel config) async {
    await _db
        .collection('configuraciones_empresa')
        .doc(config.idEmpresa)
        .set(config.toMap(), SetOptions(merge: true));
  }

  /// Sincroniza el historial de UTM en la configuración de la empresa.
  /// Fusiona los nuevos datos con los existentes para no perder registros antiguos.
  Future<void> syncUtmHistory(String idEmpresa, Map<String, double> newHistory) async {
    final docRef = _db.collection('configuraciones_empresa').doc(idEmpresa);
    final doc = await docRef.get();
    
    if (doc.exists) {
      final currentMap = Map<String, dynamic>.from(doc.data()?['utmHistory'] ?? {});
      // Fusionamos: nuevos datos sobreescriben o añaden a los actuales
      newHistory.forEach((key, value) {
        currentMap[key] = value;
      });
      
      await docRef.update({'utmHistory': currentMap});
    } else {
      // Si no existe el doc, lo creamos solo con el historial (fallback raro)
      await docRef.set({'utmHistory': newHistory}, SetOptions(merge: true));
    }
  }

  // ─── SOLICITUDES DE SERVICIO (IA Inbox) ───────────────────────────────────

  /// Busca el último viaje realizado en la misma ruta para sugerir una tarifa.
  Future<double?> getSuggestedRate(String idEmpresa, String origin, String destination) async {
    final snap = await _db
        .collection('viajes')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .where('origin', isEqualTo: origin)
        .where('destination', isEqualTo: destination)
        .orderBy('startDate', descending: true)
        .limit(1)
        .get();
    
    if (snap.docs.isEmpty) return null;
    return (snap.docs.first.data()['value'] as num?)?.toDouble();
  }

  Future<void> updateServiceRequest(String requestId, Map<String, dynamic> data) async {
    await _db.collection('service_requests').doc(requestId).update(data);
  }

  // ─── COTIZACIONES ───────────────────────────────────────────────────────────

  Future<CotizacionModel> saveCotizacion(CotizacionModel cotizacion) async {
    final docRef = _db.collection('cotizaciones').doc(); 
    
    final year = DateTime.now().year;
    final counterRef = _db.collection('contadores').doc('cotizaciones_${cotizacion.idEmpresa}_$year');
    
    String assignedNum = '';

    await _db.runTransaction<void>((transaction) async {
      final counterDoc = await transaction.get(counterRef);
      int seq = 0;
      if (counterDoc.exists) {
        seq = (counterDoc.data()?['seq'] as num?)?.toInt() ?? 0;
      }
      final int newSeq = seq + 1;
      transaction.set(
          counterRef,
          {'seq': newSeq, 'idEmpresa': cotizacion.idEmpresa},
          SetOptions(merge: true),
      );

      assignedNum = 'COT-$year-${newSeq.toString().padLeft(3, '0')}';

      final updatedCotizacion = cotizacion.copyWith(
        id: docRef.id,
        numeroCotizacion: assignedNum,
      );

      transaction.set(docRef, updatedCotizacion.toMap());
    });

    return cotizacion.copyWith(id: docRef.id, numeroCotizacion: assignedNum);
  }

  Future<void> updateCotizacion(CotizacionModel cotizacion) async {
    // Preserve static fields by letting the backend override whatever is in the passed model 
    // with the existing static fields if needed, OR we can just do an update of specific fields.
    // However, the cleanest is to update the document with all fields from the model, but 
    // we should trust the presentation layer passed the original static fields in the model.
    // The user said: "Debe preservar explícitamente estos campos estaticos del documento original (no tomarlos del modelo que llega): createdAt, numeroCotizacion, creadoPor, idEmpresa."
    // So we fetch the existing doc, merge it into the new model, and then update.
    
    final docRef = _db.collection('cotizaciones').doc(cotizacion.id);
    final doc = await docRef.get();
    
    if (doc.exists) {
      final data = doc.data()!;
      final updatedData = cotizacion.toMap();
      
      // Preserve static fields
      updatedData['createdAt'] = data['createdAt'];
      updatedData['numeroCotizacion'] = data['numeroCotizacion'];
      updatedData['creadoPor'] = data['creadoPor'];
      updatedData['idEmpresa'] = data['idEmpresa'];
      
      await docRef.update(updatedData);
    }
  }

  Future<void> softDeleteCotizacion(String id) async {
    await _db.collection('cotizaciones').doc(id).update({'eliminada': true});
  }

  Future<void> updateCotizacionStatus(String id, String newStatus) async {
    await _db.collection('cotizaciones').doc(id).update({'estado': newStatus});
  }

  Stream<List<CotizacionModel>> watchCotizaciones(String idEmpresa) {
    return _db
        .collection('cotizaciones')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => CotizacionModel.fromMap(d.data(), d.id)).toList());
  }
}
