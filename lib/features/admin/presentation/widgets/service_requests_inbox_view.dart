import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../domain/models/service_request_model.dart';
import '../providers/admin_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// ── PROVIDERS ───────────────────────────────────────────────────────────────

final serviceRequestsProvider = StreamProvider<List<ServiceRequest>>((ref) {
  return FirebaseFirestore.instance
      .collection('service_requests')
      .where('status', whereIn: ['pending', 'assigned'])
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => ServiceRequest.fromFirestore(doc)).toList());
});

// ── VIEW ────────────────────────────────────────────────────────────────────

class ServiceRequestsInboxView extends ConsumerWidget {
  const ServiceRequestsInboxView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(serviceRequestsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bandeja de Entrada Inteligente',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 8),
                Text('Solicitudes procesadas automáticamente por la IA desde WhatsApp y Correo.',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
          
          Expanded(
            child: requestsAsync.when(
              data: (requests) {
                if (requests.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.white10),
                        SizedBox(height: 16),
                        Text('No hay solicitudes pendientes', style: TextStyle(color: Colors.white24)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return _buildRequestCard(context, ref, request);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.redAccent))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, WidgetRef ref, ServiceRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(request.clientName, 
                    style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const Spacer(),
                Text(DateFormat('dd MMM, HH:mm').format(request.createdAt), 
                  style: const TextStyle(color: Colors.white24, fontSize: 11)),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white38, size: 16),
                      const SizedBox(width: 8),
                      Text('${request.origin} → ${request.destination}', 
                        style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (request.loadType != null)
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, color: Colors.white38, size: 16),
                        const SizedBox(width: 8),
                        Text('Carga: ${request.loadType}', 
                          style: const TextStyle(color: Colors.white38, fontSize: 13)),
                      ],
                    ),
                  const SizedBox(height: 20),
                  if (request.status == ServiceRequestStatus.assigned)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Esperando que ${request.assignedToName} inicie jornada...',
                              style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (request.proposedValue != null)
                            Text(
                              'Tarifa: \$${NumberFormat('#,###', 'es_CL').format(request.proposedValue)}',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        request.rawText,
                        style: const TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Acciones
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _rejectRequest(request.id),
                  child: const Text('RECHAZAR', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
                const SizedBox(width: 16),
                if (request.status == ServiceRequestStatus.pending)
                  ElevatedButton.icon(
                    onPressed: () => _showAssignDriverDialog(context, ref, request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('ASIGNAR A CONDUCTOR'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _showAssignDriverDialog(context, ref, request),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('REASIGNAR'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _rejectRequest(String id) {
    FirebaseFirestore.instance.collection('service_requests').doc(id).update({
      'status': 'rejected',
    });
  }

  Future<void> _showAssignDriverDialog(BuildContext context, WidgetRef ref, ServiceRequest request) async {
    try {
      final user = ref.read(currentUserProfileProvider).value;
      if (user == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Usuario no identificado. Reintente.')),
          );
        }
        return;
      }

      final repo = ref.read(adminRepositoryProvider);
      final choferes = ref.read(choferesProvider).value ?? [];
      
      // Buscar tarifa sugerida por historial (con timeout o catch para que no bloquee)
      double? suggestedRate;
      try {
        suggestedRate = await repo.getSuggestedRate(user.idEmpresa, request.origin, request.destination);
      } catch (e) {
        debugPrint('Error obteniendo tarifa sugerida: $e');
      }

      final valueController = TextEditingController(
        text: suggestedRate != null ? suggestedRate.toInt().toString() : ''
      );

      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Asignar Conductor', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (suggestedRate != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline, color: Colors.green, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Tarifa sugerida (historial): \$${NumberFormat('#,###', 'es_CL').format(suggestedRate)}',
                              style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextField(
                  controller: valueController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tarifa del Viaje (\$)',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Seleccione Conductor:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                if (choferes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No hay conductores registrados', style: TextStyle(color: Colors.white24)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: choferes.length,
                      itemBuilder: (context, index) {
                        final chofer = choferes[index];
                        return ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.white70)),
                          title: Text(chofer.nombre, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: Text(chofer.rut ?? '', style: const TextStyle(color: Colors.white24, fontSize: 11)),
                          onTap: () async {
                            final val = double.tryParse(valueController.text.replaceAll('.', '')) ?? suggestedRate ?? 0.0;
                            await repo.updateServiceRequest(request.id, {
                              'status': 'assigned',
                              'assignedTo': chofer.uid,
                              'assignedToName': chofer.nombre,
                              'proposedValue': val,
                              'assignedAt': FieldValue.serverTimestamp(),
                            });
                            if (context.mounted) Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir diálogo: $e')),
        );
      }
    }
  }
}
