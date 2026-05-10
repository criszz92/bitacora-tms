import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

// ── MODELO ──────────────────────────────────────────────────────────────────

class GpsUnit {
  final String id;
  final String plate;
  final String driverName;
  final LatLng position;
  final double speed;
  final String status; // 'moving', 'idle', 'stopped'
  final DateTime lastUpdate;

  GpsUnit({
    required this.id,
    required this.plate,
    required this.driverName,
    required this.position,
    required this.speed,
    required this.status,
    required this.lastUpdate,
  });
}

// ── SERVICE (MOCK) ──────────────────────────────────────────────────────────

class GpsService {
  // Aquí integraremos la API de liot.cl luego
  Future<List<GpsUnit>> fetchUnits() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      GpsUnit(
        id: '1',
        plate: 'ABCD-12',
        driverName: 'Juan Pérez',
        position: const LatLng(-36.8270, -73.0503), // Concepción
        speed: 85.0,
        status: 'moving',
        lastUpdate: DateTime.now(),
      ),
      GpsUnit(
        id: '2',
        plate: 'WXYZ-34',
        driverName: 'Pedro Soto',
        position: const LatLng(-36.7200, -73.1200), // Talcahuano
        speed: 0.0,
        status: 'stopped',
        lastUpdate: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ];
  }
}

final gpsServiceProvider = Provider((ref) => GpsService());

final fleetStreamProvider = StreamProvider<List<GpsUnit>>((ref) async* {
  final service = ref.read(gpsServiceProvider);
  while (true) {
    yield await service.fetchUnits();
    await Future.delayed(const Duration(seconds: 10)); // Simular tiempo real
  }
});

// ── VIEW ────────────────────────────────────────────────────────────────────

class ControlTowerView extends ConsumerStatefulWidget {
  const ControlTowerView({super.key});

  @override
  ConsumerState<ControlTowerView> createState() => _ControlTowerViewState();
}

class _ControlTowerViewState extends ConsumerState<ControlTowerView> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final fleetAsync = ref.watch(fleetStreamProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // Mapa
          Expanded(
            flex: 7,
            child: fleetAsync.when(
              data: (units) => FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: units.isNotEmpty ? units.first.position : const LatLng(-36.8270, -73.0503),
                  initialZoom: 12,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                  ),
                  MarkerLayer(
                    markers: units.map((unit) => Marker(
                      point: unit.position,
                      width: 40,
                      height: 40,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(unit.plate, style: const TextStyle(color: Colors.white, fontSize: 8)),
                          ),
                          Icon(
                            Icons.local_shipping,
                            color: unit.status == 'moving' ? Colors.greenAccent : (unit.status == 'idle' ? Colors.orange : Colors.redAccent),
                            size: 24,
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
            ),
          ),

          // Panel Lateral
          Container(
            width: 350,
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Torre de Control', 
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: fleetAsync.when(
                    data: (units) => ListView.builder(
                      itemCount: units.length,
                      itemBuilder: (context, index) {
                        final unit = units[index];
                        return _buildUnitCard(unit);
                      },
                    ),
                    loading: () => const SizedBox(),
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
    Color statusColor = unit.status == 'moving' ? Colors.greenAccent : (unit.status == 'idle' ? Colors.orange : Colors.redAccent);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: () => _mapController.move(unit.position, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(unit.plate, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const Spacer(),
                Text(unit.status == 'moving' ? '${unit.speed} km/h' : 'Detenido', 
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text(unit.driverName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.white24, size: 12),
                const SizedBox(width: 4),
                Text('Hace ${DateTime.now().difference(unit.lastUpdate).inMinutes} min', 
                  style: const TextStyle(color: Colors.white24, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
