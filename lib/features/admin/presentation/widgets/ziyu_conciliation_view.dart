import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../domain/models/ziyu_models.dart';
import '../../domain/services/ziyu_service.dart';
import '../../domain/models/liquidacion_model.dart';
import '../providers/admin_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ZiyuConciliationView extends ConsumerStatefulWidget {
  const ZiyuConciliationView({super.key});

  @override
  ConsumerState<ZiyuConciliationView> createState() => _ZiyuConciliationViewState();
}

class _ZiyuConciliationViewState extends ConsumerState<ZiyuConciliationView> {
  final _referenciaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Cargar viajes pendientes al iniciar para visibilidad inmediata
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarViajesPendientes());
  }

  Future<void> _cargarViajesPendientes() async {
    final userProfile = ref.read(currentUserProfileProvider).value;
    if (userProfile == null) return;
    
    final bitacoraTrips = await ref.read(adminRepositoryProvider).getTripsForConciliation(userProfile.idEmpresa);
    
    // Si no hay resultados de Excel activos, mostrar solo los de Bitácora
    final state = ref.read(ziyuConciliationProvider);
    if (state.results == null) {
      final results = ZiyuService.reconcile(ziyuRecords: [], bitacoraTrips: bitacoraTrips);
      ref.read(ziyuConciliationProvider.notifier).setResults('', results, ZiyuService.summarize(results));
    }
  }

  Future<void> _pickExcelFile() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf'],
      withData: true,
    );

    if (result != null) {
      final fileName = result.files.single.name;
      final notifier = ref.read(ziyuConciliationProvider.notifier);
      
      notifier.setProcessing(true);

      try {
        final bytes = result.files.single.bytes;
        if (bytes == null) throw Exception('No se pudo leer el archivo (bytes null).');

        // 1. Parsear archivo (Excel o CSV)
        final ziyuRecords = ZiyuService.parseFile(bytes, fileName);

        // 2. Obtener TODOS los viajes OS de la empresa de la BD
        final userProfile = ref.read(currentUserProfileProvider).value;
        if (userProfile == null) throw Exception('Usuario no cargado');
        
        final bitacoraTrips = await ref.read(adminRepositoryProvider).getTripsForConciliation(userProfile.idEmpresa);

        // 3. Ejecutar motor de conciliación
        final results = ZiyuService.reconcile(
          ziyuRecords: ziyuRecords,
          bitacoraTrips: bitacoraTrips,
        );

        notifier.setResults(fileName, results, ZiyuService.summarize(results));
      } catch (e) {
        ref.read(ziyuConciliationProvider.notifier).setProcessing(false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error procesando archivo: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _generarLiquidacion() async {
    final state = ref.read(ziyuConciliationProvider);
    final matchedResults = state.results?.where((r) => r.status == ReconciliationStatus.matched).toList();
    if (matchedResults == null || matchedResults.isEmpty) return;

    // Sugerir la primera OS encontrada como referencia
    final firstMatch = matchedResults.firstWhere((r) => r.ziyuRecord?.osNumber != null, orElse: () => matchedResults.first);
    _referenciaController.text = firstMatch.ziyuRecord?.osNumber ?? 'Liq ${DateTime.now().day}/${DateTime.now().month}';

    final referencia = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirmar Liquidación', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa un nombre o número de OS para identificar esta liquidación.', 
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _referenciaController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Referencia / Nº OS',
                labelStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF121212),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFFFFF)),
            onPressed: () => Navigator.pop(ctx, _referenciaController.text.trim()),
            child: const Text('Generar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (referencia == null || referencia.isEmpty) return;
 
    ref.read(ziyuConciliationProvider.notifier).setProcessing(true);

    try {
      final userProfile = ref.read(currentUserProfileProvider).value;
      if (userProfile == null) throw Exception('Usuario no cargado');

      final tripIds = matchedResults.map((r) => r.tripModel!.id as String).toList();
      final montoTotal = matchedResults.fold(0.0, (sum, r) => sum + (r.ziyuRecord?.value ?? 0.0));
      
      final detalleCruce = matchedResults.map((r) => {
        'tripId': r.tripModel!.id,
        'vehicleId': r.tripModel!.vehicleId, // Importante para filtros
        'os': r.ziyuRecord?.osNumber ?? r.matchKey,
        'bitacoraValue': r.tripModel!.value,
        'ziyuValue': r.ziyuRecord?.value ?? 0.0,
        'diferencia': r.diferencia ?? 0.0,
        'contenedor': r.ziyuRecord?.containerNumber,
      }).toList();

      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      final liq = LiquidacionModel(
        id: docId,
        idEmpresa: userProfile.idEmpresa,
        montoTotal: montoTotal,
        viajesCount: tripIds.length,
        estado: 'pendiente',
        referencia: referencia,
        fechaCreacion: DateTime.now(),
        tripIds: tripIds,
        detalleCruce: detalleCruce,
      );

      await ref.read(adminRepositoryProvider).createLiquidacion(liq);
 
      ref.read(ziyuConciliationProvider.notifier).clear();
      _cargarViajesPendientes(); // Recargar para limpiar los ya liquidados

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liquidación generada con éxito.'), backgroundColor: Color(0xFFFFFFFF)),
        );
      }
    } catch (e) {
      ref.read(ziyuConciliationProvider.notifier).setProcessing(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ziyuConciliationProvider);
    
    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Conciliación Ziyu / Proformas',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 6),
                  Text(
                    'Sube el Excel o Proforma y el sistema cruzará inteligentemente\nla información con los viajes registrados por tus conductores.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
              if (state.results != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E1E1E),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: () => ref.read(ziyuConciliationProvider.notifier).clear(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Nueva Conciliación'),
                ),
            ],
          ),
          const SizedBox(height: 40),

          // Pantalla de carga o upload si no hay resultados
          if (state.results == null)
            _buildUploader(state)
          else if (state.fileName == null && state.results != null)
             Expanded(
               child: Column(
                 children: [
                   _buildUploader(state),
                   const SizedBox(height: 24),
                   Expanded(child: _buildResultsDashboard(state)),
                 ],
               ),
             )
          else
            Expanded(child: _buildResultsDashboard(state)),
        ],
      ),
    );
  }

  Widget _buildUploader(ZiyuConciliationState state) {
    return InkWell(
      onTap: state.isProcessing ? null : _pickExcelFile,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 250,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: const Color(0xFFE0E0E0).withValues(alpha: 0.5), width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (state.isProcessing)
              const Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFFE0E0E0)),
                  SizedBox(height: 24),
                  Text('Motor IA analizando y cruzando datos...',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                ],
              )
            else ...[
              const Icon(Icons.analytics_outlined, size: 70, color: Color(0xFFE0E0E0)),
              const SizedBox(height: 20),
              Text(
                state.fileName ?? 'Haz clic para seleccionar reporte (.xlsx, .csv)',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: state.fileName == null ? Colors.white : const Color(0xFFE0E0E0)),
              ),
              if (state.fileName == null) ...[
                const SizedBox(height: 8),
                const Text('El motor detecta las columnas automáticamente.',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ]
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildResultsDashboard(ZiyuConciliationState state) {
    final summary = state.summary!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tarjetas de resumen
        Row(
          children: [
            _summaryCard('Total Procesados', summary['total'].toString(),
                Icons.list_alt, Colors.blue),
            const SizedBox(width: 16),
            _summaryCard('Conciliados', summary['matched'].toString(),
                Icons.check_circle_outline, const Color(0xFFFFFFFF)),
            const SizedBox(width: 16),
            _summaryCard('Solo en Ziyu', summary['onlyZiyu'].toString(),
                Icons.warning_amber_rounded, Colors.orange),
            const SizedBox(width: 16),
            _summaryCard('Solo en Bitácora', summary['onlyBitacora'].toString(),
                Icons.help_outline, Colors.redAccent),
          ],
        ),
        const SizedBox(height: 24),
        
        // Botón Generar Liquidación
        if ((summary['matched'] ?? 0) > 0)
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFFFFF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
              onPressed: state.isProcessing ? null : _generarLiquidacion,
              icon: state.isProcessing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                : const Icon(Icons.receipt_long),
              label: Text('Generar Liquidación (${summary['matched']} viajes)'),
            ),
          ),

        const SizedBox(height: 24),
        const Text('Detalle de Conciliación',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: state.results!.length,
            itemBuilder: (context, index) {
              final result = state.results![index];
              return _buildResultRow(result);
            },
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(ReconciliationResult r) {
    Color bgColor;
    Color accentColor;

    switch (r.status) {
      case ReconciliationStatus.matched:
        bgColor = const Color(0xFFFFFFFF).withValues(alpha: 0.05);
        accentColor = const Color(0xFFFFFFFF);
        break;
      case ReconciliationStatus.warningPlate:
        bgColor = Colors.orange.withValues(alpha: 0.08);
        accentColor = Colors.orange;
        break;
      case ReconciliationStatus.onlyInZiyu:
        bgColor = Colors.orange.withValues(alpha: 0.05);
        accentColor = Colors.orange;
        break;
      case ReconciliationStatus.onlyInBitacora:
        bgColor = Colors.redAccent.withValues(alpha: 0.05);
        accentColor = Colors.redAccent;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.statusIcon),
                const SizedBox(width: 6),
                Text(r.statusLabel,
                    style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Clave: ${r.matchKey}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (r.status == ReconciliationStatus.warningPlate) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PATENTE: ${r.ziyuRecord?.vehiclePlate} (Ziyu) vs ${r.tripModel?.vehicleId} (App)',
                          style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (r.ziyuRecord != null)
                  Text('Ziyu: [${r.ziyuRecord!.date != null ? DateFormat('dd/MM').format(r.ziyuRecord!.date!) : '-'}] ${r.ziyuRecord!.origin ?? ''} → ${r.ziyuRecord!.destination ?? ''} | \$${r.ziyuRecord!.value ?? '-'}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (r.tripModel != null)
                  Text('Bitácora: [${DateFormat('dd/MM').format(r.tripModel.startDate)}] ${r.tripModel.displayRoute3Steps} | \$${r.tripModel.value.toInt()}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          if (r.diferencia != null && r.diferencia != 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Diferencia', style: TextStyle(color: Colors.grey, fontSize: 10)),
                Text(
                  '\$${r.diferencia!.abs().toStringAsFixed(0)}',
                  style: TextStyle(
                    color: r.diferencia! < 0 ? Colors.red : const Color(0xFFFFFFFF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
