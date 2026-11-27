import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/trip_provider.dart';
import '../../domain/models/shift_model.dart';
import '../../domain/models/vehicle_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_container.dart';

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

      final odo = int.tryParse(_odometerCtrl.text.replaceAll('.', '').trim()) ?? 0;
      final newShift = ShiftModel(
        id: 'SHIFT-${DateTime.now().millisecondsSinceEpoch}',
        idEmpresa: user.idEmpresa,
        idChofer: user.uid,
        patenteCamion: _plateCtrl.text.toUpperCase().trim(),
        startTime: DateTime.now(),
        startOdometer: odo,
        status: 'Activa',
      );

      await ref.read(tripRepositoryProvider).startShift(newShift);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Iniciar Jornada',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.background.withValues(alpha: 0.85),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Resplandor ambiental de cabina
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.4),
                  radius: 0.9,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.07),
                    AppColors.backgroundSecondary.withValues(alpha: 0.5),
                    AppColors.background,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlassContainer(
                      padding: const EdgeInsets.all(22.0),
                      borderRadius: BorderRadius.circular(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: const Icon(Icons.local_shipping_rounded, color: AppColors.primary, size: 24),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Registro de Máquina',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Selecciona el camión asignado a tu turno',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Autocomplete con patentes reales desde Firestore
                          vehiclesAsync.when(
                            loading: () => const LinearProgressIndicator(color: AppColors.primary),
                            error: (e, _) => Text('Error al cargar camiones: $e', style: const TextStyle(color: AppColors.error)),
                            data: (vehicles) => _buildPlateAutocomplete(vehicles),
                          ),
                          const SizedBox(height: 20),

                          TextFormField(
                            controller: _odometerCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Kilometraje Inicial',
                              labelStyle: const TextStyle(color: AppColors.textSecondary),
                              hintText: 'Ej: 154000',
                              hintStyle: const TextStyle(color: AppColors.textMuted),
                              filled: true,
                              fillColor: AppColors.surfaceElevated.withValues(alpha: 0.7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.speed_rounded, color: AppColors.primary),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'El kilometraje es obligatorio';
                              if (int.tryParse(v.replaceAll('.', '').trim()) == null) return 'Ingresa un número válido';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.verified_outlined, size: 16, color: AppColors.info),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Verifica siempre el odómetro físico en el tablero del camión antes de confirmar.',
                                    style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 11.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

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
                            onTap: _isLoading ? null : _startShift,
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(color: AppColors.background, strokeWidth: 2.5),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_arrow_rounded, color: AppColors.background, size: 28),
                                        SizedBox(width: 8),
                                        Text(
                                          'INICIAR DÍA DE TRABAJO',
                                          style: TextStyle(
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlateAutocomplete(List<VehicleModel> vehicles) {
    final plates = vehicles.map((v) => v.patente).toList();

    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return plates;
        }
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
        controller.addListener(() {
          _plateCtrl.text = controller.text;
        });
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, letterSpacing: 1.0),
          decoration: InputDecoration(
            labelText: 'Patente del Camión',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            hintText: 'AB-CD-12',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceElevated.withValues(alpha: 0.7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            prefixIcon: const Icon(Icons.directions_bus_rounded, color: AppColors.primary),
            helperText: plates.isEmpty
                ? 'Sin camiones registrados — escribe la patente'
                : '${plates.length} camión(es) disponibles en flota',
            helperStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          validator: (v) => v == null || v.isEmpty ? 'La patente es obligatoria' : null,
        );
      },
    );
  }
}
