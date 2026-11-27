import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../../core/utils/road_infrastructure_detector.dart';
import '../../../admin/data/repositories/infraestructura_repository.dart';
import '../../../admin/domain/models/infraestructura_vial_model.dart';
import '../../../admin/domain/services/modogps_service.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/services/distance_service.dart';
import '../../../trips/presentation/providers/trip_provider.dart';

class DetectedTollPass {
  final String id;
  final PuntoInfraestructuraModel peaje;
  final DateTime passTime;
  final double distanceMeters;
  final bool isFromGps;
  bool isSelected;
  final bool isAlreadySaved;
  final TextEditingController amountController;

  DetectedTollPass({
    required this.id,
    required this.peaje,
    required this.passTime,
    required this.distanceMeters,
    this.isFromGps = true,
    this.isSelected = true,
    this.isAlreadySaved = false,
    required double initialAmount,
  }) : amountController = TextEditingController(
          text: initialAmount > 0 ? initialAmount.toInt().toString() : '0',
        );

  double get amount => double.tryParse(amountController.text.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;

  void dispose() {
    amountController.dispose();
  }
}

class EndTripDialog extends ConsumerStatefulWidget {
  final TripModel trip;
  final String targetPlate;

  const EndTripDialog({
    super.key,
    required this.trip,
    required this.targetPlate,
  });

  @override
  ConsumerState<EndTripDialog> createState() => EndTripDialogState();
}

class EndTripDialogState extends ConsumerState<EndTripDialog> {
  late final TextEditingController _guideCtrl;
  late final TextEditingController _kmCtrl;
  late final TextEditingController _containerCtrl;
  final _formKey = GlobalKey<FormState>();

  bool _isLoadingGps = true;
  bool _isLoadingTolls = true;
  double? _gpsKm;
  double? _suggestedTheoreticalKm;
  bool _isFinalizing = false;

  List<DetectedTollPass> _detectedTolls = [];
  List<PuntoInfraestructuraModel> _allAvailablePeajes = [];

  @override
  void initState() {
    super.initState();
    _guideCtrl = TextEditingController(text: widget.trip.guideNumber ?? '');
    _containerCtrl = TextEditingController(text: widget.trip.containerNumber ?? '');
    _kmCtrl = TextEditingController(
      text: (widget.trip.totalKm != null && widget.trip.totalKm! > 0)
          ? widget.trip.totalKm!.toStringAsFixed(1)
          : '',
    );
    _queryGpsAndTolls();
  }

  @override
  void dispose() {
    _guideCtrl.dispose();
    _kmCtrl.dispose();
    _containerCtrl.dispose();
    for (final t in _detectedTolls) {
      t.dispose();
    }
    super.dispose();
  }

  double get _totalValidatedTolls {
    double total = 0.0;
    for (final toll in _detectedTolls) {
      if (toll.isSelected && !toll.isAlreadySaved) {
        total += toll.amount;
      }
    }
    return total;
  }

