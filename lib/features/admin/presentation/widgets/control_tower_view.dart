import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';

// ── MODELO ──────────────────────────────────────────────────────────────────

class GpsUnit {
  final String id;
  final String plate;
  final String driverName;
  final LatLng position;
  final double speed;
  final String status; // 'online', 'offline', 'unknown'
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

// ── SERVICE (DIRECT API POLLING) ──────────────────────────────────────────

class DirectGpsService {
  // Probamos con AllOrigins que es más permisivo con los Preflights de CORS
  final String baseUrl = "https://api.allorigins.win/raw?url=http://liot.cl:8082/api";

  Future<List<GpsUnit>> fetchLiotData() async {
    try {
      // 1. Obtener credenciales de Firestore
      final secretDoc = await FirebaseFirestore.instance.collection('secrets').doc('Liot').get();
      if (!secretDoc.exists) throw Exception('No se encontraron credenciales de Liot.');
      
      final data = secretDoc.data()!;
      // Extraemos del campo que mostraste en la captura o usamos placeholders
      final user = data['user'] ?? 'tte.inostroza@gmail.com'; 
      final pass = data['pass'] ?? '2025liot';

      final auth = base64Encode(utf8.encode('$user:$pass'));
      final headers = { 'Authorization': 'Basic $auth', 'Accept': 'application/json' };

      // 2. Obtener Dispositivos
      final devRes = await http.get(Uri.parse('$baseUrl/devices'), headers: headers);
      if (devRes.statusCode != 200) throw Exception('Error API Devices: ${devRes.statusCode}');
      final List devices = json.decode(devRes.body);

      // 3. Obtener Posiciones
      final posRes = await http.get(Uri.parse('$baseUrl/positions'), headers: headers);
      if (posRes.statusCode != 200) throw Exception('Error API Positions: ${posRes.statusCode}');
      final List positions = json.decode(posRes.body);

      // 4. Cruzar datos
      return devices.map((dev) {
        final pos = positions.firstWhere((p) => p['deviceId'] == dev['id'], orElse: () => null);
        return GpsUnit(
          id: dev['id'].toString(),
          plate: dev['name'] ?? 'S/P',
          driverName: 'Chofer',
          position: LatLng(
            (pos?['latitude'] as num?)?.toDouble() ?? 0.0,
            (pos?['longitude'] as num?)?.toDouble() ?? 0.0,
          ),
          speed: (pos?['speed'] as num?)?.toDouble() ?? 0.0,
          status: dev['status'] ?? 'unknown',
          lastUpdate: pos != null ? DateTime.parse(pos['deviceTime']) : DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint("Error GPS Directo: $e");
      return [];
    }
  }
}

final gpsServiceProvider = Provider((ref) => DirectGpsService());

final fleetStreamProvider = StreamProvider<List<GpsUnit>>((ref) async* {
  final service = ref.read(gpsServiceProvider);
  while (true) {
    final units = await service.fetchLiotData();
    yield units;
    await Future.delayed(const Duration(seconds: 60)); // Poll cada minuto
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
              data: (units) => units.isEmpty 
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.satellite_alt, color: Colors.orange, size: 48),
                        SizedBox(height: 16),
                        Text('Esperando señal de Liot...', style: TextStyle(color: Colors.white, fontSize: 18)),
                        SizedBox(height: 8),
                        Text('Verifique su extensión de CORS y conexión.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )
                : FlutterMap(
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
                                color: unit.status == 'online' ? Colors.greenAccent : (unit.status == 'offline' ? Colors.redAccent : Colors.orange),
                                size: 24,
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ],
                  ),
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.orange)),
              error: (e, s) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    const Text('Error de Conexión GPS', style: TextStyle(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text('$e', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ],
                ),
              ),
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
    Color statusColor = unit.status == 'online' ? Colors.greenAccent : (unit.status == 'offline' ? Colors.redAccent : Colors.orange);
    
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
                Text(unit.status == 'online' ? '${unit.speed.toStringAsFixed(1)} knots' : 'Desconectado', 
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
