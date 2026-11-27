import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Hito/parada dentro del recorrido en cabina.
class CabinWaypoint {
  final String name;
  final LatLng position;
  final bool completed;

  const CabinWaypoint({
    required this.name,
    required this.position,
    this.completed = false,
  });

  CabinWaypoint copyWith({bool? completed}) => CabinWaypoint(
        name: name,
        position: position,
        completed: completed ?? this.completed,
      );
}

/// Pantalla de Navegador GPS Integrado en Cabina (Modo Nocturno OLED).
class CabinNavigatorScreen extends StatefulWidget {
  final String tripId;
  final String originName;
  final String destinationName;
  final List<CabinWaypoint> waypoints;
  final List<LatLng>? activeRoutePoints;
  final List<LatLng>? futureRoutePoints;
  final String initialStatusLabel;
  final VoidCallback? onAdvanceMilestone;
  final VoidCallback? onOpenDetails;

  const CabinNavigatorScreen({
    super.key,
    required this.tripId,
    required this.originName,
    required this.destinationName,
    required this.waypoints,
    this.activeRoutePoints,
    this.futureRoutePoints,
    this.initialStatusLabel = 'En Tránsito',
    this.onAdvanceMilestone,
    this.onOpenDetails,
  });

  @override
  State<CabinNavigatorScreen> createState() => _CabinNavigatorScreenState();
}

