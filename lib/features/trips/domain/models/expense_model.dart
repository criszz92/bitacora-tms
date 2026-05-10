class ExpenseModel {
  final String id;
  final String idEmpresa;
  final String idChofer;
  final String idJornada;
  final String? tripId;
  final double amount;
  final String type;    // 'Peaje', 'Combustible'
  final double? litros; // Solo para Combustible (para calcular km/litro)
  final DateTime date;
  final String description;
  final String status;  // 'Pendiente', 'Rendido', 'Pagado'
  final String? vehicleId; // Patente del vehículo asociado

  ExpenseModel({
    required this.id,
    required this.idEmpresa,
    required this.idChofer,
    required this.idJornada,
    this.tripId,
    required this.amount,
    required this.type,
    this.litros,
    required this.date,
    required this.description,
    required this.status,
    this.vehicleId,
  });

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'idChofer': idChofer,
      'idJornada': idJornada,
      'tripId': tripId,
      'amount': amount,
      'type': type,
      'litros': litros,
      'date': date.toIso8601String(),
      'description': description,
      'status': status,
      'vehicleId': vehicleId,
    };
  }

  factory ExpenseModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ExpenseModel(
      id: documentId,
      idEmpresa: map['idEmpresa'] ?? '',
      idChofer: map['idChofer'] ?? '',
      idJornada: map['idJornada'] ?? '',
      tripId: map['tripId'],
      amount: map['amount']?.toDouble() ?? 0.0,
      type: map['type'] ?? '',
      litros: map['litros']?.toDouble(),
      date: DateTime.parse(map['date']),
      description: map['description'] ?? '',
      status: map['status'] ?? 'Pendiente',
      vehicleId: map['vehicleId'],
    );
  }
}
