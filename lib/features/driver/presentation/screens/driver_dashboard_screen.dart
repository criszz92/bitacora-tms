import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../trips/presentation/providers/trip_provider.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/shift_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../admin/presentation/providers/admin_provider.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../trips/domain/services/distance_service.dart';
import '../../../admin/domain/models/incidencia_model.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../admin/domain/models/service_request_model.dart';
import '../../../admin/domain/services/modogps_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../admin/domain/models/infraestructura_vial_model.dart';
import '../../../../core/utils/road_infrastructure_detector.dart';
import '../../../../core/utils/route_live_monitor.dart';
import '../../../admin/data/repositories/infraestructura_repository.dart';
import '../../../trips/domain/models/expense_model.dart';

class DriverDashboardScreen extends ConsumerWidget {
  const DriverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeShiftAsync = ref.watch(activeShiftProvider);
    final shiftTripsAsync = ref.watch(currentShiftTripsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bitacora Conductor', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      drawer: _buildDriverDrawer(context, ref),
      body: SafeArea(
        child: activeShiftAsync.when(
          data: (shift) {
            if (shift == null) {
              return _buildNoShiftView(context, ref);
            }
            // Listener para reportes automáticos de documentos
            _setupAutoDocumentReportListener(ref, shift);
            
            return _buildDashboardContent(context, ref, shiftTripsAsync, shift);
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFFFFF))),
          error: (err, stack) => Center(child: Text('Error al cargar jornada: $err')),
        ),
      ),
    );
  }

  // ================= PANTALLA DE BLOQUEO =================
  Widget _buildNoShiftView(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_clock, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Jornada Cerrada',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            _buildAssignedRequestBanner(context, ref), // Banner dinámico
            const SizedBox(height: 16),
            const Text(
              'Para registrar viajes o viáticos, debes iniciar tu día de trabajo indicando el camión y el kilometraje.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  context.push('/start-shift');
                },
                icon: const Icon(Icons.play_arrow, size: 32),
                label: const Text('INICIAR JORNADA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= DRAWER (MENÚ LATERAL) =================
  Widget _buildDriverDrawer(BuildContext context, WidgetRef ref) {
    final user = ref.read(currentUserProfileProvider).value;
    final isAdmin = user?.rol == 'ADMIN';
    
    String displayName = 'Conductor';
    String initial = 'C';
    if (user != null && user.nombre.isNotEmpty) {
      final parts = user.nombre.trim().split(RegExp(r'\s+'));
      displayName = parts.length > 1 ? '${parts[0]} ${parts[1]}' : parts[0];
      initial = displayName[0].toUpperCase();
    }

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFFFFFFF),
                      foregroundColor: Colors.black,
                      radius: 24,
                      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, 
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(user?.email ?? 'Sin correo', 
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.local_gas_station, color: Colors.white),
            title: const Text('Carga de Combustible'),
            onTap: () {
              context.pop();
              context.push('/add-expense?type=Combustible');
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_road, color: Colors.white),
            title: const Text('Peajes'),
            onTap: () {
              context.pop();
              context.push('/add-expense?type=Peaje');
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.request_quote, color: Color(0xFFE0E0E0)),
            title: const Text('Rendición de Viáticos', style: TextStyle(color: Color(0xFFE0E0E0), fontWeight: FontWeight.bold)),
            onTap: () {
              context.pop();
              context.push('/viaticos-request');
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics_outlined, color: Colors.blueAccent),
            title: const Text('Resumen del Mes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Ver viajes, viáticos y comisiones', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              context.pop();
              context.push('/monthly-summary');
            },
          ),
          ListTile(
            leading: const Icon(Icons.build_circle_outlined, color: Colors.orangeAccent),
            title: const Text('Salud del Camión', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('Estado de mantención y documentos', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              context.pop();
              _showVehicleMaintenanceDialog(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.white60),
            title: const Text('Agregar Viaje Pasado', style: TextStyle(color: Colors.white60)),
            subtitle: const Text('Olvidé registrar un viaje', style: TextStyle(color: Colors.white30, fontSize: 11)),
            onTap: () {
              context.pop();
              context.push('/retro-trip');
            },
          ),
          if (isAdmin) ...[
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.orangeAccent),
              title: const Text('Volver a Administración', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
              onTap: () {
                context.pop();
                context.go('/admin');
              },
            ),
          ],
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () async {
              context.pop();
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }

  // ================= DASHBOARD REAL MÓVIL =================
  Widget _buildDashboardContent(BuildContext context, WidgetRef ref, AsyncValue<List<TripModel>> shiftTripsAsync, ShiftModel shift) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildExpirationBanner(ref),
          _buildAssignedRequestBanner(context, ref), // Banner dinámico
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tus Registros',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Camión asignado: ${shift.patenteCamion}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _showEndShiftDialog(context, ref, shift),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_circle, color: Colors.redAccent, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Cerrar Jornada',
                        style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          shiftTripsAsync.when(
            data: (trips) {
              final activeCount = trips.where((t) => t.status == 'En Ruta').length;
              final completedTrips = trips.where((t) => t.status != 'En Ruta').toList();
              final double totalKmJornada = completedTrips.fold(0.0, (acc, t) => acc + (t.totalKm ?? 0.0));
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E222B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping, size: 16, color: activeCount > 0 ? Colors.greenAccent : Colors.white60),
                    const SizedBox(width: 6),
                    Text('$activeCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    const SizedBox(width: 4),
                    Text(activeCount == 1 ? 'Activo' : 'Activos', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 16, color: Colors.white12),
                    const SizedBox(width: 12),
                    const Icon(Icons.route, size: 16, color: Colors.purpleAccent),
                    const SizedBox(width: 6),
                    Text('${totalKmJornada.toStringAsFixed(0)} KM', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    const SizedBox(width: 4),
                    const Text('Jornada', style: TextStyle(color: Colors.white60, fontSize: 11)),
                    const Spacer(),
                    InkWell(
                      onTap: () => _showReportIncidentDialog(context, ref, shift),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.report_problem_outlined, size: 13, color: Colors.redAccent),
                            SizedBox(width: 4),
                            Text('Incidencia', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => Container(height: 38, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12))),
            error: (err, stack) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Viajes de la Jornada',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              shiftTripsAsync.maybeWhen(
                data: (trips) {
                  final hasActive = trips.any((t) => t.status == 'En Ruta');
                  if (!hasActive) return const SizedBox.shrink();
                  return TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _showStartMovementOptions(context),
                    icon: const Icon(Icons.add, size: 16, color: Colors.blueAccent),
                    label: const Text('Nuevo Movimiento', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shiftTripsAsync.when(
              data: (trips) {
                if (trips.isEmpty) {
                  return const Center(child: Text('No hay viajes registrados en esta jornada', style: TextStyle(color: Colors.grey)));
                }
                final sorted = List<TripModel>.from(trips)..sort((a, b) {
                  if (a.status == 'En Ruta' && b.status != 'En Ruta') return -1;
                  if (a.status != 'En Ruta' && b.status == 'En Ruta') return 1;
                  return b.startDate.compareTo(a.startDate);
                });
                return ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    return _buildTripCard(context, ref, sorted[index], shift.patenteCamion);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFFFFF))),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
          // Botón inferior: solo se muestra destacado si NO hay viaje activo para no tapar la pantalla
          shiftTripsAsync.maybeWhen(
            data: (trips) {
              final hasActive = trips.any((t) => t.status == 'En Ruta');
              if (hasActive) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFFFFF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _showStartMovementOptions(context),
                    icon: const Icon(Icons.add_box, color: Colors.black, size: 20),
                    label: const Text('INICIAR NUEVA ACTIVIDAD', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _showStartMovementOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selecciona el Tipo de Movimiento',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Elige si inicias un servicio comercial o un desplazamiento sin ganancias.',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildMovementOptionTile(
                ctx,
                icon: Icons.local_shipping,
                color: Colors.greenAccent,
                title: 'Viaje Operativo (Comercial)',
                subtitle: 'Flete con cliente y tarifa. Suma comisión y viáticos según corresponda.',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/add-trip?tipo=operativo');
                },
              ),
              const SizedBox(height: 12),
              _buildMovementOptionTile(
                ctx,
                icon: Icons.inventory_2_outlined,
                color: Colors.amberAccent,
                title: 'Retiro Anticipado (Sin Ganancia)',
                subtitle: 'Desplazamiento previo a faena o depósito. Registra KM y peajes sin comisión ni viático.',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/add-trip?tipo=retiro_anticipado');
                },
              ),
              const SizedBox(height: 12),
              _buildMovementOptionTile(
                ctx,
                icon: Icons.build_circle_outlined,
                color: Colors.cyanAccent,
                title: 'Traslado a Mantenimiento',
                subtitle: 'Movimiento de camión a taller o revisión técnica. Sin ganancias (\$0).',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/add-trip?tipo=traslado_mantenimiento');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovementOptionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161A22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  // ================= ALERTAS DE DOCUMENTACIÓN =================

  Widget _buildExpirationBanner(WidgetRef ref) {
    final vehicleAsync = ref.watch(currentVehicleProvider);
    
    return vehicleAsync.when(
      data: (vehicle) {
        if (vehicle == null || !vehicle.hasExpiringDocs) return const SizedBox.shrink();
        
        final expiring = vehicle.getExpiringDocuments(7);
        final hasCritical = expiring.any((d) => d['esCritico'] as bool);
        
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hasCritical ? Colors.redAccent.withValues(alpha: 0.1) : Colors.orangeAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hasCritical ? Colors.redAccent : Colors.orangeAccent, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(hasCritical ? Icons.error_outline : Icons.warning_amber_rounded, 
                       color: hasCritical ? Colors.redAccent : Colors.orangeAccent, size: 20),
                  const SizedBox(width: 12),
                  const Text('ALERTA DE DOCUMENTACIÓN', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: 8),
              ...expiring.map((doc) => Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 4),
                child: Text(
                  '${doc['nombre']}: vence en ${doc['diasRestantes']} días (${DateFormat('dd/MM').format(doc['fecha'])})',
                  style: TextStyle(color: hasCritical ? Colors.redAccent : Colors.orangeAccent, fontSize: 12),
                ),
              )),
              const SizedBox(height: 8),
              const Text('Favor dar aviso manual a jefatura lo antes posible.', 
                style: TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  void _setupAutoDocumentReportListener(WidgetRef ref, ShiftModel shift) {
    // Escuchamos el vehículo actual para detectar cambios en documentos
    ref.listen(currentVehicleProvider, (previous, next) {
      final vehicle = next.value;
      if (vehicle == null) return;

      final criticalDocs = vehicle.getExpiringDocuments(1); // 1 día o menos
      if (criticalDocs.isEmpty) return;

      // Generamos un reporte automático por cada documento crítico
      for (final doc in criticalDocs) {
        _triggerAutoReport(ref, shift, vehicle, doc['nombre'] as String, doc['diasRestantes'] as int);
      }
    });
  }

  void _triggerAutoReport(WidgetRef ref, ShiftModel shift, VehicleModel vehicle, String docName, int days) async {
    final user = ref.read(currentUserProfileProvider).value;
    if (user == null) return;

    final id = const Uuid().v4();
    final descripcion = 'SISTEMA: Alerta automática - El documento "$docName" ${days < 0 ? "ESTÁ VENCIDO" : (days == 0 ? "VENCE HOY" : "VENCE MAÑANA")}. '
                        'Favor gestionar renovación urgente.';

    final incidencia = IncidenciaModel(
      id: id,
      idEmpresa: shift.idEmpresa,
      idChofer: user.uid,
      choferNombre: user.nombre,
      vehicleId: vehicle.id,
      vehiclePatente: vehicle.patente,
      tipo: 'Documentos',
      descripcion: descripcion,
      fecha: DateTime.now(),
      estado: 'Pendiente',
    );

    await ref.read(tripRepositoryProvider).reportIncidencia(incidencia);
  }

  // ================= MANTENIMIENTO DIALOGS =================
  void _showVehicleMaintenanceDialog(BuildContext context, WidgetRef ref) async {
    final activeShift = ref.read(activeShiftProvider).value;
    if (activeShift == null) return;

    // Fetch vehicles from repository instead of relying on an uninitialized provider
    final vehicles = await ref.read(adminRepositoryProvider).watchVehicles(activeShift.idEmpresa).first;
    
    VehicleModel? vehicle;
    for (var v in vehicles) {
      if (v.patente == activeShift.patenteCamion) {
        vehicle = v;
        break;
      }
    }

    if (!context.mounted) return;

    if (vehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró información del camión')));
      return;
    }

    final nextService = vehicle.nextOilChangeKm ?? 0.0;
    final remaining = nextService - vehicle.currentOdometer;
    
    final v = vehicle; // Safe non-nullable reference for the closure

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Estado: ${v.patente}', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Kilometraje Actual', '${NumberFormat('#,###').format(v.currentOdometer)} km'),
            _buildInfoRow('Próximo Servicio', '${NumberFormat('#,###').format(nextService)} km'),
            const Divider(color: Colors.white10, height: 24),
            _buildInfoRow('Mantenimiento', remaining > 0 ? '${NumberFormat('#,###').format(remaining)} km restantes' : 'VENCIDO', color: remaining > 500 ? Colors.greenAccent : Colors.redAccent),
            const Divider(color: Colors.white10, height: 24),
            _buildDateRow('Revisión Técnica', v.rtExpirationDate),
            _buildDateRow('SOAP', v.soapExpirationDate),
            _buildDateRow('Permiso Circulación', v.permisoExpirationDate),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _showReportIncidentDialog(BuildContext context, WidgetRef ref, ShiftModel shift) {
    final user = ref.read(currentUserProfileProvider).value;
    final descCtrl = TextEditingController();
    String? selectedType;
    final types = ['Mecánica', 'Neumáticos', 'Documentos', 'Otros'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Reportar Incidencia', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Tipo de Problema', labelStyle: TextStyle(color: Colors.grey)),
                items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => selectedType = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Descripción breve',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.black26,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: selectedType == null ? null : () async {
                final vehicles = ref.read(vehiclesProvider).value ?? [];
                final matchedVehicle = vehicles.where((v) => v.patente == shift.patenteCamion).firstOrNull;
                final vehicleDocId = matchedVehicle?.id ?? '';

                final incidencia = IncidenciaModel(
                  id: const Uuid().v4(),
                  idEmpresa: shift.idEmpresa,
                  vehicleId: vehicleDocId,
                  vehiclePatente: shift.patenteCamion,
                  idChofer: shift.idChofer,
                  choferNombre: user?.nombre ?? 'Conductor',
                  tipo: selectedType!,
                  descripcion: descCtrl.text,
                  fecha: DateTime.now(),
                );
                try {
                  await ref.read(tripRepositoryProvider).reportIncidencia(incidencia);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte enviado correctamente')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Enviar Reporte'),
            ),
          ],
        ),
      ),
    );
  }

  // ================= AUXILIARES =================
  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDateRow(String label, DateTime? date) {
    final isExpired = date != null && date.isBefore(DateTime.now());
    return _buildInfoRow(label, date != null ? DateFormat('dd/MM/yyyy').format(date) : 'No cargado', color: isExpired ? Colors.redAccent : null);
  }



  Widget _buildTripCard(BuildContext context, WidgetRef ref, TripModel trip, String defaultPlate) {
    final isEnRuta = trip.status == 'En Ruta';
    final targetPlate = trip.vehicleId ?? defaultPlate;
    final gpsUnitAsync = ref.watch(singleVehicleGpsProvider(targetPlate));

    if (isEnRuta) {
      return _buildActiveTripCard(context, ref, trip, targetPlate, gpsUnitAsync);
    } else {
      return _buildCompletedTripCard(context, ref, trip, targetPlate);
    }
  }

  Widget _buildActiveTripCard(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
    String targetPlate,
    AsyncValue<GpsUnit?> gpsUnitAsync,
  ) {
    final nextHito = _getNextHito(trip.hitoActual);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF22C55E), width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF161B22),
              const Color(0xFF0F172A).withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header del viaje activo
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: trip.isRetiroAnticipado 
                        ? const Color(0xFFFBBF24) 
                        : (trip.isMantenimiento ? const Color(0xFF38BDF8) : const Color(0xFF22C55E)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  trip.isRetiroAnticipado
                      ? 'RETIRO ANTICIPADO'
                      : (trip.isMantenimiento ? 'MANTENIMIENTO' : 'VIAJE EN CURSO'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: trip.isRetiroAnticipado 
                        ? const Color(0xFFFBBF24) 
                        : (trip.isMantenimiento ? const Color(0xFF38BDF8) : const Color(0xFF4ADE80)),
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                if (!trip.isOperativo) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: const Text('SIN GANANCIAS', style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                if (trip.containerNumber != null && trip.containerNumber!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          trip.containerNumber!,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else if (trip.guideNumber != null && trip.guideNumber!.isNotEmpty)
                  Text('Guía: ${trip.guideNumber}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('HH:mm').format(trip.startDate),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── MONITOREO DE RUTA EN VIVO (Alertas de Romanas, Restricciones y Peajes) ──
            Builder(
              builder: (ctx) {
                final monitorState = ref.watch(routeMonitorStreamProvider(targetPlate)).value ?? RouteMonitorState();
                if (monitorState.activeAlerts.isEmpty && monitorState.passedTolls.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  children: [
                    // Alertas activas prioritarias (Romanas o Restricciones Horarias)
                    ...monitorState.activeAlerts.take(2).map((alert) {
                      final isRomana = alert.tipo == TipoPuntoInfraestructura.romana;
                      final isRestriccion = alert.tipo == TipoPuntoInfraestructura.restriccion;
                      final alertColor = isRomana ? Colors.amberAccent : (isRestriccion ? Colors.redAccent : Colors.cyanAccent);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: alertColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: alertColor.withValues(alpha: 0.6), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Icon(isRomana ? Icons.balance : (isRestriccion ? Icons.block : Icons.toll), color: alertColor, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(alert.title, style: TextStyle(color: alertColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text(alert.message, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // Acumulador de peajes detectados en vivo en ruta
                    if (monitorState.passedTolls.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.toll_outlined, color: Colors.tealAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Peajes cruzados: ${monitorState.passedTolls.length} • Estimado: \$${monitorState.estimatedTollsTotal.toInt()}',
                                style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),

            // Telemetría GPS en vivo / Geocerca detectada
            gpsUnitAsync.when(
              data: (unit) {
                if (unit == null) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.satellite_alt, size: 12, color: Colors.white38),
                        SizedBox(width: 6),
                        Text('Sincronizando con ModoGPS...', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  );
                }

                final inGeofence = unit.currentGeofence != null && unit.currentGeofence!.isNotEmpty;
                final isIdle = (unit.isIgnitionOn == true) && unit.speed < 2;

                if (isIdle) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pause_circle_outline, size: 14, color: Colors.amberAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            inGeofence
                                ? 'Motor en Ralentí • En ${unit.currentGeofence}'
                                : 'Motor Encendido Detenido • Modo Ralentí (0 km/h)',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (inGeofence) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F5132).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Geocerca GPS: ${unit.currentGeofence}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  final isRalenti = (unit.isIgnitionOn == true) && unit.speed < 2;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isRalenti 
                          ? Colors.orange.withValues(alpha: 0.2) 
                          : const Color(0xFF1E3A8A).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isRalenti ? Colors.orangeAccent.withValues(alpha: 0.6) : Colors.blueAccent.withValues(alpha: 0.4), 
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isRalenti ? Icons.hourglass_top_rounded : Icons.satellite_alt, 
                          size: 13, 
                          color: isRalenti ? Colors.orangeAccent : Colors.lightBlueAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isRalenti
                                ? 'Motor Encendido • Modo Ralentí (0 km/h) • Cuidado Turbo'
                                : (unit.status == 'online'
                                    ? 'GPS Conectado • En Ruta (${unit.speed.toStringAsFixed(0)} km/h)'
                                    : 'GPS Conectado • Detenido'),
                            style: TextStyle(
                              color: isRalenti ? Colors.orangeAccent : const Color(0xFF93C5FD), 
                              fontSize: 11.5, 
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),

            // Trazado de Ruta: Origen ➔ Destino (compacto y elegante)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.radio_button_checked, size: 14, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trip.origin,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6.5, top: 2, bottom: 2),
                    child: Row(
                      children: [
                        Container(width: 1.5, height: 14, color: Colors.white24),
                        const SizedBox(width: 14),
                        Text('Cliente: ${trip.client}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trip.destination,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Hito Operativo Actual y Avance Rápido (1 solo toque)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag_rounded, size: 15, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hito: ${trip.hitoActual ?? "En Tránsito Inicial"}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trip.hitos != null && trip.hitos!.isNotEmpty)
                        Text('${trip.hitos!.length} reg.', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            await ref.read(tripRepositoryProvider).registrarHito(trip.id, nextHito);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Hito avanzado a: "$nextHito"'),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: const Color(0xFF1E3A8A),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.fast_forward_rounded, size: 15),
                          label: Text(
                            'Avanzar: $nextHito',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                        ),
                        icon: const Icon(Icons.more_horiz, size: 18, color: Colors.white70),
                        tooltip: 'Ver lista completa de hitos',
                        onPressed: () => _showChangeHitoModal(context, ref, trip),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '🤖 ModoGPS detecta paradas automáticamente por satélite.',
                    style: TextStyle(color: Colors.white38, fontSize: 9.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Botones de Acción: FINALIZAR VIAJE + Trazado GPS
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: () => _showEndTripDialog(context, ref, trip, targetPlate),
                    icon: const Icon(Icons.check_circle, color: Colors.black, size: 18),
                    label: const Text(
                      'FINALIZAR VIAJE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.lightBlueAccent,
                    side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showTripGpsComparisonDialog(context, ref, trip, targetPlate),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.satellite_alt_outlined, size: 16),
                      SizedBox(width: 4),
                      Text('GPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedTripCard(BuildContext context, WidgetRef ref, TripModel trip, String targetPlate) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  trip.isRetiroAnticipado
                      ? 'RETIRO ANTICIPADO'
                      : (trip.isMantenimiento ? 'MANTENIMIENTO' : 'VIAJE COMPLETADO'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: trip.isRetiroAnticipado
                        ? Colors.amberAccent
                        : (trip.isMantenimiento ? Colors.cyanAccent : Colors.white70),
                    fontSize: 12,
                  ),
                ),
                Row(
                  children: [
                    if (!trip.isOperativo)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('SIN GANANCIAS', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        trip.status,
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16, color: Colors.white12),
            _buildRouteRow(Icons.my_location, 'Origen', trip.origin),
            const SizedBox(height: 8),
            _buildRouteRow(Icons.location_on, 'Destino', trip.destination),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.inventory_2, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trip.containerNumber != null && trip.containerNumber!.isNotEmpty
                        ? trip.containerNumber!
                        : (trip.guideNumber != null && trip.guideNumber!.isNotEmpty
                            ? 'Guía: ${trip.guideNumber}'
                            : 'Carga Suelta'),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trip.totalKm != null) ...[
                  const Icon(Icons.route, size: 14, color: Colors.purpleAccent),
                  const SizedBox(width: 4),
                  Text(
                    '${trip.totalKm!.toStringAsFixed(1)} KM',
                    style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () => _showEditTripDriverDialog(context, ref, trip),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('EDITAR KM / GUÍA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNextHito(String? current) {
    if (current == null) return 'En Faena (Carga / Retiro)';
    final c = current.toLowerCase();
    if (c.contains('base') || c.contains('inicial') || c.contains('tránsito a puerto')) {
      return 'En Faena (Carga / Retiro)';
    } else if (c.contains('faena') || c.contains('antepuerto') || c.contains('retiro') || c.contains('puerto')) {
      return 'En Ruta a Destino';
    } else if (c.contains('ruta a destino') || c.contains('tránsito a cliente') || c.contains('cliente 1')) {
      return 'Llegada a Destino (Descarga)';
    } else if (c.contains('llegada') || c.contains('destino') || c.contains('descarga') || c.contains('devolución')) {
      return 'Retorno a Base / Cierre';
    }
    return 'En Faena (Carga / Retiro)';
  }

  Future<void> _showChangeHitoModal(BuildContext context, WidgetRef ref, TripModel trip) async {
    final macroHitos = [
      {'nombre': 'En Tránsito Inicial / A Carga', 'icon': Icons.directions_bus_outlined, 'desc': 'Traslado inicial hacia punto de retiro o faena'},
      {'nombre': 'En Faena / Carga / Operación', 'icon': Icons.storefront_outlined, 'desc': 'En cliente o terminal cargando o realizando faena'},
      {'nombre': 'En Ruta a Destino', 'icon': Icons.route_outlined, 'desc': 'Viaje por carretera con carga hacia destino final'},
      {'nombre': 'Llegada a Destino (Descarga)', 'icon': Icons.done_all_rounded, 'desc': 'En planta de descarga o entrega de contenedor'},
    ];

    final hitosDetallados = [
      {'nombre': 'En Base (Preparación)', 'icon': Icons.home_work_outlined},
      {'nombre': 'En Antepuerto (Espera / Stacking)', 'icon': Icons.hourglass_top_rounded},
      {'nombre': 'En Puerto / Depósito (Retiro de Vacío)', 'icon': Icons.archive_outlined},
      {'nombre': 'En Cliente 2 (Consolidación / Punto Adicional)', 'icon': Icons.add_business_outlined},
      {'nombre': 'En Puerto / Depósito (Entrega de Contenedor)', 'icon': Icons.unarchive_outlined},
      {'nombre': 'Retorno a Base / Cierre de Ciclo', 'icon': Icons.home_rounded},
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Hito Operativo de Ruta',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: Colors.lightBlueAccent),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ModoGPS detecta paradas y geocercas satelitalmente sin necesidad de ingreso manual.',
                            style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'ETAPAS PRINCIPALES (RECOMENDADO):',
                    style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  ...macroHitos.map((item) {
                    final isSelected = trip.hitoActual == item['nombre'];
                    return ListTile(
                      dense: true,
                      leading: Icon(item['icon'] as IconData, color: isSelected ? Colors.greenAccent : Colors.white70),
                      title: Text(
                        item['nombre'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.greenAccent : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        item['desc'] as String,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18) : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await ref.read(tripRepositoryProvider).registrarHito(trip.id, item['nombre'] as String);
                      },
                    );
                  }),
                  const Divider(color: Colors.white12, height: 20),
                  const Text(
                    'HITOS ESPECÍFICOS DE PUERTO / FAENA:',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  ...hitosDetallados.map((item) {
                    final isSelected = trip.hitoActual == item['nombre'];
                    return ListTile(
                      dense: true,
                      leading: Icon(item['icon'] as IconData, size: 18, color: isSelected ? Colors.amber : Colors.white60),
                      title: Text(
                        item['nombre'] as String,
                        style: TextStyle(color: isSelected ? Colors.amber : Colors.white70, fontSize: 12),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.amber, size: 16) : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await ref.read(tripRepositoryProvider).registrarHito(trip.id, item['nombre'] as String);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTripGpsComparisonDialog(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
    String plate,
  ) async {
    final modoGps = ref.read(modoGpsServiceProvider);
    final startTime = trip.startDate;
    final endTime = trip.endDate ?? DateTime.now();
    final timeFmt = DateFormat('HH:mm');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.satellite_alt, color: Colors.blueAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Comparativa GPS de Tramo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Cruce exacto fecha y hora con ModoGPS', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: FutureBuilder<GpsHistoricalTrip?>(
          future: modoGps.fetchTripInterval(
            plate: plate,
            startTime: startTime,
            endTime: endTime,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blueAccent),
                      SizedBox(height: 16),
                      Text('Consultando recorrido exacto en ModoGPS...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              return SizedBox(
                height: 140,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 36),
                      const SizedBox(height: 10),
                      Text(
                        'No se encontraron puntos GPS para este rango horario (${timeFmt.format(startTime)} - ${timeFmt.format(endTime)}).',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }

            final hTrip = snapshot.data!;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(
                          '${timeFmt.format(startTime)} ➔ ${timeFmt.format(endTime)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Spacer(),
                        Text('Placa: ${hTrip.plate}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          'KM GPS',
                          '${hTrip.totalDistanceKm.toStringAsFixed(1)} KM',
                          Icons.straighten,
                          Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricTile(
                          'KM Registrados',
                          trip.totalKm != null ? '${trip.totalKm!.toStringAsFixed(1)} KM' : 'Sin reg.',
                          Icons.route,
                          Colors.purpleAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          'Vel. Promedio',
                          '${hTrip.avgSpeed.toStringAsFixed(0)} km/h',
                          Icons.speed,
                          Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricTile(
                          'Vel. Máxima',
                          '${hTrip.maxSpeed.toStringAsFixed(0)} km/h',
                          Icons.trending_up,
                          Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Hitos y Geocercas Detectadas:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (hTrip.stays.isEmpty)
                    const Text('No se registraron paradas dentro de geocercas en este intervalo.', style: TextStyle(color: Colors.white38, fontSize: 11))
                  else
                    ...hTrip.stays.map((stay) => Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.greenAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(stay.geofenceName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            Text(
                              '${timeFmt.format(stay.entryTime)} - ${timeFmt.format(stay.exitTime)} (${stay.durationMinutes}m)',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
                Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEndTripDialog(BuildContext context, WidgetRef ref, TripModel trip, String targetPlate) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EndTripDialog(trip: trip, targetPlate: targetPlate),
    );
  }

  Future<void> _showEditTripDriverDialog(BuildContext context, WidgetRef ref, TripModel trip) async {
    final guideCtrl = TextEditingController(text: trip.guideNumber ?? '');
    final kmCtrl = TextEditingController(
      text: (trip.totalKm != null && trip.totalKm! > 0) ? trip.totalKm!.toStringAsFixed(1) : '',
    );
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar Kilometraje / Guía', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${trip.origin} → ${trip.destination}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              TextFormField(
                controller: guideCtrl,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nº Guía de Despacho',
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Kilómetros aprox. recorridos',
                  suffixText: 'KM',
                  suffixStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa los kilómetros aproximados';
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFFFFF), foregroundColor: Colors.black),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final parsedKm = double.tryParse(kmCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;

              await ref.read(tripRepositoryProvider).updateTripDetails(
                trip.id,
                guideNumber: guideCtrl.text.trim(),
                totalKm: parsedKm,
              );

              if (ctx.mounted) Navigator.pop(ctx);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ Kilometraje actualizado a ${parsedKm.toStringAsFixed(1)} KM'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEndShiftDialog(BuildContext context, WidgetRef ref, ShiftModel shift) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Finalizar Jornada', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Odómetro Final', filled: true, fillColor: Colors.black26, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                ref.read(tripRepositoryProvider).endShift(shift.id, int.parse(ctrl.text));
                Navigator.pop(ctx);
              }
            },
            child: const Text('CERRAR JORNADA'),
          )
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  // ================= BANNER DE ASIGNACIÓN IA =================

  Widget _buildAssignedRequestBanner(BuildContext context, WidgetRef ref) {
    final assignedAsync = ref.watch(assignedRequestsProvider);

    return assignedAsync.when(
      data: (requests) {
        if (requests.isEmpty) return const SizedBox.shrink();
        
        final ServiceRequest request = requests.first;
        final shift = ref.read(activeShiftProvider).value;
        final hasShift = shift != null;
        
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'SOLICITUD DE ${request.clientName.toUpperCase()}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 12),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${request.origin} → ${request.destination}',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (!hasShift) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠ Tienes un servicio asignado. Para verlo debes INICIAR JORNADA.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else {
                      context.push('/add-trip', extra: request);
                    }
                  },
                  child: Text(
                    hasShift ? 'ACEPTAR E INICIAR VIAJE' : 'INICIA JORNADA PARA VER VIAJE',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

class _DetectedTollPass {
  final String id;
  final PuntoInfraestructuraModel peaje;
  final DateTime passTime;
  final double distanceMeters;
  final bool isFromGps;
  bool isSelected;
  final bool isAlreadySaved;
  final TextEditingController amountController;

  _DetectedTollPass({
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

class _EndTripDialog extends ConsumerStatefulWidget {
  final TripModel trip;
  final String targetPlate;

  const _EndTripDialog({
    required this.trip,
    required this.targetPlate,
  });

  @override
  ConsumerState<_EndTripDialog> createState() => _EndTripDialogState();
}

class _EndTripDialogState extends ConsumerState<_EndTripDialog> {
  late final TextEditingController _guideCtrl;
  late final TextEditingController _kmCtrl;
  late final TextEditingController _containerCtrl;
  final _formKey = GlobalKey<FormState>();

  bool _isLoadingGps = true;
  bool _isLoadingTolls = true;
  double? _gpsKm;
  double? _suggestedTheoreticalKm;
  bool _isFinalizing = false;

  List<_DetectedTollPass> _detectedTolls = [];
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
        startTime: widget.trip.startDate,
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
        final detected = <_DetectedTollPass>[];

        // Lista de candidatos potenciales con distancia y punto exacto de cruce
        final candidatePasses = <_DetectedTollPass>[];

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
            final distM = distanceCalc.as(LengthUnit.Meter, peajeLatLng, pt.position);

            if (distM <= maxRadius) {
              // Calcular rumbo del camión en ese momento
              double? ptBearing;
              if (ptIdx > 0) {
                final prevPt = hTrip.points[ptIdx - 1];
                ptBearing = RoadInfrastructureDetector.calculateBearing(prevPt.position, pt.position);
              } else if (ptIdx < hTrip.points.length - 1) {
                final nextPt = hTrip.points[ptIdx + 1];
                ptBearing = RoadInfrastructureDetector.calculateBearing(pt.position, nextPt.position);
              }

              // Validar concordancia de sentido (Norte a Sur vs Sur a Norte, etc.)
              if (!RoadInfrastructureDetector.matchesDirection(truckHeading: ptBearing, sentidoPunto: peaje.sentido)) {
                continue;
              }

              if (lastDetectionTime == null || pt.timestamp.difference(lastDetectionTime).inMinutes.abs() > 8) {
                if (lastDetectionTime != null && minDistanceInPass < double.infinity) {
                  final defaultAmount = peaje.tarifaCamionPesado ?? peaje.tarifaCamionSimple ?? 0.0;
                  final isSaved = existingPeajeNames.any((n) => n.contains(peaje.nombre.toLowerCase()));
                  candidatePasses.add(_DetectedTollPass(
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
            candidatePasses.add(_DetectedTollPass(
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

                final newPass = _DetectedTollPass(
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

                      final expenseId = 'EXP-TOLL-${DateTime.now().millisecondsSinceEpoch}-$savedTollsCount';
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
                        vehicleId: widget.targetPlate,
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
