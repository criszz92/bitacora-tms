import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../domain/models/liquidacion_model.dart';
import 'package:intl/intl.dart';

class LiquidacionesAdminView extends ConsumerStatefulWidget {
  const LiquidacionesAdminView({super.key});

  @override
  ConsumerState<LiquidacionesAdminView> createState() => _LiquidacionesAdminViewState();
}

class _LiquidacionesAdminViewState extends ConsumerState<LiquidacionesAdminView> {
  final _facturaController = TextEditingController();

  Future<void> _vincularFactura(LiquidacionModel liq) async {
    _facturaController.clear();
    final nroFactura = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Vincular Factura', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa el número de factura SII para esta liquidación.', 
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _facturaController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nº Factura',
                labelStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF121212),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE0E0E0)),
            onPressed: () => Navigator.pop(ctx, _facturaController.text.trim()),
            child: const Text('Vincular', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (nroFactura != null && nroFactura.isNotEmpty) {
      await ref.read(adminRepositoryProvider).linkFactura(liq.id, nroFactura, liq.tripIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Factura vinculada correctamente'), backgroundColor: Color(0xFFFFFFFF)),
        );
      }
    }
  }

  Future<void> _marcarPagada(LiquidacionModel liq) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirmar Pago', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Al confirmar el pago, la liquidación y todos sus viajes asociados se marcarán como Pagados. Esta acción no se puede deshacer.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFFFFF)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, confirmar pago', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await ref.read(adminRepositoryProvider).markLiquidacionPaid(liq.id, liq.tripIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liquidación pagada con éxito'), backgroundColor: Color(0xFFFFFFFF)),
        );
      }
    }
  }

  Future<void> _eliminarLiquidacion(LiquidacionModel liq) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('¿Eliminar Liquidación?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Se eliminará el registro y los viajes volverán a estar disponibles para conciliar. Esta acción es útil si te equivocaste de mes o de OS.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await ref.read(adminRepositoryProvider).deleteLiquidacion(liq.id, liq.tripIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liquidación eliminada correctamente'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Liquidaciones Ziyu',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 6),
                    const Text('Gestiona la facturación y cobranza de los viajes conciliados.',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 8),
                    Consumer(builder: (context, ref, _) {
                       final liqs = ref.watch(liquidacionesProvider).value ?? [];
                       return Text('Liquidaciones detectadas: ${liqs.length}', 
                           style: const TextStyle(color: Colors.white24, fontSize: 10));
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMonthSelector(ref),
                  const SizedBox(width: 12),
                  _buildVehicleSelector(ref),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          Expanded(
            child: ref.watch(liquidacionesProvider).when(
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFE0E0E0))),
              error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
              data: (liquidaciones) {
                if (liquidaciones.isEmpty) {
                  return const Center(child: Text('No hay liquidaciones generadas aún.', style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  itemCount: liquidaciones.length,
                  itemBuilder: (ctx, i) {
                    final liq = liquidaciones[i];
                    return InkWell(
                      onTap: () => _showLiquidacionDetail(liq),
                      borderRadius: BorderRadius.circular(16),
                      child: _buildLiqCard(liq),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(WidgetRef ref) {
    final currentMonth = ref.watch(selectedMonthProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonHideUnderline(
          child: DropdownButton<DateTime>(
          value: DateTime(currentMonth.year, currentMonth.month),
          dropdownColor: const Color(0xFF1E1E1E),
          icon: const Icon(Icons.calendar_month, color: Colors.grey, size: 18),
          items: List.generate(6, (i) {
            final date = DateTime(DateTime.now().year, DateTime.now().month - i, 1);
            // Formato más simple para evitar problemas de locale en Web
            final dateStr = '${date.month}/${date.year}'; 
            return DropdownMenuItem(
              value: date,
              child: Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 13)),
            );
          }),
          onChanged: (val) {
            if (val != null) ref.read(selectedMonthProvider.notifier).setMonth(val);
          },
        ),
      ),
    );
  }

  Widget _buildVehicleSelector(WidgetRef ref) {
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final selectedVehicleId = ref.watch(selectedVehicleProvider);
    final vehicles = vehiclesAsync.value ?? [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selectedVehicleId,
          dropdownColor: const Color(0xFF1E1E1E),
          icon: const Icon(Icons.local_shipping, color: Colors.orange, size: 20),
          hint: const Text('Toda la Flota', style: TextStyle(color: Colors.white, fontSize: 13)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Toda la Flota', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ...vehicles.map((v) => DropdownMenuItem(
              value: v.id,
              child: Text(v.patente, style: const TextStyle(color: Colors.white)),
            )),
          ],
          onChanged: (val) => ref.read(selectedVehicleProvider.notifier).setVehicle(val),
        ),
      ),
    );
  }

  void _showLiquidacionDetail(LiquidacionModel liq) {
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Auditoría Liq. #${liq.id.substring(0,6)}', style: const TextStyle(color: Colors.white)),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.grey)),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Encabezados de la pantalla dividida
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text('IDENTIFICACIÓN (OS/CNTR)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 2, child: Text('VALOR ZIYU (EXCEL)', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 2, child: Text('VALOR BITÁCORA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 1, child: Text('DIFERENCIA', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              if (liq.detalleCruce == null || liq.detalleCruce!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Text('Esta liquidación no tiene detalle de auditoría (generada antes de la actualización).', style: TextStyle(color: Colors.grey)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: liq.detalleCruce!.length,
                    itemBuilder: (context, index) {
                      final item = liq.detalleCruce![index];
                      final diff = (item['diferencia'] as num?)?.toDouble() ?? 0.0;
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['os'] ?? 'Sin OS', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  if (item['contenedor'] != null)
                                    Text(item['contenedor'], style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                ],
                              ),
                            ),
                            Expanded(flex: 2, child: Text(currency.format(item['ziyuValue'] ?? 0), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            Expanded(flex: 2, child: Text(currency.format(item['bitacoraValue'] ?? 0), style: const TextStyle(color: Colors.white))),
                            Expanded(
                              flex: 1, 
                              child: Text(
                                currency.format(diff), 
                                style: TextStyle(
                                  color: diff == 0 ? Colors.grey : (diff > 0 ? Colors.green : Colors.redAccent),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12
                                )
                              )
                            ),
                          ],
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

  Widget _buildLiqCard(LiquidacionModel liq) {
    Color statusColor;
    IconData statusIcon;

    switch (liq.estado) {
      case 'facturada':
        statusColor = const Color(0xFFE0E0E0); // Azul
        statusIcon = Icons.receipt_long;
        break;
      case 'pagada':
        statusColor = const Color(0xFFFFFFFF); // Verde
        statusIcon = Icons.check_circle;
        break;
      case 'pendiente':
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending_actions;
        break;
    }

    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Icono Estado
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 32),
          ),
          const SizedBox(width: 24),
          
          // Datos Liquidación
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(liq.referencia ?? 'Liq. #${liq.id.substring(0, 6).toUpperCase()}', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(liq.estado.toUpperCase(), 
                          style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(liq.fechaCreacion)}', 
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text('${liq.viajesCount} viajes consolidados', 
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                if (liq.nroFactura != null) ...[
                  const SizedBox(height: 4),
                  Text('Factura SII: N° ${liq.nroFactura}', 
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ]
              ],
            ),
          ),
          
          // Monto
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Monto Total', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(currency.format(liq.montoTotal), 
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(width: 32),

          // Acciones
          if (liq.estado == 'pendiente')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE0E0E0).withValues(alpha: 0.1),
                foregroundColor: const Color(0xFFE0E0E0),
                elevation: 0,
              ),
              onPressed: () => _vincularFactura(liq),
              icon: const Icon(Icons.add_link),
              label: const Text('Facturar'),
            )
          else if (liq.estado == 'facturada')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFFFFF).withValues(alpha: 0.1),
                foregroundColor: const Color(0xFFFFFFFF),
                elevation: 0,
              ),
              onPressed: () => _marcarPagada(liq),
              icon: const Icon(Icons.monetization_on_outlined),
              label: const Text('Marcar Pagada'),
            ),
          
          if (liq.estado != 'pagada') ...[
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => _eliminarLiquidacion(liq),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Eliminar Liquidación',
            ),
          ],
        ],
      ),
    );
  }
}
