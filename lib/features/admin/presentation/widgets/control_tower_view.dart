import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/services/modogps_service.dart';

export '../../domain/services/modogps_service.dart' show GpsUnit;

final modoGpsServiceProvider = Provider((ref) => ModoGpsService());

class RefreshTriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() => state++;
}

final refreshTriggerProvider = NotifierProvider<RefreshTriggerNotifier, int>(() => RefreshTriggerNotifier());

final fleetStreamProvider = StreamProvider<List<GpsUnit>>((ref) async* {
  final service = ref.read(modoGpsServiceProvider);
  ref.watch(refreshTriggerProvider);

  while (true) {
    try {
      final units = await service.fetchFleetData();
      yield units;
    } catch (e) {
      debugPrint("Error obteniendo flota ModoGPS: $e");
    }
    await Future.delayed(const Duration(seconds: 45));
  }
});

class ControlTowerView extends ConsumerStatefulWidget {
  const ControlTowerView({super.key});

  @override
  ConsumerState<ControlTowerView> createState() => _ControlTowerViewState();
}

class _ControlTowerViewState extends ConsumerState<ControlTowerView> {
  final MapController _mapController = MapController();
  bool _hasCenteredInitial = false;

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

                // Centrar automáticamente en la primera unidad una sola vez al cargar
                if (!_hasCenteredInitial && units.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _mapController.move(units.first.position, 13);
                      _hasCenteredInitial = true;
                    }
                  });
                }

                return FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: units.isNotEmpty ? units.first.position : const LatLng(-36.9840, -73.1774),
                    initialZoom: 13,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    MarkerLayer(
                      markers: units.map((unit) {
                        final isMoving = unit.speed > 0;
                        final color = isMoving 
                            ? Colors.greenAccent 
                            : (unit.status == 'offline' ? Colors.redAccent : Colors.orangeAccent);

                        return Marker(
                          point: unit.position,
                          width: 70,
                          height: 60,
                          child: GestureDetector(
                            onTap: () => _mapController.move(unit.position, 15),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
                                  ),
                                  child: Text(
                                    unit.plate,
                                    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color, width: 1.5),
                                  ),
                                  child: Icon(
                                    Icons.local_shipping,
                                    color: color,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: () => _mapController.move(unit.position, 15),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    unit.plate,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
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
