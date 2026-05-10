import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/admin_provider.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../domain/models/company_config_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ConductoresView extends ConsumerStatefulWidget {
  const ConductoresView({super.key});

  @override
  ConsumerState<ConductoresView> createState() => _ConductoresViewState();
}

class _ConductoresViewState extends ConsumerState<ConductoresView> {
  bool _isListView = false;
  UserModel? _selectedChofer;
  bool _isGeneratingCode = false;
  String? _lastGeneratedCode;

  @override
  Widget build(BuildContext context) {
    final choferesAsync = ref.watch(choferesProvider);
    final configAsync = ref.watch(companyConfigProvider);
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: isMobile 
        ? _buildMobileLayout(choferesAsync, configAsync)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── LISTA DE CONDUCTORES ──────────────────────────────────────────
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isMobile),
                    const SizedBox(height: 32),
                    _buildToggleAndConfig(configAsync, isMobile),
                    const SizedBox(height: 24),
                    Expanded(
                      child: choferesAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
                        error: (e, s) => Text('Error: $e'),
                        data: (choferes) => _isListView 
                          ? _buildListView(choferes) 
                          : _buildGridView(choferes, isMobile),
                      ),
                    ),
                  ],
                ),
              ),
              
              // ── PANEL DE EDICIÓN (DETALLE) ────────────────────────────────────
              if (_selectedChofer != null) ...[
                const SizedBox(width: 40),
                Expanded(
                  flex: 3,
                  child: _buildEditPanel(_selectedChofer!, configAsync.value),
                ),
              ],
            ],
          ),
    );
  }

  Widget _buildMobileLayout(AsyncValue<List<UserModel>> choferesAsync, AsyncValue<CompanyConfigModel?> configAsync) {
    if (_selectedChofer != null) {
      return _buildEditPanel(_selectedChofer!, configAsync.value);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(true),
        const SizedBox(height: 24),
        _buildToggleAndConfig(configAsync, true),
        const SizedBox(height: 16),
        Expanded(
          child: choferesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
            error: (e, s) => Text('Error: $e'),
            data: (choferes) => _isListView 
              ? _buildListView(choferes) 
              : _buildGridView(choferes, true),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isMobile ? 'Conductores' : 'Gestión de Conductores',
            style: TextStyle(fontSize: isMobile ? 22 : 28, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        const Text('Administra perfiles, licencias y pagos.',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        if (_lastGeneratedCode != null) _buildCodeBanner(),
      ],
    );
  }

  Widget _buildCodeBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code, color: Colors.green),
          const SizedBox(width: 12),
          Text('Código de invitación: $_lastGeneratedCode', 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
            onPressed: () => setState(() => _lastGeneratedCode = null),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleAndConfig(AsyncValue<CompanyConfigModel?> configAsync, bool isMobile) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Toggle Vista
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _viewToggleButton(Icons.grid_view, !_isListView, () => setState(() => _isListView = false)),
              _viewToggleButton(Icons.list, _isListView, () => setState(() => _isListView = true)),
            ],
          ),
        ),
        
        // Botón Generar Código
        TextButton.icon(
          onPressed: _isGeneratingCode ? null : _generarCodigo,
          icon: _isGeneratingCode 
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Invitar'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      ],
    );
  }

  Widget _viewToggleButton(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white10 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: active ? Colors.white : Colors.grey, size: 18),
      ),
    );
  }

  // ── VISTAS DE LISTA Y GRILLA ──────────────────────────────────────────────

  Widget _buildGridView(List<UserModel> choferes, bool isMobile) {
    final width = MediaQuery.of(context).size.width;
    int columns = 2;
    double ratio = 2.8;
    
    if (width < 600) {
      columns = 1;
      ratio = 3.5;
    } else if (width < 1200) {
      columns = 2;
      ratio = 2.5;
    } else {
      columns = 3;
      ratio = 3.0;
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: ratio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: choferes.length,
      itemBuilder: (context, index) => _choferCard(choferes[index], isMobile),
    );
  }

  Widget _buildListView(List<UserModel> choferes) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.separated(
        itemCount: choferes.length,
        separatorBuilder: (_, index) => const Divider(color: Colors.white10, height: 1),
        itemBuilder: (context, index) => _choferListTile(choferes[index]),
      ),
    );
  }

  Widget _choferCard(UserModel c, bool isMobile) {
    final isSelected = _selectedChofer?.uid == c.uid;
    return InkWell(
      onTap: () => setState(() => _selectedChofer = c),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? Colors.white : Colors.white10, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: isMobile ? 18 : 22,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              child: Icon(Icons.person, color: Colors.white, size: isMobile ? 18 : 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(c.nombre, 
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 13 : 14)),
                  Text(c.rut ?? 'Sin RUT', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 4,
                    children: (c.licencias ?? []).take(2).map((l) => _licenseBadge(l)).toList(),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 20),
              tooltip: 'Ver Resumen Mensual',
              onPressed: () => context.push('/monthly-summary?userId=${c.uid}'),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _choferListTile(UserModel c) {
    final isSelected = _selectedChofer?.uid == c.uid;
    return ListTile(
      onTap: () => setState(() => _selectedChofer = c),
      selected: isSelected,
      selectedTileColor: Colors.white.withValues(alpha: 0.05),
      leading: const Icon(Icons.person_outline, color: Colors.grey),
      title: Text(c.nombre, style: const TextStyle(color: Colors.white)),
      subtitle: Text(c.rut ?? 'Sin RUT', style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...(c.licencias ?? []).take(2).map((l) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _licenseBadge(l),
          )),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 18),
            onPressed: () => context.push('/monthly-summary?userId=${c.uid}'),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _licenseBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  // ── PANEL DE EDICIÓN ──────────────────────────────────────────────────────

  Widget _buildEditPanel(UserModel chofer, CompanyConfigModel? config) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: Colors.white),
                const SizedBox(width: 12),
                const Text('Editar Perfil', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => setState(() => _selectedChofer = null)),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: _DriverEditForm(
              key: ValueKey(chofer.uid),
              chofer: chofer,
              config: config,
              onSaved: (updated) async {
                try {
                  await ref.read(adminRepositoryProvider).updateChoferProfile(updated);
                  if (mounted) {
                    setState(() => _selectedChofer = updated);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Perfil actualizado con éxito'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red));
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── ACCIONES ──────────────────────────────────────────────────────────────

  Future<void> _generarCodigo() async {
    final user = ref.read(currentUserProfileProvider).value;
    if (user == null) return;
    setState(() => _isGeneratingCode = true);
    try {
      final code = await ref.read(authRepositoryProvider).generateInvitationCode(user.idEmpresa);
      setState(() => _lastGeneratedCode = code);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isGeneratingCode = false);
    }
  }
}

// ── FORMULARIO DE EDICIÓN DE CONDUCTOR ─────────────────────────────────────

class _DriverEditForm extends StatefulWidget {
  final UserModel chofer;
  final CompanyConfigModel? config;
  final Function(UserModel) onSaved;

  const _DriverEditForm({required this.chofer, this.config, required this.onSaved, super.key});

  @override
  State<_DriverEditForm> createState() => _DriverEditFormState();
}

class _DriverEditFormState extends State<_DriverEditForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _rutController;
  late TextEditingController _sueldoController;
  late TextEditingController _viaticoLocalController;
  late TextEditingController _viaticoLargoController;
  late List<String> _selectedLicenses;
  late String _tipoContrato;
  late String _baseImponible;
  late bool _empresaAsumeLeyes;
  late TextEditingController _tasaAFPController;
  late TextEditingController _tasaSaludController;
  late Map<String, bool> _toggles;

  @override
  void initState() {
    super.initState();
    final c = widget.chofer;
    _rutController = TextEditingController(text: c.rut);
    _sueldoController = TextEditingController(text: (c.sueldoBase ?? widget.config?.sueldoMinimo ?? 539000).toInt().toString());
    _viaticoLocalController = TextEditingController(text: (c.montoViaticoLocal ?? 6500).toInt().toString());
    _viaticoLargoController = TextEditingController(text: (c.montoViaticoLargo ?? 10000).toInt().toString());
    _selectedLicenses = List<String>.from(c.licencias ?? []);
    _tipoContrato = c.tipoContrato ?? 'Indefinido';
    _baseImponible = c.baseImponible ?? 'Total';
    _empresaAsumeLeyes = c.empresaAsumeLeyes ?? false;
    _tasaAFPController = TextEditingController(text: c.tasaAFP?.toString() ?? '10.58');
    _tasaSaludController = TextEditingController(text: c.tasaSalud?.toString() ?? '7.0');
    _toggles = Map<String, bool>.from(c.configuracionPagos ?? {
      'Gratificación': true,
      'Seguro Cesantía': true,
      'SIS': true,
      'Mutual': true,
      'AFP': true,
      'Salud': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _section('DATOS PERSONALES'),
          _input('RUT', _rutController, Icons.badge_outlined),
          const SizedBox(height: 16),
          const Text('Licencias de Conducir', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['A1', 'A2', 'A3', 'A4', 'A5', 'B', 'C', 'D', 'E', 'F'].map((l) {
              final active = _selectedLicenses.contains(l);
              return FilterChip(
                label: Text(l, style: TextStyle(fontSize: 12, color: active ? Colors.black : Colors.white)),
                selected: active,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedLicenses.add(l);
                    } else {
                      _selectedLicenses.remove(l);
                    }
                  });
                },
                selectedColor: Colors.white,
                backgroundColor: Colors.white10,
                checkmarkColor: Colors.black,
              );
            }).toList(),
          ),
          
          const SizedBox(height: 32),
          _section('CONFIGURACIÓN DE VIÁTICOS'),
          _input(r'Monto Local ($)', _viaticoLocalController, Icons.location_on_outlined),
          const SizedBox(height: 16),
          _input(r'Monto Largo ($)', _viaticoLargoController, Icons.map_outlined),
          
          const SizedBox(height: 32),
          _section('REMUNERACIONES Y DESCUENTOS'),
          _input(r'Sueldo Base ($)', _sueldoController, Icons.money),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _tipoContrato,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDeco('Tipo de Contrato', Icons.description_outlined),
            items: ['Indefinido', 'Plazo Fijo'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) => setState(() => _tipoContrato = val!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _baseImponible,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDeco('Imponer Sobre', Icons.calculate_outlined),
            items: ['Total', 'Sueldo Base'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) => setState(() => _baseImponible = val!),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _input('Tasa AFP (%)', _tasaAFPController, Icons.account_balance_outlined)),
              const SizedBox(width: 16),
              Expanded(child: _input('Tasa Salud (%)', _tasaSaludController, Icons.medical_services_outlined)),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Empresa asume Descuentos Legales', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: const Text('Sueldo Líquido Pactado (El Costo Empresa sumará AFP/Salud).', style: TextStyle(color: Colors.grey, fontSize: 11)),
            value: _empresaAsumeLeyes,
            onChanged: (val) => setState(() => _empresaAsumeLeyes = val),
            activeThumbColor: Colors.black,
            activeTrackColor: Colors.white,
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.white10,
            contentPadding: EdgeInsets.zero,
          ),
          
          const SizedBox(height: 24),
          const Text('Items de Pago Aplicables', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          ..._toggles.entries.map((e) => CheckboxListTile(
            title: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 13)),
            value: e.value,
            onChanged: (val) => setState(() => _toggles[e.key] = val!),
            dense: true,
            activeColor: Colors.white,
            checkColor: Colors.black,
            contentPadding: EdgeInsets.zero,
          )),
          
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Guardar Cambios', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final updated = UserModel(
        uid: widget.chofer.uid,
        idEmpresa: widget.chofer.idEmpresa,
        email: widget.chofer.email,
        nombre: widget.chofer.nombre,
        rol: widget.chofer.rol,
        rut: _rutController.text,
        licencias: _selectedLicenses,
        sueldoBase: double.tryParse(_sueldoController.text),
        tipoContrato: _tipoContrato,
        montoViaticoLocal: double.tryParse(_viaticoLocalController.text),
        montoViaticoLargo: double.tryParse(_viaticoLargoController.text),
        tasaAFP: double.tryParse(_tasaAFPController.text),
        tasaSalud: double.tryParse(_tasaSaludController.text),
        baseImponible: _baseImponible,
        empresaAsumeLeyes: _empresaAsumeLeyes,
        configuracionPagos: _toggles,
      );
      widget.onSaved(updated);
    }
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _input(String label, TextEditingController controller, IconData icon) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: _fieldDeco(label, icon),
      keyboardType: TextInputType.number,
    );
  }

  InputDecoration _fieldDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.white24, size: 20),
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
    );
  }
}