  Future<void> _queryGpsAndTolls() async {
    if (!mounted) return;
    setState(() {
      _isLoadingGps = true;
      _isLoadingTolls = true;
    });

    try {
      final modoGps = ref.read(modoGpsServiceProvider);
      final activeShift = ref.read(activeShiftProvider).value;
      final endTime = widget.trip.endDate ?? DateTime.now();
      final startTime = widget.trip.startDate;

      // 1. Cargar catálogo universal de peajes
      try {
        final infraRepo = ref.read(infraestructuraRepositoryProvider);
        final puntos = await infraRepo.getPuntos(soloActivos: true);
        _allAvailablePeajes = puntos.where((p) => p.tipo == TipoPuntoInfraestructura.peaje).toList();
      } catch (e) {
        debugPrint('[Peajes] Error cargando catálogo de peajes: $e');
      }

      // 2. Cargar gastos existentes para este viaje (para no duplicar si ya rindió un peaje)
      final existingPeajeNames = <String>[];
      try {
        final existingGastos = await FirebaseFirestore.instance
            .collection('gastos')
            .where('tripId', isEqualTo: widget.trip.id)
            .where('type', isEqualTo: 'Peaje')
            .get();
        for (final doc in existingGastos.docs) {
          final desc = (doc.data()['description'] ?? '').toString().toLowerCase();
          existingPeajeNames.add(desc);
        }
      } catch (e) {
        debugPrint('[Peajes] Error consultando gastos existentes: $e');
      }

      // 3. Consultar intervalo GPS
      final hTrip = await modoGps.fetchTripInterval(
        plate: widget.targetPlate,
        startTime: startTime,
        endTime: endTime,
        idEmpresa: activeShift?.idEmpresa,
      );

      if (hTrip != null && hTrip.totalDistanceKm > 0) {
        _gpsKm = hTrip.totalDistanceKm;
        _kmCtrl.text = _gpsKm!.toStringAsFixed(1);
      } else {
        final distSvc = ref.read(distanceServiceProvider);
        final theoretical = distSvc.lookupKm(widget.trip.client, widget.trip.destination);
        if (theoretical != null) {
          _suggestedTheoreticalKm = theoretical;
          if (_kmCtrl.text.isEmpty) {
            _kmCtrl.text = theoretical.toStringAsFixed(0);
          }
        }
      }

      // 4. Cruzar puntos de ruta GPS con catálogo de peajes
      if (hTrip != null && hTrip.points.isNotEmpty && _allAvailablePeajes.isNotEmpty) {
        const distanceCalc = Distance();
        final detected = <DetectedTollPass>[];

        // Lista de candidatos potenciales con distancia y punto exacto de cruce
        final candidatePasses = <DetectedTollPass>[];

        for (final peaje in _allAvailablePeajes) {
          final peajeLatLng = LatLng(peaje.lat, peaje.lng);

          // Radio adaptativo:
          // Peajes Laterales: radio estricto de 18m para no atrapar el camión que viaja por la autopista central
          // Peajes Troncales: radio de 45m para cubrir las pistas de la calzada
          final maxRadius = RoadInfrastructureDetector.getOptimalDetectionRadius(
            tipoCode: peaje.tipo.code,
            subtipo: peaje.subtipo,
            radioConfigurado: peaje.radioMetros,
          );

          DateTime? lastDetectionTime;
          double minDistanceInPass = double.infinity;
          DateTime bestPointTime = peaje.createdAt;

          for (int ptIdx = 0; ptIdx < hTrip.points.length; ptIdx++) {
            final pt = hTrip.points[ptIdx];
            final distM = ptIdx > 0
                ? RoadInfrastructureDetector.calculateDistanceToSegmentMeters(
                    peajeLatLng,
                    hTrip.points[ptIdx - 1].position,
                    pt.position,
                  )
                : distanceCalc.as(LengthUnit.Meter, peajeLatLng, pt.position);

            if (distM <= maxRadius) {
              // Calcular rumbo del camión evitando jitter si el punto anterior está muy cerca (< 15m)
              double? ptBearing;
              for (int back = ptIdx - 1; back >= 0; back--) {
                final prevPt = hTrip.points[back];
                if (RoadInfrastructureDetector.calculateDistanceMeters(prevPt.position, pt.position) >= 15.0) {
                  ptBearing = RoadInfrastructureDetector.calculateBearing(prevPt.position, pt.position);
                  break;
                }
              }
              if (ptBearing == null && ptIdx < hTrip.points.length - 1) {
                for (int fwd = ptIdx + 1; fwd < hTrip.points.length; fwd++) {
                  final nextPt = hTrip.points[fwd];
                  if (RoadInfrastructureDetector.calculateDistanceMeters(pt.position, nextPt.position) >= 15.0) {
                    ptBearing = RoadInfrastructureDetector.calculateBearing(pt.position, nextPt.position);
                    break;
                  }
                }
              }

              // Validar concordancia de sentido (Norte a Sur vs Sur a Norte, etc.)
              if (!RoadInfrastructureDetector.matchesDirection(truckHeading: ptBearing, sentidoPunto: peaje.sentido)) {
                continue;
              }

              if (lastDetectionTime == null || pt.timestamp.difference(lastDetectionTime).inMinutes.abs() > 20) {
                if (lastDetectionTime != null && minDistanceInPass < double.infinity) {
                  final defaultAmount = peaje.tarifaCamionPesado ?? peaje.tarifaCamionSimple ?? 0.0;
                  final isSaved = existingPeajeNames.any((n) => n.contains(peaje.nombre.toLowerCase()));
                  candidatePasses.add(DetectedTollPass(
                    id: 'pass-${peaje.id}-${bestPointTime.millisecondsSinceEpoch}',
                    peaje: peaje,
                    passTime: bestPointTime,
                    distanceMeters: minDistanceInPass,
                    isAlreadySaved: isSaved,
                    isSelected: !isSaved,
                    initialAmount: defaultAmount,
                  ));
                }
                lastDetectionTime = pt.timestamp;
                minDistanceInPass = distM;
                bestPointTime = pt.timestamp;
              } else {
                if (distM < minDistanceInPass) {
                  minDistanceInPass = distM;
                  bestPointTime = pt.timestamp;
                }
              }
            }
          }

          if (lastDetectionTime != null && minDistanceInPass < double.infinity) {
            final defaultAmount = peaje.tarifaCamionPesado ?? peaje.tarifaCamionSimple ?? 0.0;
            final isSaved = existingPeajeNames.any((n) => n.contains(peaje.nombre.toLowerCase()));
            candidatePasses.add(DetectedTollPass(
              id: 'pass-${peaje.id}-${bestPointTime.millisecondsSinceEpoch}',
              peaje: peaje,
              passTime: bestPointTime,
              distanceMeters: minDistanceInPass,
              isAlreadySaved: isSaved,
              isSelected: !isSaved,
              initialAmount: defaultAmount,
            ));
          }
        }

        // DESEMPATE DE CASILLAS PARALELAS (Nearest Gate Competition):
        // Si dos casetas de peaje (ej. Cabrero Norte vs Sur, o Puente Industrial) fueron detectadas
        // en una misma ventana de tiempo (< 3 minutos), nos quedamos con la que tuvo menor distancia física
        // al camión (la pista exacta por la que circulaba).
        candidatePasses.sort((a, b) => a.passTime.compareTo(b.passTime));

        for (final cand in candidatePasses) {
          final conflictingIdx = detected.indexWhere((existing) {
            final diffSec = cand.passTime.difference(existing.passTime).inSeconds.abs();
            return diffSec < 180; // Misma ventana de paso
          });

          if (conflictingIdx >= 0) {
            final existing = detected[conflictingIdx];
            // Si el nuevo candidato está físicamente más cerca de la calzada que el anterior, lo reemplaza
            if (cand.distanceMeters < existing.distanceMeters) {
              detected[conflictingIdx] = cand;
            }
          } else {
            detected.add(cand);
          }
        }

        detected.sort((a, b) => a.passTime.compareTo(b.passTime));

        for (final t in _detectedTolls) {
          t.dispose();
        }
        _detectedTolls = detected;
      }
    } catch (e) {
      debugPrint('[FinalizarViaje] Error en telemetría o peajes: $e');
      final distSvc = ref.read(distanceServiceProvider);
      final theoretical = distSvc.lookupKm(widget.trip.client, widget.trip.destination);
      if (theoretical != null && _kmCtrl.text.isEmpty) {
        _suggestedTheoreticalKm = theoretical;
        _kmCtrl.text = theoretical.toStringAsFixed(0);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGps = false;
          _isLoadingTolls = false;
        });
      }
    }
  }

  void _showAddManualTollDialog() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    PuntoInfraestructuraModel? selectedFromCatalog;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E242B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_road, color: Colors.amberAccent, size: 20),
              SizedBox(width: 8),
              Text('Agregar Peaje al Viaje', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Seleccionar del Catálogo de Peajes:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PuntoInfraestructuraModel?>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E242B),
                      value: selectedFromCatalog,
                      hint: const Text('Elegir peaje registrado...', style: TextStyle(color: Colors.white60, fontSize: 13)),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Otro (Ingreso manual libre)', style: TextStyle(color: Colors.cyanAccent, fontSize: 13)),
                        ),
                        ..._allAvailablePeajes.map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                '${p.nombre} (${p.ruta})',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (val) {
                        setDlgState(() {
                          selectedFromCatalog = val;
                          if (val != null) {
                            nameCtrl.text = val.nombre;
                            final rate = val.tarifaCamionPesado ?? val.tarifaCamionSimple ?? 0.0;
                            if (rate > 0) amountCtrl.text = rate.toInt().toString();
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Nombre del Peaje',
                    labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Monto a Rendir (\$)',
                    labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(color: Colors.amberAccent),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (name.isEmpty) return;

                final model = selectedFromCatalog ??
                    PuntoInfraestructuraModel(
                      id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                      nombre: name,
                      tipo: TipoPuntoInfraestructura.peaje,
                      subtipo: 'Manual',
                      ruta: '',
                      lat: 0.0,
                      lng: 0.0,
                      radioMetros: 0,
                      sentido: 'Bidireccional',
                      creadoPor: 'CONDUCTOR',
                      createdAt: DateTime.now(),
                    );

                final newPass = DetectedTollPass(
                  id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                  peaje: model,
                  passTime: DateTime.now(),
                  distanceMeters: 0,
                  isFromGps: false,
                  isSelected: true,
                  initialAmount: amount,
                );

                setState(() {
                  _detectedTolls.add(newPass);
                });

                Navigator.pop(ctx);
              },
              child: const Text('AGREGAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTollsSection() {
    final currencyFmt = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.toll_outlined, size: 16, color: Colors.amberAccent),
                const SizedBox(width: 6),
                const Text(
                  'Peajes en Ruta',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (_detectedTolls.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_detectedTolls.length}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            if (_isLoadingTolls)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
              ),
          ],
        ),
        const SizedBox(height: 6),

        if (_isLoadingTolls)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 14, color: Colors.amberAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Identificando pasadas por peajes...',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                  ),
                ),
              ],
            ),
          )
        else if (_detectedTolls.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.toll_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sin pasadas por peajes detectadas en este tramo.',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ),
                InkWell(
                  onTap: _showAddManualTollDialog,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Colors.amberAccent),
                        SizedBox(width: 2),
                        Text('Agregar', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          ..._detectedTolls.map((toll) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: toll.isAlreadySaved
                    ? Colors.white.withValues(alpha: 0.03)
                    : (toll.isSelected ? const Color(0xFF1E2836) : Colors.black12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: toll.isAlreadySaved
                      ? Colors.green.withValues(alpha: 0.3)
                      : (toll.isSelected ? Colors.amber.withValues(alpha: 0.4) : Colors.white10),
                ),
              ),
              child: Row(
                children: [
                  if (toll.isAlreadySaved)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle, size: 18, color: Colors.greenAccent),
                    )
                  else
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: toll.isSelected,
                        activeColor: Colors.amberAccent,
                        checkColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        visualDensity: VisualDensity.compact,
                        onChanged: (val) {
                          setState(() {
                            toll.isSelected = val ?? false;
                          });
                        },
                      ),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                toll.peaje.nombre,
                                style: TextStyle(
                                  color: toll.isSelected ? Colors.white : Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  decoration: toll.isSelected ? null : TextDecoration.lineThrough,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (toll.isAlreadySaved)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Rendido', style: TextStyle(color: Colors.greenAccent, fontSize: 9.5, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          toll.isFromGps
                              ? '${toll.peaje.ruta.isNotEmpty ? "${toll.peaje.ruta} • " : ""}🛰️ ${DateFormat('HH:mm').format(toll.passTime)} hrs (~${toll.distanceMeters.toStringAsFixed(0)}m)'
                              : '${toll.peaje.ruta.isNotEmpty ? "${toll.peaje.ruta} • " : ""}✍️ Agregado manual',
                          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 82,
                    child: TextFormField(
                      controller: toll.amountController,
                      enabled: toll.isSelected && !toll.isAlreadySaved,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: toll.isSelected ? Colors.amberAccent : Colors.grey,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: '\$ ',
                        prefixStyle: const TextStyle(color: Colors.white70, fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        filled: true,
                        fillColor: Colors.black38,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.amberAccent)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (!toll.isFromGps && !toll.isAlreadySaved)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                      padding: const EdgeInsets.only(left: 4),
                      constraints: const BoxConstraints(),
                      tooltip: 'Quitar',
                      onPressed: () {
                        setState(() {
                          toll.dispose();
                          _detectedTolls.remove(toll);
                        });
                      },
                    ),
                ],
              ),
            );
          }),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _showAddManualTollDialog,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, size: 14, color: Colors.amberAccent),
                      SizedBox(width: 4),
                      Text('Agregar otro peaje', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              Text(
                'Total: ${currencyFmt.format(_totalValidatedTolls)}',
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm');
    final startTimeStr = timeFmt.format(widget.trip.startDate);
    final endTimeStr = timeFmt.format(DateTime.now());

    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Finalizar Viaje', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.route, size: 14, color: Colors.white60),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.trip.origin} ➔ ${widget.trip.destination}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Banner de recomendación GPS
              if (_isLoadingGps)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Consultando KM reales y peajes capturados por GPS...',
                          style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_gpsKm != null && _gpsKm! > 0)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F5132).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.satellite_alt, color: Colors.greenAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🛰️ GPS Detectó: ${_gpsKm!.toStringAsFixed(1)} KM reales',
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Tramo: $startTimeStr ➔ $endTimeStr (${widget.targetPlate})',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18, color: Colors.greenAccent),
                        tooltip: 'Recalcular GPS',
                        onPressed: _queryGpsAndTolls,
                      ),
                    ],
                  ),
                )
              else if (_suggestedTheoreticalKm != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'KM sugerido por tabla: ${_suggestedTheoreticalKm!.toStringAsFixed(0)} KM',
                          style: const TextStyle(color: Colors.purpleAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Sin señal GPS en este tramo. Ingrese los KM manualmente.',
                          style: TextStyle(color: Colors.amber, fontSize: 11),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16, color: Colors.amber),
                        onPressed: _queryGpsAndTolls,
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),

              // SECCIÓN DE PEAJES DETECTADOS / VALIDACIÓN
              _buildTollsSection(),

              const SizedBox(height: 16),
              // Si el viaje no tiene contenedor (o es retiro anticipado), permitir ingresarlo aquí
              if (widget.trip.containerNumber == null || widget.trip.containerNumber!.isEmpty || widget.trip.tipoMovimiento == 'retiro_anticipado') ...[
                TextFormField(
                  controller: _containerCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Nº Contenedor Asignado (opcional)',
                    labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 13),
                    hintText: 'Ej: MSMU3836691',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.inventory_2_outlined, color: Colors.cyanAccent, size: 20),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _guideCtrl,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nº Guía de Despacho (opcional)',
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  hintText: 'Ej: 12345',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Kilómetros recorridos',
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  suffixText: 'KM',
                  suffixStyle: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: _gpsKm != null ? Colors.green.withValues(alpha: 0.1) : Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: _gpsKm != null ? const BorderSide(color: Colors.greenAccent, width: 1) : BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: _gpsKm != null ? const BorderSide(color: Colors.greenAccent, width: 1) : BorderSide.none,
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa los kilómetros recorridos';
                  }
                  final parsed = double.tryParse(val.replaceAll(',', '.').trim());
                  if (parsed == null || parsed < 0) {
                    return 'Ingresa un valor numérico válido';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isFinalizing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFFFFF),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isFinalizing
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);

                  setState(() => _isFinalizing = true);

                  final parsedKm = double.tryParse(_kmCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                  final activeShift = ref.read(activeShiftProvider).value;

                  try {
                    // 1. Finalizar viaje y registrar odómetro / guía
                    await ref.read(tripRepositoryProvider).endTripWithGuide(
                      widget.trip.id,
                      _guideCtrl.text.trim(),
                      totalKm: parsedKm,
                      containerNumber: _containerCtrl.text.trim().isNotEmpty ? _containerCtrl.text.trim().toUpperCase() : null,
                    );

                    // 2. Guardar y conciliar los peajes seleccionados en /gastos
                    int savedTollsCount = 0;
                    double totalTollsAmount = 0.0;

                    for (final toll in _detectedTolls) {
                      if (!toll.isSelected || toll.isAlreadySaved) continue;
                      final tollAmount = toll.amount;
                      if (tollAmount <= 0) continue;

                      final bucket10m = toll.passTime.millisecondsSinceEpoch ~/ 600000;
                      final expenseId = 'EXP-TOLL-${widget.trip.id}-${toll.peaje.id}-$bucket10m';
                      final expense = ExpenseModel(
                        id: expenseId,
                        idEmpresa: activeShift?.idEmpresa ?? widget.trip.idEmpresa,
                        idChofer: widget.trip.idChofer,
                        idJornada: widget.trip.idJornada,
                        tripId: widget.trip.id,
                        amount: tollAmount,
                        type: 'Peaje',
                        litros: null,
                        date: toll.passTime,
                        description: 'Peaje: ${toll.peaje.nombre}${toll.peaje.ruta.isNotEmpty ? ' (${toll.peaje.ruta})' : ''}',
                        status: 'Pendiente',
                        vehicleId: widget.trip.vehicleId ?? widget.targetPlate,
                      );

                      await ref.read(tripRepositoryProvider).addExpense(expense);
                      savedTollsCount++;
                      totalTollsAmount += tollAmount;
                    }

                    nav.pop();

                    final currencyFmt = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);
                    final tollsMsg = savedTollsCount > 0
                        ? ' • $savedTollsCount peajes conciliados (${currencyFmt.format(totalTollsAmount)})'
                        : '';

                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('✓ Viaje cerrado: ${parsedKm.toStringAsFixed(1)} KM$tollsMsg'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isFinalizing = false);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error al finalizar viaje: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
          child: _isFinalizing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('FINALIZAR', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ================= DIÁLOGO DE CIERRE Y CONCILIACIÓN DE JORNADA =================

