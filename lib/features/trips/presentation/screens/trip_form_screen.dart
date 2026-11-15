import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/trip_provider.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/services/fuzzy_search_service.dart';
import '../../domain/services/container_validator.dart';
import '../../domain/services/route_mission_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../admin/domain/models/service_request_model.dart';
import '../providers/trip_draft_provider.dart';

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
  final ServiceRequest? preAssignment;
  final String initialTipoMovimiento;
  const TripFormScreen({
    super.key,
    this.preAssignment,
    this.initialTipoMovimiento = 'operativo',
  });

  @override
  ConsumerState<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends ConsumerState<TripFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores externos (reciben el texto desde los Autocomplete internos)
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _puntoDescargaCtrl = TextEditingController();
  final List<TextEditingController> _intermediateStopsCtrls = [];
  final _containerCtrl = TextEditingController();
  final _clientCtrl = TextEditingController();
  final _mandanteCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();

  // Estado de la pantalla
  late String _tipoMovimiento = widget.initialTipoMovimiento;
  bool _isZiyu = true;              // true = OS (Ziyu), false = OT (Manual)
  CargoType _cargoType = CargoType.completo;
  bool _isLoading = false;
  String? _containerError; // Feedback en tiempo real del validador ISO 6346

  @override
  void initState() {
    super.initState();
    
    // Cargar datos iniciales (Borrador o Pre-asignación)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });

    // Validadores de contenedor en tiempo real
    _containerCtrl.addListener(_onContainerChange);
    
    // Listeners para auto-guardado de borrador
    _originCtrl.addListener(_saveDraft);
    _destCtrl.addListener(_saveDraft);
    _puntoDescargaCtrl.addListener(_saveDraft);
    _clientCtrl.addListener(_saveDraft);
    _mandanteCtrl.addListener(_saveDraft);
    _valueCtrl.addListener(_saveDraft);
    _containerCtrl.addListener(_saveDraft);
  }

  void _initializeData() {
    final draft = ref.read(tripDraftProvider);
    
    // Prioridad 1: Si venimos de una pre-asignación NUEVA (distinta a la guardada)
    if (widget.preAssignment != null && widget.preAssignment!.id != draft.preAssignmentId) {
      _applyPreAssignment(widget.preAssignment!);
      return;
    }

    // Prioridad 2: Si hay un borrador con datos, lo recuperamos
    if (draft.origin.isNotEmpty || draft.destination.isNotEmpty || draft.client.isNotEmpty) {
      setState(() {
        _originCtrl.text = draft.origin;
        _destCtrl.text = draft.destination;
        _puntoDescargaCtrl.text = draft.puntoDescarga.isNotEmpty ? draft.puntoDescarga : draft.destination;
        _clientCtrl.text = draft.client;
        _mandanteCtrl.text = draft.mandante;
        _valueCtrl.text = draft.value;
        _containerCtrl.text = draft.container;
        _isZiyu = draft.isZiyu;
        _cargoType = CargoType.values.firstWhere((e) => e.name == draft.cargoType, orElse: () => CargoType.completo);
      });
    } else if (widget.preAssignment != null) {
      // Prioridad 3: Si no hay borrador pero hay pre-asignación
      _applyPreAssignment(widget.preAssignment!);
    }
  }

  void _applyPreAssignment(ServiceRequest req) {
    setState(() {
      _originCtrl.text = req.origin;
      _destCtrl.text = req.destination;
      _puntoDescargaCtrl.text = req.destination;
      _clientCtrl.text = req.clientName;
      _mandanteCtrl.text = 'MEDLOG TRUCK'; // Valor por defecto común
      _valueCtrl.text = _formatValue(req.proposedValue ?? 0);
      _isZiyu = true;
      _cargoType = req.loadType?.toLowerCase().contains('suelta') == true ? CargoType.suelta : CargoType.completo;
    });
    _saveDraft();
  }

  String _formatValue(double val) {
    if (val == 0) return '';
    final s = val.toInt().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  void _onContainerChange() {
    final raw = ContainerValidator.clean(_containerCtrl.text);
    if (raw.length == 11) {
      setState(() => _containerError = ContainerValidator.validate(_containerCtrl.text));
    } else if (raw.isEmpty) {
      setState(() => _containerError = null);
    }
  }

  void _saveDraft() {
    ref.read(tripDraftProvider.notifier).updateDraft(TripDraft(
      client: _clientCtrl.text,
      origin: _originCtrl.text,
      destination: _destCtrl.text,
      puntoDescarga: _puntoDescargaCtrl.text,
      container: _containerCtrl.text,
      value: _valueCtrl.text,
      mandante: _mandanteCtrl.text,
      cargoType: _cargoType.name,
      isZiyu: _isZiyu,
      preAssignmentId: widget.preAssignment?.id,
    ));
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _puntoDescargaCtrl.dispose();
    for (final c in _intermediateStopsCtrls) {
      c.dispose();
    }
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

      // RESPALDO DE PATENTE: Si la jornada no la tiene, intentamos del perfil o avisamos
      String? vehicleId = shift.patenteCamion.trim().isEmpty ? null : shift.patenteCamion;
      if (vehicleId == null && user.patenteAsignada != null) {
        vehicleId = user.patenteAsignada;
      }

      if (vehicleId == null || vehicleId.isEmpty) {
        throw Exception('No se detectó patente para este viaje. Por favor verifique su perfil o jornada.');
      }

      final isOperativo = _tipoMovimiento == 'operativo';
      final isRetiro = _tipoMovimiento == 'retiro_anticipado';
      final isMantenimiento = _tipoMovimiento == 'traslado_mantenimiento';

      // Parsea el valor eliminando separadores de miles (0 para movimientos no operativos)
      final value = isOperativo ? (double.tryParse(_valueCtrl.text.replaceAll('.', '')) ?? 0.0) : 0.0;
      final client = isOperativo
          ? _clientCtrl.text.trim()
          : (_clientCtrl.text.trim().isNotEmpty
              ? _clientCtrl.text.trim()
              : (isRetiro ? 'Retiro Anticipado' : 'Mantenimiento'));
      final mandante = isOperativo
          ? _mandanteCtrl.text.trim()
          : (isRetiro ? 'MEDLOG TRUCK' : 'MANTENIMIENTO');

      final puntoDescarga = _puntoDescargaCtrl.text.trim();
      final destination = isOperativo
          ? (puntoDescarga.isNotEmpty ? puntoDescarga : _destCtrl.text.trim())
          : _destCtrl.text.trim();
      final paradas = _intermediateStopsCtrls
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final tramos = isOperativo
          ? RouteMissionService.buildMissionLegs(
              origin: _originCtrl.text.trim(),
              client: client,
              puntoDescarga: destination,
              paradasIntermedias: paradas.isNotEmpty ? paradas : null,
            )
          : null;

      final geocercaCarga = RouteMissionService.findGeofenceForClient(client);
      final geocercaDescarga = RouteMissionService.findGeofenceForDestination(destination);

      final newTripId = 'VIAJE-${DateTime.now().millisecondsSinceEpoch}';
      final newTrip = TripModel(
        id: newTripId,
        idEmpresa: user.idEmpresa,
        idChofer: user.uid,
        idJornada: shift.id,
        origin: _originCtrl.text.trim(),
        destination: destination,
        cargoType: isMantenimiento
            ? 'suelta' 
            : (isRetiro ? 'retiro' : _cargoType.name),
        containerNumber: (isOperativo && _cargoType != CargoType.suelta)
            ? (_containerCtrl.text.trim().isEmpty 
                ? null 
                : ContainerValidator.format(_containerCtrl.text))
            : null,
        guideNumber: null, // Se solicitará al CERRAR el viaje
        startDate: DateTime.now(),
        status: 'En Ruta',
        client: client,
        mandante: mandante,
        value: value,
        billingType: _isZiyu ? 'OS' : 'OT',
        vehicleId: vehicleId, // USAMOS EL RESPALDO
        comments: '',
        tipoMovimiento: _tipoMovimiento,
        puntoDescarga: isOperativo ? destination : null,
        geocercaCarga: geocercaCarga,
        geocercaDescarga: geocercaDescarga,
        tramos: tramos,
        paradasIntermedias: paradas.isNotEmpty ? paradas : null,
      );

      await ref.read(tripRepositoryProvider).startTrip(newTrip);

      // Si venimos de una pre-asignación, la marcamos como completada
      if (widget.preAssignment != null) {
        await ref.read(tripRepositoryProvider).updateServiceRequestStatus(widget.preAssignment!.id, 'completed');
      }

      // Limpiar borrador al éxito
      await ref.read(tripDraftProvider.notifier).clearDraft();

      if (mounted) {
        final labelExito = isRetiro 
            ? '✓ Retiro anticipado iniciado (Sin ganancias)' 
            : (isMantenimiento ? '✓ Traslado a mantenimiento iniciado' : '✓ Viaje iniciado correctamente');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(labelExito),
            backgroundColor: const Color(0xFF2E7D32),
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
    final isOperativo = _tipoMovimiento == 'operativo';
    final isRetiro = _tipoMovimiento == 'retiro_anticipado';
    final isMantenimiento = _tipoMovimiento == 'traslado_mantenimiento';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isRetiro 
              ? 'Retiro Anticipado' 
              : (isMantenimiento ? 'Traslado a Mantenimiento' : 'Registrar Viaje'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [

            // ── 0. TIPO DE ACTIVIDAD / MOVIMIENTO ──────────────────────────
            _sectionHeader('Tipo de Movimiento', Icons.alt_route),
            const SizedBox(height: 12),
            _buildTipoMovimientoSelector(),
            const SizedBox(height: 14),
            _buildTipoMovimientoBanner(),
            const SizedBox(height: 24),

            // ── 1. TIPO DE SERVICIO (Ziyu / OT) (Solo operativo) ───────────
            if (isOperativo) ...[
              _sectionHeader('Tipo de Servicio', Icons.business_center_outlined),
              const SizedBox(height: 12),
              _buildZiyuToggle(),
              const SizedBox(height: 28),
            ],

            // ── 2. TIPO DE CARGA (Solo Operativo estándar) ─────────────────────
            // En Retiro Anticipado y Mantenimiento NO se exige ni se solicita tipo de carga
            if (isOperativo) ...[
              _sectionHeader('Tipo de Carga', Icons.inventory_2_outlined),
              const SizedBox(height: 12),
              _buildCargoTypeSelector(),
              const SizedBox(height: 28),
            ],

            // ── 3. RUTA & MISIÓN DE TRANSPORTE ───────────────────────────
            _sectionHeader(
              isOperativo ? 'Ruta & Misión de Transporte' : 'Ruta del Desplazamiento',
              Icons.route_outlined,
            ),
            const SizedBox(height: 12),
            _buildFuzzyField(
              label: isOperativo ? 'Punto de Partida (Origen)' : 'Origen',
              controller: _originCtrl,
              icon: Icons.my_location,
              isRequired: true,
            ),
            const SizedBox(height: 14),

            if (isOperativo) ...[
              // PLANTA O CLIENTE DE CARGA
              _buildFuzzyField(
                label: 'Planta o Cliente de Carga (1er Hito)',
                controller: _clientCtrl,
                icon: Icons.business_outlined,
                isRequired: true,
              ),
              const SizedBox(height: 14),

              // PARADAS INTERMEDIAS DINÁMICAS (MULTI-PARADA)
              if (_intermediateStopsCtrls.isNotEmpty) ...[
                for (int i = 0; i < _intermediateStopsCtrls.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildFuzzyField(
                          label: 'Parada Intermedia #${i + 1}',
                          controller: _intermediateStopsCtrls[i],
                          icon: Icons.alt_route,
                          isRequired: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                        tooltip: 'Eliminar parada',
                        onPressed: () {
                          setState(() {
                            _intermediateStopsCtrls[i].dispose();
                            _intermediateStopsCtrls.removeAt(i);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ],

              // BOTÓN AGREGAR PARADA INTERMEDIA
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Agregar Parada Intermedia (Opcional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      _intermediateStopsCtrls.add(TextEditingController());
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),

              // PUERTO O DEPÓSITO DE ENTREGA (OBLIGATORIO)
              _buildPuntoDescargaField(),
            ] else ...[
              _buildFuzzyField(
                label: 'Destino',
                controller: _destCtrl,
                icon: Icons.location_on_outlined,
                isRequired: true,
              ),
            ],
            const SizedBox(height: 28),

            // ── 4. DOCUMENTACIÓN DE CARGA (Solo para viajes operativos con contenedor) ──
            if (isOperativo && _cargoType != CargoType.suelta) ...[
              _sectionHeader('Documentación de Carga', Icons.description_outlined),
              const SizedBox(height: 12),
              _buildContainerField(),
              const SizedBox(height: 14),
            ] else if (isRetiro) ...[
              // Para retiro anticipado: Mensaje informativo claro de que el contenedor no se exige ahora
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.amberAccent, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Desplazamiento para retiro: El Nº de contenedor podrá ser ingresado al momento de retirarlo en puerto o al finalizar.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                      'Los peajes y kilometraje real se detectarán automáticamente y se conciliarán al finalizar.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── 5. DATOS COMERCIALES (Solo para viajes operativos) ────────
            if (isOperativo) ...[
              _sectionHeader('Datos Comerciales', Icons.attach_money),
              const SizedBox(height: 12),
              _buildFuzzyField(
                label: 'Mandante',
                controller: _mandanteCtrl,
                icon: Icons.account_tree_outlined,
                isRequired: true,
                alwaysPinMedlog: true,
              ),
              const SizedBox(height: 14),
              _buildValueField(),
              const SizedBox(height: 40),
            ] else if (isRetiro) ...[
              // Para retiro anticipado, cliente es opcional
              _sectionHeader('Referencia de Operación (Opcional)', Icons.business_outlined),
              const SizedBox(height: 12),
              _buildFuzzyField(
                label: 'Cliente / Faena a la que corresponde (opcional)',
                controller: _clientCtrl,
                icon: Icons.business_outlined,
                isRequired: false,
              ),
              const SizedBox(height: 40),
            ] else ...[
              const SizedBox(height: 20),
            ],

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
                  _isLoading 
                      ? 'Guardando...' 
                      : (isRetiro ? 'INICIAR RETIRO ANTICIPADO' : (isMantenimiento ? 'INICIAR MANTENIMIENTO' : 'INICIAR VIAJE')),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoMovimientoSelector() {
    final options = [
      {'tipo': 'operativo', 'label': 'Viaje Operativo', 'icon': Icons.local_shipping_outlined},
      {'tipo': 'retiro_anticipado', 'label': 'Retiro Anticipado', 'icon': Icons.inventory_2_outlined},
      {'tipo': 'traslado_mantenimiento', 'label': 'Mantenimiento', 'icon': Icons.build_circle_outlined},
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = _tipoMovimiento == opt['tipo'];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => setState(() => _tipoMovimiento = opt['tipo'] as String),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFFFFF) : const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white12,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opt['icon'] as IconData,
                      color: isSelected ? Colors.black : Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      opt['label'] as String,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTipoMovimientoBanner() {
    if (_tipoMovimiento == 'retiro_anticipado') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.amberAccent, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Retiro Anticipado: Registra el desplazamiento del camión, odómetro y peajes. No suma comisión ni viáticos al chofer (\$0 en liquidación).',
                style: TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ),
          ],
        ),
      );
    } else if (_tipoMovimiento == 'traslado_mantenimiento') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.cyan.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Row(
          children: [
            Icon(Icons.build_circle_outlined, color: Colors.cyanAccent, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Traslado a Mantenimiento: Movimiento a taller o revisión técnica. Odómetro y costos registrados sin ganancia de flete ni viático.',
                style: TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
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

  // ─── Campo Selector de Puerto / Depósito de Entrega ──────────────────────

  Widget _buildPuntoDescargaField() {
    final frequentAsync = ref.watch(frequentDestinationsProvider);
    final List<String> frequentDestList = frequentAsync.maybeWhen(
      data: (list) => list.isNotEmpty
          ? list
          : const [
              'Puerto Coronel',
              'DP World Lirquén',
              'Puerto SVTI',
              'Medlog Coronel',
              'Sitrans San Vicente',
              'D&C San Vicente',
              'Contopsa San Vicente',
            ],
      orElse: () => const [
        'Puerto Coronel',
        'DP World Lirquén',
        'Puerto SVTI',
        'Medlog Coronel',
        'Sitrans San Vicente',
        'D&C San Vicente',
        'Contopsa San Vicente',
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFuzzyField(
          label: 'Puerto o Depósito de Entrega (Obligatorio)',
          controller: _puntoDescargaCtrl,
          icon: Icons.anchor_outlined,
          isRequired: true,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Destinos frecuentes: ', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ...frequentDestList.map(
                (quickDest) => Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    label: Text(quickDest, style: const TextStyle(fontSize: 11, color: Colors.white)),
                    backgroundColor: _puntoDescargaCtrl.text == quickDest
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF262626),
                    side: BorderSide(
                      color: _puntoDescargaCtrl.text == quickDest ? Colors.blueAccent : Colors.white12,
                    ),
                    onPressed: () {
                      setState(() {
                        _puntoDescargaCtrl.text = quickDest;
                        _destCtrl.text = quickDest;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Autocomplete<String>(
          key: ValueKey('${controller.hashCode}_${value.text}'),
          initialValue: value,
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
          onSelected: (String selection) {
            controller.text = selection;
          },
          fieldViewBuilder: (ctx, innerCtrl, focusNode, onEditingComplete) {
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
