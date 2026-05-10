import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/trip_provider.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/services/fuzzy_search_service.dart';
import '../../domain/services/container_validator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/services/location_service.dart';

// ─── Tipos de carga disponibles ───────────────────────────────────────────────
enum CargoType {
  completo('Viaje Completo', Icons.swap_horiz, 'Con Contenedor'),
  porteo('Porteo', Icons.arrow_forward, 'Solo Contenedor'),
  suelta('Carga Suelta', Icons.inventory_2_outlined, 'Sin Contenedor');

  const CargoType(this.label, this.icon, this.description);
  final String label;
  final IconData icon;
  final String description;
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class TripFormScreen extends ConsumerStatefulWidget {
  const TripFormScreen({super.key});

  @override
  ConsumerState<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends ConsumerState<TripFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores externos (reciben el texto desde los Autocomplete internos)
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _containerCtrl = TextEditingController();
  final _clientCtrl = TextEditingController();
  final _mandanteCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();

  // Estado de la pantalla
  bool _isZiyu = true;              // true = OS (Ziyu), false = OT (Manual)
  CargoType _cargoType = CargoType.completo;
  bool _isLoading = false;
  String? _containerError; // Feedback en tiempo real del validador ISO 6346

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
    _clientCtrl.dispose();
    _mandanteCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProfileProvider).value;
      final shift = ref.read(activeShiftProvider).value;
      if (user == null || shift == null) throw Exception('No hay jornada activa.');

      // Parsea el valor eliminando separadores de miles
      final value = double.tryParse(_valueCtrl.text.replaceAll('.', '')) ?? 0.0;

      final newTrip = TripModel(
        id: 'VIAJE-${DateTime.now().millisecondsSinceEpoch}',
        idEmpresa: user.idEmpresa,
        idChofer: user.uid,
        idJornada: shift.id,
        origin: _originCtrl.text.trim(),
        destination: _destCtrl.text.trim(),
        cargoType: _cargoType.name,
        containerNumber: _cargoType != CargoType.suelta
            ? (_containerCtrl.text.trim().isEmpty 
                ? null 
                : ContainerValidator.format(_containerCtrl.text))
            : null,
        guideNumber: null, // Se solicitará al CERRAR el viaje
        startDate: DateTime.now(),
        status: 'En Ruta',
        client: _clientCtrl.text.trim(),
        mandante: _mandanteCtrl.text.trim(),
        value: value,
        billingType: _isZiyu ? 'OS' : 'OT',
        vehicleId: shift.patenteCamion, // AUTOMÁTICO: Rescatamos la patente de la jornada
        comments: '',
      );

      await ref.read(tripRepositoryProvider).startTrip(newTrip);