class _CabinNavigatorScreenState extends State<CabinNavigatorScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _altSearchController = TextEditingController();

  StreamSubscription<Position>? _posSub;
  LatLng _truckPosition = const LatLng(-36.82699, -73.04977);
  double _truckHeading = 0.0;
  bool _followTruck = true;
  bool _isMuted = false;
  int _currentWaypointIndex = 0;
  late List<CabinWaypoint> _waypoints;
  final List<LatLng> _traveledPoints = [];

  @override
  void initState() {
    super.initState();
    _waypoints = List<CabinWaypoint>.from(widget.waypoints);
    if (_waypoints.isNotEmpty) {
      _truckPosition = _waypoints.first.position;
    }
    _startGpsStream();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _altSearchController.dispose();
    super.dispose();
  }

  Future<void> _startGpsStream() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((pos) {
        if (!mounted) return;
        final next = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _truckPosition = next;
          _truckHeading = pos.heading;
          _traveledPoints.add(next);
        });
        if (_followTruck) {
          _mapController.move(next, _mapController.camera.zoom);
        }
      });
    } catch (_) {
      // Fallback silencioso si GPS no está disponible en Web/emulador
    }
  }

  void _centerOnTruck() {
    setState(() => _followTruck = true);
    _mapController.move(_truckPosition, 14.5);
  }

  void _fitOverview() {
    setState(() => _followTruck = false);
    final allPts = <LatLng>[
      _truckPosition,
      ..._waypoints.map((w) => w.position),
      ...(widget.activeRoutePoints ?? const []),
      ...(widget.futureRoutePoints ?? const []),
    ];
    if (allPts.length < 2) {
      _mapController.move(_truckPosition, 12);
      return;
    }
    final bounds = LatLngBounds.fromPoints(allPts);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(48, 140, 72, 230)),
    );
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isMuted ? 'Audio de navegación silenciado' : 'Voz y alertas activadas'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showIncidentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161A22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reportar Incidencia en Ruta',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _incidentChip(ctx, 'Taco / Accidente', Icons.car_crash, Colors.redAccent),
                  _incidentChip(ctx, 'Carabineros / Pesaje', Icons.local_police, Colors.amber),
                  _incidentChip(ctx, 'Corte / Obra Vial', Icons.construction, Colors.orangeAccent),
                  _incidentChip(ctx, 'Falla Mecánica', Icons.build_circle, Colors.purpleAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incidentChip(BuildContext ctx, String label, IconData icon, Color color) {
    return ActionChip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: const Color(0xFF1E2430),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      onPressed: () {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incidencia reportada: $label'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      },
    );
  }

  void _advanceWaypoint() {
    if (_currentWaypointIndex < _waypoints.length - 1) {
      setState(() {
        _waypoints[_currentWaypointIndex] = _waypoints[_currentWaypointIndex].copyWith(completed: true);
        _currentWaypointIndex++;
      });
    }
    widget.onAdvanceMilestone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final currentTarget = _waypoints.isNotEmpty ? _waypoints[_currentWaypointIndex].name : widget.destinationName;

    return Scaffold(
      backgroundColor: const Color(0xFF121417),
      body: Stack(
        children: [
          // 1. Mapa en Modo Nocturno
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _truckPosition,
              initialZoom: 13.5,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _followTruck) {
                  setState(() => _followTruck = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'cl.heirlog.bitacora',
                tileBuilder: (context, tileWidget, tile) {
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      -0.85, 0, 0, 0, 235,
                      0, -0.85, 0, 0, 235,
                      0, 0, -0.85, 0, 240,
                      0, 0, 0, 1, 0,
                    ]),
                    child: tileWidget,
                  );
                },
              ),
              PolylineLayer(
                polylines: [
                  if (_traveledPoints.length >= 2)
                    Polyline(
                      points: _traveledPoints,
                      color: const Color(0xFF546E7A),
                      strokeWidth: 4,
                    ),
                  if ((widget.futureRoutePoints ?? const []).length >= 2)
                    Polyline(
                      points: widget.futureRoutePoints!,
                      color: const Color(0xFF00E5FF),
                      strokeWidth: 5,
                    ),
                  if ((widget.activeRoutePoints ?? const []).length >= 2)
                    Polyline(
                      points: widget.activeRoutePoints!,
                      color: const Color(0xFFFF9800),
                      strokeWidth: 6,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (int i = 0; i < _waypoints.length; i++)
                    Marker(
                      point: _waypoints[i].position,
                      width: 170,
                      height: 54,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161A22).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: i == _currentWaypointIndex ? const Color(0xFFFF9800) : Colors.white24,
                              ),
                            ),
                            child: Text(
                              '${i + 1} - ${_waypoints[i].name}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: i == _currentWaypointIndex ? const Color(0xFFFF9800) : const Color(0xFF00E5FF),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  Marker(
                    point: _truckPosition,
                    width: 44,
                    height: 44,
                    child: Transform.rotate(
                      angle: _truckHeading * 3.14159265 / 180,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFF9800), width: 2),
                        ),
                        child: const Icon(Icons.local_shipping, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Barra Superior Flotante (Maniobras + Buscador)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF161A22).withValues(alpha: 0.9)),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161A22).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Color(0xFF4ADE80), size: 8),
                            SizedBox(width: 6),
                            Text('Bitácora Conductor', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A22).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.turn_right, color: Colors.white, size: 32),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'En ruta',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                currentTarget,
                                style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 140,
                          height: 36,
                          child: TextField(
                            controller: _altSearchController,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Ruta alternativa...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                              prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                              filled: true,
                              fillColor: const Color(0xFF1E2430),
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Botones Laterales Derechos
          Positioned(
            right: 12,
            bottom: 225,
            child: Column(
              children: [
                _sideFab(Icons.my_location, _followTruck ? Colors.amber : Colors.white, _centerOnTruck, 'Centrar'),
                const SizedBox(height: 10),
                _sideFab(Icons.zoom_out_map, Colors.white, _fitOverview, 'Vista Global'),
                const SizedBox(height: 10),
                _sideFab(
                  _isMuted ? Icons.volume_off : Icons.volume_up,
                  _isMuted ? Colors.redAccent : Colors.white,
                  _toggleMute,
                  _isMuted ? 'Silenciado' : 'Audio',
                ),
                const SizedBox(height: 10),
                _sideFab(Icons.warning_amber_rounded, Colors.orangeAccent, _showIncidentSheet, 'Incidencia'),
              ],
            ),
          ),

          // 4. Bottom Sheet Deslizable (Control del Viaje)
          DraggableScrollableSheet(
            initialChildSize: 0.24,
            minChildSize: 0.18,
            maxChildSize: 0.45,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF161A22),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Text('INICIO', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                          for (int i = 0; i < _waypoints.length; i++) ...[
                            Container(width: 24, height: 2, color: i <= _currentWaypointIndex ? const Color(0xFFFF9800) : Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 6)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: i == _currentWaypointIndex ? const Color(0xFFFF9800) : const Color(0xFF1E2430),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${i + 1} (${_waypoints[i].name})',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          Container(width: 24, height: 2, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 6)),
                          const Text('DESTINO', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hito: ${widget.initialStatusLabel} - Camino a $currentTarget',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _advanceWaypoint,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.fast_forward, size: 18),
                            label: const Text('Avanzar Hito', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: widget.onOpenDetails ?? () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Detalles'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sideFab(IconData icon, Color color, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF161A22).withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}

