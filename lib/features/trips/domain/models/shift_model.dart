class ShiftModel {
  final String id;
  final String idEmpresa;
  final String idChofer;
  final String patenteCamion; // Qué camión se usa hoy
  final DateTime startTime;
  final DateTime? endTime;
  final int startOdometer;
  final int? endOdometer;
  final String status; // 'Activa', 'Cerrada'
  final double? tripsKm;
  final double? totalGpsKm;
  final double? unregisteredKm;
  final String? unregisteredReason;
  final double? odometerVariationPercent;

  int get deltaOdometer => (endOdometer != null && endOdometer! >= startOdometer)
      ? (endOdometer! - startOdometer)
      : 0;

  ShiftModel({
    required this.id,
    required this.idEmpresa,
    required this.idChofer,
    required this.patenteCamion,
    required this.startTime,
    this.endTime,
    required this.startOdometer,
    this.endOdometer,
    required this.status,
    this.tripsKm,
    this.totalGpsKm,
    this.unregisteredKm,
    this.unregisteredReason,
    this.odometerVariationPercent,
  });

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'idChofer': idChofer,
      'patenteCamion': patenteCamion,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'startOdometer': startOdometer,
      'endOdometer': endOdometer,
      'status': status,
      if (tripsKm != null) 'tripsKm': tripsKm,
      if (totalGpsKm != null) 'totalGpsKm': totalGpsKm,
      if (unregisteredKm != null) 'unregisteredKm': unregisteredKm,
      if (unregisteredReason != null) 'unregisteredReason': unregisteredReason,
      if (odometerVariationPercent != null) 'odometerVariationPercent': odometerVariationPercent,
    };
  }

  factory ShiftModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ShiftModel(
      id: documentId,
      idEmpresa: map['idEmpresa'] ?? '',
      idChofer: map['idChofer'] ?? '',
      patenteCamion: map['patenteCamion'] ?? '',
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      startOdometer: map['startOdometer']?.toInt() ?? 0,
      endOdometer: map['endOdometer']?.toInt(),
      status: map['status'] ?? 'Activa',
      tripsKm: (map['tripsKm'] as num?)?.toDouble(),
      totalGpsKm: (map['totalGpsKm'] as num?)?.toDouble(),
      unregisteredKm: (map['unregisteredKm'] as num?)?.toDouble(),
      unregisteredReason: map['unregisteredReason'] as String?,
      odometerVariationPercent: (map['odometerVariationPercent'] as num?)?.toDouble(),
    );
  }
}
