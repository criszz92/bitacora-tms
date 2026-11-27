import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../admin/domain/services/modogps_service.dart';
import '../../../trips/domain/models/shift_model.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/presentation/providers/trip_provider.dart';

class EndShiftDialog extends ConsumerStatefulWidget {
  final ShiftModel shift;
  final List<TripModel> completedTrips;

  const EndShiftDialog({
    super.key,
    required this.shift,
    required this.completedTrips,
  });

  @override
  ConsumerState<EndShiftDialog> createState() => EndShiftDialogState();
}

class EndShiftDialogState extends ConsumerState<EndShiftDialog> {
  final _ctrl = TextEditingController();
  bool _isLoadingGps = true;
  double? _gpsTotalKm;
  String _unregisteredReason = 'Retorno a Base vacío';
  bool _isSubmitting = false;

  final List<String> _reasonOptions = [
    'Retorno a Base vacío',
    'Traslado a Taller / Mantención',
    'Carga de Combustible / Servicios',
    'Movimiento Operacional en Patio',
    'Otro movimiento autorizado',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    _fetchGpsDistance();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fetchGpsDistance() async {
    try {
      final modoGps = ref.read(modoGpsServiceProvider);
      final dist = await modoGps.getGpsDistanceForInterval(
        plate: widget.shift.patenteCamion,
        startTime: widget.shift.startTime,
        endTime: DateTime.now(),
        idEmpresa: widget.shift.idEmpresa,
      );
      if (mounted) {
        setState(() {
          _gpsTotalKm = dist;
          _isLoadingGps = false;
          // Si el chofer aún no ha tipeado y el GPS arrojó distancia positiva, sugerir el odómetro calculado
          if (_ctrl.text.isEmpty && dist != null && dist > 0) {
            final suggested = widget.shift.startOdometer + dist.round();
            _ctrl.text = suggested.toString();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingGps = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripsKm = widget.completedTrips.fold(0.0, (acc, t) => acc + (t.totalKm ?? 0.0));
    final enteredOdo = int.tryParse(_ctrl.text.trim());
    final bool hasValidOdo = enteredOdo != null && enteredOdo >= widget.shift.startOdometer;
    
    final int deltaOdo = hasValidOdo ? (enteredOdo - widget.shift.startOdometer) : 0;
    final double unregisteredKm = (hasValidOdo && deltaOdo > tripsKm) ? (deltaOdo - tripsKm) : 0.0;
    
    double? variationPercent;
    if (hasValidOdo && deltaOdo > 0 && _gpsTotalKm != null && _gpsTotalKm! > 0) {
      variationPercent = ((deltaOdo - _gpsTotalKm!).abs() / deltaOdo) * 100.0;
    }

    final numberFormat = NumberFormat('#,###');

    return AlertDialog(
      backgroundColor: const Color(0xFF16181F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_circle, color: Colors.redAccent, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cierre de Jornada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                    Text('Conciliación de Kilometraje y Odómetro', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Camión: ${widget.shift.patenteCamion}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
                Text('Inicio: ${DateFormat('HH:mm').format(widget.shift.startTime)} hrs', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Odómetro Inicial (Verificado)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E222B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.lightBlueAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Odómetro Inicial (Verificado al inicio)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          Text(
                            '${numberFormat.format(widget.shift.startOdometer)} KM',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Input Odómetro Final
              TextFormField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Odómetro Final (Verificar con Tablero)',
                  hintText: 'Ingresa el kilometraje actual',
                  helperText: _isLoadingGps
                      ? 'Consultando telemetría GPS...'
                      : (_gpsTotalKm != null ? 'GPS estimó aprox. ${numberFormat.format(widget.shift.startOdometer + _gpsTotalKm!.round())} KM' : null),
                  helperStyle: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF222632),
                  prefixIcon: const Icon(Icons.pin_outlined, color: Colors.white70),
                  suffixText: 'KM',
                  suffixStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent, width: 2)),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Panel de Conciliación
              if (hasValidOdo) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      _buildMetricRow('Rodaje Total Tablero (Δ):', '${numberFormat.format(deltaOdo)} KM', isBold: true),
                      const Divider(color: Colors.white10, height: 16),
                      _buildMetricRow('Viajes Registrados (GPS):', '${tripsKm.toStringAsFixed(1)} KM (${widget.completedTrips.length} viajes)', color: Colors.greenAccent),
                      const Divider(color: Colors.white10, height: 16),
                      _buildMetricRow('Distancia Total Satelital:', _isLoadingGps ? 'Calculando...' : '${_gpsTotalKm?.toStringAsFixed(1) ?? '--'} KM', color: Colors.cyanAccent),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Alerta de Kilómetros No Registrados (Km Muertos)
                if (unregisteredKm > 2.0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.alt_route, color: Colors.amberAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '+${unregisteredKm.toStringAsFixed(1)} KM no registrados en viajes',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Diferencia entre el rodaje de tablero y los viajes formalizados. Se justificará como:',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _unregisteredReason,
                          dropdownColor: const Color(0xFF1E222B),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            filled: true,
                            fillColor: const Color(0xFF14171F),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: _reasonOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _unregisteredReason = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. Badge de % de Variación Tablero vs GPS
                if (variationPercent != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: variationPercent <= 3.0
                          ? Colors.green.withValues(alpha: 0.15)
                          : (variationPercent <= 8.0
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.18)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: variationPercent <= 3.0
                            ? Colors.greenAccent.withValues(alpha: 0.5)
                            : (variationPercent <= 8.0
                                ? Colors.amberAccent.withValues(alpha: 0.5)
                                : Colors.redAccent.withValues(alpha: 0.6)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          variationPercent <= 3.0
                              ? Icons.verified
                              : (variationPercent <= 8.0 ? Icons.info_outline : Icons.warning_amber),
                          color: variationPercent <= 3.0
                              ? Colors.greenAccent
                              : (variationPercent <= 8.0 ? Colors.amberAccent : Colors.redAccent),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            variationPercent <= 3.0
                                ? 'Variación ${variationPercent.toStringAsFixed(1)}% • Tablero y GPS se condicen perfectamente'
                                : (variationPercent <= 8.0
                                    ? 'Variación ${variationPercent.toStringAsFixed(1)}% • Tolerancia normal de rodado'
                                    : 'Variación alta (${variationPercent.toStringAsFixed(1)}%) • Revisa si el odómetro final coincide con el camión'),
                            style: TextStyle(
                              color: variationPercent <= 3.0
                                  ? Colors.greenAccent
                                  : (variationPercent <= 8.0 ? Colors.amberAccent : Colors.redAccent),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else if (_ctrl.text.isNotEmpty && (enteredOdo == null || enteredOdo < widget.shift.startOdometer)) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El odómetro final debe ser mayor o igual al inicial (${numberFormat.format(widget.shift.startOdometer)} KM)',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: (!hasValidOdo || _isSubmitting)
              ? null
              : () async {
                  setState(() => _isSubmitting = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);
                  try {
                    await ref.read(tripRepositoryProvider).endShift(
                      widget.shift.id,
                      enteredOdo,
                      tripsKm: tripsKm,
                      totalGpsKm: _gpsTotalKm,
                      unregisteredKm: unregisteredKm > 0 ? unregisteredKm : 0.0,
                      unregisteredReason: unregisteredKm > 2.0 ? _unregisteredReason : null,
                      odometerVariationPercent: variationPercent,
                    );
                    if (mounted) {
                      nav.pop();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('✓ Jornada cerrada y kilometraje conciliado exitosamente.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error al cerrar jornada: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
          child: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('CONFIRMAR Y FINALIZAR JORNADA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 14 : 12,
          ),
        ),
      ],
    );
  }
}
