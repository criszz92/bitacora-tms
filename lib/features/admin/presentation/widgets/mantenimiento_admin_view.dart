import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../domain/models/incidencia_model.dart';
import 'package:intl/intl.dart';

class MantenimientoAdminView extends ConsumerWidget {
  const MantenimientoAdminView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gestión de Flota y Mantenimiento',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(
                      child: Row(
                        children: [
                          const Icon(Icons.local_shipping_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Text('Estado de Flota'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        children: [
                          const Icon(Icons.notification_important_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Text('Reportes de Choferes'),
                          const SizedBox(width: 8),
                          _buildBadge(ref),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _FleetStatusTab(),
            _IncidenciasTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(WidgetRef ref) {
    final incidenciasAsync = ref.watch(adminIncidenciasProvider);
    final count = incidenciasAsync.value?.where((i) => i.estado == 'Pendiente').length ?? 0;
    
    if (count == 0) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _FleetStatusTab extends ConsumerWidget {
  const _FleetStatusTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(adminVehiclesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (vehicles) => _buildFleetList(context, ref, vehicles),
      ),
    );
  }

  Widget _buildFleetList(BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    if (vehicles.isEmpty) {
      return const Center(
        child: Text('No hay vehículos registrados', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      itemCount: vehicles.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildVehicleCard(context, ref, vehicles[index]),
    );
  }

  Widget _buildVehicleCard(BuildContext context, WidgetRef ref, VehicleModel vehicle) {
    final nextService = vehicle.nextOilChangeKm ?? 0.0;
    final lastService = vehicle.lastServiceOdometer ?? 0.0;
    final remaining = nextService - vehicle.currentOdometer;

    // Determinar estado según km restantes
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    if (nextService == 0) {
      statusColor = Colors.grey;
      statusLabel = 'Sin configurar';
      statusIcon = Icons.help_outline;
    } else if (remaining > 2000) {
      statusColor = Colors.greenAccent;
      statusLabel = 'Óptimo';
      statusIcon = Icons.check_circle_outline;
    } else if (remaining > 1000) {
      statusColor = Colors.cyanAccent;
      statusLabel = 'Planificar';
      statusIcon = Icons.schedule;
    } else if (remaining > 500) {
      statusColor = Colors.yellowAccent;
      statusLabel = 'Próximo';
      statusIcon = Icons.warning_amber_outlined;
    } else if (remaining > 0) {
      statusColor = Colors.orangeAccent;
      statusLabel = 'Crítico';
      statusIcon = Icons.priority_high;
    } else {
      statusColor = Colors.redAccent;
      statusLabel = 'Vencido';
      statusIcon = Icons.error_outline;
    }

    // Calcular progreso CORRECTO:
    // Si tenemos lastServiceOdometer, la barra va desde ese punto hasta el objetivo
    // Si no, mostramos 0 (no tiene sentido mostrar sin punto de referencia)
    double progressValue = 0.0;
    if (nextService > 0 && lastService < nextService) {
      final interval = nextService - lastService;
      final traveled = vehicle.currentOdometer - lastService;
      progressValue = (traveled / interval).clamp(0.0, 1.0);
    } else if (nextService > 0 && vehicle.currentOdometer >= nextService) {
      progressValue = 1.0; // Vencido
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: nextService > 0 && remaining <= 500
              ? statusColor.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
          width: nextService > 0 && remaining <= 500 ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fila superior: icono, patente, modelo, badge de estado ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.local_shipping, color: statusColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.patente,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      '${vehicle.marca ?? ''} ${vehicle.modelo ?? ''}'.trim().isEmpty
                          ? 'Vehículo sin datos'
                          : '${vehicle.marca ?? ''} ${vehicle.modelo ?? ''}'.trim(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              // KM actuales
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${NumberFormat('#,###').format(vehicle.currentOdometer)} km',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Text('odómetro actual', style: TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
              const SizedBox(width: 16),
              // Badge de estado
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.grey),
                tooltip: 'Gestionar mantenimiento',
                onPressed: () => _showEditMaintenanceDialog(context, ref, vehicle),
              ),
            ],
          ),

          // ── Barra de progreso con zonas de color ──
          const SizedBox(height: 16),
          if (nextService > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progreso hacia próximo cambio de aceite',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                Text(
                  remaining > 0
                      ? '${NumberFormat('#,###').format(remaining.round())} km restantes'
                      : 'Cambio vencido por ${NumberFormat('#,###').format(remaining.abs().round())} km',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: remaining > 0 ? statusColor : Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildProgressBar(progressValue, statusColor),
            const SizedBox(height: 4),
            // Etiquetas de referencia bajo la barra
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lastService > 0
                      ? '${NumberFormat('#,###').format(lastService.round())} km (último serv.)'
                      : 'Inicio',
                  style: const TextStyle(fontSize: 9, color: Colors.white24),
                ),
                Text(
                  '${NumberFormat('#,###').format(nextService.round())} km (objetivo)',
                  style: const TextStyle(fontSize: 9, color: Colors.white24),
                ),
              ],
            ),
          ] else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Configura el próximo cambio de aceite para ver el indicador de progreso',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Barra de progreso con gradiente de colores que refleja las zonas de alerta.
  Widget _buildProgressBar(double progress, Color currentColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            // Fondo de la barra
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            // Marcas de zona (lineas sutiles en 50%, 75%, 90%)
            Positioned(
              left: width * 0.5,
              top: 0,
              child: Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.08)),
            ),
            Positioned(
              left: width * 0.75,
              top: 0,
              child: Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.08)),
            ),
            Positioned(
              left: width * 0.9,
              top: 0,
              child: Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.08)),
            ),
            // Barra de progreso con gradiente
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              height: 10,
              width: width * progress,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(
                  colors: [
                    Colors.greenAccent.withValues(alpha: 0.8),
                    Colors.cyanAccent.withValues(alpha: 0.8),
                    Colors.yellowAccent.withValues(alpha: 0.9),
                    Colors.orangeAccent,
                    Colors.redAccent,
                  ],
                  stops: const [0.0, 0.5, 0.75, 0.9, 1.0],
                ),
                boxShadow: [
                  BoxShadow(color: currentColor.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 0),
                ],
              ),
            ),
            // Indicador de posición actual (puntero)
            if (progress > 0.02 && progress < 0.98)
              Positioned(
                left: (width * progress) - 4,
                top: -2,
                child: Container(
                  width: 8,
                  height: 14,
                  decoration: BoxDecoration(
                    color: currentColor,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [BoxShadow(color: currentColor.withValues(alpha: 0.6), blurRadius: 4)],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showEditMaintenanceDialog(BuildContext context, WidgetRef ref, VehicleModel vehicle) {
    final lastServiceCtrl = TextEditingController(text: (vehicle.lastServiceOdometer ?? vehicle.currentOdometer).toStringAsFixed(0));
    final odometerCtrl = TextEditingController(text: vehicle.currentOdometer.toStringAsFixed(0));
    final previousInterval = (vehicle.nextOilChangeKm != null && vehicle.lastServiceOdometer != null)
        ? (vehicle.nextOilChangeKm! - vehicle.lastServiceOdometer!).toStringAsFixed(0)
        : '15000';
    final intervalCtrl = TextEditingController(text: previousInterval);

    DateTime? rtDate = vehicle.rtExpirationDate;
    DateTime? soapDate = vehicle.soapExpirationDate;
    DateTime? permisoDate = vehicle.permisoExpirationDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final lastService = double.tryParse(lastServiceCtrl.text) ?? (vehicle.lastServiceOdometer ?? vehicle.currentOdometer);
          final interval = double.tryParse(intervalCtrl.text) ?? 15000;
          final calculatedNextKm = lastService + interval;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.build_circle_outlined, color: Colors.orange, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mantenimiento: ${vehicle.patente}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Sección cambio de aceite ──
                  const Text(
                    'CAMBIO DE ACEITE',
                    style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 12),
                  _buildField('Último Cambio de Aceite (km)', lastServiceCtrl, Icons.history,
                    onChanged: (_) => setState(() {})),
                  const SizedBox(height: 12),
                  _buildField('Kilometraje Actual (Chofer)', odometerCtrl, Icons.speed,
                    onChanged: (_) => setState(() {})),
                  const SizedBox(height: 12),
                  _buildField('Kilómetros para próximo cambio', intervalCtrl, Icons.loop,
                    hint: 'Ej: 15000',
                    onChanged: (_) => setState(() {})),
                  const SizedBox(height: 12),
                  // Vista previa del cálculo automático
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_fix_high, color: Colors.orange, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Próximo cambio calculado automáticamente:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 4),
                              Text(
                                '${NumberFormat('#,###').format(calculatedNextKm.round())} km',
                                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  // ── Sección documentación ──
                  const Text(
                    'DOCUMENTACIÓN DEL VEHÍCULO',
                    style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 12),
                  _buildDatePicker(context, 'Vencimiento Rev. Técnica', rtDate, (d) => setState(() => rtDate = d)),
                  _buildDatePicker(context, 'Vencimiento SOAP', soapDate, (d) => setState(() => soapDate = d)),
                  _buildDatePicker(context, 'Vencimiento Permiso Circ.', permisoDate, (d) => setState(() => permisoDate = d)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final newLastService = double.tryParse(lastServiceCtrl.text) ?? (vehicle.lastServiceOdometer ?? vehicle.currentOdometer);
                  final newCurrent = double.tryParse(odometerCtrl.text) ?? vehicle.currentOdometer;
                  final newInterval = double.tryParse(intervalCtrl.text) ?? 15000;
                  final newNextKm = newLastService + newInterval;

                  final updated = VehicleModel(
                    id: vehicle.id,
                    idEmpresa: vehicle.idEmpresa,
                    patente: vehicle.patente,
                    marca: vehicle.marca,
                    modelo: vehicle.modelo,
                    anio: vehicle.anio,
                    currentOdometer: newCurrent,
                    nextOilChangeKm: newNextKm,
                    lastServiceOdometer: newLastService,
                    rtExpirationDate: rtDate,
                    soapExpirationDate: soapDate,
                    permisoExpirationDate: permisoDate,
                    rendimientoKmPorLitro: vehicle.rendimientoKmPorLitro,
                    categoriaPeaje: vehicle.categoriaPeaje,
                  );
                  await ref.read(adminRepositoryProvider).updateVehicle(updated);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, IconData icon,
      {String? hint, void Function(String)? onChanged}) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey),
        filled: true,
        fillColor: Colors.black,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.orange)),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, String label, DateTime? date, Function(DateTime) onPick) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      subtitle: Text(
        date != null ? DateFormat('dd/MM/yyyy').format(date) : 'No configurado',
        style: TextStyle(color: date != null ? Colors.white : Colors.white38),
      ),
      trailing: const Icon(Icons.calendar_month, color: Colors.grey, size: 18),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2032),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

