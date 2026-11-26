import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/admin_provider.dart';
import 'package:intl/intl.dart';


class AnalyticsView extends ConsumerWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(ref),
          const SizedBox(height: 32),
          
          // ── TENDENCIA DE INGRESOS VS GASTOS ─────────────────────────
          _sectionTitle('Tendencia Histórica (6 meses)'),
          const SizedBox(height: 20),
          _buildTrendChart(ref),
          
          const SizedBox(height: 48),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── DISTRIBUCIÓN DE GASTOS ──────────────────────────────
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Distribución de Gastos'),
                    const SizedBox(height: 20),
                    _buildExpensePie(ref),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              // ── TOP CLIENTES ────────────────────────────────────────
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Top 5 Clientes (Ingresos)'),
                    const SizedBox(height: 20),
                    _buildTopClientsBar(ref),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 48),

          // ── ASISTENTE DE OPERACIONES (IA) ──────────────────────────
          _sectionTitle('Asistente de Operaciones IA'),
          const SizedBox(height: 8),
          const Text('Análisis estratégico basado en Groq Llama 3', 
            style: TextStyle(color: Colors.white24, fontSize: 12)),
          const SizedBox(height: 20),
          
          _buildAIAssistant(ref),
          
          const SizedBox(height: 48),

          // ── INTELIGENCIA DE RUTAS (FUSIÓN) ──────────────────────────
          _sectionTitle('Inteligencia de Rutas y Rentabilidad'),
          const SizedBox(height: 8),
          const Text('Ranking avanzado que cruza frecuencia, kilometraje y costos operacionales para encontrar tus rutas más valiosas.', 
              style: TextStyle(color: Colors.white24, fontSize: 11)),
          const SizedBox(height: 20),
          _buildRouteIntelligenceTable(ref),
          
          const SizedBox(height: 100), // Espacio final para scroll cómodo
        ],
      ),
    );
  }

  Widget _buildHeader(WidgetRef ref) {
    final months = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final selected = ref.watch(selectedMonthProvider);
    final now = DateTime.now();
    final isCurrentMonth = selected.year == now.year && selected.month == now.month;

    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Analítica Financiera',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              SizedBox(height: 2),
              Text('Análisis detallado para toma de decisiones',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.grey),
                onPressed: () {
                  ref.read(selectedMonthProvider.notifier).setMonth(
                      DateTime(selected.year, selected.month - 1, 1));
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${months[selected.month]} ${selected.year}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? Colors.white24 : Colors.grey),
                onPressed: isCurrentMonth
                    ? null
                    : () {
                        ref.read(selectedMonthProvider.notifier).setMonth(
                            DateTime(selected.year, selected.month + 1, 1));
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white54));
  }

  // ── ASISTENTE DE OPERACIONES IA ───────────────────────────────────────────

  Widget _buildAIAssistant(WidgetRef ref) {
    final aiResult = ref.watch(aiAnalysisResultProvider);
    final routeData = ref.watch(routeProfitabilityProvider).value ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 20),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Asistente de Operaciones IA', 
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Análisis estratégico basado en Groq Llama 3', 
                    style: TextStyle(color: Colors.white24, fontSize: 11)),
                ],
              ),
              const Spacer(),
              if (aiResult.value == null && !aiResult.isLoading)
                ElevatedButton.icon(
                  onPressed: routeData.isEmpty ? null : () => ref.read(aiAnalysisResultProvider.notifier).runAnalysis(routeData),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.psychology_outlined, size: 18),
                  label: const Text('GENERAR ANÁLISIS DEL MES'),
                )
              else if (aiResult.value != null)
                TextButton.icon(
                  onPressed: () => ref.read(aiAnalysisResultProvider.notifier).clear(),
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white24),
                  label: const Text('Limpiar Análisis', style: TextStyle(color: Colors.white24, fontSize: 12)),
                ),
            ],
          ),
          
          if (aiResult.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 16),
                    Text('Analizando rentabilidad y buscando oportunidades...', 
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ),
            
          if (aiResult.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  aiResult.value!,
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6, letterSpacing: 0.3),
                ),
              ),
            ),
            
          if (aiResult.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text('Error: ${aiResult.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ── GRÁFICO DE TENDENCIA ──────────────────────────────────────────────────

  Widget _buildTrendChart(WidgetRef ref) {
    final trendAsync = ref.watch(trendProvider);

    return trendAsync.when(
      loading: () => _chartPlaceholder(180, true),
      error: (e, s) => Text('Error: $e'),
      data: (data) {
        if (data.isEmpty) return _chartPlaceholder(180, false);

        return Container(
          height: 300,
          padding: const EdgeInsets.fromLTRB(20, 40, 40, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 500000),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      if (val < 0 || val >= data.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(data[val.toInt()].label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    getTitlesWidget: (val, meta) {
                      if (val == 0) return const SizedBox();
                      return Text('${(val/1000000).toStringAsFixed(1)}M', style: const TextStyle(color: Colors.grey, fontSize: 10));
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: Colors.white,
                  barWidth: 4,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ingresos)).toList(),
                ),
                LineChartBarData(
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.gastos)).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── DISTRIBUCIÓN DE GASTOS ───────────────────────────────────────────────

  Widget _buildExpensePie(WidgetRef ref) {
    final breakdownAsync = ref.watch(expenseBreakdownProvider);

    return breakdownAsync.when(
      loading: () => _chartPlaceholder(250, true),
      error: (e, s) => Text('Error: $e'),
      data: (data) {
        if (data.isEmpty) return _chartPlaceholder(250, false, msg: 'Sin gastos este mes');

        final colors = [Colors.white, Colors.orange, Colors.blue, Colors.green, Colors.purple];
        int colorIdx = 0;

        return Container(
          height: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: 50,
                    sections: data.entries.map((e) {
                      final color = colors[colorIdx % colors.length];
                      colorIdx++;
                      return PieChartSectionData(
                        color: color,
                        value: e.value,
                        title: '',
                        radius: 30,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ...data.entries.map((e) {
                final color = colors[data.keys.toList().indexOf(e.key) % colors.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                      Text(NumberFormat.currency(symbol: r'$', decimalDigits: 0).format(e.value), 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ── TOP CLIENTES ─────────────────────────────────────────────────────────

  Widget _buildTopClientsBar(WidgetRef ref) {
    final clientsAsync = ref.watch(topClientsProvider);

    return clientsAsync.when(
      loading: () => _chartPlaceholder(350, true),
      error: (e, s) => Text('Error: $e'),
      data: (data) {
        if (data.isEmpty) return _chartPlaceholder(350, false);

        return Container(
          height: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      if (val < 0 || val >= data.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          data[val.toInt()].key.split(' ').first, 
                          style: const TextStyle(color: Colors.grey, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: data.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.value,
                      color: Colors.white,
                      width: 20,
                      borderRadius: BorderRadius.circular(4),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: data.first.value,
                        color: Colors.white10,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ── INTELIGENCIA DE RUTAS (FUSIÓN MAESTRA) ───────────────────────────────

  Widget _buildRouteIntelligenceTable(WidgetRef ref) {
    final profitAsync = ref.watch(routeProfitabilityProvider);

    return profitAsync.when(
      loading: () => _chartPlaceholder(300, true),
      error: (e, s) => Text('Error: $e'),
      data: (data) {
        if (data.isEmpty) return _chartPlaceholder(300, false, msg: 'Sin datos operacionales registrados');

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: Text('RUTA / ORIGEN-DESTINO', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold))),
                    const Expanded(flex: 1, child: Text('VJS', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    const Expanded(flex: 1, child: Text('KM TOT', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    const Expanded(flex: 2, child: Text('CPK', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                    const Expanded(flex: 2, child: Text('MARGEN NETO', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                    const Expanded(flex: 1, child: Text('%', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: data.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final route = data[index];
                  final isPositive = route.netMargin > 0;
                  // CPK = Cost per KM (TODOS los costos operacionales / KM Totales)
                  final totalCosts = route.totalFuelCost + route.totalTolls + route.totalViaticos + route.totalPersonal + route.totalMaintenance;
                  final cpk = route.totalKm > 0 ? totalCosts / route.totalKm : 0.0;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(route.route, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'ING: ${NumberFormat.compactCurrency(symbol: r'$', decimalDigits: 0).format(route.totalIncome)} | '
                                'COMB: ${NumberFormat.compactCurrency(symbol: r'$', decimalDigits: 0).format(route.totalFuelCost)} | '
                                'PEAJE: ${NumberFormat.compactCurrency(symbol: r'$', decimalDigits: 0).format(route.totalTolls)} | '
                                'VIAT: ${NumberFormat.compactCurrency(symbol: r'$', decimalDigits: 0).format(route.totalViaticos)} | '
                                'PERS: ${NumberFormat.compactCurrency(symbol: r'$', decimalDigits: 0).format(route.totalPersonal)} | '
                                'MANT: ${NumberFormat.compactCurrency(symbol: r'$', decimalDigits: 0).format(route.totalMaintenance)}',
                                style: const TextStyle(color: Colors.white24, fontSize: 9),
                              ),
                            ),
                          ],
                        )),
                        Expanded(flex: 1, child: Text(route.tripCount.toString(), style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text(NumberFormat('#,###').format(route.totalKm), style: const TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center)),
                        Expanded(flex: 2, child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(NumberFormat.currency(symbol: r'$', decimalDigits: 0).format(cpk), 
                                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            const Text('por KM', style: TextStyle(color: Colors.white24, fontSize: 9)),
                          ],
                        )),
                        Expanded(flex: 2, child: Text(NumberFormat.currency(symbol: r'$', decimalDigits: 0).format(route.netMargin), 
                            style: TextStyle(color: isPositive ? Colors.greenAccent : Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                        Expanded(flex: 1, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isPositive ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('${route.marginPercentage.toStringAsFixed(1)}%', 
                              style: TextStyle(color: isPositive ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                        )),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chartPlaceholder(double height, bool isLoading, {String msg = 'Cargando datos...'}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: isLoading 
          ? const CircularProgressIndicator(color: Colors.white)
          : Text(msg, style: const TextStyle(color: Colors.white24)),
      ),
    );
  }
}
