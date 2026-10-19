import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/services/modogps_service.dart';
import '../../domain/services/gps_harvest_service.dart';

export '../../domain/services/modogps_service.dart' show GpsUnit;

final modoGpsServiceProvider = Provider((ref) => ModoGpsService());
final gpsHarvestServiceProvider = Provider((ref) => GpsHarvestService());

class RefreshTriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() => state++;
}

final refreshTriggerProvider = NotifierProvider<RefreshTriggerNotifier, int>(() => RefreshTriggerNotifier());

final fleetStreamProvider = StreamProvider<List<GpsUnit>>((ref) async* {
  final service = ref.read(modoGpsServiceProvider);
  final harvest = ref.read(gpsHarvestServiceProvider);
  final userProfile = ref.watch(currentUserProfileProvider).value;
  ref.watch(refreshTriggerProvider);

  while (true) {
    try {
      final units = await service.fetchFleetData(idEmpresa: userProfile?.idEmpresa);
      // Cosecha automática: posiciones, eventos y viajes se guardan en Firestore
      harvest.ingest(units, idEmpresa: userProfile?.idEmpresa).ignore();
      yield units;
    } catch (e) {
      debugPrint("Error obteniendo flota ModoGPS: $e");
    }
    await Future.delayed(const Duration(seconds: 5));
  }
});

class _UnitMotionState {
  final LatLng startPosition;
  final LatLng targetPosition;
  final double startHeading;
  final double targetHeading;

  _UnitMotionState({
    required this.startPosition,
    required this.targetPosition,
    required this.startHeading,
    required this.targetHeading,
  });
}

class ControlTowerView extends ConsumerStatefulWidget {
  const ControlTowerView({super.key});

  @override
  ConsumerState<ControlTowerView> createState() => _ControlTowerViewState();
}

