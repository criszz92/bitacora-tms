class InvitationModel {
  final String id;
  final String codigo;      // Ej: "BIT-7492"
  final String idEmpresa;  // La empresa a la que pertenece este código
  final bool usada;         // true cuando un chofer ya lo usó
  final DateTime creadaEn;
  final String? usadaPor;   // uid del chofer que lo usó (para auditoría)

  InvitationModel({
    required this.id,
    required this.codigo,
    required this.idEmpresa,
    required this.usada,
    required this.creadaEn,
    this.usadaPor,
  });

  Map<String, dynamic> toMap() {
    return {
      'codigo': codigo,
      'idEmpresa': idEmpresa,
      'usada': usada,
      'creadaEn': creadaEn.toIso8601String(),
      'usadaPor': usadaPor,
    };
  }

  factory InvitationModel.fromMap(Map<String, dynamic> map, String documentId) {
    return InvitationModel(
      id: documentId,
      codigo: map['codigo'] ?? '',
      idEmpresa: map['idEmpresa'] ?? '',
      usada: map['usada'] ?? false,
      creadaEn: DateTime.parse(map['creadaEn']),
      usadaPor: map['usadaPor'],
    );
  }
}
