import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../trips/domain/models/viatico_model.dart';
import '../../../trips/domain/services/pdf_service.dart';
import '../../../trips/presentation/providers/trip_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:bitacora/features/admin/presentation/providers/admin_provider.dart';
import 'package:bitacora/features/admin/domain/models/company_config_model.dart';

class ViaticosRequestScreen extends ConsumerStatefulWidget {
  const ViaticosRequestScreen({super.key});

  @override
  ConsumerState<ViaticosRequestScreen> createState() =>
      _ViaticosRequestScreenState();
}

class _ViaticosRequestScreenState extends ConsumerState<ViaticosRequestScreen> {
  DateTimeRange? _selectedRange;
  bool _isGenerating = false;

  // ─── Selección de fechas ────────────────────────────────────────────────────

  Future<void> _selectDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Selecciona los días a cobrar',
      saveText: 'CONFIRMAR',
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE0E0E0),
            onPrimary: Colors.white,
            surface: Color(0xFF1E1E1E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _selectedRange = range);
  }

  // ─── Generar PDF y guardar en Firestore ────────────────────────────────────

  Future<void> _sendRequest() async {
    if (_selectedRange == null) return;
    setState(() => _isGenerating = true);

    try {
      final user = ref.read(currentUserProfileProvider).value;
      final config = ref.read(companyConfigProvider).value ?? CompanyConfigModel(idEmpresa: user?.idEmpresa ?? '');
      if (user == null) throw Exception('No hay usuario activo');

      final existingViaticos = ref.read(viaticosProvider).value ?? [];
      for (final v in existingViaticos) {
        // Verificar superposición: StartA <= EndB y EndA >= StartB
        final sA = DateUtils.dateOnly(_selectedRange!.start);
        final eA = DateUtils.dateOnly(_selectedRange!.end);
        final sB = DateUtils.dateOnly(v.fechaInicio);
        final eB = DateUtils.dateOnly(v.fechaFin);
        
        if (sA.isBefore(eB.add(const Duration(days: 1))) && eA.isAfter(sB.subtract(const Duration(days: 1)))) {
           throw Exception('El rango seleccionado se superpone con la rendición del ${_fmtDate(v.fechaInicio)} al ${_fmtDate(v.fechaFin)}.\n\nPara corregir, debes eliminar esa rendición pendiente.');
        }
      }

      final trips = await ref.read(tripRepositoryProvider).getTripsByDateRange(
            _selectedRange!.start,
            _selectedRange!.end,
          );

      if (trips.isEmpty) {
        throw Exception('No hay viajes registrados en este rango de fechas.');
      }

      // Genera y comparte el PDF
      await PdfService.generateAndShareViaticosPdf(
          user, _selectedRange!.start, _selectedRange!.end, trips, config);

      // Guarda la rendición en Firestore para el marcado visual del calendario
      final viatico = ViaticoModel(
        id: 'VIAT-${DateTime.now().millisecondsSinceEpoch}',
        idChofer: user.uid,
        idEmpresa: user.idEmpresa,
        fechaInicio: _selectedRange!.start,
        fechaFin: _selectedRange!.end,
        estado: 'pendiente',
        creadoEn: DateTime.now(),
      );
      await ref.read(tripRepositoryProvider).saveViatico(viatico);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✓ PDF generado y rendición registrada como pendiente de pago.',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
            backgroundColor: Color(0xFFFFFFFF),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viaticosAsync = ref.watch(viaticosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendición de Viáticos',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Selecciona los días trabajados. El sistema cruzará automáticamente con tus viajes completados en esas fechas.',
              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),

            // ── Leyenda de colores ──────────────────────────────────────
            viaticosAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, s) => const SizedBox.shrink(),
              data: (viaticos) => viaticos.isEmpty
                  ? const SizedBox.shrink()
                  : _buildLeyenda(),
            ),

            const SizedBox(height: 16),

            // ── Selector de fechas con indicadores visuales ──────────────
            GestureDetector(
              onTap: _selectDateRange,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedRange != null
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFFE0E0E0).withValues(alpha: 0.3),
                    width: _selectedRange != null ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.date_range,
                        size: 56, color: Color(0xFFE0E0E0)),
                    const SizedBox(height: 16),
                    Text(
                      _selectedRange == null
                          ? 'Toca para seleccionar fechas'
                          : '${_fmtDate(_selectedRange!.start)}  →  ${_fmtDate(_selectedRange!.end)}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _selectedRange != null
                            ? Colors.white
                            : Colors.grey,
                      ),
                    ),
                    if (_selectedRange != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${_selectedRange!.duration.inDays + 1} día(s) seleccionado(s)',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Historial de rendiciones con marcado visual ───────────────
            viaticosAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFE0E0E0)),
              ),
              error: (e, s) => Text('Error: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (viaticos) => viaticos.isEmpty
                  ? const SizedBox.shrink()
                  : _buildHistorial(viaticos),
            ),

            const Spacer(),

            // ── Botón Compartir ──────────────────────────────────────────
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE0E0E0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: (_selectedRange == null || _isGenerating)
                    ? null
                    : _sendRequest,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Icon(Icons.share),
                label: Text(
                  _isGenerating ? 'GENERANDO PDF...' : 'COMPARTIR RENDICIÓN',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── Leyenda de colores ────────────────────────────────────────────────────

  Widget _buildLeyenda() {
    return Row(
      children: [
        _legendaItem(
          color: const Color(0xFF9E9E9E).withValues(alpha: 0.25),
          border: const Color(0xFF9E9E9E),
          label: 'Pendiente de pago',
        ),
        const SizedBox(width: 12),
        _legendaItem(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
          border: const Color(0xFFFFFFFF),
          label: 'Pagado',
        ),
      ],
    );
  }

  Widget _legendaItem({required Color color, required Color border, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  // ─── Historial de rendiciones ──────────────────────────────────────────────

  Widget _buildHistorial(List<ViaticoModel> viaticos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Rendiciones anteriores:',
            style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        ...viaticos.take(4).map((v) => _buildViaticoBadge(v)),
      ],
    );
  }

  Widget _buildViaticoBadge(ViaticoModel v) {
    // Colores según estado (tenue y traslúcido, como acordado)
    final isPendiente = v.isPendiente;
    final bgColor = isPendiente
        ? const Color(0xFF9E9E9E).withValues(alpha: 0.12)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.10);
    final borderColor = isPendiente
        ? const Color(0xFF9E9E9E).withValues(alpha: 0.5)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.5);
    final textColor = isPendiente ? const Color(0xFF9E9E9E) : const Color(0xFFFFFFFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Icon(
            isPendiente ? Icons.access_time : Icons.check_circle_outline,
            size: 16,
            color: textColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_fmtDate(v.fechaInicio)} → ${_fmtDate(v.fechaFin)}',
              style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isPendiente ? 'Pendiente' : 'Pagado',
              style: TextStyle(
                  color: isPendiente ? Colors.black : Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          // ── Menú de opciones ──
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: textColor, size: 20),
            color: const Color(0xFF1E1E1E),
            onSelected: (val) {
              if (val == 'pdf') {
                _regenerarPdf(v);
              } else if (val == 'delete') {
                _eliminarRendicion(v);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Descargar PDF', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              if (isPendiente)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Eliminar Rendición', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Funciones de opciones ────────────────────────────────────────────────

  Future<void> _regenerarPdf(ViaticoModel v) async {
    setState(() => _isGenerating = true);
    try {
      final user = ref.read(currentUserProfileProvider).value;
      final config = ref.read(companyConfigProvider).value ?? CompanyConfigModel(idEmpresa: user?.idEmpresa ?? '');
      if (user == null) throw Exception('No hay usuario activo');

      final trips = await ref.read(tripRepositoryProvider).getTripsByDateRange(
            v.fechaInicio,
            v.fechaFin,
          );

      if (trips.isEmpty) {
         throw Exception('No se encontraron viajes para ese periodo.');
      }

      await PdfService.generateAndShareViaticosPdf(
          user, v.fechaInicio, v.fechaFin, trips, config);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _eliminarRendicion(ViaticoModel v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Eliminar Rendición', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Estás seguro de que deseas eliminar esta rendición pendiente?\n\nAl eliminarla, los días y viajes quedarán liberados para que puedas incluirlos en una nueva rendición.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(tripRepositoryProvider).deleteViatico(v.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rendición eliminada correctamente.'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
