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
    );
  }
}
