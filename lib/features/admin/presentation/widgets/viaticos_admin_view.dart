import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../trips/domain/models/viatico_model.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../auth/domain/models/user_model.dart';

/// Vista del Admin para gestionar rendiciones de viáticos.
/// Muestra las pendientes primero, permite marcarlas como pagadas.
/// Al marcar como pagada, el calendario del conductor se actualiza en tiempo real.
class ViaticosAdminView extends ConsumerWidget {
  const ViaticosAdminView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viaticosAsync = ref.watch(adminViaticosProvider);

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bandeja de Viáticos',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          const Text(
            'Gestiona las rendiciones enviadas por tus conductores. Haz clic en una rendición para ver el detalle de los viajes realizados.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: viaticosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFFFFF))),
              error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
              data: (viaticos) => viaticos.isEmpty
                  ? _buildEmpty()
                  : _buildList(context, ref, viaticos),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, List<ViaticoModel> viaticos) {
    final pendientes = viaticos.where((v) => v.isPendiente).toList();
    final pagados = viaticos.where((v) => v.isPagado).toList();

    return ListView(
      children: [
        if (pendientes.isNotEmpty) ...[
          _sectionHeader('PENDIENTES DE PAGO', pendientes.length, const Color(0xFF9E9E9E)),
          ...pendientes.map((v) => _buildViaticoCard(context, ref, v)),
          const SizedBox(height: 24),
        ],
        if (pagados.isNotEmpty) ...[
          _sectionHeader('PAGADOS', pagados.length, const Color(0xFFFFFFFF)),
          ...pagados.map((v) => _buildViaticoCard(context, ref, v)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  letterSpacing: 1.5, color: color)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: color.withValues(alpha: 0.3))),
        ],
      ),
    );
  }

  Widget _buildViaticoCard(BuildContext context, WidgetRef ref, ViaticoModel v) {
    final isPendiente = v.isPendiente;
    final color = isPendiente ? const Color(0xFF9E9E9E) : const Color(0xFFFFFFFF);
    
    final choferes = ref.read(choferesProvider).value ?? [];
    final choferName = choferes.firstWhere((c) => c.uid == v.idChofer, 
        orElse: () => UserModel(uid: '', email: '', nombre: 'ID: ${v.idChofer.substring(0,8)}', rol: '', idEmpresa: '')).nombre;

    return InkWell(
      onTap: () => _showViaticoDetails(context, ref, v, choferName),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPendiente ? Icons.access_time : Icons.check_circle_outline,
                color: color, size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_fmtDate(v.fechaInicio)}  →  ${_fmtDate(v.fechaFin)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${v.fechaFin.difference(v.fechaInicio).inDays + 1} día(s) · Enviado el ${_fmtDate(v.creadoEn)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text('Conductor: $choferName',
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
            if (isPendiente)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _marcarPagado(context, ref, v),
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Marcar Pagado',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              )
            else
              const Text('Pagado ✓',
                  style: TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _showViaticoDetails(BuildContext context, WidgetRef ref, ViaticoModel v, String choferName) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Rendición: $choferName', style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: SizedBox(
          width: 500, // Fijar un ancho para evitar el gris de layout
          child: FutureBuilder<List<TripModel>>(
            future: ref.read(adminRepositoryProvider).getTripsForViatico(v.idEmpresa, v.idChofer, v.fechaInicio, v.fechaFin),
            builder: (c, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Color(0xFFFFFFFF))));
              }
              if (snap.hasError) {
                return Text('Error: ${snap.error}', style: const TextStyle(color: Colors.red));
              }
              final trips = snap.data ?? [];
              if (trips.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No se encontraron viajes en este periodo.', style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                itemCount: trips.length,
                itemBuilder: (context, i) {
                  final t = trips[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.local_shipping, color: Color(0xFFE0E0E0)),
                    title: Text('${t.origin} → ${t.destination}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    subtitle: Text('${_fmtDate(t.startDate)} · ${t.client.isEmpty ? 'Sin cliente' : t.client}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    trailing: Text('\$${t.value.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.bold)),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar', style: TextStyle(color: Colors.grey))),
          if (v.isPendiente)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFFFFF), foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(ctx);
                _marcarPagado(context, ref, v);
              },
              child: const Text('Marcar Pagado'),
            ),
        ],
      ),
    );
  }

  Future<void> _marcarPagado(BuildContext context, WidgetRef ref, ViaticoModel v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirmar Pago'),
        content: Text(
          '¿Confirmas el pago de la rendición del periodo\n${_fmtDate(v.fechaInicio)} al ${_fmtDate(v.fechaFin)}?\n\nEl conductor verá el cambio inmediatamente.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFFFFF), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar Pago'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Calcular el monto total a pagar
      double montoTotal = 0;
      try {
        final trips = await ref.read(adminRepositoryProvider).getTripsForViatico(v.idEmpresa, v.idChofer, v.fechaInicio, v.fechaFin);
        final config = ref.read(companyConfigProvider).value;
        final choferes = ref.read(choferesProvider).value ?? [];
        final chofer = choferes.firstWhere((c) => c.uid == v.idChofer, orElse: () => UserModel(uid: '', email: '', nombre: '', rol: '', idEmpresa: ''));
        
        if (config != null) {
          if (config.tipoViatico == 'POR_VIAJE') {
            for (final t in trips) {
              final isLongTrip = (t.totalKm ?? 0) >= config.umbralKilometrosViatico;
              montoTotal += isLongTrip ? (chofer.montoViaticoLargo ?? 10000) : (chofer.montoViaticoLocal ?? 6500);
            }
          } else {
            final Map<String, List<TripModel>> tripsByDay = {};
            for (final t in trips) {
              final dayKey = '${t.startDate.year}-${t.startDate.month}-${t.startDate.day}';
              tripsByDay.putIfAbsent(dayKey, () => []).add(t);
            }
            for (final dayTrips in tripsByDay.values) {
               bool existsLongTrip = dayTrips.any((t) => (t.totalKm ?? 0.0) >= config.umbralKilometrosViatico);
               montoTotal += existsLongTrip ? (chofer.montoViaticoLargo ?? 10000) : (chofer.montoViaticoLocal ?? 6500);
            }
          }
        }
      } catch (e) {
        debugPrint('Error calculando viático: $e');
      }

      await ref.read(adminRepositoryProvider).markViaticoPaid(v.id, montoTotal);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Viático marcado como pagado. El conductor lo verá en verde.'),
            backgroundColor: Color(0xFFFFFFFF),
          ),
        );
      }
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 72, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No hay rendiciones registradas.',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Las rendiciones aparecerán aquí cuando los conductores las envíen.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
