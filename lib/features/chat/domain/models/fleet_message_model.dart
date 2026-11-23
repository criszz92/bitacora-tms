import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  text,
  audio,
  broadcast,
  quickStatus,
}

class FleetMessageModel {
  final String id;
  final String companyId;
  final String channelType; // 'announcements' (Avisos) o 'fleet_chat' (Chat Flota)
  final String senderId;
  final String senderName;
  final String senderRole; // 'ADMIN' o 'DRIVER'
  final String? patente;
  final String? activeDestination; // Ej: 'FORSAC CHILLAN' o 'Puerto Coronel'
  final MessageType type;
  final String content; // Texto o URL de Storage para audio
  final int? audioDurationSec;
  final bool isUrgent;
  final List<String> readBy;
  final DateTime createdAt;

  FleetMessageModel({
    required this.id,
    required this.companyId,
    required this.channelType,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    this.patente,
    this.activeDestination,
    required this.type,
    required this.content,
    this.audioDurationSec,
    this.isUrgent = false,
    this.readBy = const [],
    required this.createdAt,
  });

  factory FleetMessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    MessageType parseType(String? val) {
      switch (val) {
        case 'audio':
          return MessageType.audio;
        case 'broadcast':
          return MessageType.broadcast;
        case 'quickStatus':
          return MessageType.quickStatus;
        default:
          return MessageType.text;
      }
    }

    return FleetMessageModel(
      id: doc.id,
      companyId: data['companyId'] ?? '',
      channelType: data['channelType'] ?? 'fleet_chat',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Anónimo',
      senderRole: data['senderRole'] ?? 'DRIVER',
      patente: data['patente'],
      activeDestination: data['activeDestination'],
      type: parseType(data['type']),
      content: data['content'] ?? '',
      audioDurationSec: data['audioDurationSec'],
      isUrgent: data['isUrgent'] ?? false,
      readBy: List<String>.from(data['readBy'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'companyId': companyId,
      'channelType': channelType,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'patente': patente,
      'activeDestination': activeDestination,
      'type': type.name,
      'content': content,
      'audioDurationSec': audioDurationSec,
      'isUrgent': isUrgent,
      'readBy': readBy,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

