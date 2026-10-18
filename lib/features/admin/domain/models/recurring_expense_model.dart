/// Modelo para gastos fijos recurrentes (plantillas).
/// Se almacenan en la configuración de la empresa y se aplican mensualmente.
class RecurringExpenseModel {
  final String id;           // UUID generado al crear
  final String nombre;       // Ej: "GPS ModoGPS", "Seguro de Carga"
  final String tipo;         // Tipo de gasto: Seguro, GPS, Arriendo, Leasing, etc.
  final double monto;        // Monto fijo mensual (bruto con IVA)
  final String? vehicleId;   // null = gasto general, con ID = asignado a vehículo
  final bool activo;         // Para desactivar sin eliminar

  RecurringExpenseModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.monto,
    this.vehicleId,
    this.activo = true,
  });

  factory RecurringExpenseModel.fromMap(Map<String, dynamic> map) {
    return RecurringExpenseModel(
      id: map['id'] ?? '',
      nombre: map['nombre'] ?? '',
      tipo: map['tipo'] ?? 'Otros',
      monto: (map['monto'] as num?)?.toDouble() ?? 0.0,
      vehicleId: map['vehicleId'],
      activo: map['activo'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'tipo': tipo,
      'monto': monto,
      'vehicleId': vehicleId,
      'activo': activo,
    };
  }

  RecurringExpenseModel copyWith({
    String? id,
    String? nombre,
    String? tipo,
    double? monto,
    String? vehicleId,
    bool? activo,
    bool clearVehicle = false,
  }) {
    return RecurringExpenseModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      tipo: tipo ?? this.tipo,
      monto: monto ?? this.monto,
      vehicleId: clearVehicle ? null : (vehicleId ?? this.vehicleId),
      activo: activo ?? this.activo,
    );
  }
}
