import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Clasificación de la infraestructura vial para transporte de carga
enum TipoPuntoInfraestructura {
  peaje,
  romana,
  restriccion,
  descanso,
}

extension TipoPuntoInfraestructuraExtension on TipoPuntoInfraestructura {
  String get label {
    switch (this) {
      case TipoPuntoInfraestructura.peaje:
        return 'Peaje';
      case TipoPuntoInfraestructura.romana:
        return 'Romana / Pesaje';
      case TipoPuntoInfraestructura.restriccion:
        return 'Restricción';
      case TipoPuntoInfraestructura.descanso:
        return 'Área de Descanso';
    }
  }

  String get code {
    switch (this) {
      case TipoPuntoInfraestructura.peaje:
        return 'peaje';
      case TipoPuntoInfraestructura.romana:
        return 'romana';
      case TipoPuntoInfraestructura.restriccion:
        return 'restriccion';
      case TipoPuntoInfraestructura.descanso:
        return 'descanso';
    }
  }

  static TipoPuntoInfraestructura fromCode(String code) {
    switch (code.toLowerCase()) {
      case 'peaje':
        return TipoPuntoInfraestructura.peaje;
      case 'romana':
      case 'pesaje':
        return TipoPuntoInfraestructura.romana;
      case 'restriccion':
        return TipoPuntoInfraestructura.restriccion;
      case 'descanso':
        return TipoPuntoInfraestructura.descanso;
      default:
        return TipoPuntoInfraestructura.peaje;
    }
  }
}

/// Modelo universal para representar infraestructura vial en Chile
/// Compartido por todos los tenants (empresas) de Bitácora TMS
class PuntoInfraestructuraModel {
  final String id;
  final String nombre;
  final TipoPuntoInfraestructura tipo;
  final String subtipo; // ej: 'Troncal', 'Pórtico TAG', 'Lateral', 'Pesaje Fijo', 'Paso Bajo Nivel'
  final String ruta; // ej: 'Ruta 148', 'Ruta 5 Sur', 'Autopista del Itata'
  final double? km;
  final double lat;
  final double lng;
  final double radioMetros; // Radio de detección para geocerca virtual
  final String sentido; // 'Norte-Sur', 'Sur-Norte', 'Oriente-Poniente', 'Poniente-Oriente', 'Bidireccional'

  // ─── Atributos para Peajes ──────────────────────────────────────────────
  final double? tarifaCamionSimple; // Camión 2 ejes
  final double? tarifaCamionPesado; // Camión > 2 ejes con semirremolque
  final bool admiteTag;
  final String? concesionaria;

  // ─── Atributos para Romanas ─────────────────────────────────────────────
  final String? entidadFiscalizadora; // 'MOP / Dirección de Vialidad', 'Carabineros'
  final String? pistaObligatoria; // 'Pista Derecha', 'Todas'

  // ─── Atributos para Restricciones ───────────────────────────────────────
  final double? alturaMaximaMetros; // Gálibo máximo (puentes, pasos bajo nivel)
  final double? pesoMaximoToneladas; // Peso Bruto Vehicular máximo
  final String? horarioRestriccion; // Franja horaria restringida
  final bool permiteCargasPeligrosas;

  // ─── Atributos para Áreas de Descanso ───────────────────────────────────
  final int? capacidadCamiones;
  final bool tieneDuchas;
  final bool tieneSeguridad;
  final bool combustibleAltoFlujo;

  // ─── Gobernanza y Auditoría ─────────────────────────────────────────────
  final String creadoPor;
  final DateTime createdAt;
  final DateTime? actualizadoEn;
  final bool activo;
  final String origenDato; // 'maestro', 'mop_oficial', 'reporte_comunitario'

  LatLng get position => LatLng(lat, lng);

  PuntoInfraestructuraModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.subtipo = 'General',
    this.ruta = '',
    this.km,
    required this.lat,
    required this.lng,
    this.radioMetros = 100.0,
    this.sentido = 'Bidireccional',
    this.tarifaCamionSimple,
    this.tarifaCamionPesado,
    this.admiteTag = false,
    this.concesionaria,
    this.entidadFiscalizadora,
    this.pistaObligatoria,
    this.alturaMaximaMetros,
    this.pesoMaximoToneladas,
    this.horarioRestriccion,
    this.permiteCargasPeligrosas = true,
    this.capacidadCamiones,
    this.tieneDuchas = false,
    this.tieneSeguridad = false,
    this.combustibleAltoFlujo = false,
    required this.creadoPor,
    required this.createdAt,
    this.actualizadoEn,
    this.activo = true,
    this.origenDato = 'maestro',
  });

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'tipo': tipo.code,
      'subtipo': subtipo,
      'ruta': ruta,
      'km': km,
      'lat': lat,
      'lng': lng,
      'radioMetros': radioMetros,
      'sentido': sentido,
      if (tarifaCamionSimple != null) 'tarifaCamionSimple': tarifaCamionSimple,
      if (tarifaCamionPesado != null) 'tarifaCamionPesado': tarifaCamionPesado,
      'admiteTag': admiteTag,
      if (concesionaria != null) 'concesionaria': concesionaria,
      if (entidadFiscalizadora != null) 'entidadFiscalizadora': entidadFiscalizadora,
      if (pistaObligatoria != null) 'pistaObligatoria': pistaObligatoria,
      if (alturaMaximaMetros != null) 'alturaMaximaMetros': alturaMaximaMetros,
      if (pesoMaximoToneladas != null) 'pesoMaximoToneladas': pesoMaximoToneladas,
      if (horarioRestriccion != null) 'horarioRestriccion': horarioRestriccion,
      'permiteCargasPeligrosas': permiteCargasPeligrosas,
      if (capacidadCamiones != null) 'capacidadCamiones': capacidadCamiones,
      'tieneDuchas': tieneDuchas,
      'tieneSeguridad': tieneSeguridad,
      'combustibleAltoFlujo': combustibleAltoFlujo,
      'creadoPor': creadoPor,
      'createdAt': Timestamp.fromDate(createdAt),
      if (actualizadoEn != null) 'actualizadoEn': Timestamp.fromDate(actualizadoEn!),
      'activo': activo,
      'origenDato': origenDato,
    };
  }

  factory PuntoInfraestructuraModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return PuntoInfraestructuraModel(
      id: id,
      nombre: map['nombre'] ?? '',
      tipo: TipoPuntoInfraestructuraExtension.fromCode(map['tipo'] ?? 'peaje'),
      subtipo: map['subtipo'] ?? 'General',
      ruta: map['ruta'] ?? '',
      km: (map['km'] as num?)?.toDouble(),
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      radioMetros: (map['radioMetros'] as num?)?.toDouble() ?? 100.0,
      sentido: map['sentido'] ?? 'Bidireccional',
      tarifaCamionSimple: (map['tarifaCamionSimple'] as num?)?.toDouble(),
      tarifaCamionPesado: (map['tarifaCamionPesado'] as num?)?.toDouble(),
      admiteTag: map['admiteTag'] == true,
      concesionaria: map['concesionaria'],
      entidadFiscalizadora: map['entidadFiscalizadora'],
      pistaObligatoria: map['pistaObligatoria'],
      alturaMaximaMetros: (map['alturaMaximaMetros'] as num?)?.toDouble(),
      pesoMaximoToneladas: (map['pesoMaximoToneladas'] as num?)?.toDouble(),
      horarioRestriccion: map['horarioRestriccion'],
      permiteCargasPeligrosas: map['permiteCargasPeligrosas'] ?? true,
      capacidadCamiones: (map['capacidadCamiones'] as num?)?.toInt(),
      tieneDuchas: map['tieneDuchas'] == true,
      tieneSeguridad: map['tieneSeguridad'] == true,
      combustibleAltoFlujo: map['combustibleAltoFlujo'] == true,
      creadoPor: map['creadoPor'] ?? '',
      createdAt: parseTimestamp(map['createdAt']),
      actualizadoEn: map['actualizadoEn'] != null ? parseTimestamp(map['actualizadoEn']) : null,
      activo: map['activo'] ?? true,
      origenDato: map['origenDato'] ?? 'maestro',
    );
  }

  PuntoInfraestructuraModel copyWith({
    String? nombre,
    TipoPuntoInfraestructura? tipo,
    String? subtipo,
    String? ruta,
    double? km,
    double? lat,
    double? lng,
    double? radioMetros,
    String? sentido,
    double? tarifaCamionSimple,
    double? tarifaCamionPesado,
    bool? admiteTag,
    String? concesionaria,
    String? entidadFiscalizadora,
    String? pistaObligatoria,
    double? alturaMaximaMetros,
    double? pesoMaximoToneladas,
    String? horarioRestriccion,
    bool? permiteCargasPeligrosas,
    int? capacidadCamiones,
    bool? tieneDuchas,
    bool? tieneSeguridad,
    bool? combustibleAltoFlujo,
    bool? activo,
    String? origenDato,
  }) {
    return PuntoInfraestructuraModel(
      id: id,
      nombre: nombre ?? this.nombre,
      tipo: tipo ?? this.tipo,
      subtipo: subtipo ?? this.subtipo,
      ruta: ruta ?? this.ruta,
      km: km ?? this.km,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radioMetros: radioMetros ?? this.radioMetros,
      sentido: sentido ?? this.sentido,
      tarifaCamionSimple: tarifaCamionSimple ?? this.tarifaCamionSimple,
      tarifaCamionPesado: tarifaCamionPesado ?? this.tarifaCamionPesado,
      admiteTag: admiteTag ?? this.admiteTag,
      concesionaria: concesionaria ?? this.concesionaria,
      entidadFiscalizadora: entidadFiscalizadora ?? this.entidadFiscalizadora,
      pistaObligatoria: pistaObligatoria ?? this.pistaObligatoria,
      alturaMaximaMetros: alturaMaximaMetros ?? this.alturaMaximaMetros,
      pesoMaximoToneladas: pesoMaximoToneladas ?? this.pesoMaximoToneladas,
      horarioRestriccion: horarioRestriccion ?? this.horarioRestriccion,
      permiteCargasPeligrosas: permiteCargasPeligrosas ?? this.permiteCargasPeligrosas,
      capacidadCamiones: capacidadCamiones ?? this.capacidadCamiones,
      tieneDuchas: tieneDuchas ?? this.tieneDuchas,
      tieneSeguridad: tieneSeguridad ?? this.tieneSeguridad,
      combustibleAltoFlujo: combustibleAltoFlujo ?? this.combustibleAltoFlujo,
      creadoPor: creadoPor,
      createdAt: createdAt,
      actualizadoEn: DateTime.now(),
      activo: activo ?? this.activo,
      origenDato: origenDato ?? this.origenDato,
    );
  }
}
