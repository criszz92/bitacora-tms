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
  final String? vehicleId; // Patente o ID del vehículo asociado

  // --- CONTROL AVANZADO DE COMBUSTIBLE Y ESTANQUE DIGITAL ---
  final String? destinoCombustible; // 'CAMION' | 'AUXILIAR'
  final bool isFullTank;            // True si se llenó a tope (evento de calibración/cierre de ciclo)
  final double? odometerAtFill;     // Odómetro del camión al momento de la carga
  final double? horometroAtFill;    // Horómetro del generador/thermo al momento de la carga
  final double? kmRecorridosTramo;  // KM recorridos desde el último Full Tank (calculado)
  final double? rendimientoTramo;   // Km/L real obtenido en este ciclo (calculado)
  final double? litrosCargasIntermedias; // Litros parciales intermedios sumados al ciclo
  final double? onboardComputerL100km; // Lectura del computador a bordo (ej: 34.1 L/100km)
  final double? variacionComputadorPct; // % de diferencia (Real vs Computador a bordo)

  // --- TRATAMIENTO TRIBUTARIO CHILENO (EXENTO VS AFECTO) ---
  final bool isExento;              // True si el documento es Exento (ej. Peajes, arriendos s/IVA, romanas)
  final double? customIva;          // IVA específico informado en factura (útil para diésel con MEPCO)

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
    this.destinoCombustible = 'CAMION',
    this.isFullTank = false,
    this.odometerAtFill,
    this.horometroAtFill,
    this.kmRecorridosTramo,
    this.rendimientoTramo,
    this.litrosCargasIntermedias,
    this.onboardComputerL100km,
    this.variacionComputadorPct,
    this.isExento = false,
    this.customIva,
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
      'destinoCombustible': destinoCombustible,
      'isFullTank': isFullTank,
      'odometerAtFill': odometerAtFill,
      'horometroAtFill': horometroAtFill,
      'kmRecorridosTramo': kmRecorridosTramo,
      'rendimientoTramo': rendimientoTramo,
      'litrosCargasIntermedias': litrosCargasIntermedias,
      'onboardComputerL100km': onboardComputerL100km,
      'variacionComputadorPct': variacionComputadorPct,
      'isExento': isExento,
      'customIva': customIva,
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
      destinoCombustible: map['destinoCombustible'] ?? 'CAMION',
      isFullTank: map['isFullTank'] as bool? ?? false,
      odometerAtFill: (map['odometerAtFill'] as num?)?.toDouble(),
      horometroAtFill: (map['horometroAtFill'] as num?)?.toDouble(),
      kmRecorridosTramo: (map['kmRecorridosTramo'] as num?)?.toDouble(),
      rendimientoTramo: (map['rendimientoTramo'] as num?)?.toDouble(),
      litrosCargasIntermedias: (map['litrosCargasIntermedias'] as num?)?.toDouble(),
      onboardComputerL100km: (map['onboardComputerL100km'] as num?)?.toDouble(),
      variacionComputadorPct: (map['variacionComputadorPct'] as num?)?.toDouble(),
      isExento: map['isExento'] as bool? ?? (map['type']?.toString().toLowerCase() == 'peaje'),
      customIva: (map['customIva'] as num?)?.toDouble(),
    );
  }
}
