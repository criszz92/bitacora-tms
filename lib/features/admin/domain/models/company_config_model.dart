import 'recurring_expense_model.dart';

class CompanyConfigModel {
  final String idEmpresa;
  final double sueldoMinimo;
  final double umbralKilometrosViatico;
  final double tasaMutual;
  final double tasaSIS;
  final double porcentajeComision;
  final String tipoViatico; // 'POR_VIAJE' o 'POR_JORNADA'
  final double valorUTM;    // Valor base de respaldo
  final Map<String, double> utmHistory; // Historial mensual {"2024-05": 65443.0}
  final double precioDieselNeto; // Precio de referencia neto base
  final Map<String, double> dieselHistory; // Historial mensual {"2024-05": 1050.0}
  final List<Map<String, dynamic>> maintenanceRules; // Reglas dinámicas de mantenimiento
  final int diasLaboralesMes;            // default: 22
  final double margenObjetivoCotizacion; // default: 25.0 (porcentaje)
  final List<RecurringExpenseModel> gastosRecurrentes; // Gastos fijos mensuales preestablecidos
  final List<String> mesesGastosFijosAplicados; // Meses donde ya se aplicaron ("2026-09")
  
  // ─── Parámetros Tributarios F29 Avanzados (Fuente de Verdad SII) ───────────
  final double tasaPPM; // % de Pago Provisional Mensual sobre ventas netas (default: 1.5%)
  final double porcentajeRecuperacionIepd; // % según Ley 19.764 (default: 80% para ventas <= 2400 UF)
  final double remanenteCreditoFiscalAcumulado; // Saldo de IVA crédito arrastrado (ej. por compra de camión)

  final Map<String, dynamic> extras;

  // ─── Datos del Emisor (para PDF de cotizaciones) ─────────────────────────
  final String emisorRazonSocial;
  final String emisorRut;
  final String emisorGiro;
  final String emisorDireccion;
  final String emisorTelefono;
  final String emisorEmail;
  final String emisorLogoBase64; // Logo comprimido en Base64 (~300px ancho)

  CompanyConfigModel({
    required this.idEmpresa,
    this.sueldoMinimo = 539000,
    this.umbralKilometrosViatico = 100,
    this.tasaMutual = 0.90,
    this.tasaSIS = 1.49,
    this.porcentajeComision = 0.0,
    this.tipoViatico = 'POR_JORNADA',
    this.valorUTM = 65000,
    this.utmHistory = const {},
    this.precioDieselNeto = 800,
    this.dieselHistory = const {},
    this.maintenanceRules = const [],
    this.diasLaboralesMes = 22,
    this.margenObjetivoCotizacion = 25.0,
    this.gastosRecurrentes = const [],
    this.mesesGastosFijosAplicados = const [],
    this.tasaPPM = 1.5,
    this.porcentajeRecuperacionIepd = 80.0,
    this.remanenteCreditoFiscalAcumulado = 0.0,
    this.extras = const {},
    this.emisorRazonSocial = '',
    this.emisorRut = '',
    this.emisorGiro = '',
    this.emisorDireccion = '',
    this.emisorTelefono = '',
    this.emisorEmail = '',
    this.emisorLogoBase64 = '',
  });

