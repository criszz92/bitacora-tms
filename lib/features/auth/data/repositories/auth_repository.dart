import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../domain/models/user_model.dart';
import '../../domain/models/company_model.dart';
import '../../domain/models/invitation_model.dart';

class AuthRepository {
  final FirebaseFirestore _firestore;

  AuthRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ─────────────────────────────────────────────
  // FLUJO ADMIN — Primer registro
  // ─────────────────────────────────────────────

  /// Crea el perfil de un administrador nuevo.
  /// Genera un idEmpresa único a partir del nombre de la empresa.
  /// Crea el documento en `empresas` y en `usuarios`.
  Future<void> createAdminProfile({
    required User authUser,
    required String nombre,
    required String nombreEmpresa,
  }) async {
    final idEmpresa = _generateEmpresaId(nombreEmpresa);

    final company = CompanyModel(
      id: idEmpresa,
      nombre: nombreEmpresa,
      idAdmin: authUser.uid,
      creadaEn: DateTime.now(),
    );

    final userProfile = UserModel(
      uid: authUser.uid,
      idEmpresa: idEmpresa,
      email: authUser.email ?? '',
      nombre: nombre,
      rol: 'ADMIN',
    );

    // Transacción atómica: ambos documentos se crean juntos
    final batch = _firestore.batch();
    batch.set(_firestore.collection('empresas').doc(idEmpresa), company.toMap());
    batch.set(_firestore.collection('usuarios').doc(authUser.uid), userProfile.toMap());
    await batch.commit();
  }

  // ─────────────────────────────────────────────
  // FLUJO CHOFER — Registro con código de invitación
  // ─────────────────────────────────────────────

  /// Valida el código de invitación. Retorna el modelo si es válido y no fue usado.
  /// Retorna `null` si el código no existe o ya fue utilizado.
  Future<InvitationModel?> validateInvitationCode(String code) async {
    final normalizedCode = code.trim().toUpperCase();

    final snapshot = await _firestore
        .collection('invitaciones')
        .where('codigo', isEqualTo: normalizedCode)
        .where('usada', isEqualTo: false)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    return InvitationModel.fromMap(doc.data(), doc.id);
  }

  /// Crea el perfil del chofer y marca el código de invitación como usado.
  Future<void> createChoferProfile({
    required User authUser,
    required String nombre,
    required InvitationModel invitation,
  }) async {
    final userProfile = UserModel(
      uid: authUser.uid,
      idEmpresa: invitation.idEmpresa,
      email: authUser.email ?? '',
      nombre: nombre,
      rol: 'CHOFER',
    );

    final batch = _firestore.batch();

    // Crea el perfil del chofer
    batch.set(
      _firestore.collection('usuarios').doc(authUser.uid),
      userProfile.toMap(),
    );

    // Marca el código como usado (candado de un solo uso)
    batch.update(
      _firestore.collection('invitaciones').doc(invitation.id),
      {'usada': true, 'usadaPor': authUser.uid},
    );

    await batch.commit();
  }

  // ─────────────────────────────────────────────
  // GENERACIÓN DE CÓDIGO DE INVITACIÓN (Admin)
  // ─────────────────────────────────────────────

  /// Genera un código único de 8 caracteres en formato "BIT-XXXX".
  /// El admin lo copia y envía al chofer por WhatsApp u otro medio.
  Future<String> generateInvitationCode(String idEmpresa) async {
    final code = _generateUniqueCode();

    final invitation = InvitationModel(
      id: _firestore.collection('invitaciones').doc().id,
      codigo: code,
      idEmpresa: idEmpresa,
      usada: false,
      creadaEn: DateTime.now(),
    );

    await _firestore
        .collection('invitaciones')
        .doc(invitation.id)
        .set(invitation.toMap());

    return code;
  }

  /// Retorna todos los códigos de invitación generados por la empresa.
  Stream<List<InvitationModel>> watchInvitationCodes(String idEmpresa) {
    return _firestore
        .collection('invitaciones')
        .where('idEmpresa', isEqualTo: idEmpresa)
        .orderBy('creadaEn', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => InvitationModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // ─────────────────────────────────────────────
  // HELPERS PRIVADOS
  // ─────────────────────────────────────────────

  /// Convierte "Transportes Inostroza SpA" → "transportes_inostroza_spa_3f2a"
  String _generateEmpresaId(String nombreEmpresa) {
    final slug = nombreEmpresa
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'ñ'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    // Sufijo aleatorio de 4 chars para evitar colisiones entre empresas con mismo nombre
    final suffix = _randomHex(4);
    return '${slug}_$suffix';
  }

  /// Genera un código de invitación como "BIT-7F3A"
  String _generateUniqueCode() {
    return 'BIT-${_randomHex(4)}';
  }

  String _randomHex(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
