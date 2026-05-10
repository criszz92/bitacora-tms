import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';

// ─── Firebase Auth state ──────────────────────────────────────────────────────

/// Escucha en tiempo real si hay un usuario conectado en FirebaseAuth.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Extrae el perfil real desde Firestore basado en el usuario conectado.
/// Aquí es donde se carga el vital 'idEmpresa' y el 'rol'.
final currentUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final authUser = ref.watch(authStateProvider).value;

  if (authUser == null) {
    return Stream.value(null);
  }

  return FirebaseFirestore.instance
      .collection('usuarios')
      .doc(authUser.uid)
      .snapshots()
      .map((doc) {
    if (doc.exists && doc.data() != null) {
      return UserModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  });
});

// ─── AuthService (Login / Logout) ────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(FirebaseAuth.instance);
});

class AuthService {
  final FirebaseAuth _auth;
  AuthService(this._auth);

  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

// ─── AuthRepository (Onboarding / Invitaciones) ───────────────────────────────

/// Repositorio para las operaciones de registro y gestión de invitaciones.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});
