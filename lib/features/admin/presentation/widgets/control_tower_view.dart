import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/services/modogps_service.dart';
import '../../domain/services/gps_harvest_service.dart';
import '../../domain/models/infraestructura_vial_model.dart';
import '../../data/repositories/infraestructura_repository.dart';

export '../../domain/services/modogps_service.dart' show GpsUnit, modoGpsServiceProvider, singleVehicleGpsProvider, GpsGeofence;

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
  bool _showGeofences = true;
  bool _showInfraestructura = true;

  // Modo de vista: 0 = En Vivo, 1 = Historial de Recorridos
  int _viewMode = 0;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 59);
  bool _isLoadingHistory = false;
  GpsHistoricalTrip? _historicalTrip;
  List<GpsGeofence> _cachedGeofencesList = [];
  int? _selectedLegIndex; // null = ver todos los tramos, o índice de tramo específico

  @override
  void initState() {
    super.initState();
    _loadGeofences();
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

  Future<void> _loadGeofences() async {
    try {
      final userProfile = ref.read(currentUserProfileProvider).value;
      final service = ref.read(modoGpsServiceProvider);
      final geofences = await service.fetchGeofences(idEmpresa: userProfile?.idEmpresa);
      if (mounted) {
        setState(() {
          _cachedGeofencesList = geofences;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchHistoricalRoute(String plate) async {
    setState(() {
      _isLoadingHistory = true;
      _historicalTrip = null;
    });

    try {
      final userProfile = ref.read(currentUserProfileProvider).value;
      final service = ref.read(modoGpsServiceProvider);

      final startDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      final endDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _endTime.hour,
        _endTime.minute,
      );

      final trip = await service.fetchTripInterval(
        plate: plate,
        startTime: startDateTime,
        endTime: endDateTime,
        idEmpresa: userProfile?.idEmpresa,
      );

      if (mounted) {
        setState(() {
          _historicalTrip = trip;
          _isLoadingHistory = false;
        });

        if (trip != null && trip.points.isNotEmpty) {
          // Centrar mapa en el punto medio del recorrido
          final midPoint = trip.points[trip.points.length ~/ 2].position;
          _mapController.move(midPoint, 13);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se encontraron registros de movimiento para este horario.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al consultar historial: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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
    final puntosInfraAsync = ref.watch(puntosInfraestructuraProvider);
    final puntosInfra = puntosInfraAsync.value ?? [];
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final isSuperAdmin = currentUser?.isSuperAdmin ?? false;

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

                        // Capa de Geocercas ModoGPS (Polígonos y Áreas)
                        if (_showGeofences && _cachedGeofencesList.isNotEmpty)
                          PolygonLayer(
                            polygons: _cachedGeofencesList.map((g) {
                              final isBase = g.name.toUpperCase().contains('BASE') || g.name.toUpperCase().contains('CASA');
                              final isPuerto = g.name.toUpperCase().contains('PUERTO') || g.name.toUpperCase().contains('SVTI');
                              final color = isBase 
                                  ? Colors.greenAccent 
                                  : (isPuerto ? Colors.cyanAccent : Colors.amberAccent);

                              // Convertir bounding box en polígono cuadrangular
                              final polyPoints = [
                                LatLng(g.minLat, g.minLng),
                                LatLng(g.minLat, g.maxLng),
                                LatLng(g.maxLat, g.maxLng),
                                LatLng(g.maxLat, g.minLng),
                              ];

                              return Polygon(
                                points: polyPoints,
                                color: color.withValues(alpha: 0.15),
                                borderColor: color.withValues(alpha: 0.8),
                                borderStrokeWidth: 1.8,
                              );
                            }).toList(),
                          ),

                        // Capa de Etiquetas de Geocercas en el mapa
                        if (_showGeofences && _cachedGeofencesList.isNotEmpty)
                          MarkerLayer(
                            markers: _cachedGeofencesList.map((g) {
                              return Marker(
                                point: g.center,
                                width: 120,
                                height: 26,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.white24, width: 0.8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      g.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                        // Capa de Infraestructura Vial Universal (Peajes, Romanas, Restricciones)
                        if (_showInfraestructura && puntosInfra.isNotEmpty)
                          MarkerLayer(
                            markers: puntosInfra.map((p) => _buildInfraestructuraMarker(p, isSuperAdmin)).toList(),
                          ),

                        // Capa de Trazado Histórico (Ruta segmentada por tramos de color y paradas)
                        if (_viewMode == 1 && _historicalTrip != null && _historicalTrip!.points.isNotEmpty) ...[
                          // Polylines coloreadas según el tramo (Ida vs Retorno)
                          PolylineLayer(
                            polylines: (_historicalTrip!.legs.isNotEmpty
                                    ? _historicalTrip!.legs
                                        .where((leg) => _selectedLegIndex == null || _selectedLegIndex == leg.index)
                                        .map((leg) {
                                        return Polyline(
                                          points: leg.points.map((p) => p.position).toList(),
                                          color: leg.color,
                                          strokeWidth: 5.5,
                                          borderColor: Colors.black,
                                          borderStrokeWidth: 1.5,
                                        );
                                      }).toList()
                                    : [
                                        Polyline(
                                          points: _historicalTrip!.points.map((p) => p.position).toList(),
                                          color: const Color(0xFF00E5FF),
                                          strokeWidth: 5.5,
                                          borderColor: Colors.black,
                                          borderStrokeWidth: 1.5,
                                        ),
                                      ]),
                          ),

                          // Flechas direccionales de rumbo y Marcadores de Paradas
                          MarkerLayer(
                            markers: [
                              // Marcador Inicio
                              Marker(
                                point: _historicalTrip!.points.first.position,
                                width: 36,
                                height: 36,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                                  ),
                                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                                ),
                              ),

                              // Marcador Fin
                              Marker(
                                point: _historicalTrip!.points.last.position,
                                width: 36,
                                height: 36,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                                  ),
                                  child: const Icon(Icons.flag, color: Colors.white, size: 18),
                                ),
                              ),

                              // Flechas de dirección sobre la ruta (cada ~15 puntos con movimiento)
                              ...() {
                                final arrows = <Marker>[];
                                final visibleLegs = _historicalTrip!.legs.isNotEmpty
                                    ? _historicalTrip!.legs.where((leg) => _selectedLegIndex == null || _selectedLegIndex == leg.index)
                                    : [GpsTripLeg(index: 1, name: '', startTime: _historicalTrip!.startTime, endTime: _historicalTrip!.endTime, distanceKm: 0, maxSpeed: 0, avgSpeed: 0, points: _historicalTrip!.points, color: Colors.cyan)];

                                for (final leg in visibleLegs) {
                                  final pts = leg.points;
                                  final step = math.max(12, pts.length ~/ 15);
                                  for (int i = step; i < pts.length - 2; i += step) {
                                    final p1 = pts[i];
                                    final p2 = pts[i + 1];
                                    if (p1.speed > 8.0) {
                                      final dLat = p2.position.latitude - p1.position.latitude;
                                      final dLng = p2.position.longitude - p1.position.longitude;
                                      final headingRad = math.atan2(dLng, dLat);

                                      arrows.add(
                                        Marker(
                                          point: p1.position,
                                          width: 22,
                                          height: 22,
                                          child: Transform.rotate(
                                            angle: headingRad,
                                            child: Icon(
                                              Icons.navigation,
                                              size: 14,
                                              color: Colors.white.withValues(alpha: 0.95),
                                              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                                return arrows;
                              }(),

                              // Marcadores de Paradas y Detenciones (ej: Repostaje de combustible, Espera en Cliente)
                              ..._historicalTrip!.stops.map((stop) {
                                final isGasStation = (stop.geofenceName ?? '').toUpperCase().contains('COPEC') ||
                                    (stop.geofenceName ?? '').toUpperCase().contains('SHELL') ||
                                    (stop.geofenceName ?? '').toUpperCase().contains('PETROBRAS');
                                final dur = stop.durationMinutes >= 60
                                    ? '${stop.durationMinutes ~/ 60}h ${stop.durationMinutes % 60}m'
                                    : '${stop.durationMinutes}m';

                                return Marker(
                                  point: stop.position,
                                  width: 90,
                                  height: 50,
                                  child: GestureDetector(
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '🛑 Parada: $dur ${stop.geofenceName != null ? 'en ${stop.geofenceName}' : ''} (${stop.startTime.hour.toString().padLeft(2, '0')}:${stop.startTime.minute.toString().padLeft(2, '0')} - ${stop.endTime.hour.toString().padLeft(2, '0')}:${stop.endTime.minute.toString().padLeft(2, '0')})',
                                          ),
                                          backgroundColor: Colors.amber[800],
                                        ),
                                      );
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.85),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amberAccent, width: 1),
                                          ),
                                          child: Text(
                                            dur,
                                            style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.amber[800],
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 1.5),
                                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                                          ),
                                          child: Icon(
                                            isGasStation ? Icons.local_gas_station : Icons.pause_circle_filled,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],

                        // Estela / Migas de pan de la unidad seleccionada (se limpia al cambiar de camión)
                        if (_viewMode == 0)
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
                            const SizedBox(width: 4),
                            // Botón Mostrar/Ocultar Geocercas
                            InkWell(
                              onTap: () => setState(() => _showGeofences = !_showGeofences),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _showGeofences ? Colors.amber.withValues(alpha: 0.25) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _showGeofences ? Colors.amber : Colors.transparent,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.polyline, size: 14, color: _showGeofences ? Colors.amber : Colors.white60),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Geocercas (${_cachedGeofencesList.length})',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _showGeofences ? Colors.amber : Colors.white60),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Botón Mostrar/Ocultar Infraestructura (Peajes, Romanas)
                            InkWell(
                              onTap: () => setState(() => _showInfraestructura = !_showInfraestructura),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _showInfraestructura ? const Color(0xFF00E676).withValues(alpha: 0.25) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _showInfraestructura ? const Color(0xFF00E676) : Colors.transparent,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.toll, size: 14, color: _showInfraestructura ? const Color(0xFF00E676) : Colors.white60),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Puntos Viales (${puntosInfra.length})',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _showInfraestructura ? const Color(0xFF00E676) : Colors.white60),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Botón Agregar Punto Vial (Solo SuperAdmin)
                            if (isSuperAdmin) ...[
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _showCrearEditarPuntoDialog(context, initialPos: _mapController.camera.center),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E676),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_location_alt, size: 14, color: Colors.black),
                                      SizedBox(width: 4),
                                      Text(
                                        '+ Punto Vial',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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

                // ── SELECTOR DE MODO: EN VIVO vs HISTORIAL ──────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _viewMode = 0),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _viewMode == 0 ? Colors.blueAccent : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.sensors, size: 14, color: _viewMode == 0 ? Colors.white : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'En Vivo',
                                    style: TextStyle(
                                      color: _viewMode == 0 ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _viewMode = 1),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _viewMode == 1 ? Colors.blueAccent : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.history, size: 14, color: _viewMode == 1 ? Colors.white : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Historial',
                                    style: TextStyle(
                                      color: _viewMode == 1 ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
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
                ),

                const Divider(color: Colors.white10, height: 1),

                // ── CONTENIDO SEGÚN MODO SELECCIONADO ─────────────
                Expanded(
                  child: _viewMode == 0
                      // MODO 0: EN VIVO
                      ? fleetAsync.when(
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
                        )
                      // MODO 1: HISTORIAL DE RECORRIDOS
                      : _buildHistoryPanel(fleetAsync.value ?? []),
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

  Widget _buildHistoryPanel(List<GpsUnit> units) {
    // Si no hay camión seleccionado pero hay unidades, preseleccionar la primera
    final availablePlates = units.map((u) => u.plate).toList();
    if (availablePlates.isNotEmpty && (_selectedPlate == null || !availablePlates.contains(_selectedPlate))) {
      _selectedPlate = availablePlates.first;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selector de Camión
          const Text('UNIDAD / CAMIÓN', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPlate,
                isExpanded: true,
                dropdownColor: const Color(0xFF161B22),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                items: availablePlates.map((plate) {
                  return DropdownMenuItem(
                    value: plate,
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(plate),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedPlate = val;
                      _historicalTrip = null;
                    });
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Selector de Fecha
          const Text('FECHA DE RECORRIDO', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2024, 1),
                lastDate: DateTime.now(),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(primary: Colors.blueAccent),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                  _historicalTrip = null;
                });
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Selector de Horas (Desde - Hasta)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DESDE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (picked != null) {
                          setState(() {
                            _startTime = picked;
                            _historicalTrip = null;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.access_time, color: Colors.white54, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HASTA', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (picked != null) {
                          setState(() {
                            _endTime = picked;
                            _historicalTrip = null;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.access_time, color: Colors.white54, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Botón Cargar Recorrido
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoadingHistory || _selectedPlate == null
                  ? null
                  : () => _fetchHistoricalRoute(_selectedPlate!),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _isLoadingHistory
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Icon(Icons.route, size: 18),
              label: Text(
                _isLoadingHistory ? 'Descargando Telemetría...' : 'Trazar Recorrido en Mapa',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),

          // ── RESUMEN TELEMÁTICO DEL RECORRIDO CARGADO ──────────────
          if (_historicalTrip != null) ...[
            const SizedBox(height: 24),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),

            // ── TARJETAS: INICIO Y TÉRMINO INTELIGENTE DE JORNADA ────
            if (_historicalTrip!.journeyStart != null) ...[
              _buildJourneyStartCard(_historicalTrip!.journeyStart!),
              const SizedBox(height: 10),
            ],
            if (_historicalTrip!.journeyEnd != null) ...[
              _buildJourneyEndCard(_historicalTrip!.journeyEnd!),
              const SizedBox(height: 14),
            ],
            if (_historicalTrip!.journeyStart != null || _historicalTrip!.journeyEnd != null) ...[
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'RESUMEN DEL RECORRIDO',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const Spacer(),
                Text(
                  '${_historicalTrip!.points.length} puntos',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Métricas: Km y Diésel
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Distancia Real', style: TextStyle(color: Colors.white54, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(
                          '${_historicalTrip!.totalDistanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Combustible Est.', style: TextStyle(color: Colors.white54, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(
                          '${(_historicalTrip!.totalDistanceKm / 2.5).toStringAsFixed(1)} Lts',
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            const SizedBox(height: 10),

            // Velocidades
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      Text('Vel. Máx: ${_historicalTrip!.maxSpeed.toStringAsFixed(0)} km/h', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                  Text('Prom: ${_historicalTrip!.avgSpeed.toStringAsFixed(0)} km/h', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── TRAMOS DEL RECORRIDO (IDA Y RETORNO) ──────────
            if (_historicalTrip!.legs.isNotEmpty) ...[
              Row(
                children: [
                  const Text('TRAMOS / RECORRIDOS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_selectedLegIndex != null)
                    InkWell(
                      onTap: () => setState(() => _selectedLegIndex = null),
                      child: const Text('Ver Todos', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ..._historicalTrip!.legs.map((leg) {
                final isSelected = _selectedLegIndex == leg.index;
                final startStr = '${leg.startTime.hour.toString().padLeft(2, '0')}:${leg.startTime.minute.toString().padLeft(2, '0')}';
                final endStr = '${leg.endTime.hour.toString().padLeft(2, '0')}:${leg.endTime.minute.toString().padLeft(2, '0')}';

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? leg.color.withValues(alpha: 0.15) : const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? leg.color : leg.color.withValues(alpha: 0.3),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    onTap: () {
                      setState(() {
                        if (_selectedLegIndex == leg.index) {
                          _selectedLegIndex = null;
                        } else {
                          _selectedLegIndex = leg.index;
                          if (leg.points.isNotEmpty) {
                            _mapController.move(leg.points[leg.points.length ~/ 2].position, 13);
                          }
                        }
                      });
                    },
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: leg.color,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: leg.color.withValues(alpha: 0.6), blurRadius: 4)],
                      ),
                    ),
                    title: Text(
                      leg.name,
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '$startStr - $endStr  •  ${leg.distanceKm.toStringAsFixed(1)} km  •  ${leg.maxSpeed.toStringAsFixed(0)} km/h máx',
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    trailing: Icon(
                      isSelected ? Icons.check_circle : Icons.visibility_outlined,
                      color: isSelected ? leg.color : Colors.white24,
                      size: 18,
                    ),
                  ),
                );
              }),
            ],

            // ── PARADAS / DETENCIONES DETECTADAS ───────────────
            if (_historicalTrip!.stops.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('PARADAS DETECTADAS (${_historicalTrip!.stops.length})', style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ..._historicalTrip!.stops.map((stop) {
                final dur = stop.durationMinutes >= 60
                    ? '${stop.durationMinutes ~/ 60}h ${stop.durationMinutes % 60}m'
                    : '${stop.durationMinutes}m';
                final hora = '${stop.startTime.hour.toString().padLeft(2, '0')}:${stop.startTime.minute.toString().padLeft(2, '0')}';

                return InkWell(
                  onTap: () => _mapController.move(stop.position, 16),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pause_circle_filled, color: Colors.amberAccent, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stop.geofenceName ?? 'Detención en Ruta ($hora)',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            dur,
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],

            // Geocercas Visitadas y Tiempos de Espera
            if (_historicalTrip!.stays.isNotEmpty) ...[
              const Text('GEOCERCAS Y TIEMPOS DE ESTADÍA', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...List.generate(_historicalTrip!.stays.length, (idx) {
                final s = _historicalTrip!.stays[idx];
                final durMin = s.durationMinutes;
                final durStr = durMin >= 60 ? '${durMin ~/ 60}h ${durMin % 60}m' : '${durMin}m';

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.geofenceName,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          durStr,
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildJourneyStartCard(GpsJourneyStart start) {
    final determinedTime = start.determinedStartTime;
    final timeStr = '${determinedTime.hour.toString().padLeft(2, '0')}:${determinedTime.minute.toString().padLeft(2, '0')}';

    // Diferencia entre primer GPS y primer movimiento
    String? delayStr;
    if (start.firstMotionTime != null) {
      final delayMin = start.firstMotionTime!.difference(start.firstGpsTime).inMinutes;
      if (delayMin > 0) {
        delayStr = '${delayMin}m entre encendido y primer mov.';
      }
    }

    final gpsTimeStr = '${start.firstGpsTime.hour.toString().padLeft(2, '0')}:${start.firstGpsTime.minute.toString().padLeft(2, '0')}';
    final motionTimeStr = start.firstMotionTime != null
        ? '${start.firstMotionTime!.hour.toString().padLeft(2, '0')}:${start.firstMotionTime!.minute.toString().padLeft(2, '0')}'
        : null;

    // Nivel de confianza de la determinación
    final String confidence;
    final Color confidenceColor;
    if (start.firstMotionTime != null && start.engineOnAtStart) {
      confidence = 'ALTA';
      confidenceColor = Colors.greenAccent;
    } else if (start.firstMotionTime != null) {
      confidence = 'MEDIA';
      confidenceColor = Colors.amberAccent;
    } else {
      confidence = 'BAJA';
      confidenceColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D2137),
            const Color(0xFF091929),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.12),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.play_circle_filled, color: Colors.blueAccent, size: 16),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'INICIO DE JORNADA',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: confidenceColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'CONF. $confidence',
                  style: TextStyle(color: confidenceColor, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Hora principal determinada
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      start.firstMotionTime != null ? 'Primer movimiento' : 'Primer dato GPS',
                      style: const TextStyle(color: Colors.white60, fontSize: 10),
                    ),
                    if (start.startGeofenceName != null)
                      Text(
                        start.startGeofenceName!,
                        style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),

          // Desglose de señales cruzadas
          _buildStartSignalRow(
            icon: Icons.gps_fixed,
            label: 'Primer GPS del día',
            value: gpsTimeStr,
            active: true,
            color: Colors.cyanAccent,
          ),
          const SizedBox(height: 6),
          _buildStartSignalRow(
            icon: Icons.directions_car,
            label: 'Primer movimiento (>3 km/h)',
            value: motionTimeStr ?? 'No detectado',
            active: motionTimeStr != null,
            color: Colors.greenAccent,
          ),
          const SizedBox(height: 6),
          _buildStartSignalRow(
            icon: Icons.power,
            label: 'Motor al inicio',
            value: start.engineOnAtStart ? 'Encendido ✓' : 'Sin datos / Apagado',
            active: start.engineOnAtStart,
            color: Colors.amberAccent,
          ),

          // Nota de demora si aplica
          if (delayStr != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white38, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    delayStr,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartSignalRow({
    required IconData icon,
    required String label,
    required String value,
    required bool active,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 12, color: active ? color : Colors.white24),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ),
        Text(
          value,
          style: TextStyle(
            color: active ? color : Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildJourneyEndCard(GpsJourneyEnd end) {
    final determinedTime = end.determinedEndTime;
    final timeStr = '${determinedTime.hour.toString().padLeft(2, '0')}:${determinedTime.minute.toString().padLeft(2, '0')}';
    final dur = end.totalDuration;
    final durStr = '${dur.inHours}h ${dur.inMinutes % 60}m';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF26122F),
            Color(0xFF190C1F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.purpleAccent.withValues(alpha: 0.12),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.stop_circle, color: Colors.purpleAccent, size: 16),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'TÉRMINO DE JORNADA',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'JORNADA $durStr',
                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Hora principal determinada
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      end.isStopped ? 'Vehículo detenido' : 'En movimiento',
                      style: const TextStyle(color: Colors.white60, fontSize: 10),
                    ),
                    if (end.endGeofenceName != null)
                      Text(
                        end.endGeofenceName!,
                        style: const TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),

          // Desglose de señales
          _buildStartSignalRow(
            icon: Icons.flag,
            label: 'Último reporte GPS',
            value: timeStr,
            active: true,
            color: Colors.purpleAccent,
          ),
          const SizedBox(height: 6),
          _buildStartSignalRow(
            icon: Icons.pause_circle_outline,
            label: 'Estado al finalizar',
            value: end.isStopped ? 'Detenido (0 km/h)' : '${end.lastSpeed.toStringAsFixed(0)} km/h',
            active: end.isStopped,
            color: Colors.greenAccent,
          ),
          const SizedBox(height: 6),
          _buildStartSignalRow(
            icon: Icons.timelapse,
            label: 'Duración total de jornada',
            value: durStr,
            active: true,
            color: Colors.amberAccent,
          ),
        ],
      ),
    );
  }

  // ─── INFRAESTRUCTURA VIAL UNIVERSAL (PEAJES, ROMANAS, RESTRICCIONES) ─────

  Marker _buildInfraestructuraMarker(PuntoInfraestructuraModel p, bool isSuperAdmin) {
    Color color = Colors.amberAccent;
    IconData icon = Icons.toll;
    String badgeText = 'Punto';

    switch (p.tipo) {
      case TipoPuntoInfraestructura.peaje:
        color = Colors.amberAccent;
        icon = Icons.toll;
        final tarifa = p.tarifaCamionPesado ?? p.tarifaCamionSimple;
        badgeText = tarifa != null ? '\$${tarifa.toStringAsFixed(0)}' : 'Peaje';
        break;
      case TipoPuntoInfraestructura.romana:
        color = Colors.cyanAccent;
        icon = Icons.scale;
        badgeText = 'Romana';
        break;
      case TipoPuntoInfraestructura.restriccion:
        color = Colors.redAccent;
        icon = Icons.warning_amber_rounded;
        badgeText = p.alturaMaximaMetros != null ? '${p.alturaMaximaMetros}m' : 'Restricción';
        break;
      case TipoPuntoInfraestructura.descanso:
        color = Colors.greenAccent;
        icon = Icons.local_gas_station;
        badgeText = 'Descanso';
        break;
    }

    return Marker(
      point: p.position,
      width: 120,
      height: 48,
      child: GestureDetector(
        onTap: () => _showPuntoInfraestructuraDialog(context, p, isSuperAdmin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color, width: 1),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 10, color: color),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      badgeText,
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
              ),
              child: Icon(
                icon,
                color: color,
                size: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPuntoInfraestructuraDialog(BuildContext context, PuntoInfraestructuraModel p, bool isSuperAdmin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                p.tipo == TipoPuntoInfraestructura.peaje
                    ? Icons.toll
                    : (p.tipo == TipoPuntoInfraestructura.romana
                        ? Icons.scale
                        : (p.tipo == TipoPuntoInfraestructura.restriccion ? Icons.warning_amber_rounded : Icons.local_gas_station)),
                color: Colors.blueAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nombre,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${p.tipo.label} • ${p.subtipo}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.ruta.isNotEmpty)
                _buildInfraDetailRow('Ruta / Autopista:', p.km != null ? '${p.ruta} (Km ${p.km})' : p.ruta),
              _buildInfraDetailRow('Sentido:', p.sentido),
              _buildInfraDetailRow('Coordenadas:', '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'),
              const Divider(color: Colors.white10, height: 16),
              if (p.tipo == TipoPuntoInfraestructura.peaje) ...[
                if (p.tarifaCamionSimple != null)
                  _buildInfraDetailRow('Tarifa Camión 2 Ejes:', '\$${p.tarifaCamionSimple!.toStringAsFixed(0)}'),
                if (p.tarifaCamionPesado != null)
                  _buildInfraDetailRow('Tarifa Camión >2 Ejes (Rampla):', '\$${p.tarifaCamionPesado!.toStringAsFixed(0)}'),
                _buildInfraDetailRow('Modalidad de Cobro:', p.admiteTag ? 'Efectivo y TAG (Free Flow)' : 'Solo Manual / Efectivo'),
                if (p.concesionaria != null)
                  _buildInfraDetailRow('Concesionaria:', p.concesionaria!),
              ] else if (p.tipo == TipoPuntoInfraestructura.romana) ...[
                _buildInfraDetailRow('Entidad:', p.entidadFiscalizadora ?? 'MOP / Vialidad'),
                _buildInfraDetailRow('Pista de Pesaje:', p.pistaObligatoria ?? 'Pista Derecha Obligatoria'),
              ] else if (p.tipo == TipoPuntoInfraestructura.restriccion) ...[
                if (p.alturaMaximaMetros != null)
                  _buildInfraDetailRow('Gálibo / Altura Máxima:', '${p.alturaMaximaMetros} metros'),
                if (p.pesoMaximoToneladas != null)
                  _buildInfraDetailRow('Peso Máximo PBV:', '${p.pesoMaximoToneladas} toneladas'),
                if (p.horarioRestriccion != null)
                  _buildInfraDetailRow('Horario Restricción:', p.horarioRestriccion!),
                _buildInfraDetailRow('Cargas Peligrosas:', p.permiteCargasPeligrosas ? 'Permitido' : 'Prohibido (Desvío obligatorio)'),
              ] else if (p.tipo == TipoPuntoInfraestructura.descanso) ...[
                if (p.capacidadCamiones != null)
                  _buildInfraDetailRow('Capacidad Estimada:', '${p.capacidadCamiones} camiones'),
                _buildInfraDetailRow('Servicios:', [
                  if (p.tieneDuchas) 'Duchas',
                  if (p.tieneSeguridad) 'Seguridad 24h',
                  if (p.combustibleAltoFlujo) 'Diésel Alto Flujo',
                ].join(', ')),
              ],
            ],
          ),
        ),
        actions: [
          if (isSuperAdmin) ...[
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text('Eliminar Punto', style: TextStyle(color: Colors.redAccent)),
                    content: Text('¿Seguro que deseas eliminar "${p.nombre}" del catálogo universal?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(infraestructuraRepositoryProvider).eliminarPunto(p.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showCrearEditarPuntoDialog(context, punto: p);
              },
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Editar'),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white60)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfraDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showCrearEditarPuntoDialog(BuildContext context, {PuntoInfraestructuraModel? punto, LatLng? initialPos}) {
    final isEditing = punto != null;
    final nombreCtrl = TextEditingController(text: punto?.nombre ?? '');
    final rutaCtrl = TextEditingController(text: punto?.ruta ?? '');
    final kmCtrl = TextEditingController(text: punto?.km?.toString() ?? '');
    final latCtrl = TextEditingController(text: punto?.lat.toString() ?? initialPos?.latitude.toStringAsFixed(6) ?? '-36.9840');
    final lngCtrl = TextEditingController(text: punto?.lng.toString() ?? initialPos?.longitude.toStringAsFixed(6) ?? '-73.1774');
    final tarifaSimpleCtrl = TextEditingController(text: punto?.tarifaCamionSimple?.toStringAsFixed(0) ?? '');
    final tarifaPesadoCtrl = TextEditingController(text: punto?.tarifaCamionPesado?.toStringAsFixed(0) ?? '');
    final concesionariaCtrl = TextEditingController(text: punto?.concesionaria ?? '');
    final entidadCtrl = TextEditingController(text: punto?.entidadFiscalizadora ?? 'MOP / Vialidad');
    final alturaCtrl = TextEditingController(text: punto?.alturaMaximaMetros?.toString() ?? '');
    final pesoCtrl = TextEditingController(text: punto?.pesoMaximoToneladas?.toString() ?? '');
    final horarioCtrl = TextEditingController(text: punto?.horarioRestriccion ?? '');

    TipoPuntoInfraestructura tipo = punto?.tipo ?? TipoPuntoInfraestructura.peaje;
    String subtipo = punto?.subtipo ?? (tipo == TipoPuntoInfraestructura.peaje ? 'Troncal' : 'General');
    String sentido = punto?.sentido ?? 'Bidireccional';
    bool admiteTag = punto?.admiteTag ?? false;
    bool permiteHazmat = punto?.permiteCargasPeligrosas ?? true;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 520,
            constraints: const BoxConstraints(maxHeight: 720),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_location_alt, color: Color(0xFF00E676), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Editar Punto Vial' : 'Registrar Nuevo Punto Vial',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Catálogo Universal de Infraestructura (TMS)',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Tipo de Punto
                        DropdownButtonFormField<TipoPuntoInfraestructura>(
                          initialValue: tipo,
                          dropdownColor: const Color(0xFF161B22),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(labelText: 'Tipo de Infraestructura', labelStyle: TextStyle(color: Colors.grey)),
                          items: TipoPuntoInfraestructura.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                tipo = val;
                                if (tipo == TipoPuntoInfraestructura.peaje) subtipo = 'Troncal';
                                if (tipo == TipoPuntoInfraestructura.romana) subtipo = 'Pesaje Fijo';
                                if (tipo == TipoPuntoInfraestructura.restriccion) subtipo = 'Paso Bajo Nivel';
                                if (tipo == TipoPuntoInfraestructura.descanso) subtipo = 'Servicentro';
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nombreCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Nombre del Punto (ej: Peaje Agua Amarilla)', labelStyle: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: rutaCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(labelText: 'Ruta / Autopista (ej: Ruta 148)', labelStyle: TextStyle(color: Colors.grey)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: kmCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(labelText: 'Km (ej: 52.4)', labelStyle: TextStyle(color: Colors.grey)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: latCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(labelText: 'Latitud GPS', labelStyle: TextStyle(color: Colors.grey)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: lngCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(labelText: 'Longitud GPS', labelStyle: TextStyle(color: Colors.grey)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: sentido,
                          dropdownColor: const Color(0xFF161B22),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(labelText: 'Sentido de Calzada', labelStyle: TextStyle(color: Colors.grey)),
                          items: ['Bidireccional', 'Norte-Sur', 'Sur-Norte', 'Oriente-Poniente', 'Poniente-Oriente']
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (val) => setDialogState(() => sentido = val ?? 'Bidireccional'),
                        ),
                        const SizedBox(height: 14),

                        // ── Campos según Tipo ──
                        if (tipo == TipoPuntoInfraestructura.peaje) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Tarifas de Peaje (CLP)', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: tarifaSimpleCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(labelText: 'Camión 2 Ejes (\$)', labelStyle: TextStyle(color: Colors.grey)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: tarifaPesadoCtrl,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(labelText: 'Camión >2 Ejes (\$)', labelStyle: TextStyle(color: Colors.grey)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Admite TAG / Free Flow:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    Switch(
                                      value: admiteTag,
                                      activeThumbColor: Colors.amberAccent,
                                      onChanged: (val) => setDialogState(() => admiteTag = val),
                                    ),
                                  ],
                                ),
                                TextField(
                                  controller: concesionariaCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: const InputDecoration(labelText: 'Concesionaria (ej: Autopista del Itata)', labelStyle: TextStyle(color: Colors.grey)),
                                ),
                              ],
                            ),
                          ),
                        ] else if (tipo == TipoPuntoInfraestructura.romana) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.cyan.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.cyan.withValues(alpha: 0.25)),
                            ),
                            child: Column(
                              children: [
                                TextField(
                                  controller: entidadCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: const InputDecoration(labelText: 'Entidad (ej: MOP / Vialidad)', labelStyle: TextStyle(color: Colors.grey)),
                                ),
                              ],
                            ),
                          ),
                        ] else if (tipo == TipoPuntoInfraestructura.restriccion) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Límites y Restricciones', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: alturaCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(labelText: 'Altura Máx (m)', labelStyle: TextStyle(color: Colors.grey)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: pesoCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(labelText: 'Peso Máx (ton)', labelStyle: TextStyle(color: Colors.grey)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: horarioCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: const InputDecoration(labelText: 'Horario Restringido (ej: 07:00 a 09:00 hrs)', labelStyle: TextStyle(color: Colors.grey)),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Permite Cargas Peligrosas (HAZMAT):', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    Switch(
                                      value: permiteHazmat,
                                      activeThumbColor: Colors.redAccent,
                                      onChanged: (val) => setDialogState(() => permiteHazmat = val),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: isSaving ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final name = nombreCtrl.text.trim();
                              final lat = double.tryParse(latCtrl.text.trim());
                              final lng = double.tryParse(lngCtrl.text.trim());
                              if (name.isEmpty || lat == null || lng == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Por favor completa nombre y coordenadas válidas')),
                                );
                                return;
                              }

                              setDialogState(() => isSaving = true);
                              try {
                                final userProfile = ref.read(currentUserProfileProvider).value;
                                final model = PuntoInfraestructuraModel(
                                  id: punto?.id ?? '',
                                  nombre: name,
                                  tipo: tipo,
                                  subtipo: subtipo,
                                  ruta: rutaCtrl.text.trim(),
                                  km: double.tryParse(kmCtrl.text.trim()),
                                  lat: lat,
                                  lng: lng,
                                  sentido: sentido,
                                  tarifaCamionSimple: double.tryParse(tarifaSimpleCtrl.text.trim()),
                                  tarifaCamionPesado: double.tryParse(tarifaPesadoCtrl.text.trim()),
                                  admiteTag: admiteTag,
                                  concesionaria: concesionariaCtrl.text.trim().isNotEmpty ? concesionariaCtrl.text.trim() : null,
                                  entidadFiscalizadora: entidadCtrl.text.trim().isNotEmpty ? entidadCtrl.text.trim() : null,
                                  alturaMaximaMetros: double.tryParse(alturaCtrl.text.trim()),
                                  pesoMaximoToneladas: double.tryParse(pesoCtrl.text.trim()),
                                  horarioRestriccion: horarioCtrl.text.trim().isNotEmpty ? horarioCtrl.text.trim() : null,
                                  permiteCargasPeligrosas: permiteHazmat,
                                  creadoPor: userProfile?.uid ?? 'MAESTRO',
                                  createdAt: punto?.createdAt ?? DateTime.now(),
                                );

                                await ref.read(infraestructuraRepositoryProvider).guardarPunto(model);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('✓ Punto "${model.nombre}" guardado en el Catálogo Universal'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setDialogState(() => isSaving = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                      icon: isSaving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Icon(Icons.check, size: 16),
                      label: Text(isSaving ? 'Guardando...' : (isEditing ? 'Actualizar Punto' : 'Guardar Punto')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
