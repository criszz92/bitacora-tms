import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/fleet_chat_repository.dart';
import '../../domain/models/fleet_message_model.dart';
import '../../domain/services/audio_voice_service.dart';

class FleetChatScreen extends ConsumerStatefulWidget {
  const FleetChatScreen({super.key});

  @override
  ConsumerState<FleetChatScreen> createState() => _FleetChatScreenState();
}

class _FleetChatScreenState extends ConsumerState<FleetChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isHoldingMic = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _currentlyPlayingUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Suscribir al tópico de avisos masivos de la empresa
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProfileProvider).value;
      if (user?.idEmpresa != null && user!.idEmpresa.isNotEmpty) {
        PushNotificationService.subscribeToCompanyAnnouncements(user.idEmpresa);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  void _startRecordTimer() {
    _recordSeconds = 0;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  void _stopRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;
    final companyId = user?.idEmpresa ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1216),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Canal de Flota',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              user?.idEmpresa != null && user!.idEmpresa.isNotEmpty
                  ? 'Flota: ${user.idEmpresa.toUpperCase()}'
                  : 'Sin Empresa Asignada',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF161A22),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(
              icon: Icon(Icons.campaign_rounded),
              text: 'Avisos Oficiales',
            ),
            Tab(
              icon: Icon(Icons.radio_rounded),
              text: 'Canal Radial Flota',
            ),
          ],
        ),
      ),
      body: companyId.isEmpty
          ? const Center(
              child: Text(
                'Debes tener una empresa asignada para acceder al canal.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAnnouncementsTab(companyId, user?.uid ?? ''),
                _buildFleetChatTab(companyId, user),
              ],
            ),
    );
  }

  // ================= PESTAÑA 1: AVISOS OFICIALES =================
  Widget _buildAnnouncementsTab(String companyId, String currentUserId) {
    final messagesAsync = ref.watch(
      fleetMessagesStreamProvider((companyId: companyId, channelType: 'announcements')),
    );

    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (messages) {
        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none_rounded, size: 64, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                const Text(
                  'No hay avisos oficiales recientes.',
                  style: TextStyle(color: Colors.white60, fontSize: 15),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final isRead = msg.readBy.contains(currentUserId);

            // Marcar como leído automáticamente si aún no lo está
            if (!isRead && currentUserId.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(fleetChatRepositoryProvider).markAsRead(companyId, msg.id, currentUserId);
              });
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: msg.isUrgent
                    ? const Color(0xFF2A1515)
                    : const Color(0xFF161A22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: msg.isUrgent
                      ? Colors.redAccent.withValues(alpha: 0.8)
                      : AppColors.primary.withValues(alpha: 0.4),
                  width: msg.isUrgent ? 2 : 1,
                ),
                boxShadow: [
                  BoxInsets.allShadow(
                    msg.isUrgent
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: msg.isUrgent ? Colors.redAccent : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            msg.isUrgent ? Icons.warning_rounded : Icons.campaign_rounded,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.isUrgent ? 'AVISO URGENTE • ADMINISTRACIÓN' : 'COMUNICADO OFICIAL',
                                style: TextStyle(
                                  color: msg.isUrgent ? Colors.redAccent : AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                '${msg.senderName} (${msg.senderRole})',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          DateFormat('HH:mm - dd/MM').format(msg.createdAt),
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      msg.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isRead ? Icons.done_all_rounded : Icons.mark_chat_unread_rounded,
                              size: 16,
                              color: isRead ? Colors.tealAccent : Colors.orangeAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isRead ? 'Confirmado leído' : 'Nuevo aviso',
                              style: TextStyle(
                                fontSize: 12,
                                color: isRead ? Colors.tealAccent : Colors.orangeAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${msg.readBy.length} choferes lo leyeron',
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ================= PESTAÑA 2: CANAL RADIAL FLOTA =================
  Widget _buildFleetChatTab(String companyId, dynamic user) {
    final messagesAsync = ref.watch(
      fleetMessagesStreamProvider((companyId: companyId, channelType: 'fleet_chat')),
    );

    return Column(
      children: [
        // Botones de estado rápido (1 toque)
        _buildQuickStatusRow(companyId, user),

        // Lista de mensajes
        Expanded(
          child: messagesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
            data: (messages) {
              if (messages.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.radio_rounded, size: 60, color: Colors.white.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      const Text(
                        'Canal libre. Mantén presionado el micrófono para hablar.',
                        style: TextStyle(color: Colors.white60, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                controller: _scrollController,
                reverse: true, // Estilo chat: los nuevos abajo
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg.senderId == (user?.uid ?? '');
                  return _buildMessageBubble(msg, isMe);
                },
              );
            },
          ),
        ),

        // Barra inferior: Push-to-Talk y entrada de texto
        _buildBottomInputBar(companyId, user),
      ],
    );
  }

  Widget _buildQuickStatusRow(String companyId, dynamic user) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      color: const Color(0xFF13171D),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _quickStatusChip('🚧 Taco en Ruta', companyId, user),
            const SizedBox(width: 8),
            _quickStatusChip('👮 Control Pesaje / Carabineros', companyId, user),
            const SizedBox(width: 8),
            _quickStatusChip('⏳ En Fila de Puerto', companyId, user),
            const SizedBox(width: 8),
            _quickStatusChip('🟢 Ruta Despejada', companyId, user),
          ],
        ),
      ),
    );
  }

  Widget _quickStatusChip(String label, String companyId, dynamic user) {
    return ActionChip(
      backgroundColor: const Color(0xFF1E242E),
      side: const BorderSide(color: Colors.white12),
      label: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
      onPressed: () {
        ref.read(fleetChatRepositoryProvider).sendTextMessage(
          companyId: companyId,
          channelType: 'fleet_chat',
          senderId: user?.uid ?? '',
          senderName: user?.nombre ?? 'Conductor',
          senderRole: user?.rol ?? 'DRIVER',
          patente: user?.patenteAsignada,
          content: label,
          type: MessageType.quickStatus,
        );
      },
    );
  }

  Widget _buildMessageBubble(FleetMessageModel msg, bool isMe) {
    final voiceService = ref.watch(audioVoiceServiceProvider);
    final isPlaying = _currentlyPlayingUrl == msg.content;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFF1E3A5F)
              : const Color(0xFF1A1F27),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera identificadora: [NOMBRE] • [PATENTE] • [DESTINO]
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  msg.senderName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isMe ? Colors.lightBlueAccent : AppColors.primary,
                  ),
                ),
                if (msg.patente != null && msg.patente!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      msg.patente!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ),
                Text(
                  DateFormat('HH:mm').format(msg.createdAt),
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Contenido según el tipo
            if (msg.type == MessageType.audio) ...[
              // Audio Player bajo demanda (Push to talk)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                      color: AppColors.primary,
                      size: 38,
                    ),
                    onPressed: () async {
                      if (isPlaying) {
                        await voiceService.stopAudio();
                        setState(() => _currentlyPlayingUrl = null);
                      } else {
                        setState(() => _currentlyPlayingUrl = msg.content);
                        await voiceService.playAudio(msg.content);
                        voiceService.player.playerStateStream.listen((state) {
                          if (state.processingState == ProcessingState.completed) {
                            if (mounted) setState(() => _currentlyPlayingUrl = null);
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📻 Mensaje de Voz PTT',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                      ),
                      Text(
                        '${msg.audioDurationSec ?? 0}s • 16kbps Opus',
                        style: const TextStyle(fontSize: 11, color: Colors.white60),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              Text(
                msg.content,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomInputBar(String companyId, dynamic user) {
    final voiceService = ref.read(audioVoiceServiceProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: const Color(0xFF161A22),
      child: SafeArea(
        child: Row(
          children: [
            // Botón Micrófono PTT (Push to Talk)
            GestureDetector(
              onLongPressStart: (_) async {
                setState(() => _isHoldingMic = true);
                _startRecordTimer();
                await voiceService.startRecording();
              },
              onLongPressEnd: (_) async {
                setState(() => _isHoldingMic = false);
                _stopRecordTimer();
                final result = await voiceService.stopRecording();
                if (result.file != null && result.durationSec >= 1) {
                  await ref.read(fleetChatRepositoryProvider).sendAudioMessage(
                    companyId: companyId,
                    senderId: user?.uid ?? '',
                    senderName: user?.nombre ?? 'Conductor',
                    senderRole: user?.rol ?? 'DRIVER',
                    patente: user?.patenteAsignada,
                    audioFile: result.file!,
                    durationSec: result.durationSec,
                  );
                }
              },
              onLongPressCancel: () async {
                setState(() => _isHoldingMic = false);
                _stopRecordTimer();
                await voiceService.cancelRecording();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isHoldingMic ? Colors.redAccent : AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: _isHoldingMic
                      ? [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.6), blurRadius: 16)]
                      : [],
                ),
                child: Icon(
                  _isHoldingMic ? Icons.mic : Icons.mic_none_rounded,
                  color: Colors.black,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Si está grabando, muestra indicador de segundos
            if (_isHoldingMic)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Transmitiendo Radio PTT: ${_recordSeconds}s (Suelta para enviar)',
                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Campo de texto tradicional
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje a la flota...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E242E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),

            if (!_isHoldingMic) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                onPressed: () {
                  final text = _textController.text.trim();
                  if (text.isEmpty) return;

                  ref.read(fleetChatRepositoryProvider).sendTextMessage(
                    companyId: companyId,
                    channelType: 'fleet_chat',
                    senderId: user?.uid ?? '',
                    senderName: user?.nombre ?? 'Conductor',
                    senderRole: user?.rol ?? 'DRIVER',
                    patente: user?.patenteAsignada,
                    content: text,
                  );

                  _textController.clear();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BoxInsets {
  static BoxShadow allShadow(Color color) {
    return BoxShadow(color: color, blurRadius: 10, offset: const Offset(0, 4));
  }
}

