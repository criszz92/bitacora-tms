import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

/// Pantalla de registro de perfil. Se muestra cuando un usuario tiene cuenta en
/// Firebase Auth pero aún no tiene documento en Firestore.
///
/// Flujos disponibles:
///   - ADMIN: Crea su empresa, elige nombre y nombre de empresa. El sistema
///            genera el idEmpresa automáticamente (sin campo libre).
///   - CHOFER: Ingresa un Código de Invitación generado por el admin. El sistema
///             valida el código y vincula al chofer a la empresa correspondiente.
class RegisterProfileScreen extends ConsumerStatefulWidget {
  const RegisterProfileScreen({super.key});

  @override
  ConsumerState<RegisterProfileScreen> createState() =>
      _RegisterProfileScreenState();
}

// ─── Estado de la pantalla ────────────────────────────────────────────────────
enum _RegistrationFlow { choosingRole, adminFlow, choferFlow }

class _RegisterProfileScreenState
    extends ConsumerState<RegisterProfileScreen> {
  _RegistrationFlow _flow = _RegistrationFlow.choosingRole;

  final _nombreCtrl = TextEditingController();
  final _empresaCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;
  bool _codigoValidado = false;
  String? _empresaDelCodigo; // nombre de empresa que retorna la validación

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _empresaCtrl.dispose();
    _codigoCtrl.dispose();
    super.dispose();
  }

  // ─── FLUJO ADMIN ─────────────────────────────────────────────────────────────

  Future<void> _crearPerfilAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authUser = ref.read(authStateProvider).value;
      if (authUser == null) throw Exception('No hay sesión activa.');

      await ref.read(authRepositoryProvider).createAdminProfile(
        authUser: authUser,
        nombre: _nombreCtrl.text.trim(),
        nombreEmpresa: _empresaCtrl.text.trim(),
      );
      // El StreamProvider de Firestore detecta el nuevo documento y el router
      // redirige automáticamente a /admin.
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── FLUJO CHOFER — Paso 1: Validar código ────────────────────────────────

  Future<void> _validarCodigo() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.isEmpty) {
      setState(() => _errorMessage = 'Ingresa el código de invitación.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final invitation = await ref
          .read(authRepositoryProvider)
          .validateInvitationCode(codigo);

      if (invitation == null) {
        setState(() => _errorMessage = 'Código inválido o ya fue utilizado.');
      } else {
        setState(() {
          _codigoValidado = true;
          _empresaDelCodigo = invitation.idEmpresa;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── FLUJO CHOFER — Paso 2: Crear perfil ─────────────────────────────────

  Future<void> _crearPerfilChofer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authUser = ref.read(authStateProvider).value;
      if (authUser == null) throw Exception('No hay sesión activa.');

      final invitation = await ref
          .read(authRepositoryProvider)
          .validateInvitationCode(_codigoCtrl.text.trim());

      if (invitation == null) {
        setState(() => _errorMessage = 'El código ya fue utilizado. Pide uno nuevo al administrador.');
        return;
      }

      await ref.read(authRepositoryProvider).createChoferProfile(
        authUser: authUser,
        nombre: _nombreCtrl.text.trim(),
        invitation: invitation,
      );
      // El router detecta el nuevo perfil y redirige a /driver automáticamente.
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Configurar Perfil',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: _flow != _RegistrationFlow.choosingRole,
        leading: _flow != _RegistrationFlow.choosingRole
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _flow = _RegistrationFlow.choosingRole;
                  _errorMessage = null;
                  _codigoValidado = false;
                  _empresaDelCodigo = null;
                }),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Salir',
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (_flow) {
                _RegistrationFlow.choosingRole => _buildRoleChooser(authUser?.email),
                _RegistrationFlow.adminFlow => _buildAdminForm(),
                _RegistrationFlow.choferFlow => _buildChoferForm(),
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── Vista 1: Elegir rol ─────────────────────────────────────────────────

  Widget _buildRoleChooser(String? email) {
    return Column(
      key: const ValueKey('chooser'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.shield_outlined, size: 80, color: Color(0xFFFFFFFF)),
        const SizedBox(height: 24),
        const Text(
          'Bienvenido a Bitácora TMS',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          email ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tu cuenta está activa. Ahora dinos cómo usarás el sistema:',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 40),

        // Tarjeta ADMIN
        _buildRoleCard(
          icon: Icons.admin_panel_settings_outlined,
          color: const Color(0xFFE0E0E0),
          title: 'Soy Administrador',
          subtitle: 'Tengo una empresa de transporte y quiero gestionar mi flota, conductores y conciliación Ziyu.',
          onTap: () => setState(() { _flow = _RegistrationFlow.adminFlow; _errorMessage = null; }),
        ),
        const SizedBox(height: 16),

        // Tarjeta CHOFER
        _buildRoleCard(
          icon: Icons.local_shipping_outlined,
          color: const Color(0xFFFFFFFF),
          title: 'Soy Conductor',
          subtitle: 'Tengo un código de invitación de mi empleador y quiero registrar mis viajes y gastos.',
          onTap: () => setState(() { _flow = _RegistrationFlow.choferFlow; _errorMessage = null; }),
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  // ─── Vista 2: Formulario ADMIN ────────────────────────────────────────────

  Widget _buildAdminForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('admin'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.admin_panel_settings, size: 64, color: Color(0xFFE0E0E0)),
          const SizedBox(height: 20),
          const Text('Crear Empresa',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          const Text(
            'Serás el administrador principal. Luego podrás invitar a tus conductores.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 32),
          _buildTextField(
            controller: _nombreCtrl,
            label: 'Tu nombre completo',
            icon: Icons.person_outline,
            textCap: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _empresaCtrl,
            label: 'Nombre de tu empresa',
            icon: Icons.business_outlined,
            hint: 'Ej: Transportes Inostroza SpA',
            textCap: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          const Text(
            '💡 El sistema generará automáticamente un ID único para tu empresa.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _buildErrorBox(_errorMessage!),
          ],
          const SizedBox(height: 32),
          _buildPrimaryButton(
            label: 'CREAR MI EMPRESA',
            icon: Icons.rocket_launch,
            color: const Color(0xFFE0E0E0),
            onPressed: _crearPerfilAdmin,
          ),
        ],
      ),
    );
  }

  // ─── Vista 3: Formulario CHOFER ───────────────────────────────────────────

  Widget _buildChoferForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('chofer'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.local_shipping, size: 64, color: Color(0xFFFFFFFF)),
          const SizedBox(height: 20),
          const Text('Registro de Conductor',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 32),

          _buildTextField(
            controller: _nombreCtrl,
            label: 'Tu nombre completo',
            icon: Icons.person_outline,
            textCap: TextCapitalization.words,
          ),
          const SizedBox(height: 16),

          // Campo código de invitación con botón de validar inline
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _codigoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _codigoValidado ? const Color(0xFFFFFFFF) : Colors.white,
                    letterSpacing: 2,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Código de Invitación',
                    hintText: 'BIT-XXXX',
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    prefixIcon: Icon(
                      _codigoValidado ? Icons.check_circle : Icons.qr_code,
                      color: _codigoValidado ? const Color(0xFFFFFFFF) : Colors.grey,
                    ),
                    suffixIcon: _codigoValidado
                        ? const Icon(Icons.verified, color: Color(0xFFFFFFFF))
                        : null,
                  ),
                  enabled: !_codigoValidado,
                  validator: (v) => v == null || v.isEmpty ? 'Ingresa el código' : null,
                ),
              ),
              if (!_codigoValidado) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E1E),
                      foregroundColor: const Color(0xFFFFFFFF),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFFFFFFF)),
                    ),
                    onPressed: _isLoading ? null : _validarCodigo,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFFFFFFFF)),
                          )
                        : const Text('VALIDAR'),
                  ),
                ),
              ],
            ],
          ),

          if (_codigoValidado && _empresaDelCodigo != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business, size: 16, color: Color(0xFFFFFFFF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Empresa vinculada: $_empresaDelCodigo',
                      style: const TextStyle(
                          color: Color(0xFFFFFFFF), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _buildErrorBox(_errorMessage!),
          ],

          const SizedBox(height: 32),

          if (_codigoValidado)
            _buildPrimaryButton(
              label: 'UNIRME A LA EMPRESA',
              icon: Icons.how_to_reg,
              color: const Color(0xFFFFFFFF),
              onPressed: _crearPerfilChofer,
            )
          else
            const Text(
              'Valida tu código primero para continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
        ],
      ),
    );
  }

  // ─── Widgets de apoyo ─────────────────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextCapitalization textCap = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCap,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        prefixIcon: Icon(icon, color: Colors.grey),
      ),
      validator: (v) => v == null || v.trim().isEmpty ? 'Este campo es obligatorio' : null,
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: color == const Color(0xFFFFFFFF) ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _isLoading ? null : onPressed,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.red, fontSize: 13))),
        ],
      ),
    );
  }
}
