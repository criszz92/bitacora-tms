import 'package:cloud_firestore/cloud_firestore.dart';

class CotizacionModel {
  final String id;
  final String idEmpresa;
  final String origen;
  final String destino;
  final String vehicleId;
  final String vehiclePatente;
  final String idChofer;
  final String nombreChofer;
  final String numeroCotizacion;
  
  // Datos del Cliente
  final String clienteNombre;
  final String clienteRut;
  final String clienteContacto;
  
  // Inputs guardados
  final double kmPosicionamiento;
  final double kmRuta;
  final double tarifaPropuesta;
  final double precioDieselNeto;
  final double peajes;
  final double viaticoManual;
  final int diasViaje;
  final double margenObjetivo;

  // Resultados calculados guardados
  final double kmTotal;
  final double litrosConsumidos;
  final double combustibleNeto;
  final double combustibleBruto;
  final double comision;
  final double mantenimiento;
  final double costoFijoChofer;
  final double creditoIvaCombustible;
  final double recuperacionLey19764;
  final double ivaDebito;
  final double costoTotalReal;
  final double margenNetoReal;
  final double margenPorcentaje;
  final double cpk;
  final double tarifaMinimaSugerida;

  final bool idaYVuelta; // default false

  // Metadatos
  final String estado; // 'borrador' | 'enviada' | 'aceptada' | 'rechazada'
  final bool eliminada; // Soft delete flag
  final String creadoPor;
  final DateTime createdAt;

  CotizacionModel({
    required this.id,
    required this.idEmpresa,
    required this.origen,
    required this.destino,
    required this.vehicleId,
    required this.vehiclePatente,
    required this.idChofer,
    required this.nombreChofer,
    this.numeroCotizacion = '',
    this.clienteNombre = '',
    this.clienteRut = '',
    this.clienteContacto = '',
    required this.kmPosicionamiento,
    required this.kmRuta,
    required this.tarifaPropuesta,
    required this.precioDieselNeto,
    required this.peajes,
    required this.viaticoManual,
    required this.diasViaje,
    required this.margenObjetivo,
    required this.kmTotal,
    required this.litrosConsumidos,
    required this.combustibleNeto,
    required this.combustibleBruto,
    required this.comision,
    required this.mantenimiento,
    required this.costoFijoChofer,
    required this.creditoIvaCombustible,
    required this.recuperacionLey19764,
    required this.ivaDebito,
    required this.costoTotalReal,
    required this.margenNetoReal,
    required this.margenPorcentaje,
    required this.cpk,
    required this.tarifaMinimaSugerida,
    this.idaYVuelta = false,
    this.estado = 'borrador',
    this.eliminada = false,
    required this.creadoPor,
    required this.createdAt,
  });

  factory CotizacionModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    if (map['createdAt'] is Timestamp) {
      parsedDate = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is String) {
      parsedDate = DateTime.parse(map['createdAt']);
    } else {
      parsedDate = DateTime.now();
    }

