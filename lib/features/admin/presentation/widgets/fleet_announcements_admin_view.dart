import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/data/repositories/fleet_chat_repository.dart';
import '../../../chat/domain/models/fleet_message_model.dart';

class FleetAnnouncementsAdminView extends ConsumerStatefulWidget {
  const FleetAnnouncementsAdminView({super.key});

  @override
  ConsumerState<FleetAnnouncementsAdminView> createState() => _FleetAnnouncementsAdminViewState();
}

class _FleetAnnouncementsAdminViewState extends ConsumerState<FleetAnnouncementsAdminView> {
  final TextEditingController _announcementController = TextEditingController();
  bool _isUrgent = false;
  bool _isSending = false;

  @override
  void dispose() {
    _announcementController.dispose();
    super.dispose();
  }

  Future<void> _sendBroadcast(String companyId, dynamic user) async {
    final text = _announcementController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);

    try {
      await ref.read(fleetChatRepositoryProvider).sendTextMessage(
        companyId: companyId,
        channelType: 'announcements',
        senderId: user?.uid ?? '',
        senderName: user?.nombre ?? 'Administrador',
        senderRole: 'ADMIN',
        content: text,
        type: MessageType.broadcast,
        isUrgent: _isUrgent,
      );

      _announcementController.clear();
      setState(() => _isUrgent = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Comunicado masivo emitido exitosamente a toda la flota.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al emitir comunicado: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;
    final companyId = user?.idEmpresa ?? '';

    final messagesAsync = ref.watch(
      fleetMessagesStreamProvider((companyId: companyId, channelType: 'announcements')),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📢 Despacho & Avisos Masivos a la Flota',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Emite directrices operacionales y consulta qué choferes han confirmado lectura en cabina.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E242E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Empresa: ${companyId.toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Formulario de emisión
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161A22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Redactar Nuevo Comunicado Oficial',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _announcementController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: Puerto Coronel cerrará ventana de stacking a las 23:00 hrs. Todos los camiones con destino Coronel reportar estado por favor.',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF1F2530),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Switch(
                            value: _isUrgent,
                            activeThumbColor: Colors.redAccent,
                            onChanged: (val) => setState(() => _isUrgent = val),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isUrgent ? 'URGENTE (Alerta sonora prioritaria en teléfonos)' : 'Prioridad Normal',
                            style: TextStyle(
                              color: _isUrgent ? Colors.redAccent : Colors.white70,
                              fontWeight: _isUrgent ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isUrgent ? Colors.redAccent : AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isSending ? null : () => _sendBroadcast(companyId, user),
                        icon: _isSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded, size: 20),
                        label: Text(
                          _isSending ? 'Emitiendo...' : 'Transmitir a Flota',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Lista y Métricas de confirmación de lectura
            const Text(
              'Historial de Comunicados y Métricas de Lectura',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'No hay comunicados registrados aún.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final readCount = msg.readBy.length;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161A22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: msg.isUrgent ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white12,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: msg.isUrgent ? Colors.redAccent.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                msg.isUrgent ? Icons.warning_amber_rounded : Icons.campaign_rounded,
                                color: msg.isUrgent ? Colors.redAccent : AppColors.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        msg.isUrgent ? 'COMUNICADO URGENTE' : 'COMUNICADO OFICIAL',
                                        style: TextStyle(
                                          color: msg.isUrgent ? Colors.redAccent : AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('dd/MM/yyyy HH:mm').format(msg.createdAt),
                                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    msg.content,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      const Icon(Icons.people_alt_outlined, size: 16, color: Colors.tealAccent),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$readCount conductores han confirmado lectura',
                                        style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

