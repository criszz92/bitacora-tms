import 'package:cloud_firestore/cloud_firestore.dart';

enum ServiceRequestStatus { pending, assigned, rejected }

class ServiceRequest {
  final String id;
  final String clientName;
  final String origin;
  final String destination;
  final String? loadType;
  final String rawText;
  final ServiceRequestStatus status;
  final DateTime createdAt;
  final Map<String, dynamic>? extractedData;

  ServiceRequest({
    required this.id,
    required this.clientName,
    required this.origin,
    required this.destination,
    this.loadType,
    required this.rawText,
    required this.status,
    required this.createdAt,
    this.extractedData,
  });

  factory ServiceRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ServiceRequest(
      id: doc.id,
      clientName: data['clientName'] ?? 'Desconocido',
      origin: data['origin'] ?? 'No especificado',
      destination: data['destination'] ?? 'No especificado',
      loadType: data['loadType'],
      rawText: data['rawText'] ?? '',
      status: ServiceRequestStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (data['status'] ?? 'pending'),
        orElse: () => ServiceRequestStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      extractedData: data['extractedData'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientName': clientName,
      'origin': origin,
      'destination': destination,
      'loadType': loadType,
      'rawText': rawText,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'extractedData': extractedData,
    };
  }
}
