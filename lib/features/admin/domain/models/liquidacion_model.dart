import 'package:cloud_firestore/cloud_firestore.dart';

class LiquidacionModel {
  final String id;
  final String idEmpresa;
  final double montoTotal;
  final int viajesCount;
  final String estado; // 'pendiente', 'facturada', 'pagada'
  final String? nroFactura;
  final String? referencia; // Título personalizado (ej: Nº de OS)
  final DateTime fechaCreacion;
  final DateTime? fechaPago;
  
  // Lista de IDs de los viajes (TripModel) que componen esta liquidación
  final List<String> tripIds;

  // Detalle del cruce Bitácora vs Ziyu para auditoría
  final List<Map<String, dynamic>>? detalleCruce;

  LiquidacionModel({
    required this.id,
    required this.idEmpresa,
    required this.montoTotal,
    required this.viajesCount,
    required this.estado,
    this.nroFactura,
    this.referencia,
    required this.fechaCreacion,
    this.fechaPago,
    required this.tripIds,
    this.detalleCruce,
  });

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'montoTotal': montoTotal,
      'viajesCount': viajesCount,
      'estado': estado,
      'nroFactura': nroFactura,
      'referencia': referencia,
      'fechaCreacion': Timestamp.fromDate(fechaCreacion),
      'fechaPago': fechaPago != null ? Timestamp.fromDate(fechaPago!) : null,
      'tripIds': tripIds,
      'detalleCruce': detalleCruce,
    };
  }

  factory LiquidacionModel.fromMap(Map<String, dynamic> map, String documentId) {
    return LiquidacionModel(
      id: documentId,
      idEmpresa: map['idEmpresa'] ?? '',
      montoTotal: (map['montoTotal'] as num?)?.toDouble() ?? 0.0,
      viajesCount: map['viajesCount'] ?? 0,
      estado: map['estado'] ?? 'pendiente',
      nroFactura: map['nroFactura'],
      referencia: map['referencia'],
      fechaCreacion: map['fechaCreacion'] is Timestamp 
          ? (map['fechaCreacion'] as Timestamp).toDate()
          : DateTime.parse(map['fechaCreacion'] ?? DateTime.now().toIso8601String()),
      fechaPago: map['fechaPago'] != null 
          ? (map['fechaPago'] is Timestamp ? (map['fechaPago'] as Timestamp).toDate() : DateTime.parse(map['fechaPago']))
          : null,
      tripIds: List<String>.from(map['tripIds'] ?? []),
      detalleCruce: map['detalleCruce'] != null 
          ? (map['detalleCruce'] as List).map((i) => Map<String, dynamic>.from(i)).toList()
          : null,
    );
  }
}
