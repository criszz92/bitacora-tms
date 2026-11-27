import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../providers/admin_provider.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../../core/utils/chilean_financial_calculator.dart';
import '../../../../core/utils/pdf_generator.dart';

class RemuneracionesView extends ConsumerStatefulWidget {
  const RemuneracionesView({super.key});

  @override
  ConsumerState<RemuneracionesView> createState() => _RemuneracionesViewState();
}

class _RemuneracionesViewState extends ConsumerState<RemuneracionesView> {
  @override
  Widget build(BuildContext context) {
    final currentMonth = ref.watch(selectedMonthProvider);
    final driversAsync = ref.watch(choferesProvider);
    final configAsync = ref.watch(companyConfigProvider);
    final tripsAsync = ref.watch(monthlyTripsProvider);
    final viaticosAsync = ref.watch(adminViaticosProvider);
    
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Remuneraciones',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 6),
                    const Text('Liquidaciones de Sueldo (Nómina Mensual).',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              _buildMonthSelector(ref),
            ],
          ),
          const SizedBox(height: 32),

          Expanded(
            child: driversAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
              error: (e, s) => Center(child: Text('Error: $e')),
              data: (drivers) {
                final config = configAsync.value;
                final trips = tripsAsync.value ?? [];
                final viaticos = viaticosAsync.value ?? [];
                
                if (config == null) return const Center(child: Text('Cargando configuración...'));

                if (drivers.isEmpty) {
                  return const Center(child: Text('No hay conductores registrados.', style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  itemCount: drivers.length,
                  itemBuilder: (ctx, i) {
                    final driver = drivers[i];
                    
                    // Calcular viáticos reales pagados este mes
                    final viaticosChofer = viaticos.where((v) {
                       if (v.idChofer != driver.uid || !v.isPagado) return false;
                       // Usamos fechaPago si existe, si no, creadoEn
                       final dateToCompare = v.fechaPago ?? v.creadoEn;
                       return dateToCompare.month == currentMonth.month && dateToCompare.year == currentMonth.year;
                    }).toList();
                    
                    final totalViaticosPagados = viaticosChofer.fold<double>(0, (sum, v) => sum + (v.montoTotal ?? 0));
                    
                    final payslip = ChileanFinancialCalculator.calculateDriverPayslip(
                      driver: driver,
                      config: config,
                      monthlyTrips: trips,
                      viaticosYaPagados: totalViaticosPagados,
                    );
                    
                    return _buildDriverPayrollCard(driver, payslip, currency, currentMonth);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(WidgetRef ref) {
    final currentMonth = ref.watch(selectedMonthProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonHideUnderline(
        child: Builder(
          builder: (context) {
            final selectedVal = DateTime(currentMonth.year, currentMonth.month);
            final monthsList = List.generate(
              6,
              (i) => DateTime(DateTime.now().year, DateTime.now().month - i, 1),
            );
            if (!monthsList.any((d) => d.year == selectedVal.year && d.month == selectedVal.month)) {
              monthsList.add(selectedVal);
            }
            return DropdownButton<DateTime>(
              value: selectedVal,
              dropdownColor: const Color(0xFF1E1E1E),
              icon: const Icon(Icons.calendar_month, color: Colors.grey, size: 18),
              items: monthsList.map((date) {
                final dateStr = '${date.month}/${date.year}';
                return DropdownMenuItem(
                  value: date,
                  child: Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 13)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) ref.read(selectedMonthProvider.notifier).setMonth(val);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDriverPayrollCard(UserModel driver, Map<String, dynamic> payslip, NumberFormat currency, DateTime month) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            radius: 24,
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.nombre, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(driver.rut ?? 'Sin RUT', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                if (driver.empresaAsumeLeyes == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('SUELDO LÍQUIDO PACTADO', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
              ],
            ),
          ),
          
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn('Haberes', payslip['Total Haberes'] ?? 0, currency, Colors.white),
                _statColumn('Descuentos', payslip['Total Descuentos'] ?? 0, currency, Colors.redAccent),
                _statColumn('A Pago', payslip['Sueldo Líquido'] ?? 0, currency, Colors.green),
              ],
            ),
          ),
          
          const SizedBox(width: 20),
          ElevatedButton.icon(
            onPressed: () => _verLiquidacion(driver, payslip, month),
            icon: const Icon(Icons.receipt_long, size: 18),
            label: const Text('Ver Liquidación'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          )
        ],
      ),
    );
  }

  Widget _statColumn(String label, double amount, NumberFormat currency, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(currency.format(amount), style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _verLiquidacion(UserModel driver, Map<String, dynamic> payslip, DateTime month) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Liquidación de Sueldo', style: TextStyle(color: Colors.white)),
            IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.7,
          height: MediaQuery.of(context).size.height * 0.8,
          child: PdfPreview(
            build: (format) => PdfGenerator.generateLiquidacionSueldo(
              driver: driver,
              payslipData: payslip,
              period: month,
            ),
            allowPrinting: true,
            allowSharing: true,
            canChangeOrientation: false,
            canChangePageFormat: false,
          ),
        ),
      ),
    );
  }
}
