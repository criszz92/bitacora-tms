import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLogModel {
  final String id;
  final String idUsuario;
  final String nombreUsuario;
  final String idEmpresa;
  final String accion; // Ej: 'CIERRE_VIAJE', 'INICIO_JORNADA', 'REPORTE_INCIDENCIA'
  final String coleccion;
  final String documentoId;
  final Map<String, dynamic> detalles;
  final DateTime fecha;

  AuditLogModel({
    required this.id,
    required this.idUsuario,
    required this.nombreUsuario,
    required this.idEmpresa,
    required this.accion,
    required this.coleccion,
    required this.documentoId,
    required this.detalles,
    required this.fecha,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'idUsuario': idUsuario,
      'nombreUsuario': nombreUsuario,
      'idEmpresa': idEmpresa,
      'accion': accion,
      'coleccion': coleccion,
      'documentoId': documentoId,
      'detalles': detalles,
      'fecha': Timestamp.fromDate(fecha),
    };
  }
}
