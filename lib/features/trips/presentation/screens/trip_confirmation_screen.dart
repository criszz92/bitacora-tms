import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/services/container_validator.dart';
import '../../../admin/domain/models/service_request_model.dart';
import '../providers/trip_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/services/location_service.dart';

class TripConfirmationScreen extends ConsumerStatefulWidget {
  final ServiceRequest request;

  const TripConfirmationScreen({super.key, required this.request});

  @override
  ConsumerState<TripConfirmationScreen> createState() => _TripConfirmationScreenState();
}

class _TripConfirmationScreenState extends ConsumerState<TripConfirmationScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _containerCtrl;
  late TextEditingController _valueCtrl;
  bool _isLoading = false;
  String? _containerError;

  @override
  void initState() {
    super.initState();
    // Booking se muestra pero no se edita (según feedback Cris)
    // El contenedor viene vacío para que el chofer lo ingrese físicamente
    _containerCtrl = TextEditingController();
    
    // La tarifa viene pre-llenada con la sugerencia de la oficina
    final initialValue = widget.request.proposedValue?.toInt().toString() ?? '';
    _valueCtrl = TextEditingController(text: initialValue);

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
    _containerCtrl.dispose();
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

      final value = double.tryParse(_valueCtrl.text.replaceAll('.', '')) ?? 0.0;

      final newTrip = TripModel(
        id: 'VIAJE-${DateTime.now().millisecondsSinceEpoch}',
        idEmpresa: user.idEmpresa,
        idChofer: user.uid,
        idJornada: shift.id,
        origin: widget.request.origin,
        destination: widget.request.destination,
        cargoType: widget.request.loadType?.toLowerCase().contains('suelta') == true ? 'suelta' : 'completo',
        containerNumber: ContainerValidator.format(_containerCtrl.text),
        bookingNumber: widget.request.bookingNumber,
        startDate: DateTime.now(),
        status: 'En Ruta',
        client: widget.request.clientName,
        mandante: 'MEDLOG TRUCK', // Hardcoded por ser flujo Medlog
        value: value,
        billingType: 'OS',
        vehicleId: shift.patenteCamion,
        comments: 'Asignado vía IA Dashboard',
      );

      await ref.read(tripRepositoryProvider).startTrip(newTrip);
      
      // Marcar solicitud como completada para que desaparezca
      await ref.read(tripRepositoryProvider).updateServiceRequestStatus(widget.request.id, 'completed');

      final hasPermission = await LocationService.checkAndRequestPermissions();
      if (hasPermission) await LocationService.startTracking();

      if (mounted) {
        context.go('/driver');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Viaje de Medlog iniciado'), backgroundColor: Colors.green),
        );
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Confirmar Viaje Medlog', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildInfoCard(),
            const SizedBox(height: 32),
            _sectionHeader('DATOS DE LA UNIDAD', Icons.local_shipping_outlined),
            const SizedBox(height: 16),
            _buildContainerField(),
            const SizedBox(height: 24),
            _sectionHeader('DATOS COMERCIALES', Icons.attach_money),
            const SizedBox(height: 16),
            _buildValueField(),
            const SizedBox(height: 48),
            SizedBox(
              height: 64,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _submit,
                icon: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.play_circle_fill),
                label: Text(_isLoading ? 'INICIANDO...' : 'INICIAR VIAJE AHORA', 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _buildDetailRow('CLIENTE', widget.request.clientName),
          const Divider(height: 32, color: Colors.white10),
          _buildDetailRow('ORIGEN', widget.request.origin, icon: Icons.my_location),
          const SizedBox(height: 12),
          _buildDetailRow('DESTINO', widget.request.destination, icon: Icons.location_on),
          const Divider(height: 32, color: Colors.white10),
          _buildDetailRow('BOOKING', widget.request.bookingNumber ?? 'No especificado', isHighlight: true),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {IconData? icon, bool isHighlight = false}) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 12)],
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
            Text(value, style: TextStyle(
              color: isHighlight ? Colors.blueAccent : Colors.white, 
              fontSize: 15, 
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildContainerField() {
    return TextFormField(
      controller: _containerCtrl,
      textCapitalization: TextCapitalization.characters,
      maxLength: 11,
      style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: 'Número de Contenedor (Obligatorio)',
        hintText: 'Ej: MSMU3836691',
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.inventory, color: Colors.white38),
        errorText: _containerError,
        counterText: '',
        helperText: 'Ingrese la unidad física que retira',
        helperStyle: const TextStyle(color: Colors.grey),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Debe ingresar el contenedor' : _containerError,
    );
  }

  Widget _buildValueField() {
    return TextFormField(
      controller: _valueCtrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Tarifa Final del Viaje',
        prefixText: '$ ',
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.attach_money, color: Colors.white38),
        helperText: 'Sugerido por coordinación',
        helperStyle: const TextStyle(color: Colors.grey),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'El valor es obligatorio' : null,
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }
}