      // VALIDAR PERMISOS Y ACTIVAR TELEMETRÍA GPS
      final hasPermission = await LocationService.checkAndRequestPermissions();
      if (hasPermission) {
        await LocationService.startTracking();
      } else {
        // El viaje se guarda, pero avisamos que no habrá GPS
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠ No se pudieron obtener permisos de GPS. El kilometraje real no se registrará.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Viaje iniciado correctamente'),
            backgroundColor: Color(0xFFFFFFFF),
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

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Viaje', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [

            // ── 1. TIPO DE SERVICIO (Ziyu / OT) ──────────────────────────
            _sectionHeader('Tipo de Servicio', Icons.business_center_outlined),
            const SizedBox(height: 12),
            _buildZiyuToggle(),
            const SizedBox(height: 28),

            // ── 2. TIPO DE CARGA ──────────────────────────────────────────
            _sectionHeader('Tipo de Carga', Icons.inventory_2_outlined),
            const SizedBox(height: 12),
            _buildCargoTypeSelector(),
            const SizedBox(height: 28),

            // ── 3. RUTA ───────────────────────────────────────────────────
            _sectionHeader('Ruta', Icons.route_outlined),
            const SizedBox(height: 12),
            _buildFuzzyField(
              label: 'Origen',
              controller: _originCtrl,
              icon: Icons.my_location,
              isRequired: true,
            ),
            const SizedBox(height: 14),
            _buildFuzzyField(
              label: 'Destino',
              controller: _destCtrl,
              icon: Icons.location_on_outlined,
              isRequired: true,
            ),
            const SizedBox(height: 28),

            // ── 4. DOCUMENTACIÓN ──────────────────────────────────────────
            _sectionHeader('Documentación de Carga', Icons.description_outlined),
            const SizedBox(height: 12),

            // Contenedor: oculto en Carga Suelta, obligatorio en los demás
            if (_cargoType != CargoType.suelta) ...[
              _buildContainerField(),
              const SizedBox(height: 14),
            ],

            // INFO: La Guía de Despacho se solicitará al FINALIZAR el viaje
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'La Guía de Despacho se ingresará al finalizar el viaje, cuando ya la tengas en mano.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── 5. DATOS COMERCIALES ──────────────────────────────────────
            _sectionHeader('Datos Comerciales', Icons.attach_money),
            const SizedBox(height: 12),
            _buildFuzzyField(
              label: 'Cliente',
              controller: _clientCtrl,
              icon: Icons.business_outlined,
              isRequired: true,
            ),
            const SizedBox(height: 14),
            _buildFuzzyField(
              label: 'Mandante',
              controller: _mandanteCtrl,
              icon: Icons.account_tree_outlined,
              isRequired: true,
              alwaysPinMedlog: true, // Medlog Truck siempre es la primera opción
            ),
            const SizedBox(height: 14),
            _buildValueField(),
            const SizedBox(height: 40),

            // ── BOTÓN INICIAR ─────────────────────────────────────────────
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _submit,
                icon: _isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                      )
                    : const Icon(Icons.play_circle_fill, size: 26),
                label: Text(
                  _isLoading ? 'Guardando...' : 'INICIAR VIAJE',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Toggle Ziyu / OT ─────────────────────────────────────────────────────

  Widget _buildZiyuToggle() {
    final color = _isZiyu ? const Color(0xFFE0E0E0) : Colors.orange;
    return GestureDetector(
      onTap: () => setState(() => _isZiyu = !_isZiyu),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
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
                  Text(
                    _isZiyu ? 'Viaje Ziyu (OS)' : 'Viaje Manual (OT)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                  ),
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

  // ─── Selector tipo de carga ────────────────────────────────────────────────

  Widget _buildCargoTypeSelector() {
    return Row(
      children: CargoType.values.map((type) {
        final isSelected = _cargoType == type;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _cargoType = type;
              if (type == CargoType.suelta) _containerCtrl.clear();
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                left: type == CargoType.completo ? 0 : 5,
                right: type == CargoType.suelta ? 0 : 5,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFFFFFF).withValues(alpha: 0.1)
                    : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFFFFFF)
                      : Colors.grey.withValues(alpha: 0.3),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(type.icon, size: 22,
                      color: isSelected ? const Color(0xFFFFFFFF) : Colors.grey),
                  const SizedBox(height: 6),
                  Text(type.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey,
                      )),
                  const SizedBox(height: 2),
                  Text(type.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: isSelected
                            ? const Color(0xFFFFFFFF).withValues(alpha: 0.8)
                            : Colors.grey.withValues(alpha: 0.5),
                      )),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Campo Autocomplete (fuzzy) ────────────────────────────────────────────

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
          // Medlog Truck siempre ocupa el primer lugar
          final rest = results.where((r) => r != medlog).toList();
          return [medlog, ...rest];
        }

        if (query.isEmpty) return const [];
        return ref.read(fuzzySearchProvider).search(query);
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder: (ctx, innerCtrl, focusNode, onEditingComplete) {
        // Sincroniza el controlador interno con el externo
        innerCtrl.addListener(() {
          if (controller.text != innerCtrl.text) {
            controller.text = innerCtrl.text;
          }
        });
        return TextFormField(
          controller: innerCtrl,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            prefixIcon: Icon(icon, color: const Color(0xFFE0E0E0)),
          ),
          validator: isRequired
              ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null
              : null,
        );
      },
    );
  }

  // ─── Campo Contenedor ISO 6346 (con validación en tiempo real) ─────────────

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
        fillColor: const Color(0xFF1E1E1E),
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
      validator: (_) => ContainerValidator.validateRequired(_containerCtrl.text),
    );
  }

  // ─── Campo valor CLP ────────────────────────────────────────────────────────

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
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.attach_money, color: Color(0xFFFFFFFF)),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'El valor es obligatorio' : null,
    );
  }

  // ─── Header de sección ─────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFFFFFFF)),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.8,
            color: Color(0xFFFFFFFF),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
      ],
    );
  }
}

// ─── Formateador separador de miles (formato CLP: 1.200.000) ─────────────────

class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final digits = newValue.text.replaceAll('.', '');
    final number = int.tryParse(digits);
    if (number == null) return oldValue;

    final formatted = _formatWithDots(number);
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
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

// ─── Convierte automáticamente el texto a mayúsculas ─────────────────────────
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) {
    return newVal.copyWith(text: newVal.text.toUpperCase());
  }
}
