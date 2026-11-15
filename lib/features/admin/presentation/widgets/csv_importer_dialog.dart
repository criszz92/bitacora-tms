import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/infraestructura_repository.dart';
import '../../domain/models/infraestructura_vial_model.dart';
import '../../domain/services/modogps_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Diálogo y Asistente de Carga Masiva CSV para:
/// 1. Peajes con tarifas por ejes
/// 2. Clientes y Plantas operacionales
class CsvImporterDialog extends ConsumerStatefulWidget {
  const CsvImporterDialog({super.key});

  @override
  ConsumerState<CsvImporterDialog> createState() => _CsvImporterDialogState();
}

class _CsvImporterDialogState extends ConsumerState<CsvImporterDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Estado Importador de Peajes
  bool _isProcessingPeajes = false;
  String? _peajesFileName;
  List<Map<String, dynamic>> _parsedPeajes = [];
  int _peajesDuplicatesCount = 0;
  String? _peajesError;

  // Estado Importador de Clientes
  bool _isProcessingClientes = false;
  String? _clientesFileName;
  List<Map<String, dynamic>> _parsedClientes = [];
  int _clientesDuplicatesCount = 0;
  String? _clientesError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 820,
        height: 640,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.upload_file, color: Colors.blueAccent, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CENTRO DE IMPORTACIÓN MASIVA (CSV)',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Importa peajes y clientes directamente a la base de datos sin duplicaciones.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Selector de Pestañas
            Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(icon: Icon(Icons.toll, size: 18), text: 'Importar Peajes (Tarifas por Ejes)'),
                  Tab(icon: Icon(Icons.location_on, size: 18), text: 'Importar Clientes / Plantas'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Contenido según pestaña
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPeajesTab(),
                  _buildClientesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PESTAÑA 1: IMPORTADOR DE PEAJES
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildPeajesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isProcessingPeajes ? null : _pickAndParsePeajesCsv,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.file_open, size: 18),
              label: Text(_peajesFileName != null ? 'Cambiar Archivo CSV' : 'Seleccionar CSV de Peajes'),
            ),
            if (_peajesFileName != null) ...[
              const SizedBox(width: 12),
              Text(
                'Archivo: $_peajesFileName',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
            const Spacer(),
            if (_parsedPeajes.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isProcessingPeajes ? null : _savePeajesToFirestore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent[700],
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isProcessingPeajes
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  _isProcessingPeajes ? 'Guardando en Base de Datos...' : 'Guardar ${_parsedPeajes.length} Peajes',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),

        if (_peajesError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(_peajesError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          ),
        ],

        if (_peajesDuplicatesCount > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'ℹ️ Se omitieron $_peajesDuplicatesCount peajes que ya existían previamente en la base de datos para no duplicar.',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Previsualización de tabla
        Expanded(
          child: _parsedPeajes.isEmpty
              ? Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_chart_outlined, color: Colors.white24, size: 40),
                        SizedBox(height: 10),
                        Text(
                          'Selecciona tu CSV de peajes para previsualizar los datos antes de guardar.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListView.separated(
                    itemCount: _parsedPeajes.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, idx) {
                      final p = _parsedPeajes[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.toll, color: Colors.amberAccent, size: 20),
                        title: Text(p['nombre'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        subtitle: Text(
                          '${p['ruta']} • Lat: ${p['lat']} Lng: ${p['lng']}',
                          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                              child: Text(
                                '2 Ejes: \$${(p['tarifa2Ejes'] as double).toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                              child: Text(
                                '>2 Ejes: \$${(p['tarifaMas2Ejes'] as double).toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PESTAÑA 2: IMPORTADOR DE CLIENTES
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildClientesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isProcessingClientes ? null : _pickAndParseClientesCsv,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.file_open, size: 18),
              label: Text(_clientesFileName != null ? 'Cambiar Archivo CSV' : 'Seleccionar CSV de Clientes'),
            ),
            if (_clientesFileName != null) ...[
              const SizedBox(width: 12),
              Text(
                'Archivo: $_clientesFileName',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
            const Spacer(),
            if (_parsedClientes.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isProcessingClientes ? null : _saveClientesToFirestore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent[700],
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isProcessingClientes
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  _isProcessingClientes ? 'Guardando...' : 'Guardar ${_parsedClientes.length} Clientes',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),

        if (_clientesError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(_clientesError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          ),
        ],

        if (_clientesDuplicatesCount > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'ℹ️ Se omitieron $_clientesDuplicatesCount clientes duplicados o que ya se encontraban registrados.',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Previsualización de tabla
        Expanded(
          child: _parsedClientes.isEmpty
              ? Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_outlined, color: Colors.white24, size: 40),
                        SizedBox(height: 10),
                        Text(
                          'Selecciona tu CSV de clientes para previsualizar las geocercas.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: ListView.separated(
                    itemCount: _parsedClientes.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, idx) {
                      final c = _parsedClientes[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on, color: Colors.cyanAccent, size: 20),
                        title: Text(c['cliente'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        subtitle: Text('Lat: ${c['lat']} Lng: ${c['lng']}', style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Confianza: ${c['confianza']}',
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // LÓGICA DE PARSEO Y GUARDADO DE PEAJES
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _pickAndParsePeajesCsv() async {
    setState(() {
      _peajesError = null;
      _peajesDuplicatesCount = 0;
    });

    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;

      final file = res.files.first;
      final content = utf8.decode(file.bytes!);
      final lines = const LineSplitter().convert(content);

      if (lines.length <= 1) {
        setState(() => _peajesError = 'El archivo está vacío o no contiene filas.');
        return;
      }

      // Obtener peajes existentes en Firestore para evitar duplicados
      final repo = ref.read(infraestructuraRepositoryProvider);
      final existingPuntos = await repo.getPuntos(soloActivos: false);
      final existingKeys = <String>{};

      for (final ep in existingPuntos) {
        final key = '${ep.nombre.trim().toUpperCase()}_${ep.lat.toStringAsFixed(4)}_${ep.lng.toStringAsFixed(4)}';
        existingKeys.add(key);
      }

      final parsed = <Map<String, dynamic>>[];
      int duplicates = 0;

      // Detectar si el CSV viene en formato multilínea o tabular (por coma)
      final firstLine = lines.first.toLowerCase();
      final isTabular = firstLine.contains(',') && firstLine.contains('nombre');

      if (isTabular) {
        final headers = _parseCsvLine(lines.first).map((h) => h.trim().toLowerCase()).toList();
        final idxNombre = headers.indexOf('nombre');
        final idxRuta = headers.indexOf('ruta');
        final idxTipo = headers.indexOf('tipo');
        final idxLat = headers.indexOf('latitud');
        final idxLng = headers.indexOf('longitud');
        final idxT2 = headers.indexOf('tarifa_2ejes_max_clp');
        final idxTMas2 = headers.contains('tarifa_mas2ejes_normal_clp')
            ? headers.indexOf('tarifa_mas2ejes_normal_clp')
            : headers.indexOf('tarifa_mas2ejes_max_clp');

        for (int i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          final cols = _parseCsvLine(line);
          if (cols.length <= idxLat || cols.length <= idxLng) continue;

          final nombre = idxNombre != -1 ? cols[idxNombre].trim() : 'Peaje';
          final ruta = idxRuta != -1 ? cols[idxRuta].trim() : '';
          final subtipo = idxTipo != -1 ? cols[idxTipo].trim() : 'troncal';
          final lat = double.tryParse(cols[idxLat].trim());
          final lng = double.tryParse(cols[idxLng].trim());
          final t2 = idxT2 != -1 ? double.tryParse(cols[idxT2].trim()) ?? 0.0 : 0.0;
          final tMas2 = idxTMas2 != -1 ? double.tryParse(cols[idxTMas2].trim()) ?? 0.0 : 0.0;

          if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
            final key = '${nombre.toUpperCase()}_${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
            if (existingKeys.contains(key)) {
              duplicates++;
              continue;
            }
            existingKeys.add(key);
            parsed.add({
              'nombre': nombre,
              'ruta': ruta,
              'subtipo': subtipo,
              'lat': lat,
              'lng': lng,
              'tarifa2Ejes': t2,
              'tarifaMas2Ejes': tMas2,
            });
          }
        }
      } else {
        // Bloque vertical estándar
        int i = 0;
        // Saltar cabecera si viene en lista
        while (i < lines.length && (lines[i].trim().toLowerCase() == 'nombre' || lines[i].trim().toLowerCase() == 'ruta' || lines[i].trim().toLowerCase() == 'latitud')) {
          i++;
        }

        while (i < lines.length) {
          final line = lines[i].trim();
          if (line.toLowerCase().startsWith('peaje')) {
            final nombre = line;
            final ruta = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
            final subtipo = (i + 2 < lines.length) ? lines[i + 2].trim() : 'troncal';
            final lat = (i + 3 < lines.length) ? double.tryParse(lines[i + 3].trim()) : null;
            final lng = (i + 4 < lines.length) ? double.tryParse(lines[i + 4].trim()) : null;
            
            double tMas2 = 0.0;
            double t2 = 0.0;

            // Buscar tarifas numéricas en las siguientes 5 líneas
            for (int k = i + 5; k < math.min(i + 12, lines.length); k++) {
              final val = double.tryParse(lines[k].trim());
              if (val != null && val > 500) {
                if (tMas2 == 0.0) {
                  tMas2 = val;
                } else if (t2 == 0.0 && val != tMas2) {
                  t2 = val;
                }
              }
            }

            if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
              final key = '${nombre.toUpperCase()}_${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
              if (existingKeys.contains(key)) {
                duplicates++;
              } else {
                existingKeys.add(key);
                parsed.add({
                  'nombre': nombre,
                  'ruta': ruta,
                  'subtipo': subtipo,
                  'lat': lat,
                  'lng': lng,
                  'tarifa2Ejes': t2 > 0 ? t2 : (tMas2 * 0.55),
                  'tarifaMas2Ejes': tMas2,
                });
              }
            }
            i += 6;
          } else {
            i++;
          }
        }
      }

      setState(() {
        _peajesFileName = file.name;
        _parsedPeajes = parsed;
        _peajesDuplicatesCount = duplicates;
      });
    } catch (e) {
      setState(() => _peajesError = 'Error leyendo el archivo: $e');
    }
  }

  Future<void> _savePeajesToFirestore() async {
    if (_parsedPeajes.isEmpty) return;
    setState(() => _isProcessingPeajes = true);

    try {
      final repo = ref.read(infraestructuraRepositoryProvider);
      final user = ref.read(currentUserProfileProvider).value;
      final creadoPor = user?.nombre ?? 'Administrador TMS';

      for (final p in _parsedPeajes) {
        final punto = PuntoInfraestructuraModel(
          id: '',
          nombre: p['nombre'],
          tipo: TipoPuntoInfraestructura.peaje,
          subtipo: (p['subtipo'] ?? 'Troncal').toString().toUpperCase().contains('LATERAL') ? 'Lateral' : 'Troncal',
          ruta: p['ruta'] ?? '',
          lat: p['lat'],
          lng: p['lng'],
          radioMetros: 120.0,
          sentido: 'Bidireccional',
          tarifaCamionSimple: p['tarifa2Ejes'],
          tarifaCamionPesado: p['tarifaMas2Ejes'],
          admiteTag: true,
          concesionaria: p['ruta'] != null && p['ruta'].toString().isNotEmpty ? 'Autopista ${p['ruta']}' : 'Concesión Vial',
          creadoPor: creadoPor,
          createdAt: DateTime.now(),
          origenDato: 'csv_masivo',
          activo: true,
        );
        await repo.guardarPunto(punto);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_parsedPeajes.length} peajes agregados exitosamente a la base de datos.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _peajesError = 'Error al guardar peajes: $e';
        _isProcessingPeajes = false;
      });
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // LÓGICA DE PARSEO Y GUARDADO DE CLIENTES
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _pickAndParseClientesCsv() async {
    setState(() {
      _clientesError = null;
      _clientesDuplicatesCount = 0;
    });

    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;

      final file = res.files.first;
      final content = utf8.decode(file.bytes!);
      final lines = const LineSplitter().convert(content);

      if (lines.length <= 1) {
        setState(() => _clientesError = 'El archivo está vacío.');
        return;
      }

      // Obtener geocercas existentes para no duplicar
      final modoGps = ref.read(modoGpsServiceProvider);
      final existingGeofences = await modoGps.fetchGeofences();
      final existingSet = existingGeofences.map((g) => g.name.trim().toUpperCase()).toSet();

      final parsed = <Map<String, dynamic>>[];
      int duplicates = 0;

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final cols = _parseCsvLine(line);
        if (cols.length < 3) continue;

        final cliente = cols[0].replaceAll('"', '').trim();
        final lat = double.tryParse(cols[1].trim());
        final lng = double.tryParse(cols[2].trim());
        final conf = cols.length >= 4 ? cols[3].trim() : 'alta';

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          if (existingSet.contains(cliente.toUpperCase())) {
            duplicates++;
            continue;
          }
          existingSet.add(cliente.toUpperCase());
          parsed.add({
            'cliente': cliente,
            'lat': lat,
            'lng': lng,
            'confianza': conf,
          });
        }
      }

      setState(() {
        _clientesFileName = file.name;
        _parsedClientes = parsed;
        _clientesDuplicatesCount = duplicates;
      });
    } catch (e) {
      setState(() => _clientesError = 'Error leyendo archivo: $e');
    }
  }

  Future<void> _saveClientesToFirestore() async {
    if (_parsedClientes.isEmpty) return;
    setState(() => _isProcessingClientes = true);

    try {
      // Guardar clientes como geocercas en la infraestructura universal
      final repo = ref.read(infraestructuraRepositoryProvider);
      final user = ref.read(currentUserProfileProvider).value;
      final creadoPor = user?.nombre ?? 'Administrador TMS';

      for (final c in _parsedClientes) {
        final punto = PuntoInfraestructuraModel(
          id: '',
          nombre: c['cliente'],
          tipo: TipoPuntoInfraestructura.descanso, // O planta / geocerca de cliente
          subtipo: 'Cliente / Planta Industrial',
          lat: c['lat'],
          lng: c['lng'],
          radioMetros: c['confianza'] == 'alta' ? 250.0 : 350.0,
          creadoPor: creadoPor,
          createdAt: DateTime.now(),
          origenDato: 'csv_clientes',
        );
        await repo.guardarPunto(punto);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_parsedClientes.length} clientes agregados a las geocercas exitosamente.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _clientesError = 'Error al guardar clientes: $e';
        _isProcessingClientes = false;
      });
    }
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    bool inQuotes = false;
    final sb = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        result.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    result.add(sb.toString());
    return result;
  }
}
