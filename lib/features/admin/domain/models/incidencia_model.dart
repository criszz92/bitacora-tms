class IncidenciaModel {
  final String id;
  final String idEmpresa;
  final String vehicleId;
  final String vehiclePatente;
  final String idChofer;
  final String choferNombre;
  final String tipo; // 'Mecánica', 'Neumáticos', 'Documentos', 'Otros'
  final String descripcion;
  final DateTime fecha;
  final String estado; // 'Pendiente', 'En Taller', 'Solucionado'

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
    this.estado = 'Pendiente',
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
      'estado': estado,
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
      estado: map['estado'] ?? 'Pendiente',
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
    String? estado,
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
      estado: estado ?? this.estado,
    );
  }
}
