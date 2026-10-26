import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/infraestructura_vial_model.dart';

class InfraestructuraRepository {
  final FirebaseFirestore _db;
  InfraestructuraRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  static const String _collection = 'infraestructura_vial';

  /// Escucha en tiempo real todos los puntos de infraestructura vial
  Stream<List<PuntoInfraestructuraModel>> watchPuntos({bool soloActivos = true}) {
    Query query = _db.collection(_collection);
    if (soloActivos) {
      query = query.where('activo', isEqualTo: true);
    }
    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return PuntoInfraestructuraModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  /// Obtiene los puntos una sola vez
  Future<List<PuntoInfraestructuraModel>> getPuntos({bool soloActivos = true}) async {
    Query query = _db.collection(_collection);
    if (soloActivos) {
      query = query.where('activo', isEqualTo: true);
    }
    final snapshot = await query.get();
    return snapshot.docs.map((doc) {
      return PuntoInfraestructuraModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }

  /// Guarda o actualiza un punto en la colección universal
  Future<String> guardarPunto(PuntoInfraestructuraModel punto) async {
    if (punto.id.isEmpty) {
      final docRef = _db.collection(_collection).doc();
      final map = punto.toMap();
      await docRef.set(map);
      return docRef.id;
    } else {
      await _db.collection(_collection).doc(punto.id).set(punto.toMap(), SetOptions(merge: true));
      return punto.id;
    }
  }

  /// Elimina un punto de la base universal (solo Maestro)
  Future<void> eliminarPunto(String id) async {
    await _db.collection(_collection).doc(id).delete();
  }

  /// Alterna estado activo/inactivo
  Future<void> toggleActivo(String id, bool nuevoEstado) async {
    await _db.collection(_collection).doc(id).update({
      'activo': nuevoEstado,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }
}

// ─── Riverpod Providers ────────────────────────────────────────────────────────

final infraestructuraRepositoryProvider = Provider<InfraestructuraRepository>((ref) {
  return InfraestructuraRepository();
});

final puntosInfraestructuraProvider = StreamProvider<List<PuntoInfraestructuraModel>>((ref) {
  final repo = ref.watch(infraestructuraRepositoryProvider);
  return repo.watchPuntos(soloActivos: true);
});

final peajesProvider = Provider<List<PuntoInfraestructuraModel>>((ref) {
  final puntosAsync = ref.watch(puntosInfraestructuraProvider);
  return (puntosAsync.value ?? []).where((p) => p.tipo == TipoPuntoInfraestructura.peaje).toList();
});

final romanasProvider = Provider<List<PuntoInfraestructuraModel>>((ref) {
  final puntosAsync = ref.watch(puntosInfraestructuraProvider);
  return (puntosAsync.value ?? []).where((p) => p.tipo == TipoPuntoInfraestructura.romana).toList();
});

final restriccionesProvider = Provider<List<PuntoInfraestructuraModel>>((ref) {
  final puntosAsync = ref.watch(puntosInfraestructuraProvider);
  return (puntosAsync.value ?? []).where((p) => p.tipo == TipoPuntoInfraestructura.restriccion).toList();
});
