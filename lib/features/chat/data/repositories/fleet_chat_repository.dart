import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/fleet_message_model.dart';

final fleetChatRepositoryProvider = Provider<FleetChatRepository>((ref) {
  return FleetChatRepository(
    firestore: FirebaseFirestore.instance,
    storage: FirebaseStorage.instance,
  );
});

// Stream de mensajes paginados estrictamente (últimos 35) para respetar Plan Spark ($0)
final fleetMessagesStreamProvider = StreamProvider.family<List<FleetMessageModel>, ({String companyId, String channelType})>((ref, params) {
  final repo = ref.watch(fleetChatRepositoryProvider);
  return repo.watchMessages(params.companyId, params.channelType);
});

class FleetChatRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  FleetChatRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  CollectionReference _messagesRef(String companyId) {
    return _firestore.collection('empresas').doc(companyId).collection('mensajes');
  }

  /// Escucha en tiempo real los últimos 35 mensajes del canal seleccionado
  /// Utiliza caché local offline-first de Firestore
  Stream<List<FleetMessageModel>> watchMessages(String companyId, String channelType) {
    if (companyId.isEmpty) return Stream.value([]);

    return _messagesRef(companyId)
        .where('channelType', isEqualTo: channelType)
        .orderBy('createdAt', descending: true)
        .limit(35)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => FleetMessageModel.fromFirestore(doc)).toList();
    });
  }

  /// Envía un mensaje de texto o estado rápido
  Future<void> sendTextMessage({
    required String companyId,
    required String channelType,
    required String senderId,
    required String senderName,
    required String senderRole,
    String? patente,
    String? activeDestination,
    required String content,
    MessageType type = MessageType.text,
    bool isUrgent = false,
  }) async {
    final message = FleetMessageModel(
      id: '',
      companyId: companyId,
      channelType: channelType,
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      patente: patente,
      activeDestination: activeDestination,
      type: type,
      content: content,
      isUrgent: isUrgent,
      readBy: [senderId],
      createdAt: DateTime.now(),
    );

    await _messagesRef(companyId).add(message.toFirestore());
  }

  /// Sube nota de voz Opus/M4A ultra-comprimida a Storage y crea el mensaje
  Future<void> sendAudioMessage({
    required String companyId,
    required String senderId,
    required String senderName,
    required String senderRole,
    String? patente,
    String? activeDestination,
    required File audioFile,
    required int durationSec,
  }) async {
    final fileName = 'PTT_${DateTime.now().millisecondsSinceEpoch}_$senderId.m4a';
    final ref = _storage.ref().child('empresas/$companyId/audios/$fileName');

    // Metadatos para auto-identificación y expiración
    final metadata = SettableMetadata(
      contentType: 'audio/m4a',
      customMetadata: {
        'senderId': senderId,
        'duration': durationSec.toString(),
      },
    );

    final uploadTask = await ref.putFile(audioFile, metadata);
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    final message = FleetMessageModel(
      id: '',
      companyId: companyId,
      channelType: 'fleet_chat',
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      patente: patente,
      activeDestination: activeDestination,
      type: MessageType.audio,
      content: downloadUrl,
      audioDurationSec: durationSec,
      readBy: [senderId],
      createdAt: DateTime.now(),
    );

    await _messagesRef(companyId).add(message.toFirestore());
  }

  /// Marca el aviso como leído sin lecturas adicionales (vía arrayUnion)
  Future<void> markAsRead(String companyId, String messageId, String userId) async {
    try {
      await _messagesRef(companyId).doc(messageId).update({
        'readBy': FieldValue.arrayUnion([userId]),
      });
    } catch (_) {
      // Ignorar si el doc ya fue purgado
    }
  }
}

