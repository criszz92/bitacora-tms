class IncidenciaModel {
  final String id;
  final String idEmpresa;
  final String vehicleId;
  final String vehiclePatente;
  final String idChofer;
  final String choferNombre;
  final String tipo; // 'Mecánica', 'Neumáticos', 'Documentos', 'Preventivo', 'Otros'
  final String descripcion;
  final DateTime fecha; // Fecha de inicio o reporte de la falla
  final DateTime? fechaIngresoTaller; // Fecha en que ingresó físicamente al taller
  final DateTime? fechaResolucion; // Fecha en que salió del taller / volvió a operar
  final String estado; // 'Pendiente', 'En Taller', 'Solucionado'
  final double? costoReparacion; // Monto real cobrado por taller o repuesto ($)
  final String? tallerProveedor; // Nombre del taller mecánico o repuestera
  final String? numeroFactura; // Número de factura o boleta de respaldo

  IncidenciaModel({
    required this.id,
    required this.idEmpresa,
    required this.vehicleId,
    required this.vehiclePatente,
    required this.idChofer,
    required this.choferNombre,
    required this.tipo,
    required this.descripcion,
    required this.fecha,
    this.fechaIngresoTaller,
    this.fechaResolucion,
    this.estado = 'Pendiente',
    this.costoReparacion,
    this.tallerProveedor,
    this.numeroFactura,
  });

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'vehicleId': vehicleId,
      'vehiclePatente': vehiclePatente,
      'idChofer': idChofer,
      'choferNombre': choferNombre,
      'tipo': tipo,
      'descripcion': descripcion,
      'fecha': fecha.toIso8601String(),
      if (fechaIngresoTaller != null) 'fechaIngresoTaller': fechaIngresoTaller!.toIso8601String(),
      if (fechaResolucion != null) 'fechaResolucion': fechaResolucion!.toIso8601String(),
      'estado': estado,
      if (costoReparacion != null) 'costoReparacion': costoReparacion,
      if (tallerProveedor != null) 'tallerProveedor': tallerProveedor,
      if (numeroFactura != null) 'numeroFactura': numeroFactura,
    };
  }

  factory IncidenciaModel.fromMap(Map<String, dynamic> map, String docId) {
    return IncidenciaModel(
      id: docId,
      idEmpresa: map['idEmpresa'] ?? '',
      vehicleId: map['vehicleId'] ?? '',
      vehiclePatente: map['vehiclePatente'] ?? '',
      idChofer: map['idChofer'] ?? '',
      choferNombre: map['choferNombre'] ?? '',
      tipo: map['tipo'] ?? 'Otros',
      descripcion: map['descripcion'] ?? '',
      fecha: DateTime.parse(map['fecha']),
      fechaIngresoTaller: map['fechaIngresoTaller'] != null ? DateTime.tryParse(map['fechaIngresoTaller']) : null,
      fechaResolucion: map['fechaResolucion'] != null ? DateTime.tryParse(map['fechaResolucion']) : null,
      estado: map['estado'] ?? 'Pendiente',
      costoReparacion: (map['costoReparacion'] as num?)?.toDouble(),
      tallerProveedor: map['tallerProveedor'],
      numeroFactura: map['numeroFactura'],
    );
  }

  IncidenciaModel copyWith({
    String? id,
    String? idEmpresa,
    String? vehicleId,
    String? vehiclePatente,
    String? idChofer,
    String? choferNombre,
    String? tipo,
    String? descripcion,
    DateTime? fecha,
    DateTime? fechaIngresoTaller,
    DateTime? fechaResolucion,
    String? estado,
    double? costoReparacion,
    String? tallerProveedor,
    String? numeroFactura,
  }) {
    return IncidenciaModel(
      id: id ?? this.id,
      idEmpresa: idEmpresa ?? this.idEmpresa,
      vehicleId: vehicleId ?? this.vehicleId,
      vehiclePatente: vehiclePatente ?? this.vehiclePatente,
      idChofer: idChofer ?? this.idChofer,
      choferNombre: choferNombre ?? this.choferNombre,
      tipo: tipo ?? this.tipo,
      descripcion: descripcion ?? this.descripcion,
      fecha: fecha ?? this.fecha,
      fechaIngresoTaller: fechaIngresoTaller ?? this.fechaIngresoTaller,
      fechaResolucion: fechaResolucion ?? this.fechaResolucion,
      estado: estado ?? this.estado,
      costoReparacion: costoReparacion ?? this.costoReparacion,
      tallerProveedor: tallerProveedor ?? this.tallerProveedor,
      numeroFactura: numeroFactura ?? this.numeroFactura,
    );
  }
}
