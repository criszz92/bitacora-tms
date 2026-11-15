import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/trip_provider.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/models/vehicle_model.dart';
import '../../domain/services/fuzzy_search_service.dart';
import '../../domain/services/container_validator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';

/// Pantalla para registrar un viaje que el conductor olvidó ingresar en su momento.
/// No requiere jornada activa y permite seleccionar la fecha manualmente.
class RetroTripFormScreen extends ConsumerStatefulWidget {
  const RetroTripFormScreen({super.key});

  @override
  ConsumerState<RetroTripFormScreen> createState() => _RetroTripFormScreenState();
}

class _RetroTripFormScreenState extends ConsumerState<RetroTripFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _containerCtrl = TextEditingController();
  final _guideCtrl = TextEditingController();
  final _clientCtrl = TextEditingController();
  final _mandanteCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _patenteCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isZiyu = true;
  bool _isLoading = false;
  String? _containerError;

  @override
  void initState() {
    super.initState();
    _containerCtrl.addListener(() {
      final raw = ContainerValidator.clean(_containerCtrl.text);
      if (raw.length == 11) {
        setState(() => _containerError = ContainerValidator.validate(_containerCtrl.text));
      } else if (raw.isEmpty) {
        setState(() => _containerError = null);
      }
    });
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _containerCtrl.dispose();
    _guideCtrl.dispose();
    _clientCtrl.dispose();
    _mandanteCtrl.dispose();
    _valueCtrl.dispose();
    _kmCtrl.dispose();
    _patenteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFFFFF),
            onPrimary: Colors.black,
            surface: Color(0xFF161A22),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProfileProvider).value;
      if (user == null) throw Exception('Sin sesión activa.');

      final value = double.tryParse(_valueCtrl.text.replaceAll('.', '')) ?? 0.0;

      final newTrip = TripModel(
        id: 'RETRO-${DateTime.now().millisecondsSinceEpoch}',
        idEmpresa: user.idEmpresa,
        idChofer: user.uid,
        idJornada: 'RETROACTIVO',
        origin: _originCtrl.text.trim(),
        destination: _destCtrl.text.trim(),
        cargoType: 'completo',
        containerNumber: _containerCtrl.text.trim().isEmpty
            ? null
            : ContainerValidator.format(_containerCtrl.text),
        guideNumber: _guideCtrl.text.trim().isEmpty ? null : _guideCtrl.text.trim(),
        startDate: _selectedDate,
        status: 'Finalizado',  // Los viajes retroactivos se guardan directamente como finalizados
        client: _clientCtrl.text.trim(),
        mandante: _mandanteCtrl.text.trim(),
        value: value,
        billingType: _isZiyu ? 'OS' : 'OT',
        totalKm: double.tryParse(_kmCtrl.text.trim()),
        vehicleId: _patenteCtrl.text.trim(),
        comments: 'Registro retroactivo',
      );

      await ref.read(tripRepositoryProvider).startTrip(newTrip);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Viaje registrado correctamente'),
            backgroundColor: Color(0xFF161A22),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Viaje Retroactivo', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [

            // Banner informativo
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.history, color: Colors.orange, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Estás registrando un viaje de una fecha anterior. Selecciona la fecha exacta del servicio.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── FECHA DEL SERVICIO ──────────────────────────────────────────
            _sectionHeader('Fecha del Servicio', Icons.calendar_today_outlined),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── VEHÍCULO ─────────────────────────────────────────────────────
            _sectionHeader('Vehículo', Icons.local_shipping_outlined),
            const SizedBox(height: 12),
            _buildVehicleSelector(),
            const SizedBox(height: 28),

            // ── TIPO DE SERVICIO ─────────────────────────────────────────────
            _sectionHeader('Tipo de Servicio', Icons.business_center_outlined),
            const SizedBox(height: 12),
            _buildZiyuToggle(),
            const SizedBox(height: 28),

            // ── RUTA ──────────────────────────────────────────────────────────
            _sectionHeader('Ruta', Icons.route_outlined),
            const SizedBox(height: 12),
            _buildFuzzyField(label: 'Origen', controller: _originCtrl, icon: Icons.my_location, isRequired: true),
            const SizedBox(height: 14),
            _buildFuzzyField(label: 'Destino', controller: _destCtrl, icon: Icons.location_on_outlined, isRequired: true),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _kmCtrl,
              label: 'Kilómetros Recorridos',
              icon: Icons.speed_outlined,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 28),

            // ── DOCUMENTACIÓN ─────────────────────────────────────────────────
            _sectionHeader('Documentación', Icons.description_outlined),
            const SizedBox(height: 12),
            _buildContainerField(),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _guideCtrl,
              label: 'Guía de Despacho',
              icon: Icons.receipt_long_outlined,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 28),

            // ── DATOS COMERCIALES ─────────────────────────────────────────────
            _sectionHeader('Datos Comerciales', Icons.attach_money),
            const SizedBox(height: 12),
            _buildFuzzyField(label: 'Cliente', controller: _clientCtrl, icon: Icons.business_outlined, isRequired: true),
            const SizedBox(height: 14),
            _buildFuzzyField(label: 'Mandante', controller: _mandanteCtrl, icon: Icons.account_tree_outlined, isRequired: true, alwaysPinMedlog: true),
            const SizedBox(height: 14),
            _buildValueField(),
            const SizedBox(height: 40),

            // ── BOTÓN GUARDAR ─────────────────────────────────────────────────
            SizedBox(
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _isLoading ? null : _submit,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isLoading)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.background),
                            )
                          else
                            const Icon(Icons.save_rounded, size: 24, color: AppColors.background),
                          const SizedBox(width: 10),
                          Text(
                            _isLoading ? 'Guardando...' : 'GUARDAR VIAJE',
                            style: const TextStyle(
                              color: AppColors.background,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleSelector() {
    return StreamBuilder<List<VehicleModel>>(
      stream: ref.read(tripRepositoryProvider).watchVehicles(),
      builder: (context, snapshot) {
        final vehicles = snapshot.data ?? [];
        return Autocomplete<String>(
          optionsBuilder: (TextEditingValue textValue) {
            if (textValue.text.isEmpty) return vehicles.map((v) => v.patente);
            return vehicles
                .where((v) => v.patente.toLowerCase().contains(textValue.text.toLowerCase()))
                .map((v) => v.patente);
          },
          onSelected: (String selection) => _patenteCtrl.text = selection,
          fieldViewBuilder: (ctx, ctrl, focusNode, onEditingComplete) {
            return TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Patente del Camión',
                hintText: 'Selecciona o escribe la patente',
                filled: true,
                fillColor: const Color(0xFF161A22),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.local_shipping, color: Color(0xFFE0E0E0)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'La patente es obligatoria' : null,
            );
          },
        );
      }
    );
  }

  Widget _buildZiyuToggle() {
    final color = _isZiyu ? const Color(0xFFE0E0E0) : Colors.orange;
    return GestureDetector(
      onTap: () => setState(() => _isZiyu = !_isZiyu),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF161A22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(_isZiyu ? Icons.cloud_sync_outlined : Icons.edit_note, color: color, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isZiyu ? 'Viaje Ziyu (OS)' : 'Viaje Manual (OT)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 2),
                  Text(
                    _isZiyu
                        ? 'Aparecerá en la conciliación Ziyu automáticamente'
                        : 'No se espera en Ziyu — registrado como OT manual',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: _isZiyu,
              onChanged: (val) => setState(() => _isZiyu = val),
              activeThumbColor: const Color(0xFFE0E0E0),
              inactiveThumbColor: Colors.orange,
              inactiveTrackColor: Colors.orange.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuzzyField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isRequired,
    bool alwaysPinMedlog = false,
  }) {
    const medlog = 'MEDLOG TRUCK';
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textValue) {
        final query = textValue.text.trim();
        if (alwaysPinMedlog) {
          if (query.isEmpty) return [medlog];
          final results = ref.read(fuzzySearchProvider).search(query);
          final rest = results.where((r) => r != medlog).toList();
          return [medlog, ...rest];
        }
        if (query.isEmpty) return const [];
        return ref.read(fuzzySearchProvider).search(query);
      },
      onSelected: (String selection) { controller.text = selection; },
      fieldViewBuilder: (ctx, innerCtrl, focusNode, onEditingComplete) {
        innerCtrl.addListener(() {
          if (controller.text != innerCtrl.text) controller.text = innerCtrl.text;
        });
        return TextFormField(
          controller: innerCtrl,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: const Color(0xFF161A22),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: Icon(icon, color: const Color(0xFFE0E0E0)),
          ),
          validator: isRequired ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null : null,
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isRequired = false,
    TextCapitalization textCap = TextCapitalization.none,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCap,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF161A22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        prefixIcon: Icon(icon, color: Colors.grey),
        helperText: !isRequired ? 'Opcional' : null,
        helperStyle: const TextStyle(color: Colors.grey, fontSize: 11),
      ),
      validator: isRequired ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null : null,
    );
  }

  Widget _buildValueField() {
    return TextFormField(
      controller: _valueCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _ThousandsSeparatorFormatter(),
      ],
      decoration: InputDecoration(
        labelText: 'Valor del Servicio',
        prefixText: '\$ ',
        hintText: '1.200.000',
        filled: true,
        fillColor: const Color(0xFF161A22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.attach_money, color: Color(0xFFFFFFFF)),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'El valor es obligatorio' : null,
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFFFFFFF)),
        const SizedBox(width: 8),
        Text(title.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.8, color: Color(0xFFFFFFFF))),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
      ],
    );
  }

  // ─── Campo Contenedor ISO 6346 ─────────────────────────────────────────────

  Widget _buildContainerField() {
    final raw = ContainerValidator.clean(_containerCtrl.text);
    final isComplete = raw.length == 11;
    final isValid = isComplete && _containerError == null;
    final isInvalid = isComplete && _containerError != null;

    Color borderColor = Colors.grey.withValues(alpha: 0.3);
    Color iconColor = Colors.grey;
    IconData suffixIcon = Icons.inventory;

    if (isValid) {
      borderColor = Colors.white54;
      iconColor = Colors.white;
      suffixIcon = Icons.check_circle_outline;
    } else if (isInvalid) {
      borderColor = Colors.redAccent.withValues(alpha: 0.7);
      iconColor = Colors.redAccent;
      suffixIcon = Icons.error_outline;
    }

    return TextFormField(
      controller: _containerCtrl,
      textCapitalization: TextCapitalization.characters,
      maxLength: 11,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
        _UpperCaseFormatter(),
      ],
      style: TextStyle(
        color: isValid ? Colors.white : isInvalid ? Colors.redAccent : Colors.white,
        letterSpacing: 1.5,
        fontWeight: FontWeight.bold,
      ),
      decoration: InputDecoration(
        labelText: 'Número de Contenedor (ISO 6346)',
        hintText: 'Ej: MSMU3836691',
        hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 1),
        helperText: isValid
            ? '✓ Válido → ${ContainerValidator.format(_containerCtrl.text)}'
            : !isComplete
                ? '11 caracteres sin guión (${raw.length}/11)'
                : null,
        helperStyle: TextStyle(color: isValid ? Colors.white60 : Colors.grey, fontSize: 11),
        errorText: isInvalid ? _containerError : null,
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF161A22),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isValid ? Colors.white : borderColor, width: 1.5),
        ),
        prefixIcon: Icon(Icons.inventory, color: iconColor),
        suffixIcon: isComplete ? Icon(suffixIcon, color: iconColor, size: 20) : null,
      ),
      validator: (_) => ContainerValidator.validate(_containerCtrl.text), // Opcional en retroactivo
    );
  }
}

class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final digits = newValue.text.replaceAll('.', '');
    final number = int.tryParse(digits);
    if (number == null) return oldValue;
    final formatted = _formatWithDots(number);
    return newValue.copyWith(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }

  String _formatWithDots(int number) {
    final s = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) {
    return newVal.copyWith(text: newVal.text.toUpperCase());
  }
}
