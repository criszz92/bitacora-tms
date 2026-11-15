class TripModel {
  final String id;
  final String idEmpresa;       // Multitenancy
  final String idChofer;
  final String idJornada;
  final String origin;
  final String destination;
  final String status;          // 'En Ruta', 'Finalizado', 'Liquidada', 'Facturada', 'Pagada'
  final DateTime startDate;
  final DateTime? endDate;
  final String cargoType;       // 'completo' | 'porteo' | 'suelta'
  final String? containerNumber;
  final String? guideNumber;
  final String client;
  final String mandante;
  final double value;
  final String billingType;     // 'OS' (Ziyu) | 'OT' (Manual)
  final double? totalKm;        // Kilómetros recorridos en este viaje
  final String? bookingNumber;
  final String? vehicleId;     // Patente del vehículo asociado
  final String comments;        // Mantenido en modelo por retrocompatibilidad, no se muestra en UI
  final double? extraCostos;
  final double? sobreEstadia;
  final String? kmEditadoPor;   // UID del usuario que modificó totalKm por última vez
  final DateTime? kmEditadoEn;  // Timestamp de la última edición de totalKm
  final String? hitoActual;     // Hito operativo actual (ej: "En Antepuerto", "En Cliente", etc.)
  final List<Map<String, dynamic>>? hitos; // Historial de hitos registrados con timestamp
  final String tipoMovimiento;  // 'operativo' (default) | 'retiro_anticipado' | 'traslado_mantenimiento'
  final String? puntoDescarga;  // Puerto o Depósito final obligatorio de entrega
  final String? geocercaCarga;  // Geocerca ModoGPS del punto de carga (ej: "FORSAC_CHILLAN")
  final String? geocercaDescarga; // Geocerca ModoGPS del punto de descarga (ej: "PUERTO_CORONEL")
  final List<Map<String, dynamic>>? tramos; // Segmentación inteligente de la misión
  final List<String>? paradasIntermedias; // Paradas intermedias opcionales

  bool get isOperativo => tipoMovimiento == 'operativo';
  bool get isRetiroAnticipado => tipoMovimiento == 'retiro_anticipado';
  bool get isMantenimiento => tipoMovimiento == 'traslado_mantenimiento';
  bool get generaGanancia => isOperativo;

  /// Obtiene el índice del tramo actualmente en curso (o 0 por defecto)
  int get tramoActualIndex {
    if (tramos == null || tramos!.isEmpty) return 0;
    final idx = tramos!.indexWhere((t) => t['estado'] == 'en_ruta');
    return idx >= 0 ? idx : (tramos!.length - 1);
  }

  /// Retorna el tramo actualmente activo de la misión
  Map<String, dynamic>? get tramoActual {
    if (tramos == null || tramos!.isEmpty) return null;
    return tramos![tramoActualIndex];
  }

  bool get hasMultipleTramos => tramos != null && tramos!.length > 1;

  TripModel({
    required this.id,
    required this.idEmpresa,
    required this.idChofer,
    required this.idJornada,
    required this.origin,
    required this.destination,
    required this.status,
    required this.startDate,
    this.endDate,
    required this.cargoType,
    this.containerNumber,
    this.bookingNumber,
    this.guideNumber,
    required this.client,
    required this.mandante,
    required this.value,
    required this.billingType,
    this.totalKm,
    this.vehicleId,
    required this.comments,
    this.extraCostos,
    this.sobreEstadia,
    this.kmEditadoPor,
    this.kmEditadoEn,
    this.hitoActual,
    this.hitos,
    this.tipoMovimiento = 'operativo',
    this.puntoDescarga,
    this.geocercaCarga,
    this.geocercaDescarga,
    this.tramos,
    this.paradasIntermedias,
  });

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'idChofer': idChofer,
      'idJornada': idJornada,
      'origin': origin,
      'destination': destination,
      'status': status,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'cargoType': cargoType,
      'containerNumber': containerNumber,
      'bookingNumber': bookingNumber,
      'guideNumber': guideNumber,
      'client': client,
      'mandante': mandante,
      'value': value,
      'billingType': billingType,
      'totalKm': totalKm,
      'vehicleId': vehicleId,
      'comments': comments,
      'extraCostos': extraCostos,
      'sobreEstadia': sobreEstadia,
      'tipoMovimiento': tipoMovimiento,
      if (kmEditadoPor != null) 'kmEditadoPor': kmEditadoPor,
      if (kmEditadoEn != null) 'kmEditadoEn': kmEditadoEn!.toIso8601String(),
      if (hitoActual != null) 'hitoActual': hitoActual,
      if (hitos != null) 'hitos': hitos,
      if (puntoDescarga != null) 'puntoDescarga': puntoDescarga,
      if (geocercaCarga != null) 'geocercaCarga': geocercaCarga,
      if (geocercaDescarga != null) 'geocercaDescarga': geocercaDescarga,
      if (tramos != null) 'tramos': tramos,
      if (paradasIntermedias != null) 'paradasIntermedias': paradasIntermedias,
    };
  }

  factory TripModel.fromMap(Map<String, dynamic> map, String documentId) {
    return TripModel(
      id: documentId,
      idEmpresa: map['idEmpresa'] ?? '',
      idChofer: map['idChofer'] ?? '',
      idJornada: map['idJornada'] ?? '',
      origin: map['origin'] ?? '',
      destination: map['destination'] ?? '',
      status: map['status'] ?? '',
      startDate: DateTime.parse(map['startDate']),
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
      cargoType: map['cargoType'] ?? (map['containerNumber'] != null ? 'completo' : 'suelta'),
      containerNumber: map['containerNumber'],
      bookingNumber: map['bookingNumber'],
      guideNumber: map['guideNumber'],
      client: map['client'] ?? '',
      mandante: map['mandante'] ?? '',
      value: map['value']?.toDouble() ?? 0.0,
      billingType: map['billingType'] ?? 'OS',
      totalKm: map['totalKm']?.toDouble(),
      vehicleId: map['vehicleId'],
      comments: map['comments'] ?? '',
      extraCostos: map['extraCostos']?.toDouble(),
      sobreEstadia: map['sobreEstadia']?.toDouble(),
      kmEditadoPor: map['kmEditadoPor'],
      kmEditadoEn: map['kmEditadoEn'] != null ? DateTime.parse(map['kmEditadoEn']) : null,
      hitoActual: map['hitoActual'],
      hitos: map['hitos'] != null ? List<Map<String, dynamic>>.from(map['hitos']) : null,
      tipoMovimiento: map['tipoMovimiento'] ?? 'operativo',
      puntoDescarga: map['puntoDescarga'],
      geocercaCarga: map['geocercaCarga'],
      geocercaDescarga: map['geocercaDescarga'],
      tramos: map['tramos'] != null ? List<Map<String, dynamic>>.from(map['tramos']) : null,
      paradasIntermedias: map['paradasIntermedias'] != null ? List<String>.from(map['paradasIntermedias']) : null,
    );
  }

  TripModel copyWith({
    String? id,
    String? idEmpresa,
    String? idChofer,
    String? idJornada,
    String? origin,
    String? destination,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    String? cargoType,
    String? containerNumber,
    String? bookingNumber,
    String? guideNumber,
    String? client,
    String? mandante,
    double? value,
    String? billingType,
    double? totalKm,
    String? vehicleId,
    String? comments,
    double? extraCostos,
    double? sobreEstadia,
    String? kmEditadoPor,
    DateTime? kmEditadoEn,
    String? hitoActual,
    List<Map<String, dynamic>>? hitos,
    String? tipoMovimiento,
    String? puntoDescarga,
    String? geocercaCarga,
    String? geocercaDescarga,
    List<Map<String, dynamic>>? tramos,
    List<String>? paradasIntermedias,
  }) {
    return TripModel(
      id: id ?? this.id,
      idEmpresa: idEmpresa ?? this.idEmpresa,
      idChofer: idChofer ?? this.idChofer,
      idJornada: idJornada ?? this.idJornada,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      cargoType: cargoType ?? this.cargoType,
      containerNumber: containerNumber ?? this.containerNumber,
      bookingNumber: bookingNumber ?? this.bookingNumber,
      guideNumber: guideNumber ?? this.guideNumber,
      client: client ?? this.client,
      mandante: mandante ?? this.mandante,
      value: value ?? this.value,
      billingType: billingType ?? this.billingType,
      totalKm: totalKm ?? this.totalKm,
      vehicleId: vehicleId ?? this.vehicleId,
      comments: comments ?? this.comments,
      extraCostos: extraCostos ?? this.extraCostos,
      sobreEstadia: sobreEstadia ?? this.sobreEstadia,
      kmEditadoPor: kmEditadoPor ?? this.kmEditadoPor,
      kmEditadoEn: kmEditadoEn ?? this.kmEditadoEn,
      hitoActual: hitoActual ?? this.hitoActual,
      hitos: hitos ?? this.hitos,
      tipoMovimiento: tipoMovimiento ?? this.tipoMovimiento,
      puntoDescarga: puntoDescarga ?? this.puntoDescarga,
      geocercaCarga: geocercaCarga ?? this.geocercaCarga,
      geocercaDescarga: geocercaDescarga ?? this.geocercaDescarga,
      tramos: tramos ?? this.tramos,
      paradasIntermedias: paradasIntermedias ?? this.paradasIntermedias,
    );
  }
}
