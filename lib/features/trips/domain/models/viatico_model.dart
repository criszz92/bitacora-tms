import '../../../../core/utils/tms_backbone.dart';
/// Modelo para la colección `viaticos` en Firestore.
/// Registra cada rendición enviada por un conductor, con su estado de pago.
class ViaticoModel {
  final String id;
  final String idChofer;
  final String idEmpresa;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String estado;    // 'pendiente' | 'pagado'
  final DateTime creadoEn;
  final double? montoTotal;
  final DateTime? fechaPago;

  ViaticoModel({
    required this.id,
    required this.idChofer,
    required this.idEmpresa,
    required this.fechaInicio,
    required this.fechaFin,
    required this.estado,
    required this.creadoEn,
    this.montoTotal,
    this.fechaPago,
  });

  bool get isPendiente => estado == 'pendiente';
  bool get isPagado => estado == 'pagado';

  Map<String, dynamic> toMap() {
    return {
      'idChofer': idChofer,
      'idEmpresa': idEmpresa,
      'fechaInicio': fechaInicio.toIso8601String(),
      'fechaFin': fechaFin.toIso8601String(),
      'estado': estado,
      'creadoEn': creadoEn.toIso8601String(),
      if (montoTotal != null) 'montoTotal': montoTotal,
      if (fechaPago != null) 'fechaPago': fechaPago!.toIso8601String(),
    };
  }

  factory ViaticoModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ViaticoModel(
      id: documentId,
      idChofer: map['idChofer'] ?? '',
      idEmpresa: map['idEmpresa'] ?? '',
      fechaInicio: TmsBackbone.parseDate(map['fechaInicio']),
      fechaFin: TmsBackbone.parseDate(map['fechaFin']),
      estado: map['estado'] ?? 'pendiente',
      creadoEn: TmsBackbone.parseDate(map['creadoEn']),
      montoTotal: (map['montoTotal'] as num?)?.toDouble(),
      fechaPago: map['fechaPago'] != null ? DateTime.parse(map['fechaPago']) : null,
    );
  }
}
