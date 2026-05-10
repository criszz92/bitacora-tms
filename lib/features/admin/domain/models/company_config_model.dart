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
  final Map<String, dynamic> extras;

  CompanyConfigModel({
    required this.idEmpresa,
    this.sueldoMinimo = 539000,
    this.umbralKilometrosViatico = 100,
    this.tasaMutual = 0.90,
    this.tasaSIS = 1.49,
    this.porcentajeComision = 0.0,
    this.tipoViatico = 'POR_VIAJE',
    this.valorUTM = 65000,
    this.utmHistory = const {},
    this.precioDieselNeto = 800,
    this.dieselHistory = const {},
    this.maintenanceRules = const [],
    this.extras = const {},
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

    return CompanyConfigModel(
      idEmpresa: id,
      sueldoMinimo: (map['sueldoMinimo'] as num?)?.toDouble() ?? 539000,
      umbralKilometrosViatico: (map['umbralKilometrosViatico'] as num?)?.toDouble() ?? 100,
      tasaMutual: (map['tasaMutual'] as num?)?.toDouble() ?? 0.90,
      tasaSIS: (map['tasaSIS'] as num?)?.toDouble() ?? 1.49,
      porcentajeComision: (map['porcentajeComision'] as num?)?.toDouble() ?? 0.0,
      tipoViatico: map['tipoViatico'] ?? 'POR_VIAJE',
      valorUTM: (map['valorUTM'] as num?)?.toDouble() ?? 65000,
      utmHistory: history,
      precioDieselNeto: (map['precioDieselNeto'] as num?)?.toDouble() ?? 800,
      dieselHistory: dHistory,
      maintenanceRules: mRules,
      extras: map['extras'] ?? {},
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
      'extras': extras,
    };
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