    return CotizacionModel(
      id: id,
      idEmpresa: map['idEmpresa'] ?? '',
      origen: map['origen'] ?? '',
      destino: map['destino'] ?? '',
      vehicleId: map['vehicleId'] ?? '',
      vehiclePatente: map['vehiclePatente'] ?? '',
      idChofer: map['idChofer'] ?? '',
      nombreChofer: map['nombreChofer'] ?? '',
      numeroCotizacion: map['numeroCotizacion'] ?? '',
      clienteNombre: map['clienteNombre'] ?? '',
      clienteRut: map['clienteRut'] ?? '',
      clienteContacto: map['clienteContacto'] ?? '',
      kmPosicionamiento: (map['kmPosicionamiento'] as num?)?.toDouble() ?? 0.0,
      kmRuta: (map['kmRuta'] as num?)?.toDouble() ?? 0.0,
      tarifaPropuesta: (map['tarifaPropuesta'] as num?)?.toDouble() ?? 0.0,
      precioDieselNeto: (map['precioDieselNeto'] as num?)?.toDouble() ?? 0.0,
      peajes: (map['peajes'] as num?)?.toDouble() ?? 0.0,
      viaticoManual: (map['viaticoManual'] as num?)?.toDouble() ?? 0.0,
      diasViaje: (map['diasViaje'] as num?)?.toInt() ?? 1,
      margenObjetivo: (map['margenObjetivo'] as num?)?.toDouble() ?? 25.0,
      kmTotal: (map['kmTotal'] as num?)?.toDouble() ?? 0.0,
      litrosConsumidos: (map['litrosConsumidos'] as num?)?.toDouble() ?? 0.0,
      combustibleNeto: (map['combustibleNeto'] as num?)?.toDouble() ?? 0.0,
      combustibleBruto: (map['combustibleBruto'] as num?)?.toDouble() ?? 0.0,
      comision: (map['comision'] as num?)?.toDouble() ?? 0.0,
      mantenimiento: (map['mantenimiento'] as num?)?.toDouble() ?? 0.0,
      costoFijoChofer: (map['costoFijoChofer'] as num?)?.toDouble() ?? 0.0,
      creditoIvaCombustible: (map['creditoIvaCombustible'] as num?)?.toDouble() ?? 0.0,
      recuperacionLey19764: (map['recuperacionLey19764'] as num?)?.toDouble() ?? 0.0,
      ivaDebito: (map['ivaDebito'] as num?)?.toDouble() ?? 0.0,
      costoTotalReal: (map['costoTotalReal'] as num?)?.toDouble() ?? 0.0,
      margenNetoReal: (map['margenNetoReal'] as num?)?.toDouble() ?? 0.0,
      margenPorcentaje: (map['margenPorcentaje'] as num?)?.toDouble() ?? 0.0,
      cpk: (map['cpk'] as num?)?.toDouble() ?? 0.0,
      tarifaMinimaSugerida: (map['tarifaMinimaSugerida'] as num?)?.toDouble() ?? 0.0,
      idaYVuelta: map['idaYVuelta'] ?? false,
      estado: map['estado'] ?? 'borrador',
      eliminada: map['eliminada'] ?? false,
      creadoPor: map['creadoPor'] ?? '',
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'origen': origen,
      'destino': destino,
      'vehicleId': vehicleId,
      'vehiclePatente': vehiclePatente,
      'idChofer': idChofer,
      'nombreChofer': nombreChofer,
      'numeroCotizacion': numeroCotizacion,
      'clienteNombre': clienteNombre,
      'clienteRut': clienteRut,
      'clienteContacto': clienteContacto,
      'kmPosicionamiento': kmPosicionamiento,
      'kmRuta': kmRuta,
      'tarifaPropuesta': tarifaPropuesta,
      'precioDieselNeto': precioDieselNeto,
      'peajes': peajes,
      'viaticoManual': viaticoManual,
      'diasViaje': diasViaje,
      'margenObjetivo': margenObjetivo,
      'kmTotal': kmTotal,
      'litrosConsumidos': litrosConsumidos,
      'combustibleNeto': combustibleNeto,
      'combustibleBruto': combustibleBruto,
      'comision': comision,
      'mantenimiento': mantenimiento,
      'costoFijoChofer': costoFijoChofer,
      'creditoIvaCombustible': creditoIvaCombustible,
      'recuperacionLey19764': recuperacionLey19764,
      'ivaDebito': ivaDebito,
      'costoTotalReal': costoTotalReal,
      'margenNetoReal': margenNetoReal,
      'margenPorcentaje': margenPorcentaje,
      'cpk': cpk,
      'tarifaMinimaSugerida': tarifaMinimaSugerida,
      'idaYVuelta': idaYVuelta,
      'estado': estado,
      'eliminada': eliminada,
      'creadoPor': creadoPor,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  CotizacionModel copyWith({
    String? id,
    String? idEmpresa,
    String? origen,
    String? destino,
    String? vehicleId,
    String? vehiclePatente,
    String? idChofer,
    String? nombreChofer,
    String? numeroCotizacion,
    String? clienteNombre,
    String? clienteRut,
    String? clienteContacto,
    double? kmPosicionamiento,
    double? kmRuta,
    double? tarifaPropuesta,
    double? precioDieselNeto,
    double? peajes,
    double? viaticoManual,
    int? diasViaje,
    double? margenObjetivo,
    double? kmTotal,
    double? litrosConsumidos,
    double? combustibleNeto,
    double? combustibleBruto,
    double? comision,
    double? mantenimiento,
    double? costoFijoChofer,
    double? creditoIvaCombustible,
    double? recuperacionLey19764,
    double? ivaDebito,
    double? costoTotalReal,
    double? margenNetoReal,
    double? margenPorcentaje,
    double? cpk,
    double? tarifaMinimaSugerida,
    bool? idaYVuelta,
    String? estado,
    bool? eliminada,
    String? creadoPor,
    DateTime? createdAt,
  }) {
    return CotizacionModel(
      id: id ?? this.id,
      idEmpresa: idEmpresa ?? this.idEmpresa,
      origen: origen ?? this.origen,
      destino: destino ?? this.destino,
      vehicleId: vehicleId ?? this.vehicleId,
      vehiclePatente: vehiclePatente ?? this.vehiclePatente,
      idChofer: idChofer ?? this.idChofer,
      nombreChofer: nombreChofer ?? this.nombreChofer,
      numeroCotizacion: numeroCotizacion ?? this.numeroCotizacion,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      clienteRut: clienteRut ?? this.clienteRut,
      clienteContacto: clienteContacto ?? this.clienteContacto,
      kmPosicionamiento: kmPosicionamiento ?? this.kmPosicionamiento,
      kmRuta: kmRuta ?? this.kmRuta,
      tarifaPropuesta: tarifaPropuesta ?? this.tarifaPropuesta,
      precioDieselNeto: precioDieselNeto ?? this.precioDieselNeto,
      peajes: peajes ?? this.peajes,
      viaticoManual: viaticoManual ?? this.viaticoManual,
      diasViaje: diasViaje ?? this.diasViaje,
      margenObjetivo: margenObjetivo ?? this.margenObjetivo,
      kmTotal: kmTotal ?? this.kmTotal,
      litrosConsumidos: litrosConsumidos ?? this.litrosConsumidos,
      combustibleNeto: combustibleNeto ?? this.combustibleNeto,
      combustibleBruto: combustibleBruto ?? this.combustibleBruto,
      comision: comision ?? this.comision,
      mantenimiento: mantenimiento ?? this.mantenimiento,
      costoFijoChofer: costoFijoChofer ?? this.costoFijoChofer,
      creditoIvaCombustible: creditoIvaCombustible ?? this.creditoIvaCombustible,
      recuperacionLey19764: recuperacionLey19764 ?? this.recuperacionLey19764,
      ivaDebito: ivaDebito ?? this.ivaDebito,
      costoTotalReal: costoTotalReal ?? this.costoTotalReal,
      margenNetoReal: margenNetoReal ?? this.margenNetoReal,
      margenPorcentaje: margenPorcentaje ?? this.margenPorcentaje,
      cpk: cpk ?? this.cpk,
      tarifaMinimaSugerida: tarifaMinimaSugerida ?? this.tarifaMinimaSugerida,
      idaYVuelta: idaYVuelta ?? this.idaYVuelta,
      estado: estado ?? this.estado,
      eliminada: eliminada ?? this.eliminada,
      creadoPor: creadoPor ?? this.creadoPor,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
