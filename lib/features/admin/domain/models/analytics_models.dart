class RouteProfitability {
  final String route; // Ej: "Santiago -> Concepción"
  final int tripCount;
  final double totalKm;
  final double totalIncome;
  final double totalFuelCost;
  final double totalTolls;
  final double totalViaticos;
  final double totalPersonal;     // Nuevo: Costo de personal prorrateado
  final double totalMaintenance;  // Nuevo: Costo de mantenimiento (desgaste)
  final double netMargin;
  final double marginPercentage;

  RouteProfitability({
    required this.route,
    required this.tripCount,
    required this.totalKm,
    required this.totalIncome,
    required this.totalFuelCost,
    required this.totalTolls,
    required this.totalViaticos,
    required this.totalPersonal,
    required this.totalMaintenance,
    required this.netMargin,
    required this.marginPercentage,
  });

  factory RouteProfitability.empty(String route) {
    return RouteProfitability(
      route: route,
      tripCount: 0,
      totalKm: 0,
      totalIncome: 0,
      totalFuelCost: 0,
      totalTolls: 0,
      totalViaticos: 0,
      totalPersonal: 0,
      totalMaintenance: 0,
      netMargin: 0,
      marginPercentage: 0,
    );
  }
}

class TrendData {
  final String label; // "Ene", "Feb", etc.
  final double ingresos;
  final double gastos;
  final double margen;

  TrendData({
    required this.label,
    required this.ingresos,
    required this.gastos,
    required this.margen,
  });
}
