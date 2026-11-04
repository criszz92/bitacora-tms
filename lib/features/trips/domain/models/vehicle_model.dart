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
  final double? lastServiceOdometer; // KM en que se configuró el último servicio (punto de partida de la barra)
  final DateTime? rtExpirationDate; // Vencimiento Revisión Técnica
  final DateTime? soapExpirationDate; // Vencimiento SOAP
  final DateTime? permisoExpirationDate; // Vencimiento Permiso Circulación
  final double rendimientoKmPorLitro; // default: 2.5
  final String categoriaPeaje; // "camion_2_ejes" | "camion_mas_2_ejes"

  // --- CONTROL DE ESTANQUE DIGITAL & EQUIPOS AUXILIARES ---
  final double capacidadEstanqueLitros;     // Capacidad del estanque principal (ej. 600L)
  final bool tanqueCalibrado;               // True si ya se realizó el evento "Full Tank" inicial
  final double? ultimoLlenadoKm;            // Odómetro al momento del último Full Tank
  final DateTime? ultimoLlenadoFecha;       // Fecha del último Full Tank
  final double litrosReservaAlerta;         // Litros mínimos para encender alerta preventiva (ej. 120L)
  
  // Soporte Equipo Auxiliar (Genset / Thermo King / Under-slung)
  final bool tieneEquipoAuxiliar;           // True si tiene generador / thermo asignado
  final String? tipoEquipoAuxiliar;         // 'Genset', 'Thermo King', 'Carrier'
  final String? identificadorAuxiliar;      // Ej: 'GEN-04'
  final double? capacidadEstanqueAuxiliar;  // Capacidad estanque del generador (ej: 200L)
  final double consumoHoraAuxiliar;         // Litros/Hora esperados (ej: 2.5 L/h)
  final double? horometroActualAuxiliar;    // Horas acumuladas de motor del equipo de frío
  final double? ultimoLlenadoHorometroAux;  // Horómetro del último Full Tank del auxiliar

  // Soporte Ralentí & Cuidado de Turbo
  final double consumoRalentiLitrosHora;    // Consumo estimado con motor encendido detenido (default: 2.0 L/h)
  final int maxMinutosRalentiAlerta;        // Minutos máximos antes de encender alerta de ralentí excesivo (default: 20 min)

  // Costo de Desgaste de Mantenimiento por KM (Opcional, override por camión)
  final double? costoMantenimientoPorKm;    // Si es null, usa el valor global de la empresa ($49/km)

  VehicleModel({
    required this.id,
    required this.idEmpresa,
    required this.patente,
    this.marca,
    this.modelo,
    this.anio,
    this.currentOdometer = 0.0,
    this.nextOilChangeKm,
    this.lastServiceOdometer,
    this.rtExpirationDate,
    this.soapExpirationDate,
    this.permisoExpirationDate,
    this.rendimientoKmPorLitro = 2.5,
    this.categoriaPeaje = 'camion_mas_2_ejes',
    this.capacidadEstanqueLitros = 600.0,
    this.tanqueCalibrado = false,
    this.ultimoLlenadoKm,
    this.ultimoLlenadoFecha,
    this.litrosReservaAlerta = 120.0,
    this.tieneEquipoAuxiliar = false,
    this.tipoEquipoAuxiliar,
    this.identificadorAuxiliar,
    this.capacidadEstanqueAuxiliar,
    this.consumoHoraAuxiliar = 2.5,
    this.horometroActualAuxiliar,
    this.ultimoLlenadoHorometroAux,
    this.consumoRalentiLitrosHora = 2.0,
    this.maxMinutosRalentiAlerta = 20,
    this.costoMantenimientoPorKm,
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
      'lastServiceOdometer': lastServiceOdometer,
      'rtExpirationDate': rtExpirationDate?.toIso8601String(),
      'soapExpirationDate': soapExpirationDate?.toIso8601String(),
      'permisoExpirationDate': permisoExpirationDate?.toIso8601String(),
      'rendimientoKmPorLitro': rendimientoKmPorLitro,
      'categoriaPeaje': categoriaPeaje,
      'capacidadEstanqueLitros': capacidadEstanqueLitros,
      'tanqueCalibrado': tanqueCalibrado,
      'ultimoLlenadoKm': ultimoLlenadoKm,
      'ultimoLlenadoFecha': ultimoLlenadoFecha?.toIso8601String(),
      'litrosReservaAlerta': litrosReservaAlerta,
      'tieneEquipoAuxiliar': tieneEquipoAuxiliar,
      'tipoEquipoAuxiliar': tipoEquipoAuxiliar,
      'identificadorAuxiliar': identificadorAuxiliar,
      'capacidadEstanqueAuxiliar': capacidadEstanqueAuxiliar,
      'consumoHoraAuxiliar': consumoHoraAuxiliar,
      'horometroActualAuxiliar': horometroActualAuxiliar,
      'ultimoLlenadoHorometroAux': ultimoLlenadoHorometroAux,
      'consumoRalentiLitrosHora': consumoRalentiLitrosHora,
      'maxMinutosRalentiAlerta': maxMinutosRalentiAlerta,
      'costoMantenimientoPorKm': costoMantenimientoPorKm,
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
      lastServiceOdometer: (map['lastServiceOdometer'] as num?)?.toDouble(),
      rtExpirationDate: map['rtExpirationDate'] != null ? DateTime.parse(map['rtExpirationDate']) : null,
      soapExpirationDate: map['soapExpirationDate'] != null ? DateTime.parse(map['soapExpirationDate']) : null,
      permisoExpirationDate: map['permisoExpirationDate'] != null ? DateTime.parse(map['permisoExpirationDate']) : null,
      rendimientoKmPorLitro: (map['rendimientoKmPorLitro'] as num?)?.toDouble() ?? 2.5,
      categoriaPeaje: map['categoriaPeaje'] ?? 'camion_mas_2_ejes',
      capacidadEstanqueLitros: (map['capacidadEstanqueLitros'] as num?)?.toDouble() ?? 600.0,
      tanqueCalibrado: map['tanqueCalibrado'] as bool? ?? false,
      ultimoLlenadoKm: (map['ultimoLlenadoKm'] as num?)?.toDouble(),
      ultimoLlenadoFecha: map['ultimoLlenadoFecha'] != null ? DateTime.parse(map['ultimoLlenadoFecha']) : null,
      litrosReservaAlerta: (map['litrosReservaAlerta'] as num?)?.toDouble() ?? 120.0,
      tieneEquipoAuxiliar: map['tieneEquipoAuxiliar'] as bool? ?? false,
      tipoEquipoAuxiliar: map['tipoEquipoAuxiliar'],
      identificadorAuxiliar: map['identificadorAuxiliar'],
      capacidadEstanqueAuxiliar: (map['capacidadEstanqueAuxiliar'] as num?)?.toDouble(),
      consumoHoraAuxiliar: (map['consumoHoraAuxiliar'] as num?)?.toDouble() ?? 2.5,
      horometroActualAuxiliar: (map['horometroActualAuxiliar'] as num?)?.toDouble(),
      ultimoLlenadoHorometroAux: (map['ultimoLlenadoHorometroAux'] as num?)?.toDouble(),
      consumoRalentiLitrosHora: (map['consumoRalentiLitrosHora'] as num?)?.toDouble() ?? 2.0,
      maxMinutosRalentiAlerta: (map['maxMinutosRalentiAlerta'] as num?)?.toInt() ?? 20,
      costoMantenimientoPorKm: (map['costoMantenimientoPorKm'] as num?)?.toDouble(),
    );
  }

  VehicleModel copyWith({
    String? id,
    String? idEmpresa,
    String? patente,
    String? marca,
    String? modelo,
    int? anio,
    double? currentOdometer,
    double? nextOilChangeKm,
    double? lastServiceOdometer,
    DateTime? rtExpirationDate,
    DateTime? soapExpirationDate,
    DateTime? permisoExpirationDate,
    double? rendimientoKmPorLitro,
    String? categoriaPeaje,
    double? capacidadEstanqueLitros,
    bool? tanqueCalibrado,
    double? ultimoLlenadoKm,
    DateTime? ultimoLlenadoFecha,
    double? litrosReservaAlerta,
    bool? tieneEquipoAuxiliar,
    String? tipoEquipoAuxiliar,
    String? identificadorAuxiliar,
    double? capacidadEstanqueAuxiliar,
    double? consumoHoraAuxiliar,
    double? horometroActualAuxiliar,
    double? ultimoLlenadoHorometroAux,
    double? consumoRalentiLitrosHora,
    int? maxMinutosRalentiAlerta,
    double? costoMantenimientoPorKm,
  }) {
    return VehicleModel(
      id: id ?? this.id,
      idEmpresa: idEmpresa ?? this.idEmpresa,
      patente: patente ?? this.patente,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      anio: anio ?? this.anio,
      currentOdometer: currentOdometer ?? this.currentOdometer,
      nextOilChangeKm: nextOilChangeKm ?? this.nextOilChangeKm,
      lastServiceOdometer: lastServiceOdometer ?? this.lastServiceOdometer,
      rtExpirationDate: rtExpirationDate ?? this.rtExpirationDate,
      soapExpirationDate: soapExpirationDate ?? this.soapExpirationDate,
      permisoExpirationDate: permisoExpirationDate ?? this.permisoExpirationDate,
      rendimientoKmPorLitro: rendimientoKmPorLitro ?? this.rendimientoKmPorLitro,
      categoriaPeaje: categoriaPeaje ?? this.categoriaPeaje,
      capacidadEstanqueLitros: capacidadEstanqueLitros ?? this.capacidadEstanqueLitros,
      tanqueCalibrado: tanqueCalibrado ?? this.tanqueCalibrado,
      ultimoLlenadoKm: ultimoLlenadoKm ?? this.ultimoLlenadoKm,
      ultimoLlenadoFecha: ultimoLlenadoFecha ?? this.ultimoLlenadoFecha,
      litrosReservaAlerta: litrosReservaAlerta ?? this.litrosReservaAlerta,
      tieneEquipoAuxiliar: tieneEquipoAuxiliar ?? this.tieneEquipoAuxiliar,
      tipoEquipoAuxiliar: tipoEquipoAuxiliar ?? this.tipoEquipoAuxiliar,
      identificadorAuxiliar: identificadorAuxiliar ?? this.identificadorAuxiliar,
      capacidadEstanqueAuxiliar: capacidadEstanqueAuxiliar ?? this.capacidadEstanqueAuxiliar,
      consumoHoraAuxiliar: consumoHoraAuxiliar ?? this.consumoHoraAuxiliar,
      horometroActualAuxiliar: horometroActualAuxiliar ?? this.horometroActualAuxiliar,
      ultimoLlenadoHorometroAux: ultimoLlenadoHorometroAux ?? this.ultimoLlenadoHorometroAux,
      consumoRalentiLitrosHora: consumoRalentiLitrosHora ?? this.consumoRalentiLitrosHora,
      maxMinutosRalentiAlerta: maxMinutosRalentiAlerta ?? this.maxMinutosRalentiAlerta,
      costoMantenimientoPorKm: costoMantenimientoPorKm ?? this.costoMantenimientoPorKm,
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
