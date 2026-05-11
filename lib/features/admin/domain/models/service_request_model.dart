import 'package:cloud_firestore/cloud_firestore.dart';

enum ServiceRequestStatus { pending, assigned, rejected, completed }

class ServiceRequest {
  final String id;
  final String clientName;
  final String origin;
  final String destination;
  final String? loadType;
  final String? bookingNumber;
  final String rawText;
  final ServiceRequestStatus status;
  final DateTime createdAt;
  final String? assignedTo;
  final String? assignedToName;
  final double? proposedValue;
  final DateTime? assignedAt;
  final Map<String, dynamic>? extractedData;

  ServiceRequest({
    required this.id,
    required this.clientName,
    required this.origin,
    required this.destination,
    this.loadType,
    this.bookingNumber,
    required this.rawText,
    required this.status,
    required this.createdAt,
    this.assignedTo,
    this.assignedToName,
    this.proposedValue,
    this.assignedAt,
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
      bookingNumber: data['bookingNumber'] ?? data['booking'], // Soporte para ambos nombres
      rawText: data['rawText'] ?? '',
      status: ServiceRequestStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (data['status'] ?? 'pending'),
        orElse: () => ServiceRequestStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      assignedTo: data['assignedTo'],
      assignedToName: data['assignedToName'],
      proposedValue: (data['proposedValue'] as num?)?.toDouble(),
      assignedAt: data['assignedAt'] != null ? (data['assignedAt'] as Timestamp).toDate() : null,
      extractedData: data['extractedData'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientName': clientName,
      'origin': origin,
      'destination': destination,
      'loadType': loadType,
      'bookingNumber': bookingNumber,
      'rawText': rawText,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'proposedValue': proposedValue,
      if (assignedAt != null) 'assignedAt': Timestamp.fromDate(assignedAt!),
      'extractedData': extractedData,
    };
  }
}
