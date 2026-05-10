class VehicleModel {
  final String id;
  final String idEmpresa; // Candado multi-empresa
  final String patente; // Formato: AB-CD-12 o ABCD12
  final String? marca;
  final String? modelo;
  final int? anio;

  // --- NUEVOS CAMPOS DE MANTENIMIENTO ---
  final double currentOdometer;    // Kilometraje actual del camión
  final double? nextOilChangeKm;   // KM objetivo para próximo cambio de aceite
  final DateTime? rtExpirationDate; // Vencimiento Revisión Técnica
  final DateTime? soapExpirationDate; // Vencimiento SOAP
  final DateTime? permisoExpirationDate; // Vencimiento Permiso Circulación

  VehicleModel({
    required this.id,
    required this.idEmpresa,
    required this.patente,
    this.marca,
    this.modelo,
    this.anio,
    this.currentOdometer = 0.0,
    this.nextOilChangeKm,
    this.rtExpirationDate,
    this.soapExpirationDate,
    this.permisoExpirationDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'patente': patente,
      'marca': marca,
      'modelo': modelo,
      'anio': anio,
      'currentOdometer': currentOdometer,
      'nextOilChangeKm': nextOilChangeKm,
      'rtExpirationDate': rtExpirationDate?.toIso8601String(),
      'soapExpirationDate': soapExpirationDate?.toIso8601String(),
      'permisoExpirationDate': permisoExpirationDate?.toIso8601String(),
    };
  }

  factory VehicleModel.fromMap(Map<String, dynamic> map, String documentId) {
    return VehicleModel(
      id: documentId,
      idEmpresa: map['idEmpresa'] ?? '',
      patente: map['patente'] ?? '',
      marca: map['marca'],
      modelo: map['modelo'],
      anio: map['anio'],
      currentOdometer: (map['currentOdometer'] as num?)?.toDouble() ?? 0.0,
      nextOilChangeKm: (map['nextOilChangeKm'] as num?)?.toDouble(),
      rtExpirationDate: map['rtExpirationDate'] != null ? DateTime.parse(map['rtExpirationDate']) : null,
      soapExpirationDate: map['soapExpirationDate'] != null ? DateTime.parse(map['soapExpirationDate']) : null,
      permisoExpirationDate: map['permisoExpirationDate'] != null ? DateTime.parse(map['permisoExpirationDate']) : null,
    );
  }

  /// Devuelve una cadena legible: "AB-CD-12 · Ford Cargo 2021"
  String get displayName {
    final detalles = [if (marca != null) marca, if (modelo != null) modelo, if (anio != null) anio.toString()];
    return detalles.isEmpty ? patente : '$patente · ${detalles.join(' ')}';
  }

  // --- LÓGICA DE ALERTAS DE DOCUMENTACIÓN ---

  /// Retorna una lista de documentos que vencen en menos de [days] días
  List<Map<String, dynamic>> getExpiringDocuments(int days) {
    final now = DateTime.now();
    final threshold = DateTime(now.year, now.month, now.day).add(Duration(days: days));
    List<Map<String, dynamic>> expiring = [];

    final docs = {
      'Revisión Técnica': rtExpirationDate,
      'SOAP': soapExpirationDate,
      'Permiso de Circulación': permisoExpirationDate,
    };

    docs.forEach((name, date) {
      if (date != null && date.isBefore(threshold)) {
        final remainingDays = date.difference(now).inDays;
        expiring.add({
          'nombre': name,
          'fecha': date,
          'diasRestantes': remainingDays,
          'esCritico': remainingDays <= 1,
        });
      }
    });

    return expiring;
  }

  bool get hasExpiringDocs => getExpiringDocuments(7).isNotEmpty;
}
