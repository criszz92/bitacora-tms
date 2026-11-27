import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;

  bool _isLogin = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await ref.read(authServiceProvider).signInWithEmail(
              _emailCtrl.text.trim(),
              _passCtrl.text,
            );
      } else {
        await ref.read(authServiceProvider).signUpWithEmail(
              _emailCtrl.text.trim(),
              _passCtrl.text,
            );
      }
      // El router escuchará el cambio de estado y nos llevará al Dashboard o a crear perfil
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLogin ? 'Error: Revise credenciales' : 'Error al crear cuenta: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.local_shipping, size: 80, color: Color(0xFFFFFFFF)),
              const SizedBox(height: 24),
              const Text(
                'HEIRLOG-TMS',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              const Text(
                'Acceso a Conductores y Administración',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Correo Electrónico',
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.email, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Contraseña',
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFFFFF),
                    foregroundColor: Colors.black,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(_isLogin ? 'INICIAR SESIÓN' : 'CREAR CUENTA', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin ? '¿No tienes cuenta? Regístrate aquí' : '¿Ya tienes cuenta? Inicia sesión',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
