import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../domain/services/cabin_routing_service.dart';
import '../../domain/services/cabin_voice_service.dart';
import '../../domain/services/route_intelligence_service.dart';

/// Hito/parada dentro del recorrido en cabina.
class CabinWaypoint {
  final String name;
  final ll.LatLng position;
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

/// Pantalla de Navegador GPS Integrado en Cabina con MapLibre 3D.
class CabinNavigatorScreen extends StatefulWidget {
  final String tripId;
  final String originName;
  final String clientName;
  final String destinationName;
  final List<CabinWaypoint> waypoints;
  final List<ll.LatLng>? activeRoutePoints;
  final List<ll.LatLng>? futureRoutePoints;
  final String initialStatusLabel;
  final VoidCallback? onAdvanceMilestone;
  final VoidCallback? onOpenDetails;

  const CabinNavigatorScreen({
    super.key,
    required this.tripId,
    required this.originName,
    this.clientName = '',
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
  static const String _darkStyleUrl = 'https://tiles.openfreemap.org/styles/dark';

  MapLibreMapController? _mapController;
  final TextEditingController _altSearchController = TextEditingController();
  final CabinRoutingService _routingService = CabinRoutingService();
  final CabinVoiceService _voiceService = CabinVoiceService();
  final RouteIntelligenceService _intelligenceService = RouteIntelligenceService();

  StreamSubscription<Position>? _posSub;
  ll.LatLng _truckPosition = const ll.LatLng(-36.82699, -73.04977);
  double _truckHeading = 0.0;
  bool _followTruck = true;
  bool _isMuted = false;
  bool _isLoadingRoute = false;
  bool _styleLoaded = false;
  int _currentWaypointIndex = 0;

  late List<CabinWaypoint> _waypoints;
  List<ll.LatLng> _activeRoutePoints = [];
  List<ll.LatLng> _futureRoutePoints = [];
  List<RouteIncidentMarker> _activeIncidents = [];

  String _maneuverText = 'Calculando ruta...';
  String _routeSummaryText = '';
  bool _isOfficialRoute = false;

  @override
  void initState() {
    super.initState();
    _waypoints = List<CabinWaypoint>.from(widget.waypoints);
    _activeRoutePoints = List<ll.LatLng>.from(widget.activeRoutePoints ?? const []);
    _futureRoutePoints = List<ll.LatLng>.from(widget.futureRoutePoints ?? const []);
    if (_waypoints.isNotEmpty) {
      _truckPosition = _waypoints.first.position;
    }
    _initLocationAndRoute();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _altSearchController.dispose();
    _voiceService.stop();
    super.dispose();
  }

  LatLng _toMl(ll.LatLng p) => LatLng(p.latitude, p.longitude);

  Future<void> _initLocationAndRoute() async {
    await _startGpsStream();
    _loadActiveIncidents();
    if (_activeRoutePoints.isEmpty) {
      await _autoBuildTripRoute();
    }
  }

  Future<void> _loadActiveIncidents() async {
    final incidents = await _routingService.fetchActiveIncidents();
    if (!mounted) return;
    setState(() => _activeIncidents = incidents);
    _redrawMapLayers();
  }

  Future<void> _startGpsStream() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _truckPosition = ll.LatLng(current.latitude, current.longitude);
        });
        if (_followTruck) _moveCameraToTruck();
      }
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((pos) {
        if (!mounted) return;
        setState(() {
          _truckPosition = ll.LatLng(pos.latitude, pos.longitude);
          _truckHeading = pos.heading;
        });
        if (_followTruck) _moveCameraToTruck();
      });
    } catch (_) {}
  }

  void _moveCameraToTruck() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toMl(_truckPosition),
          zoom: 15.2,
          tilt: 52.0,
          bearing: _truckHeading,
        ),
      ),
    );
  }

  Future<void> _redrawMapLayers() async {
    final ctrl = _mapController;
    if (ctrl == null || !_styleLoaded) return;

    await ctrl.clearLines();
    await ctrl.clearCircles();

    // T2: Tramo Futuro (Cian Neón)
    if (_futureRoutePoints.length >= 2) {
      final pts = _futureRoutePoints.map(_toMl).toList();
      await ctrl.addLine(LineOptions(
        geometry: pts,
        lineColor: '#00E5FF',
        lineWidth: 11.0,
        lineOpacity: 0.25,
      ));
      await ctrl.addLine(LineOptions(
        geometry: pts,
        lineColor: '#00E5FF',
        lineWidth: 4.5,
        lineOpacity: 0.95,
      ));
    }

    // T1: Tramo Activo (Ámbar Neón)
    if (_activeRoutePoints.length >= 2) {
      final pts = _activeRoutePoints.map(_toMl).toList();
      await ctrl.addLine(LineOptions(
        geometry: pts,
        lineColor: '#FF9800',
        lineWidth: 13.0,
        lineOpacity: 0.28,
      ));
      await ctrl.addLine(LineOptions(
        geometry: pts,
        lineColor: '#FF9800',
        lineWidth: 5.5,
        lineOpacity: 1.0,
      ));
    }

    // Marcadores de hitos
    for (int i = 0; i < _waypoints.length; i++) {
      await ctrl.addCircle(CircleOptions(
        geometry: _toMl(_waypoints[i].position),
        circleRadius: 8,
        circleColor: i == _currentWaypointIndex ? '#FF9800' : '#EF4444',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ));
    }

    // Marcadores de incidencias globales
    for (final inc in _activeIncidents) {
      await ctrl.addCircle(CircleOptions(
        geometry: _toMl(inc.position),
        circleRadius: 9,
        circleColor: '#F97316',
        circleStrokeColor: '#FEF08A',
        circleStrokeWidth: 2.5,
      ));
    }
  }

  /// Resuelve Cliente (primer destino) y Destino Final, y traza la ruta real.
  Future<void> _autoBuildTripRoute() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRoute = true;
      _maneuverText = 'Buscando ruta...';
    });

    final statusLower = widget.initialStatusLabel.toLowerCase();
    final alreadyPassedClient = statusLower.contains('destino') ||
        statusLower.contains('descarga') ||
        statusLower.contains('retorno');

    final hasClient = widget.clientName.trim().isNotEmpty &&
        widget.clientName.trim().toUpperCase() != widget.destinationName.trim().toUpperCase();

    final targets = <String>[];
    if (hasClient && !alreadyPassedClient) {
      targets.add(widget.clientName.trim());
    }
    if (widget.destinationName.trim().isNotEmpty) {
      targets.add(widget.destinationName.trim());
    }

    final resolvedWaypoints = <CabinWaypoint>[];
    for (final t in targets) {
      final pos = await _routingService.geocodePlace(t);
      if (pos != null) {
        resolvedWaypoints.add(CabinWaypoint(name: t, position: pos));
      } else if (hasClient && !alreadyPassedClient && t == widget.clientName.trim()) {
        if (!mounted) return;
        setState(() {
          _isLoadingRoute = false;
          _maneuverText = 'Falta ubicación de cliente: "$t"';
        });
        return;
      }
    }

    if (!mounted) return;
    if (resolvedWaypoints.isEmpty) {
      setState(() {
        _isLoadingRoute = false;
        _maneuverText = 'Sin coordenadas para "${targets.isNotEmpty ? targets.first : 'destino'}"';
      });
      return;
    }

    setState(() {
      _waypoints = resolvedWaypoints;
      _currentWaypointIndex = 0;
    });

    final firstTarget = resolvedWaypoints.first;
    final route = await _routingService.fetchRoute(
      originName: widget.originName,
      destinationName: firstTarget.name,
      origin: _truckPosition,
      destination: firstTarget.position,
    );

    List<ll.LatLng> futurePts = [];
    if (resolvedWaypoints.length > 1) {
      final secondRoute = await _routingService.fetchRoute(
        originName: firstTarget.name,
        destinationName: resolvedWaypoints[1].name,
        origin: firstTarget.position,
        destination: resolvedWaypoints[1].position,
      );
      if (secondRoute != null) {
        futurePts = secondRoute.points;
      }
    }

    if (!mounted) return;
    if (route != null && route.points.isNotEmpty) {
      final intel = await _intelligenceService.evaluateRouteAsync(
        originName: widget.originName,
        destinationName: firstTarget.name,
        distanceKm: route.totalDistanceKm,
        routePoints: route.points,
      );
      if (!mounted) return;
      final firstStep = route.steps.isNotEmpty ? route.steps.first.instruction : 'Sigue la ruta hacia ${firstTarget.name}';
      setState(() {
        _activeRoutePoints = route.points;
        _futureRoutePoints = futurePts;
        _isOfficialRoute = route.isOfficial;
        _maneuverText = firstStep;
        _routeSummaryText =
            '${route.totalDistanceKm.toStringAsFixed(1)} km · ~${intel.estimatedTruckMinutes.round()} min · ${intel.summaryReason}';
        _isLoadingRoute = false;
      });
      await _redrawMapLayers();
      _moveCameraToTruck();
      await _voiceService.speak('Iniciando ruta hacia ${firstTarget.name}. $firstStep');
    } else {
      setState(() {
        _isLoadingRoute = false;
        _maneuverText = 'No se pudo calcular la ruta';
      });
    }
  }

  Future<void> _searchAlternativeRoute(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _isLoadingRoute = true;
      _maneuverText = 'Buscando "$q"...';
    });
    final pos = await _routingService.geocodePlace(q);
    if (pos == null) {
      if (!mounted) return;
      setState(() => _isLoadingRoute = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró "$q" en el mapa')),
      );
      return;
    }

    final route = await _routingService.fetchRoute(
      originName: 'Posición actual',
      destinationName: q,
      origin: _truckPosition,
      destination: pos,
    );
    if (!mounted) return;
    if (route != null && route.points.isNotEmpty) {
      setState(() {
        _waypoints = [CabinWaypoint(name: q, position: pos)];
        _currentWaypointIndex = 0;
        _activeRoutePoints = route.points;
        _futureRoutePoints = [];
        _isOfficialRoute = route.isOfficial;
        _maneuverText = route.steps.isNotEmpty ? route.steps.first.instruction : 'Ruta hacia $q';
        _routeSummaryText = '${route.totalDistanceKm.toStringAsFixed(1)} km · ${route.durationMinutes.round()} min';
        _isLoadingRoute = false;
      });
      await _redrawMapLayers();
      _fitOverview();
      await _voiceService.speak('Ruta alternativa cargada hacia $q');
    } else {
      setState(() => _isLoadingRoute = false);
    }
  }

  void _showSavedRoutesSheet() async {
    final routes = await _routingService.listOfficialRoutes();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161A22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rutas Oficiales Guardadas',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (routes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Aún no hay rutas oficiales guardadas.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: routes.length,
                    separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) {
                      final r = routes[i];
                      final origin = r['originName']?.toString() ?? 'Origen';
                      final client = r['clientName']?.toString() ?? '';
                      final dest = r['destinationName']?.toString() ?? 'Destino';
                      final km = (r['distanceKm'] as num?)?.toDouble() ?? 0;
                      final count = (r['tripCount'] as int?) ?? 1;
                      final title = client.isNotEmpty ? '$origin → $client → $dest' : '$origin → $dest';
                      return ListTile(
                        leading: const Icon(Icons.verified, color: Color(0xFF4ADE80)),
                        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text('${km.toStringAsFixed(1)} km · $count viajes', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final rawPts = (r['points'] as List?) ?? [];
                            final pts = rawPts
                                .whereType<Map>()
                                .map((p) => ll.LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
                                .toList();
                            if (pts.length >= 2) {
                              setState(() {
                                _activeRoutePoints = pts;
                                _futureRoutePoints = [];
                                _isOfficialRoute = true;
                                _maneuverText = 'Ruta oficial: $dest';
                                _routeSummaryText = '${km.toStringAsFixed(1)} km';
                                _waypoints = [CabinWaypoint(name: dest, position: pts.last)];
                                _currentWaypointIndex = 0;
                              });
                              await _redrawMapLayers();
                              _fitOverview();
                            }
                          },
                          child: const Text('Cargar'),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _centerOnTruck() {
    setState(() => _followTruck = true);
    _moveCameraToTruck();
  }

  void _fitOverview() {
    setState(() => _followTruck = false);
    final allPts = <ll.LatLng>[
      _truckPosition,
      ..._waypoints.map((w) => w.position),
      ..._activeRoutePoints,
      ..._futureRoutePoints,
    ];
    if (allPts.length < 2) {
      _moveCameraToTruck();
      return;
    }
    double minLat = allPts.first.latitude, maxLat = allPts.first.latitude;
    double minLng = allPts.first.longitude, maxLng = allPts.first.longitude;
    for (final p in allPts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        left: 48,
        top: 160,
        right: 72,
        bottom: 240,
      ),
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _voiceService.isMuted = _isMuted;
    });
    if (_isMuted) _voiceService.stop();
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
      onPressed: () async {
        Navigator.pop(ctx);
        await _routingService.reportIncident(
          tripId: widget.tripId,
          type: label,
          position: _truckPosition,
        );
        if (!mounted) return;
        setState(() {
          _activeIncidents = [
            ..._activeIncidents,
            RouteIncidentMarker(type: label, position: _truckPosition, createdAt: DateTime.now()),
          ];
        });
        await _redrawMapLayers();
        if (!mounted) return;
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
      _redrawMapLayers();
    }
    widget.onAdvanceMilestone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final currentTarget = _waypoints.isNotEmpty
        ? _waypoints[_currentWaypointIndex].name
        : (widget.clientName.isNotEmpty ? widget.clientName : widget.destinationName);

    return Scaffold(
      backgroundColor: const Color(0xFF0E131B),
      body: Stack(
        children: [
          // 1. Mapa Vectorial 3D MapLibre
          MapLibreMap(
            styleString: _darkStyleUrl,
            initialCameraPosition: CameraPosition(
              target: _toMl(_truckPosition),
              zoom: 15.0,
              tilt: 52.0,
              bearing: _truckHeading,
            ),
            myLocationEnabled: false,
            compassEnabled: false,
            onMapCreated: (ctrl) => _mapController = ctrl,
            onStyleLoadedCallback: () {
              _styleLoaded = true;
              _redrawMapLayers();
            },
          ),

          // Camión top-down realista centrado en modo seguimiento 3D
          if (_followTruck)
            IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 110),
                  child: CustomPaint(
                    size: const Size(34, 62),
                    painter: _TruckTopDownPainter(),
                  ),
                ),
              ),
            ),

          // 2. Barra Superior Flotante + Misión Segmentada (T1 / T2)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141B26).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
                        ),
                        const SizedBox(width: 4),
                        _isLoadingRoute
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.amber),
                              )
                            : const Icon(Icons.turn_right, color: Color(0xFF4ADE80), size: 30),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _maneuverText,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _routeSummaryText.isNotEmpty ? _routeSummaryText : currentTarget,
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 115,
                          height: 34,
                          child: TextField(
                            controller: _altSearchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: _searchAlternativeRoute,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Buscar...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                              prefixIcon: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.search, color: Colors.white70, size: 16),
                                onPressed: () => _searchAlternativeRoute(_altSearchController.text),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF1E2634),
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
                  const SizedBox(height: 8),
                  // Misión Segmentada T1: Vacío -> T2: Cargado
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141B26).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF132A2E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF2DD4BF).withValues(alpha: 0.6)),
                            ),
                            child: Text(
                              'T1: Vacío (${widget.clientName.isNotEmpty ? widget.clientName : currentTarget})',
                              style: const TextStyle(color: Color(0xFF5EEAD4), fontSize: 11, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2430),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Text(
                              'T2: Cargado (${widget.destinationName})',
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
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

          // 3. Botones Laterales Derechos (Estilo Píldora)
          Positioned(
            right: 12,
            bottom: 225,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _sideFab(Icons.my_location, _followTruck ? Colors.amber : Colors.white, _centerOnTruck, 'Centrar'),
                const SizedBox(height: 8),
                _pillButton(Icons.explore_outlined, 'ver ruta\ncompleta', Colors.cyanAccent, _fitOverview),
                const SizedBox(height: 8),
                _pillButton(Icons.route, 'Rutas\nOficiales', Colors.greenAccent, _showSavedRoutesSheet),
                const SizedBox(height: 8),
                _sideFab(
                  _isMuted ? Icons.volume_off : Icons.volume_up,
                  _isMuted ? Colors.redAccent : Colors.white,
                  _toggleMute,
                  _isMuted ? 'Silenciado' : 'Audio',
                ),
                const SizedBox(height: 8),
                _pillButton(Icons.warning_amber_rounded, 'Incidencia', Colors.redAccent, _showIncidentSheet),
              ],
            ),
          ),

          // 4. Bottom Sheet Deslizable (Control del Viaje)
          DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.18,
            maxChildSize: 0.45,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF141B26),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(widget.originName, style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.bold)),
                        const Icon(Icons.arrow_forward, color: Colors.white38, size: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFF9800)),
                          ),
                          child: Text(
                            currentTarget,
                            style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Icon(Icons.arrow_forward, color: Colors.white38, size: 14),
                        Text(widget.destinationName, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hito: ${widget.initialStatusLabel} - Camino a $currentTarget',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_isOfficialRoute)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text('Ruta Oficial Homologada', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _advanceWaypoint,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.fast_forward, size: 18),
                            label: const Text('AVANZAR HITO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: widget.onOpenDetails ?? () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Detalles', style: TextStyle(fontSize: 12)),
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
        color: const Color(0xFF141B26).withValues(alpha: 0.92),
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

  Widget _pillButton(IconData icon, String label, Color accent, VoidCallback onTap) {
    return Material(
      color: const Color(0xFF141B26).withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.1, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dibuja un tractocamión con rampla visto desde arriba para el modo 3D.
class _TruckTopDownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sombra suave
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, 4, w - 4, h - 4), const Radius.circular(6)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // Cabina (parte delantera)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, 2, w - 8, h * 0.28), const Radius.circular(5)),
      Paint()..color = const Color(0xFF64748B),
    );
    // Parabrisas
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(6, 5, w - 12, h * 0.09), const Radius.circular(2)),
      Paint()..color = const Color(0xFF0F172A),
    );

    // Rampla / Semirremolque
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(3, h * 0.32, w - 6, h * 0.62), const Radius.circular(4)),
      Paint()..color = const Color(0xFF94A3B8),
    );

    // Luces traseras rojas
    final tailPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawRect(Rect.fromLTWH(5, h * 0.92, 6, 3), tailPaint);
    canvas.drawRect(Rect.fromLTWH(w - 11, h * 0.92, 6, 3), tailPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
