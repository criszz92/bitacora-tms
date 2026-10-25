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
              const Text(
                'Tus Registros',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_car, size: 16, color: Color(0xFFE0E0E0)),
                    const SizedBox(width: 8),
                    Text(
                      shift.patenteCamion,
                      style: const TextStyle(color: Color(0xFFE0E0E0), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () {
                        _showEndShiftDialog(context, ref, shift);
                      },
                      child: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 28),
                    )
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showReportIncidentDialog(context, ref, shift),
              icon: const Icon(Icons.report_problem_outlined, size: 18),
              label: const Text('REPORTAR PROBLEMA TÉCNICO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          shiftTripsAsync.when(
            data: (trips) {
              final activeCount = trips.where((t) => t.status == 'En Ruta').length;
              final completedTrips = trips.where((t) => t.status != 'En Ruta').toList();
              final double totalKmJornada = completedTrips.fold(0.0, (acc, t) => acc + (t.totalKm ?? 0.0));
              return Row(
                children: [
                  Expanded(child: _buildSummaryCard('Viajes Activos', '$activeCount', Icons.local_shipping)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildSummaryCard('KM Jornada', totalKmJornada.toStringAsFixed(0), Icons.route)),
                ],
              );
            },
            loading: () => Row(children: [Expanded(child: _buildLoadingCard())]),
            error: (err, stack) => Row(children: [Expanded(child: _buildErrorCard())]),
          ),
          const SizedBox(height: 24),
          const Text(
            'Viajes de la Jornada',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFFFFF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      context.push('/add-trip');
                    },
                    icon: const Icon(Icons.add_box, color: Colors.black),
                    label: const Text('INICIAR NUEVO VIAJE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ),
            ],
          ),
        ],
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

  Widget _buildSummaryCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFFFFFF), size: 32),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: CircularProgressIndicator(color: Color(0xFFFFFFFF))),
      ),
    );
  }

  Widget _buildErrorCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: Icon(Icons.error, color: Colors.red)),
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, WidgetRef ref, TripModel trip, String defaultPlate) {
    final isEnRuta = trip.status == 'En Ruta';
    final targetPlate = trip.vehicleId ?? defaultPlate;
    final gpsUnitAsync = ref.watch(singleVehicleGpsProvider(targetPlate));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isEnRuta ? const Color(0xFFFFFFFF) : Colors.white24, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEnRuta ? 'VIAJE ACTIVO' : 'VIAJE COMPLETADO',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isEnRuta ? const Color(0xFFFFFFFF) : Colors.white70,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEnRuta
                        ? const Color(0xFFFFFFFF).withValues(alpha: 0.2)
                        : Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    trip.status,
                    style: TextStyle(
                      color: isEnRuta ? const Color(0xFFFFFFFF) : Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Indicador sutil de Geocerca / GPS en vivo
            if (isEnRuta) ...[
              const SizedBox(height: 8),
              gpsUnitAsync.when(
                data: (unit) {
                  if (unit == null) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.satellite_alt, size: 13, color: Colors.white54),
                          SizedBox(width: 6),
                          Text(
                            'GPS: Conectando con unidad...',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }

                  final inGeofence = unit.currentGeofence != null && unit.currentGeofence!.isNotEmpty;

                  if (inGeofence) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F5132).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'En Geocerca: ${unit.currentGeofence}',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.satellite_alt, size: 13, color: Colors.blueAccent),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              unit.status == 'online'
                                  ? 'GPS Conectado • En Ruta (${unit.speed.toStringAsFixed(0)} km/h)'
                                  : 'GPS Conectado • Detenido',
                              style: const TextStyle(
                                color: Color(0xFF93C5FD),
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
                loading: () => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54),
                      ),
                      SizedBox(width: 8),
                      Text('Sincronizando GPS...', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                error: (e, s) => const SizedBox.shrink(),
              ),
            ],

            const Divider(height: 24, color: Colors.white24),
            _buildRouteRow(Icons.my_location, 'Origen', trip.origin),
            const SizedBox(height: 12),
            _buildRouteRow(Icons.location_on, 'Destino', trip.destination),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.inventory_2, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.containerNumber != null && trip.containerNumber!.isNotEmpty
                        ? trip.containerNumber!
                        : (trip.guideNumber != null && trip.guideNumber!.isNotEmpty
                            ? 'Guía: ${trip.guideNumber}'
                            : 'Carga Suelta'),
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isEnRuta && trip.totalKm != null) ...[
                  const Icon(Icons.route, size: 16, color: Colors.purpleAccent),
                  const SizedBox(width: 6),
                  Text(
                    '${trip.totalKm!.toStringAsFixed(1)} KM',
                    style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // ─── HITOS OPERATIVOS DEL TRAMO ───
            if (isEnRuta) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'HITO OPERATIVO ACTUAL',
                          style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                        InkWell(
                          onTap: () => _showChangeHitoModal(context, ref, trip),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.edit_location_alt, size: 14, color: Colors.blueAccent),
                                SizedBox(width: 4),
                                Text('Cambiar', style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.flag_rounded, size: 16, color: Colors.amber),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.hitoActual ?? 'En Tránsito Inicial',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              if (trip.hitos != null && trip.hitos!.isNotEmpty)
                                Text(
                                  '${trip.hitos!.length} hito(s) registrado(s) en este viaje',
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Botón sutil para comparar tramo con GPS
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.lightBlueAccent,
                  backgroundColor: Colors.blue.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _showTripGpsComparisonDialog(context, ref, trip, targetPlate),
                icon: const Icon(Icons.satellite_alt_outlined, size: 15),
                label: const Text('Comparativa Tramo GPS (Fecha/Hora)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),

            if (isEnRuta)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFFFFF),
                    side: const BorderSide(color: Color(0xFFFFFFFF)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showEndTripDialog(context, ref, trip),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('FINALIZAR VIAJE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showEditTripDriverDialog(context, ref, trip),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('EDITAR KM / GUÍA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangeHitoModal(BuildContext context, WidgetRef ref, TripModel trip) async {
    final opcionesHitos = [
      {'nombre': 'En Base (Preparación)', 'icon': Icons.home_work_outlined, 'desc': 'Camión en base, iniciando jornada o alistando tracto'},
      {'nombre': 'En Tránsito a Puerto / Depósito', 'icon': Icons.directions_bus_outlined, 'desc': 'Traslado hacia terminal de retiro de vacío'},
      {'nombre': 'En Antepuerto (Espera de Turno / Stacking)', 'icon': Icons.hourglass_top_rounded, 'desc': 'Fila de espera o gestión documental en antepuerto'},
      {'nombre': 'En Puerto / Depósito (Retiro de Vacío)', 'icon': Icons.archive_outlined, 'desc': 'Ingreso al terminal, inspección y carga de contenedor'},
      {'nombre': 'En Tránsito a Cliente', 'icon': Icons.route_outlined, 'desc': 'Viaje por carretera con contenedor montado'},
      {'nombre': 'En Cliente 1 (Carga / Descarga)', 'icon': Icons.storefront_outlined, 'desc': 'Llegada a planta principal, pesaje o faena'},
      {'nombre': 'En Cliente 2 (Consolidación / Punto Adicional)', 'icon': Icons.add_business_outlined, 'desc': 'Segundo punto de carga para completar viaje'},
      {'nombre': 'En Tránsito a Puerto / Devolución', 'icon': Icons.alt_route_outlined, 'desc': 'Retorno hacia terminal marítimo o depósito'},
      {'nombre': 'En Puerto / Depósito (Entrega de Contenedor)', 'icon': Icons.unarchive_outlined, 'desc': 'Descarga en muelle o devolución de vacío con EIR'},
      {'nombre': 'Retorno a Base / Cierre de Ciclo', 'icon': Icons.home_rounded, 'desc': 'Traslado final de vuelta a la base'},
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  'Seleccionar Hito Operativo Actual',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Registra la etapa exacta en la que se encuentra el camión para control de tiempos y sobreestadías.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: opcionesHitos.length,
                    separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, idx) {
                      final item = opcionesHitos[idx];
                      final isSelected = trip.hitoActual == item['nombre'];
                      return ListTile(
                        dense: true,
                        leading: Icon(item['icon'] as IconData, color: isSelected ? Colors.amber : Colors.white70),
                        title: Text(
                          item['nombre'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.amber : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          item['desc'] as String,
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.amber, size: 18) : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          await ref.read(tripRepositoryProvider).registrarHito(trip.id, item['nombre'] as String);
                        },
                      );
                    },
                  ),
                ),
              ],
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

  Future<void> _showEndTripDialog(BuildContext context, WidgetRef ref, TripModel trip) async {
    // Intentar sugerir KM desde la tabla de distancias
    final distSvc = ref.read(distanceServiceProvider);
    final suggestedKm = (trip.totalKm == null || trip.totalKm! <= 0)
        ? distSvc.lookupKm(trip.client, trip.destination)
        : null;

    final guideCtrl = TextEditingController(text: trip.guideNumber ?? '');
    final kmCtrl = TextEditingController(
      text: (trip.totalKm != null && trip.totalKm! > 0)
          ? trip.totalKm!.toStringAsFixed(0)
          : (suggestedKm != null ? suggestedKm.toStringAsFixed(0) : ''),
    );
    final formKey = GlobalKey<FormState>();
    // Rastrear si el conductor modificó el valor sugerido
    bool isUsingSuggestion = suggestedKm != null;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Finalizar Viaje', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${trip.origin} → ${trip.destination}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              // Chip de sugerencia de KM
              if (isUsingSuggestion) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 12, color: Colors.purpleAccent),
                    const SizedBox(width: 4),
                    Text(
                      'KM sugerido desde tabla de distancias',
                      style: const TextStyle(color: Colors.purpleAccent, fontSize: 10),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: guideCtrl,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nº Guía de Despacho',
                  hintText: 'Ej: 12345',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (ctx2, setFieldState) {
                  kmCtrl.addListener(() {
                    if (isUsingSuggestion) {
                      final typed = kmCtrl.text.replaceAll(',', '.').trim();
                      final parsed = double.tryParse(typed);
                      if (parsed != null && parsed != suggestedKm) {
                        setFieldState(() => isUsingSuggestion = false);
                      }
                    }
                  });
                  return TextFormField(
                    controller: kmCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Kilómetros aprox. recorridos',
                      hintText: 'Ej: 120',
                      hintStyle: const TextStyle(color: Colors.white30),
                      suffixText: 'KM',
                      suffixStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: isUsingSuggestion
                          ? Colors.purple.withValues(alpha: 0.15)
                          : Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: isUsingSuggestion
                            ? const BorderSide(color: Colors.purpleAccent, width: 1)
                            : BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: isUsingSuggestion
                            ? const BorderSide(color: Colors.purpleAccent, width: 1)
                            : BorderSide.none,
                      ),
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
                  );
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

              await ref.read(tripRepositoryProvider).endTripWithGuide(
                trip.id,
                guideCtrl.text.trim(),
                totalKm: parsedKm,
              );

              if (ctx.mounted) Navigator.pop(ctx);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ Viaje cerrado: ${parsedKm.toStringAsFixed(1)} KM registrados'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('FINALIZAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