class _IncidenciasTab extends ConsumerWidget {
  const _IncidenciasTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidenciasAsync = ref.watch(adminIncidenciasProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: incidenciasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (incidencias) => _buildIncidenciasList(context, ref, incidencias),
      ),
    );
  }

  Widget _buildIncidenciasList(BuildContext context, WidgetRef ref, List<IncidenciaModel> incidencias) {
    if (incidencias.isEmpty) {
      return const Center(child: Text('No hay reportes de conductores', style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      itemCount: incidencias.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildIncidenciaCard(context, ref, incidencias[index]),
    );
  }

  Widget _buildIncidenciaCard(BuildContext context, WidgetRef ref, IncidenciaModel incidencia) {
    final color = incidencia.estado == 'Pendiente' ? Colors.redAccent : (incidencia.estado == 'En Taller' ? Colors.orangeAccent : Colors.greenAccent);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(incidencia.tipo, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Text(incidencia.vehiclePatente, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              Text(DateFormat('dd/MM HH:mm').format(incidencia.fecha), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(incidencia.descripcion, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.person_outline, color: Colors.grey[600], size: 14),
              const SizedBox(width: 6),
              Text(incidencia.choferNombre, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              const Spacer(),
              _buildActionButtons(context, ref, incidencia),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, IncidenciaModel incidencia) {
    if (incidencia.estado == 'Solucionado') return const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20);

    return Row(
      children: [
        if (incidencia.estado == 'Pendiente')
          TextButton(
            onPressed: () => ref.read(adminRepositoryProvider).updateIncidenciaEstado(incidencia.id, 'En Taller'),
            child: const Text('Mover a Taller', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ),
        TextButton(
          onPressed: () => _showConvertToExpenseDialog(context, ref, incidencia),
          child: const Text('Convertir en Gasto', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
        ),
        TextButton(
          onPressed: () => ref.read(adminRepositoryProvider).updateIncidenciaEstado(incidencia.id, 'Solucionado'),
          child: const Text('Solucionado (Sin Gasto)', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ],
    );
  }

  void _showConvertToExpenseDialog(BuildContext context, WidgetRef ref, IncidenciaModel incidencia) {
    final amountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Convertir Reporte a Gasto', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reporte: ${incidencia.descripcion}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('Ingresa el monto gastado en esta reparación:', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Monto Total (\$)',
                labelStyle: TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.black26,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text);
              if (amount == null || amount <= 0) return;
              
              await ref.read(adminRepositoryProvider).convertIncidenciaToExpense(incidencia, amount);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Gasto registrado y reporte solucionado'), backgroundColor: Colors.green));
              }
            },
            child: const Text('Confirmar y Guardar'),
          ),
        ],
      ),
    );
  }
}
