class UserModel {
  final String uid;
  final String idEmpresa; // El núcleo del Multi-tenant (Aislamiento de datos)
  final String email;
  final String nombre;
  final String rol; // 'ADMIN' o 'CHOFER'

  // Perfil Extendido (Conductores)
  final String? rut;
  final List<String>? licencias;
  final double? sueldoBase;
  final String? tipoContrato; // 'Indefinido', 'Plazo Fijo'
  final double? montoViaticoLocal;
  final double? montoViaticoLargo;
  
  // Parámetros Previsionales
  final double? tasaAFP;
  final double? tasaSalud;
  final String? baseImponible; // 'Total' o 'Sueldo Base'
  final bool? empresaAsumeLeyes; // Sueldo Líquido Pactado
  
  // Toggles de configuración de pagos
  final Map<String, bool>? configuracionPagos;
  final String? patenteAsignada;
  final String? fcmToken; // Token de Firebase Cloud Messaging

  /// Determina si el usuario tiene privilegios de Usuario Maestro / SuperAdmin
  bool get isSuperAdmin =>
      rol == 'SUPER_ADMIN' ||
      (rol == 'ADMIN' &&
          (email.toLowerCase().contains('inostroza') ||
              email.toLowerCase().contains('heirlog') ||
              idEmpresa.toLowerCase() == 'heirlog'));

  UserModel({
    required this.uid,
    required this.idEmpresa,
    required this.email,
    required this.nombre,
    required this.rol,
    this.rut,
    this.licencias,
    this.sueldoBase,
    this.tipoContrato,
    this.montoViaticoLocal,
    this.montoViaticoLargo,
    this.tasaAFP,
    this.tasaSalud,
    this.baseImponible,
    this.empresaAsumeLeyes,
    this.configuracionPagos,
    this.patenteAsignada,
    this.fcmToken,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String documentId) {
    return UserModel(
      uid: documentId,
      idEmpresa: map['idEmpresa'] ?? '',
      email: map['email'] ?? '',
      nombre: map['nombre'] ?? '',
      rol: map['rol'] ?? 'CHOFER',
      rut: map['rut'],
      licencias: map['licencias'] != null ? List<String>.from(map['licencias']) : null,
      sueldoBase: (map['sueldoBase'] as num?)?.toDouble(),
      tipoContrato: map['tipoContrato'],
      montoViaticoLocal: (map['montoViaticoLocal'] as num?)?.toDouble(),
      montoViaticoLargo: (map['montoViaticoLargo'] as num?)?.toDouble(),
      tasaAFP: (map['tasaAFP'] as num?)?.toDouble(),
      tasaSalud: (map['tasaSalud'] as num?)?.toDouble(),
      baseImponible: map['baseImponible'],
      empresaAsumeLeyes: map['empresaAsumeLeyes'],
      configuracionPagos: map['configuracionPagos'] != null 
          ? Map<String, bool>.from(map['configuracionPagos']) 
          : null,
      patenteAsignada: map['patenteAsignada'],
      fcmToken: map['fcmToken'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'idEmpresa': idEmpresa,
      'email': email,
      'nombre': nombre,
      'rol': rol,
      if (rut != null) 'rut': rut,
      if (licencias != null) 'licencias': licencias,
      if (sueldoBase != null) 'sueldoBase': sueldoBase,
      if (tipoContrato != null) 'tipoContrato': tipoContrato,
      if (montoViaticoLocal != null) 'montoViaticoLocal': montoViaticoLocal,
      if (montoViaticoLargo != null) 'montoViaticoLargo': montoViaticoLargo,
      if (tasaAFP != null) 'tasaAFP': tasaAFP,
      if (tasaSalud != null) 'tasaSalud': tasaSalud,
      if (baseImponible != null) 'baseImponible': baseImponible,
      if (empresaAsumeLeyes != null) 'empresaAsumeLeyes': empresaAsumeLeyes,
      if (configuracionPagos != null) 'configuracionPagos': configuracionPagos,
      if (patenteAsignada != null) 'patenteAsignada': patenteAsignada,
      if (fcmToken != null) 'fcmToken': fcmToken,
    };
  }
}
