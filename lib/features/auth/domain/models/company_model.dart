class CompanyModel {
  final String id;       // mismo valor que idEmpresa (slug auto-generado)
  final String nombre;   // "Transportes Inostroza SpA"
  final String idAdmin;  // uid del administrador que la creó
  final DateTime creadaEn;

  CompanyModel({
    required this.id,
    required this.nombre,
    required this.idAdmin,
    required this.creadaEn,
  });

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'idAdmin': idAdmin,
      'creadaEn': creadaEn.toIso8601String(),
    };
  }

  factory CompanyModel.fromMap(Map<String, dynamic> map, String documentId) {
    return CompanyModel(
      id: documentId,
      nombre: map['nombre'] ?? '',
      idAdmin: map['idAdmin'] ?? '',
      creadaEn: DateTime.parse(map['creadaEn']),
    );
  }
}
