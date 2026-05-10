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
    final remaining = nextService - vehicle.currentOdometer;
    
    Color statusColor;
    String statusLabel;
    if (nextService == 0) { statusColor = Colors.grey; statusLabel = 'Sin configurar'; }
    else if (remaining > 2000) { statusColor = Colors.greenAccent; statusLabel = 'Óptimo'; }
    else if (remaining > 1000) { statusColor = Colors.cyanAccent; statusLabel = 'Planificar (2000km)'; }
    else if (remaining > 500) { statusColor = Colors.yellowAccent; statusLabel = 'Próximo (1000km)'; }
    else if (remaining > 0) { statusColor = Colors.orangeAccent; statusLabel = 'Crítico (500km)'; }
    else { statusColor = Colors.redAccent; statusLabel = 'Vencido'; }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.local_shipping, color: statusColor, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicle.patente, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('${vehicle.marca ?? ""} ${vehicle.modelo ?? ""}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${NumberFormat('#,###').format(vehicle.currentOdometer)} km', style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: nextService > 0 ? (vehicle.currentOdometer / nextService).clamp(0, 1) : 0,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(statusLabel, textAlign: TextAlign.center, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.grey), 
            onPressed: () => _showEditMaintenanceDialog(context, ref, vehicle),
          ),
        ],
      ),
    );
  }

  void _showEditMaintenanceDialog(BuildContext context, WidgetRef ref, VehicleModel vehicle) {
    final odometerCtrl = TextEditingController(text: vehicle.currentOdometer.toStringAsFixed(0));
    final nextServiceCtrl = TextEditingController(text: (vehicle.nextOilChangeKm ?? (vehicle.currentOdometer + 10000)).toStringAsFixed(0));
    
    DateTime? rtDate = vehicle.rtExpirationDate;
    DateTime? soapDate = vehicle.soapExpirationDate;
    DateTime? permisoDate = vehicle.permisoExpirationDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text('Gestionar Mantenimiento: ${vehicle.patente}', style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField('Kilometraje Actual', odometerCtrl, Icons.speed),
                const SizedBox(height: 16),
                _buildField('Próximo Cambio Aceite (KM)', nextServiceCtrl, Icons.build),
                const SizedBox(height: 24),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),
                _buildDatePicker(context, 'Vencimiento Rev. Técnica', rtDate, (d) => setState(() => rtDate = d)),
                _buildDatePicker(context, 'Vencimiento SOAP', soapDate, (d) => setState(() => soapDate = d)),
                _buildDatePicker(context, 'Vencimiento Permiso Circ.', permisoDate, (d) => setState(() => permisoDate = d)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final updated = VehicleModel(
                  id: vehicle.id,
                  idEmpresa: vehicle.idEmpresa,
                  patente: vehicle.patente,
                  marca: vehicle.marca,
                  modelo: vehicle.modelo,
                  anio: vehicle.anio,
                  currentOdometer: double.tryParse(odometerCtrl.text) ?? vehicle.currentOdometer,
                  nextOilChangeKm: double.tryParse(nextServiceCtrl.text),
                  rtExpirationDate: rtDate,
                  soapExpirationDate: soapDate,
                  permisoExpirationDate: permisoDate,
                );
                await ref.read(adminRepositoryProvider).updateVehicle(updated);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Guardar Cambios'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: Colors.grey),
        filled: true,
        fillColor: Colors.black,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, String label, DateTime? date, Function(DateTime) onPick) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      subtitle: Text(date != null ? DateFormat('dd/MM/yyyy').format(date) : 'No configurado', style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.calendar_month, color: Colors.grey),
      onTap: () async {
        final picked = await showDatePicker(
          context: context, 
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
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