  factory CompanyConfigModel.fromMap(Map<String, dynamic> map, String id) {
    // Procesamos el mapa de historial asegurando tipos correctos
    final Map<String, double> history = {};
    if (map['utmHistory'] != null) {
      (map['utmHistory'] as Map<String, dynamic>).forEach((key, value) {
        history[key] = (value as num).toDouble();
      });
    }

    // Procesamos el historial de Diesel
    final Map<String, double> dHistory = {};
    if (map['dieselHistory'] != null) {
      (map['dieselHistory'] as Map<String, dynamic>).forEach((key, value) {
        dHistory[key] = (value as num).toDouble();
      });
    }

    // Procesamos reglas de mantenimiento
    final List<Map<String, dynamic>> mRules = [];
    if (map['maintenanceRules'] != null) {
      for (var rule in (map['maintenanceRules'] as List)) {
        mRules.add(Map<String, dynamic>.from(rule as Map));
      }
    }

    // Procesamos gastos recurrentes
    final List<RecurringExpenseModel> gRecurrentes = [];
    if (map['gastosRecurrentes'] != null) {
      for (var g in (map['gastosRecurrentes'] as List)) {
        gRecurrentes.add(RecurringExpenseModel.fromMap(Map<String, dynamic>.from(g as Map)));
      }
    }

    // Meses donde se han aplicado los gastos fijos
    final List<String> mesesAplicados = [];
    if (map['mesesGastosFijosAplicados'] != null) {
      for (var m in (map['mesesGastosFijosAplicados'] as List)) {
        mesesAplicados.add(m.toString());
      }
    }

    return CompanyConfigModel(
      idEmpresa: id,
      sueldoMinimo: (map['sueldoMinimo'] as num?)?.toDouble() ?? 539000,
      umbralKilometrosViatico: (map['umbralKilometrosViatico'] as num?)?.toDouble() ?? 100,
      tasaMutual: (map['tasaMutual'] as num?)?.toDouble() ?? 0.90,
      tasaSIS: (map['tasaSIS'] as num?)?.toDouble() ?? 1.49,
      porcentajeComision: (map['porcentajeComision'] as num?)?.toDouble() ?? 0.0,
      tipoViatico: map['tipoViatico'] ?? 'POR_JORNADA',
      valorUTM: (map['valorUTM'] as num?)?.toDouble() ?? 65000,
      utmHistory: history,
      precioDieselNeto: (map['precioDieselNeto'] as num?)?.toDouble() ?? 800,
      dieselHistory: dHistory,
      maintenanceRules: mRules,
      diasLaboralesMes: map['diasLaboralesMes'] as int? ?? 22,
      margenObjetivoCotizacion: (map['margenObjetivoCotizacion'] as num?)?.toDouble() ?? 25.0,
      gastosRecurrentes: gRecurrentes,
      mesesGastosFijosAplicados: mesesAplicados,
      tasaPPM: (map['tasaPPM'] as num?)?.toDouble() ?? 1.5,
      porcentajeRecuperacionIepd: (map['porcentajeRecuperacionIepd'] as num?)?.toDouble() ?? 80.0,
      remanenteCreditoFiscalAcumulado: (map['remanenteCreditoFiscalAcumulado'] as num?)?.toDouble() ?? 0.0,
      extras: map['extras'] ?? {},
      emisorRazonSocial: map['emisorRazonSocial'] ?? '',
      emisorRut: map['emisorRut'] ?? '',
      emisorGiro: map['emisorGiro'] ?? '',
      emisorDireccion: map['emisorDireccion'] ?? '',
      emisorTelefono: map['emisorTelefono'] ?? '',
      emisorEmail: map['emisorEmail'] ?? '',
      emisorLogoBase64: map['emisorLogoBase64'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sueldoMinimo': sueldoMinimo,
      'umbralKilometrosViatico': umbralKilometrosViatico,
      'tasaMutual': tasaMutual,
      'tasaSIS': tasaSIS,
      'porcentajeComision': porcentajeComision,
      'tipoViatico': tipoViatico,
      'valorUTM': valorUTM,
      'utmHistory': utmHistory,
      'precioDieselNeto': precioDieselNeto,
      'dieselHistory': dieselHistory,
      'maintenanceRules': maintenanceRules,
      'diasLaboralesMes': diasLaboralesMes,
      'margenObjetivoCotizacion': margenObjetivoCotizacion,
      'gastosRecurrentes': gastosRecurrentes.map((g) => g.toMap()).toList(),
      'mesesGastosFijosAplicados': mesesGastosFijosAplicados,
      'tasaPPM': tasaPPM,
      'porcentajeRecuperacionIepd': porcentajeRecuperacionIepd,
      'remanenteCreditoFiscalAcumulado': remanenteCreditoFiscalAcumulado,
      'extras': extras,
      'emisorRazonSocial': emisorRazonSocial,
      'emisorRut': emisorRut,
      'emisorGiro': emisorGiro,
      'emisorDireccion': emisorDireccion,
      'emisorTelefono': emisorTelefono,
      'emisorEmail': emisorEmail,
      'emisorLogoBase64': emisorLogoBase64,
    };
  }

  CompanyConfigModel copyWith({
    String? idEmpresa,
    double? sueldoMinimo,
    double? umbralKilometrosViatico,
    double? tasaMutual,
    double? tasaSIS,
    double? porcentajeComision,
    String? tipoViatico,
    double? valorUTM,
    Map<String, double>? utmHistory,
    double? precioDieselNeto,
    Map<String, double>? dieselHistory,
    List<Map<String, dynamic>>? maintenanceRules,
    int? diasLaboralesMes,
    double? margenObjetivoCotizacion,
    List<RecurringExpenseModel>? gastosRecurrentes,
    List<String>? mesesGastosFijosAplicados,
    double? tasaPPM,
    double? porcentajeRecuperacionIepd,
    double? remanenteCreditoFiscalAcumulado,
    Map<String, dynamic>? extras,
    String? emisorRazonSocial,
    String? emisorRut,
    String? emisorGiro,
    String? emisorDireccion,
    String? emisorTelefono,
    String? emisorEmail,
    String? emisorLogoBase64,
  }) {
    return CompanyConfigModel(
      idEmpresa: idEmpresa ?? this.idEmpresa,
      sueldoMinimo: sueldoMinimo ?? this.sueldoMinimo,
      umbralKilometrosViatico: umbralKilometrosViatico ?? this.umbralKilometrosViatico,
      tasaMutual: tasaMutual ?? this.tasaMutual,
      tasaSIS: tasaSIS ?? this.tasaSIS,
      porcentajeComision: porcentajeComision ?? this.porcentajeComision,
      tipoViatico: tipoViatico ?? this.tipoViatico,
      valorUTM: valorUTM ?? this.valorUTM,
      utmHistory: utmHistory ?? this.utmHistory,
      precioDieselNeto: precioDieselNeto ?? this.precioDieselNeto,
      dieselHistory: dieselHistory ?? this.dieselHistory,
      maintenanceRules: maintenanceRules ?? this.maintenanceRules,
      diasLaboralesMes: diasLaboralesMes ?? this.diasLaboralesMes,
      margenObjetivoCotizacion: margenObjetivoCotizacion ?? this.margenObjetivoCotizacion,
      gastosRecurrentes: gastosRecurrentes ?? this.gastosRecurrentes,
      mesesGastosFijosAplicados: mesesGastosFijosAplicados ?? this.mesesGastosFijosAplicados,
      tasaPPM: tasaPPM ?? this.tasaPPM,
      porcentajeRecuperacionIepd: porcentajeRecuperacionIepd ?? this.porcentajeRecuperacionIepd,
      remanenteCreditoFiscalAcumulado: remanenteCreditoFiscalAcumulado ?? this.remanenteCreditoFiscalAcumulado,
      extras: extras ?? this.extras,
      emisorRazonSocial: emisorRazonSocial ?? this.emisorRazonSocial,
      emisorRut: emisorRut ?? this.emisorRut,
      emisorGiro: emisorGiro ?? this.emisorGiro,
      emisorDireccion: emisorDireccion ?? this.emisorDireccion,
      emisorTelefono: emisorTelefono ?? this.emisorTelefono,
      emisorEmail: emisorEmail ?? this.emisorEmail,
      emisorLogoBase64: emisorLogoBase64 ?? this.emisorLogoBase64,
    );
  }

  /// Retorna el valor de UTM para un mes específico (YYYY-MM)
  double getUtmForMonth(String monthKey) {
    return utmHistory[monthKey] ?? valorUTM;
  }

  /// Retorna el valor de Diesel para un mes específico (YYYY-MM)
  /// Si no existe en historial, retorna null para indicar que usemos el cálculo automático.
  double? getDieselManualForMonth(String monthKey) {
    return dieselHistory[monthKey];
  }
}
