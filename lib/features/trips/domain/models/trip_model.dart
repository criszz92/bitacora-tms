class TripModel {
  final String id;
  final String idEmpresa;       // Multitenancy
  final String idChofer;
  final String idJornada;
  final String origin;
  final String destination;
  final String status;          // 'En Ruta', 'Finalizado', 'Liquidada', 'Facturada', 'Pagada'
  final DateTime startDate;
  final DateTime? endDate;
  final String cargoType;       // 'completo' | 'porteo' | 'suelta'
  final String? containerNumber;
  final String? guideNumber;
  final String client;
  final String mandante;
  final double value;
  final String billingType;     // 'OS' (Ziyu) | 'OT' (Manual)
  final double? totalKm;        // Kilómetros recorridos en este viaje
  final String? bookingNumber;
  final String? vehicleId;     // Patente del vehículo asociado
  final String comments;        // Mantenido en modelo por retrocompatibilidad, no se muestra en UI
  final double? extraCostos;
  final double? sobreEstadia;
  final String? kmEditadoPor;   // UID del usuario que modificó totalKm por última vez
  final DateTime? kmEditadoEn;  // Timestamp de la última edición de totalKm

  TripModel({
    required this.id,
    required this.idEmpresa,
    required this.idChofer,
    required this.idJornada,
    required this.origin,
    required this.destination,
    required this.status,
    required this.startDate,
    this.endDate,
    required this.cargoType,
    this.containerNumber,
    this.bookingNumber,
    this.guideNumber,
    required this.client,
    required this.mandante,
    required this.value,
    required this.billingType,
    this.totalKm,
    this.vehicleId,
    required this.comments,
    this.extraCostos,
    this.sobreEstadia,
    this.kmEditadoPor,
    this.kmEditadoEn,
  });

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'idChofer': idChofer,
      'idJornada': idJornada,
      'origin': origin,
      'destination': destination,
      'status': status,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'cargoType': cargoType,
      'containerNumber': containerNumber,
      'bookingNumber': bookingNumber,
      'guideNumber': guideNumber,
      'client': client,
      'mandante': mandante,
      'value': value,
      'billingType': billingType,
      'totalKm': totalKm,
      'vehicleId': vehicleId,
      'comments': comments,
      'extraCostos': extraCostos,
      'sobreEstadia': sobreEstadia,
      if (kmEditadoPor != null) 'kmEditadoPor': kmEditadoPor,
      if (kmEditadoEn != null) 'kmEditadoEn': kmEditadoEn!.toIso8601String(),
    };
  }

  factory TripModel.fromMap(Map<String, dynamic> map, String documentId) {
    return TripModel(
      id: documentId,
      idEmpresa: map['idEmpresa'] ?? '',
      idChofer: map['idChofer'] ?? '',
      idJornada: map['idJornada'] ?? '',
      origin: map['origin'] ?? '',
      destination: map['destination'] ?? '',
      status: map['status'] ?? '',
      startDate: DateTime.parse(map['startDate']),
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
      cargoType: map['cargoType'] ?? (map['containerNumber'] != null ? 'completo' : 'suelta'),
      containerNumber: map['containerNumber'],
      bookingNumber: map['bookingNumber'],
      guideNumber: map['guideNumber'],
      client: map['client'] ?? '',
      mandante: map['mandante'] ?? '',
      value: map['value']?.toDouble() ?? 0.0,
      billingType: map['billingType'] ?? 'OS',
      totalKm: map['totalKm']?.toDouble(),
      vehicleId: map['vehicleId'],
      comments: map['comments'] ?? '',
      extraCostos: map['extraCostos']?.toDouble(),
      sobreEstadia: map['sobreEstadia']?.toDouble(),
      kmEditadoPor: map['kmEditadoPor'],
      kmEditadoEn: map['kmEditadoEn'] != null ? DateTime.parse(map['kmEditadoEn']) : null,
    );
  }

  TripModel copyWith({
    String? id,
    String? idEmpresa,
    String? idChofer,
    String? idJornada,
    String? origin,
    String? destination,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    String? cargoType,
    String? containerNumber,
    String? bookingNumber,
    String? guideNumber,
    String? client,
    String? mandante,
    double? value,
    String? billingType,
    double? totalKm,
    String? vehicleId,
    String? comments,
    double? extraCostos,
    double? sobreEstadia,
    String? kmEditadoPor,
    DateTime? kmEditadoEn,
  }) {
    return TripModel(
      id: id ?? this.id,
      idEmpresa: idEmpresa ?? this.idEmpresa,
      idChofer: idChofer ?? this.idChofer,
      idJornada: idJornada ?? this.idJornada,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      cargoType: cargoType ?? this.cargoType,
      containerNumber: containerNumber ?? this.containerNumber,
      bookingNumber: bookingNumber ?? this.bookingNumber,
      guideNumber: guideNumber ?? this.guideNumber,
      client: client ?? this.client,
      mandante: mandante ?? this.mandante,
      value: value ?? this.value,
      billingType: billingType ?? this.billingType,
      totalKm: totalKm ?? this.totalKm,
      vehicleId: vehicleId ?? this.vehicleId,
      comments: comments ?? this.comments,
      extraCostos: extraCostos ?? this.extraCostos,
      sobreEstadia: sobreEstadia ?? this.sobreEstadia,
      kmEditadoPor: kmEditadoPor ?? this.kmEditadoPor,
      kmEditadoEn: kmEditadoEn ?? this.kmEditadoEn,
    );
  }
}
