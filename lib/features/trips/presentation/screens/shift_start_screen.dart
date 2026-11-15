import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/trip_provider.dart';
import '../../domain/models/shift_model.dart';
import '../../domain/models/vehicle_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ShiftStartScreen extends ConsumerStatefulWidget {
  const ShiftStartScreen({super.key});

  @override
  ConsumerState<ShiftStartScreen> createState() => _ShiftStartScreenState();
}

class _ShiftStartScreenState extends ConsumerState<ShiftStartScreen> {
  final _plateCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _startShift() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = ref.read(currentUserProfileProvider).value;
      if (user == null) throw Exception('Sesión de usuario no encontrada.');

      final newShift = ShiftModel(
        id: 'SHIFT-${DateTime.now().millisecondsSinceEpoch}',
        idEmpresa: user.idEmpresa,
        idChofer: user.uid,
        patenteCamion: _plateCtrl.text.toUpperCase().trim(),
        startTime: DateTime.now(),
        startOdometer: int.parse(_odometerCtrl.text),
        status: 'Activa',
      );

      await ref.read(tripRepositoryProvider).startShift(newShift);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lee los camiones registrados de la empresa desde Firestore en tiempo real
    final vehiclesAsync = ref.watch(vehiclesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Iniciar Jornada', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Registro de Camión',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Escribe la patente de tu máquina o selecciona una de la lista. (Ejemplo: AB-CD-12)',
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Autocomplete con patentes reales desde Firestore
              vehiclesAsync.when(
                loading: () => const LinearProgressIndicator(color: Color(0xFFFFFFFF)),
                error: (e, _) => Text('Error al cargar camiones: $e', style: const TextStyle(color: Colors.red)),
                data: (vehicles) => _buildPlateAutocomplete(vehicles),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _odometerCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Kilometraje Inicial (Verificar con Tablero)',
                  hintText: 'Ej: 154000',
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.speed, color: Color(0xFFE0E0E0)),
                ),
                validator: (v) => v == null || v.isEmpty ? 'El kilometraje es obligatorio' : null,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 16, color: Color(0xFF38BDF8)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Se auto-carga el último kilometraje registrado. Verifica con el tablero del camión antes de iniciar.',
                        style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              SizedBox(
                height: 64,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFFFFF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isLoading ? null : _startShift,
                  child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('INICIAR DÍA DE TRABAJO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlateAutocomplete(List<VehicleModel> vehicles) {
    final plates = vehicles.map((v) => v.patente).toList();

    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return plates; // Si está vacío, muestra todos los camiones de la empresa
        }
        // Fuzzy normalizado: ignora guiones y mayúsculas
        final query = textEditingValue.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        return plates.where((plate) {
          final normalized = plate.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          return normalized.contains(query);
        });
      },
      onSelected: (String selection) {
        _plateCtrl.text = selection;
        try {
          final v = vehicles.firstWhere((veh) => veh.patente.toUpperCase() == selection.toUpperCase());
          if (v.currentOdometer > 0) {
            _odometerCtrl.text = v.currentOdometer.toStringAsFixed(0);
          }
        } catch (_) {}
      },
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        controller.addListener(() { _plateCtrl.text = controller.text; });
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Patente del Camión',
            hintText: 'AB-CD-12',
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.local_shipping, color: Color(0xFFFFFFFF)),
            helperText: plates.isEmpty
                ? 'Sin camiones registrados — escribe la patente manualmente'
                : '${plates.length} camión(es) registrado(s) en tu empresa',
          ),
          validator: (v) => v == null || v.isEmpty ? 'La patente es obligatoria' : null,
        );
      },
    );
  }
}