class _ControlTowerViewState extends ConsumerState<ControlTowerView> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final Map<String, List<LatLng>> _recentTrails = {};
  final Map<String, _UnitMotionState> _motionStates = {};
  List<GpsUnit>? _lastUnits;
  String? _selectedPlate;
  late AnimationController _animController;
  late Animation<double> _animCurve;
  bool _hasCenteredInitial = false;
  bool _useSatellite = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );
    _animCurve = CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUrlForToken();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _checkUrlForToken() {
    try {
      final uri = Uri.base;
      String? token = uri.queryParameters['access_token'];
      if (token == null && uri.fragment.contains('access_token=')) {
        final match = RegExp(r'access_token=([a-fA-F0-9]+)').firstMatch(uri.fragment);
        token = match?.group(1);
      }
      if (token != null && token.isNotEmpty) {
        final service = ref.read(modoGpsServiceProvider);
        final userProfile = ref.read(currentUserProfileProvider).value;
        service.saveToken(token, idEmpresa: userProfile?.idEmpresa).then((_) {
          ref.read(refreshTriggerProvider.notifier).trigger();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ ModoGPS vinculado automáticamente desde el enlace.'),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      }
    } catch (_) {}
  }

  void _showGpsConfigDialog(BuildContext parentContext) {
    final textController = TextEditingController();
    final messenger = ScaffoldMessenger.of(parentContext);
    final nav = Navigator.of(parentContext, rootNavigator: true);
    bool isSaving = false;
    // 0 = Wialon/ModoGPS, 1 = Proveedor Genérico
    int selectedProvider = 0;

    showDialog(
      context: parentContext,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.satellite_alt, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vincular Proveedor GPS',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Conecta tu flota en tiempo real',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Selector de Proveedor ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => selectedProvider = 0),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: selectedProvider == 0 ? Colors.blueAccent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.verified_rounded, size: 13, color: selectedProvider == 0 ? Colors.white : Colors.white38),
                                    const SizedBox(width: 5),
                                    Text(
                                      'ModoGPS / Wialon',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: selectedProvider == 0 ? Colors.white : Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => selectedProvider = 1),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: selectedProvider == 1 ? Colors.purpleAccent.shade100.withValues(alpha: 0.8) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.settings_input_antenna, size: 13,
                                        color: selectedProvider == 1 ? Colors.white : Colors.white38),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Proveedor Genérico',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: selectedProvider == 1 ? Colors.white : Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Contenido según proveedor ──────────────────────────
                    if (selectedProvider == 0) ...[
                      // ── Wialon / ModoGPS ──
                      _buildStep(
                        number: '1',
                        title: 'Abre el portal y autoriza',
                        description: 'Haz clic en el botón de abajo. Se abrirá tu navegador con el portal de ModoGPS. Inicia sesión con tu usuario y acepta la autorización.',
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              const url = 'https://monitoreo.modogps.cl/login.html?client_id=BitacoraTMS&access_type=-1&duration=0&response_type=token';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.open_in_new, size: 15),
                            label: const Text('Abrir ModoGPS › Autorizar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStep(
                        number: '2',
                        title: 'Copia y pega el enlace de retorno',
                        description: 'Tras autorizar, el navegador te redirigirá a una URL. Copia esa URL completa (o solo el token) y pégala aquí:',
                        child: TextField(
                          controller: textController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'https://monitoreo.modogps.cl/login.html?access_token=... (o solo el token)',
                            hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                            filled: true,
                            fillColor: Colors.black38,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueAccent)),
                          ),
                        ),
                      ),
                    ] else ...[
                      // ── Proveedor Genérico ──
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, color: Colors.purpleAccent, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Compatible con cualquier plataforma basada en Wialon SDK u OAuth token. Ejemplos: Gurtam, NimBus, Flespi, TrackerMate y otros.',
                                style: TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStep(
                        number: '1',
                        title: 'Obtén tu Token de API',
                        description: 'Accede al portal de tu proveedor GPS → Perfil / Configuración → Tokens de API o Llaves de acceso. Genera un nuevo token con permisos de lectura de unidades.',
                      ),
                      const SizedBox(height: 12),
                      _buildStep(
                        number: '2',
                        title: 'Pega el token aquí',
                        description: 'Copia el token generado y pégalo en el campo. Si tu proveedor es compatible con Wialon SDK, también puedes pegar la URL de autorización completa.',
                        child: TextField(
                          controller: textController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Token de API o URL de autorización de tu proveedor GPS',
                            hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                            filled: true,
                            fillColor: Colors.black38,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.purpleAccent)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => nav.pop(),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    final raw = textController.text.trim();
                    if (raw.isEmpty) return;
                    setDialogState(() => isSaving = true);
                    try {
                      final service = ref.read(modoGpsServiceProvider);
                      final userProfile = ref.read(currentUserProfileProvider).value;
                      await service.saveToken(raw, idEmpresa: userProfile?.idEmpresa);
                      ref.read(refreshTriggerProvider.notifier).trigger();
                      if (!mounted) return;
                      nav.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(selectedProvider == 0
                              ? '✅ ModoGPS vinculado exitosamente. Sincronizando flota...'
                              : '✅ Proveedor GPS vinculado. Sincronizando flota...'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Error al guardar token: $e'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedProvider == 0 ? Colors.blueAccent : Colors.purpleAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Guardar y Conectar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStep({required String number, required String title, required String description, Widget? child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF1565C0),
            shape: BoxShape.circle,
          ),
          child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 3),
              Text(description, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              if (child != null) ...[
                const SizedBox(height: 10),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _syncUnits(List<GpsUnit> units) {
    if (identical(_lastUnits, units)) return;
    _lastUnits = units;

    if (_selectedPlate == null && units.isNotEmpty) {
      _selectedPlate = units.first.plate;
    } else if (_selectedPlate != null && !units.any((u) => u.plate == _selectedPlate)) {
      _selectedPlate = units.isNotEmpty ? units.first.plate : null;
    }

    _recordTrails(units);
    _updateMotion(units);
  }

  void _recordTrails(List<GpsUnit> units) {
    for (final unit in units) {
      final trail = _recentTrails.putIfAbsent(unit.plate, () => []);
      if (trail.isEmpty ||
          (trail.last.latitude != unit.position.latitude ||
              trail.last.longitude != unit.position.longitude)) {
        trail.add(unit.position);
        if (trail.length > 10) {
          trail.removeAt(0); // Mantenemos los últimos 10 puntos de estela reciente
        }
      }
    }
  }

  void _updateMotion(List<GpsUnit> units) {
    bool hasChanges = false;
    for (final unit in units) {
      final existing = _motionStates[unit.plate];
      final currentPos = existing != null ? _getCurrentPos(unit.plate) : unit.position;
      final currentHeading = existing != null ? _getCurrentHeading(unit.plate) : (unit.course ?? 0.0);
      final targetPos = unit.position;
      final targetHeading = unit.course ?? 0.0;

      final dist = math.sqrt(
        math.pow(currentPos.latitude - targetPos.latitude, 2) +
        math.pow(currentPos.longitude - targetPos.longitude, 2),
      );

      if (dist > 0.00001 || (currentHeading - targetHeading).abs() > 0.5) {
        hasChanges = true;
      }

      _motionStates[unit.plate] = _UnitMotionState(
        startPosition: currentPos,
        targetPosition: targetPos,
        startHeading: currentHeading,
        targetHeading: targetHeading,
      );
    }

    if (hasChanges) {
      _animController.forward(from: 0.0);
    }
  }

  LatLng _getCurrentPos(String plate) {
    final state = _motionStates[plate];
    if (state == null) return const LatLng(0, 0);
    final t = _animCurve.value;
    final lat = state.startPosition.latitude + (state.targetPosition.latitude - state.startPosition.latitude) * t;
    final lng = state.startPosition.longitude + (state.targetPosition.longitude - state.startPosition.longitude) * t;
    return LatLng(lat, lng);
  }

  double _getCurrentHeading(String plate) {
    final state = _motionStates[plate];
    if (state == null) return 0.0;
    final t = _animCurve.value;
    // Cálculo del menor ángulo de giro (-180 a 180) para interpolación suave
    final diff = ((state.targetHeading - state.startHeading + 540) % 360) - 180;
    return (state.startHeading + diff * t) % 360;
  }

  @override
  Widget build(BuildContext context) {
    final fleetAsync = ref.watch(fleetStreamProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // ── MAPA PRINCIPAL ────────────────────────────────────────────────
          Expanded(
            flex: 7,
            child: fleetAsync.when(
              data: (units) {
                if (units.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.satellite_alt, color: Colors.blueAccent, size: 48),
                        SizedBox(height: 16),
                        Text('Conectando con ModoGPS...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('Sincronizando telemetría de unidades activas.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  );
                }

                // Sincronizar estados de movimiento y estela
                _syncUnits(units);

                // Centrar automáticamente en la primera unidad una sola vez al cargar
                if (!_hasCenteredInitial && units.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _mapController.move(units.first.position, 14);
                      _hasCenteredInitial = true;
                    }
                  });
                }

                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: units.isNotEmpty ? units.first.position : const LatLng(-36.9840, -73.1774),
                        initialZoom: 14,
                      ),
                      children: [
                        // Capa Base: Satélite Esri u OpenStreetMap Limpio (Colores naturales, sin filtro oscuro)
                        if (_useSatellite)
                          TileLayer(
                            urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                            maxZoom: 19,
                          )
                        else
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.heirlog.tms',
                            maxZoom: 19,
                          ),

                        // Estela / Migas de pan de la unidad seleccionada (se limpia al cambiar de camión)
                        AnimatedBuilder(
                          animation: _animController,
                          builder: (context, _) {
                            if (_selectedPlate == null) return const SizedBox();
                            final points = List<LatLng>.from(_recentTrails[_selectedPlate] ?? []);
                            if (points.isEmpty) return const SizedBox();

                            if (_motionStates.containsKey(_selectedPlate)) {
                              points.add(_getCurrentPos(_selectedPlate!));
                            }

                            return PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: points,
                                  color: Colors.blueAccent.withValues(alpha: 0.85),
                                  strokeWidth: 4.5,
                                  borderColor: Colors.black87,
                                  borderStrokeWidth: 1.5,
                                ),
                              ],
                            );
                          },
                        ),

                        // Marcadores con posición animada (lerp) y rumbo suave
                        AnimatedBuilder(
                          animation: _animController,
                          builder: (context, _) {
                            return MarkerLayer(
                              markers: units.map((unit) {
                                final currentPos = _getCurrentPos(unit.plate);
                                final currentHeading = _getCurrentHeading(unit.plate);
                                final isSelected = unit.plate == _selectedPlate;
                                final isMoving = unit.speed > 0;
                                final color = isMoving 
                                    ? Colors.greenAccent 
                                    : (unit.status == 'offline' ? Colors.redAccent : Colors.orangeAccent);

                                final headingRadians = (currentHeading % 360) * (math.pi / 180.0);

                                return Marker(
                                  point: currentPos,
                                  width: 85,
                                  height: 75,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedPlate = unit.plate;
                                      });
                                      _mapController.move(currentPos, 16);
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.85),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: isSelected ? Colors.blueAccent : color.withValues(alpha: 0.8),
                                              width: isSelected ? 2.2 : 1.2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: isSelected ? Colors.blueAccent.withValues(alpha: 0.5) : color.withValues(alpha: 0.3),
                                                blurRadius: isSelected ? 8 : 4,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                unit.plate,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : color,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (isMoving) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${unit.speed.toStringAsFixed(0)}k',
                                                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected ? Colors.blueAccent : color,
                                              width: isSelected ? 2.5 : 2.0,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: isSelected ? Colors.blueAccent.withValues(alpha: 0.6) : color.withValues(alpha: 0.4),
                                                blurRadius: isSelected ? 8 : 6,
                                              ),
                                            ],
                                          ),
                                          child: isMoving
                                              ? Transform.rotate(
                                                  angle: headingRadians,
                                                  child: Icon(
                                                    Icons.navigation_rounded,
                                                    color: isSelected ? Colors.blueAccent : color,
                                                    size: 18,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.local_shipping,
                                                  color: isSelected ? Colors.blueAccent : color,
                                                  size: 16,
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),

                    // Selector de tipo de mapa (Calles Limpio vs. Satélite)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 6),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => setState(() => _useSatellite = false),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: !_useSatellite ? Colors.blueAccent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.map, size: 14, color: !_useSatellite ? Colors.white : Colors.white60),
                                    const SizedBox(width: 4),
                                    Text('Calles', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: !_useSatellite ? Colors.white : Colors.white60)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => setState(() => _useSatellite = true),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _useSatellite ? Colors.blueAccent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.satellite_alt, size: 14, color: _useSatellite ? Colors.white : Colors.white60),
                                    const SizedBox(width: 4),
                                    Text('Satélite', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _useSatellite ? Colors.white : Colors.white60)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 16),
                    Text('Iniciando enlace con ModoGPS...', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              error: (e, s) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    const Text('Error de Conexión ModoGPS', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text('$e', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref.read(refreshTriggerProvider.notifier).trigger(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar conexión'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showGpsConfigDialog(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      icon: const Icon(Icons.key, size: 16),
                      label: const Text('Vincular o Cambiar Cuenta ModoGPS'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── PANEL LATERAL (LISTA DE UNIDADES Y ESTADO) ─────────────────────
          Container(
            width: 360,
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.satellite_alt, color: Colors.blueAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Torre de Control',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Telemetría ModoGPS en vivo',
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        tooltip: 'Actualizar ahora',
                        icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                        onPressed: () {
                          ref.read(refreshTriggerProvider.notifier).trigger();
                        },
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showGpsConfigDialog(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.key_rounded, size: 16),
                      label: const Text('Vincular Cuenta ModoGPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),

                const Divider(color: Colors.white10, height: 1),

                // Lista de camiones
                Expanded(
                  child: fleetAsync.when(
                    data: (units) {
                      if (units.isEmpty) {
                        return const Center(
                          child: Text('Sin unidades conectadas', style: TextStyle(color: Colors.white38, fontSize: 13)),
                        );
                      }
                      return ListView.builder(
                        itemCount: units.length,
                        itemBuilder: (context, index) {
                          final unit = units[index];
                          return _buildUnitCard(unit);
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
                    error: (e, s) => const SizedBox(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitCard(GpsUnit unit) {
    final isSelected = unit.plate == _selectedPlate;
    final isMoving = unit.speed > 0;
    final color = isMoving 
        ? Colors.greenAccent 
        : (unit.status == 'offline' ? Colors.redAccent : Colors.orangeAccent);

    final statusText = isMoving
        ? '${unit.speed.toStringAsFixed(0)} km/h (En ruta)'
        : (unit.status == 'offline' ? 'Desconectado' : 'Detenido (0 km/h)');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blueAccent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.05),
          width: isSelected ? 1.8 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedPlate = unit.plate;
          });
          final pos = _getCurrentPos(unit.plate);
          _mapController.move(pos.latitude != 0 ? pos : unit.position, 15);
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blueAccent : color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    unit.plate,
                    style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                    ),
                    child: const Text(
                      'EN SEGUIMIENTO',
                      style: TextStyle(color: Colors.blueAccent, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  statusText,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Colors.white38, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${unit.position.latitude.toStringAsFixed(4)}, ${unit.position.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  unit.isIgnitionOn == true ? Icons.power : Icons.power_off,
                  color: unit.isIgnitionOn == true ? Colors.greenAccent : Colors.white24,
                  size: 13,
                ),
                const SizedBox(width: 4),
                Text(
                  unit.isIgnitionOn == true ? 'Motor Encendido' : 'Motor Apagado',
                  style: TextStyle(
                    color: unit.isIgnitionOn == true ? Colors.greenAccent : Colors.white38,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.access_time, color: Colors.white24, size: 12),
                const SizedBox(width: 4),
                Text(
                  'Hace ${DateTime.now().difference(unit.lastUpdate).inMinutes} min',
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
