import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../domain/models/company_config_model.dart';
import '../../domain/models/recurring_expense_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import 'csv_importer_dialog.dart';
import '../../../../core/services/app_update_service.dart';

class ConfigAdminView extends ConsumerStatefulWidget {
  const ConfigAdminView({super.key});

  @override
  ConsumerState<ConfigAdminView> createState() => _ConfigAdminViewState();
}

class _ConfigAdminViewState extends ConsumerState<ConfigAdminView> {
  final _sueldoMinimoCtrl = TextEditingController();
  final _umbralKmCtrl = TextEditingController();
  final _tasaSISCtrl = TextEditingController();
  final _tasaMutualCtrl = TextEditingController();
  final _comisionCtrl = TextEditingController();
  final _utmCtrl = TextEditingController();
  final _dieselNetoCtrl = TextEditingController();
  final _diasLaboralesCtrl = TextEditingController();
  final _margenObjetivoCtrl = TextEditingController();
  final _ppmCtrl = TextEditingController();
  final _remanenteCtrl = TextEditingController();
  final _recuperacionIepdCtrl = TextEditingController();
  bool _isActivatingOta = false;

  // Emisor
  final _razonSocialCtrl = TextEditingController();
  final _rutCtrl = TextEditingController();
  final _giroCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _logoBase64 = '';
  Uint8List? _logoPreviewBytes;
  bool _isUploadingLogo = false;
  
  String _tipoViatico = 'POR_VIAJE';
  bool _isSaving = false;

  List<Map<String, dynamic>> _maintenanceRules = [];
  List<RecurringExpenseModel> _recurringExpenses = [];

  String? _loadedConfigId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final config = ref.read(companyConfigProvider).value;
      if (config != null) _loadConfig(config);
    });
  }

  void _loadConfig(CompanyConfigModel config) {
    _loadedConfigId = config.idEmpresa;
    _sueldoMinimoCtrl.text = config.sueldoMinimo.toStringAsFixed(0);
    _umbralKmCtrl.text = config.umbralKilometrosViatico.toStringAsFixed(0);
    _tasaSISCtrl.text = config.tasaSIS.toString();
    _tasaMutualCtrl.text = config.tasaMutual.toString();
    _comisionCtrl.text = config.porcentajeComision.toString();
    _utmCtrl.text = config.valorUTM.toStringAsFixed(0);
    _dieselNetoCtrl.text = config.precioDieselNeto.toStringAsFixed(0);
    _diasLaboralesCtrl.text = config.diasLaboralesMes.toString();
    _margenObjetivoCtrl.text = config.margenObjetivoCotizacion.toStringAsFixed(1);
    _ppmCtrl.text = config.tasaPPM.toStringAsFixed(1);
    _remanenteCtrl.text = config.remanenteCreditoFiscalAcumulado.toStringAsFixed(0);
    _recuperacionIepdCtrl.text = config.porcentajeRecuperacionIepd.toStringAsFixed(0);
    _razonSocialCtrl.text = config.emisorRazonSocial;
    _rutCtrl.text = config.emisorRut;
    _giroCtrl.text = config.emisorGiro;
    _direccionCtrl.text = config.emisorDireccion;
    _telefonoCtrl.text = config.emisorTelefono;
    _emailCtrl.text = config.emisorEmail;
    _tipoViatico = config.tipoViatico;
    _logoBase64 = config.emisorLogoBase64;
    _logoPreviewBytes = config.emisorLogoBase64.isNotEmpty
        ? base64Decode(config.emisorLogoBase64)
        : null;
    _maintenanceRules = List<Map<String, dynamic>>.from(config.maintenanceRules.map((e) => Map<String, dynamic>.from(e)));
    _recurringExpenses = List<RecurringExpenseModel>.from(config.gastosRecurrentes);
  }

  Future<void> _pickLogo() async {
    setState(() => _isUploadingLogo = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;

      // Decodificar la imagen (soporta PNG, JPEG, BMP, GIF, etc.)
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo leer la imagen. Intenta con PNG o JPEG.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Redimensionar a máx 300px de ancho manteniendo proporción
      final resized = decoded.width > 300
          ? img.copyResize(decoded, width: 300)
          : decoded;

      // Re-codificar como PNG (preserva transparencia para logos)
      final compressedBytes = Uint8List.fromList(img.encodePng(resized));

      final b64 = base64Encode(compressedBytes);
      setState(() {
        _logoBase64 = b64;
        _logoPreviewBytes = compressedBytes;
      });

      if (mounted) {
        final sizeKB = (compressedBytes.lengthInBytes / 1024).toStringAsFixed(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Logo procesado: ${resized.width}x${resized.height}px · $sizeKB KB'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar logo: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final user = ref.read(currentUserProfileProvider).value;
      if (user == null) return;

      final currentConfig = ref.read(companyConfigProvider).value;

      final newConfig = CompanyConfigModel(
        idEmpresa: user.idEmpresa,
        sueldoMinimo: double.tryParse(_sueldoMinimoCtrl.text.replaceAll('.', '')) ?? 539000,
        umbralKilometrosViatico: double.tryParse(_umbralKmCtrl.text) ?? 100,
        tasaSIS: double.tryParse(_tasaSISCtrl.text) ?? 1.49,
        tasaMutual: double.tryParse(_tasaMutualCtrl.text) ?? 0.90,
        porcentajeComision: double.tryParse(_comisionCtrl.text) ?? 10.0,
        tipoViatico: _tipoViatico,
        valorUTM: double.tryParse(_utmCtrl.text.replaceAll('.', '')) ?? 65000,
        precioDieselNeto: double.tryParse(_dieselNetoCtrl.text.replaceAll('.', '')) ?? 800,
        diasLaboralesMes: int.tryParse(_diasLaboralesCtrl.text) ?? 22,
        margenObjetivoCotizacion: double.tryParse(_margenObjetivoCtrl.text) ?? 25.0,
        tasaPPM: double.tryParse(_ppmCtrl.text.replaceAll(',', '.')) ?? 1.5,
        remanenteCreditoFiscalAcumulado: double.tryParse(_remanenteCtrl.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0,
        porcentajeRecuperacionIepd: double.tryParse(_recuperacionIepdCtrl.text) ?? 80.0,
        maintenanceRules: _maintenanceRules,
        gastosRecurrentes: _recurringExpenses,
        mesesGastosFijosAplicados: currentConfig?.mesesGastosFijosAplicados ?? [],
        utmHistory: currentConfig?.utmHistory ?? {},
        dieselHistory: currentConfig?.dieselHistory ?? {},
        extras: currentConfig?.extras ?? {},
        emisorRazonSocial: _razonSocialCtrl.text.trim(),
        emisorRut: _rutCtrl.text.trim(),
        emisorGiro: _giroCtrl.text.trim(),
        emisorDireccion: _direccionCtrl.text.trim(),
        emisorTelefono: _telefonoCtrl.text.trim(),
        emisorEmail: _emailCtrl.text.trim(),
        emisorLogoBase64: _logoBase64,
      );

      await ref.read(adminRepositoryProvider).updateCompanyConfig(newConfig);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Configuración actualizada correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addMaintenanceRule() {
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final kmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Nueva Regla de Mantenimiento', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(nameCtrl, 'Nombre (Ej: Neumáticos)', ''),
            const SizedBox(height: 12),
            _buildTextField(costCtrl, 'Costo Total (\$)', 'Ej: 1000000'),
            const SizedBox(height: 12),
            _buildTextField(kmCtrl, 'Duración en Kilómetros', 'Ej: 100000'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              final name = nameCtrl.text;
              final cost = double.tryParse(costCtrl.text.replaceAll('.', '')) ?? 0.0;
              final km = double.tryParse(kmCtrl.text.replaceAll('.', '')) ?? 0.0;
              
              if (name.isNotEmpty && km > 0) {
                setState(() {
                  _maintenanceRules.add({
                    'name': name,
                    'cost': cost,
                    'km': km,
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _addRecurringExpense(List<VehicleModel> vehicles) {
    final nameCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    String tipo = 'Seguro';
    String? selectedVehicle;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Nuevo Gasto Fijo Mensual', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(nameCtrl, 'Nombre descriptivo', 'Ej: GPS ModoGPS, Seguro Carga'),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tipo de Gasto', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: tipo,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: ['Seguro', 'GPS', 'Arriendo', 'Leasing', 'Combustible', 'Peaje', 'Mantención', 'Sueldo', 'Otros']
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (val) => setDialogState(() => tipo = val!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(montoCtrl, 'Monto Mensual (\$)', 'Ej: 150000'),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vehículo (opcional)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: selectedVehicle,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        hint: const Text('General (toda la empresa)', style: TextStyle(color: Colors.white54)),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('General (toda la empresa)', style: TextStyle(color: Colors.white70))),
                          ...vehicles.map((v) => DropdownMenuItem(value: v.id, child: Text(v.patente))),
                        ],
                        onChanged: (val) => setDialogState(() => selectedVehicle = val),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final monto = double.tryParse(montoCtrl.text.replaceAll('.', '')) ?? 0.0;
                
                if (name.isNotEmpty && monto > 0) {
                  setState(() {
                    _recurringExpenses.add(RecurringExpenseModel(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      nombre: name,
                      tipo: tipo,
                      monto: monto,
                      vehicleId: selectedVehicle,
                      activo: true,
                    ));
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(companyConfigProvider);
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final vehicles = vehiclesAsync.value ?? [];

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
      error: (e, s) => Center(child: Text('Error: $e')),
      data: (config) {
        if (config != null && _loadedConfigId != config.idEmpresa) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _loadConfig(config));
          });
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Configuración de Empresa',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('Define las reglas de negocio y parámetros financieros globales.',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 40),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- SECCIÓN POLÍTICA DE VIÁTICOS ---
                  Expanded(
                    flex: 1,
                    child: _buildSectionCard(
                      title: 'Política de Viáticos',
                      icon: Icons.payments_outlined,
                      children: [
                        const Text('¿Cómo se deben calcular los viáticos de los conductores?',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 20),
                        RadioGroup<String>(
                          groupValue: _tipoViatico,
                          onChanged: (val) => setState(() => _tipoViatico = val!),
                          child: Column(
                            children: [
                              _buildRadioOption(
                                title: 'Por Viaje Realizado',
                                subtitle: 'Se paga un viático por cada viaje que supere el umbral de KM.',
                                value: 'POR_VIAJE',
                              ),
                              const SizedBox(height: 12),
                              _buildRadioOption(
                                title: 'Por Jornada Diaria',
                                subtitle: 'Se paga un solo viático por día trabajado (si algún viaje supera el umbral).',
                                value: 'POR_JORNADA',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildTextField(_umbralKmCtrl, 'Umbral de Kilómetros para Viático Largo', 'Ej: 100'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // --- SECCIÓN PARÁMETROS FINANCIEROS Y TRIBUTARIOS ---
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        _buildSectionCard(
                          title: 'Parámetros Financieros',
                          icon: Icons.account_balance_outlined,
                          children: [
                            _buildTextField(_sueldoMinimoCtrl, 'Sueldo Mínimo Nacional (CLP)', 'Ej: 539000'),
                            const SizedBox(height: 16),
                            _buildTextField(_comisionCtrl, 'Comisión por Facturación (%)', 'Ej: 10.0'),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _buildTextField(_tasaSISCtrl, 'Tasa SIS (%)', 'Ej: 1.49')),
                                const SizedBox(width: 16),
                                Expanded(child: _buildTextField(_tasaMutualCtrl, 'Tasa Mutual (%)', 'Ej: 0.90')),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _buildTextField(_diasLaboralesCtrl, 'Días Laborales/Mes', 'Ej: 22')),
                                const SizedBox(width: 16),
                                Expanded(child: _buildTextField(_margenObjetivoCtrl, 'Margen Cotizador (%)', 'Ej: 25.0')),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSectionCard(
                          title: 'Parámetros Tributarios (F29)',
                          icon: Icons.request_quote_outlined,
                          children: [
                            const Text('Valores para cálculo de recuperación Ley 19.764',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(child: _buildTextField(_utmCtrl, 'Valor UTM del Mes', 'Ej: 65000')),
                                const SizedBox(width: 16),
                                Expanded(child: _buildTextField(_dieselNetoCtrl, 'Diésel Neto (Referencia)', 'Ej: 800')),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _buildTextField(_remanenteCtrl, '⭐ Remanente IVA Crédito Acumulado', 'Ej: 3991596 (Compra camión)')),
                                const SizedBox(width: 16),
                                Expanded(child: _buildTextField(_ppmCtrl, 'Tasa PPM Mensual (%)', 'Ej: 1.5')),
                              ],
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<double>(
                              initialValue: [80.0, 50.0, 31.0].contains(double.tryParse(_recuperacionIepdCtrl.text))
                                  ? double.tryParse(_recuperacionIepdCtrl.text)
                                  : 80.0,
                              dropdownColor: const Color(0xFF1E1E1E),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Tramo Recuperación Diésel (Ley 19.764)',
                                labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                                helperText: '80% (Ventas ≤ 2.400 UF), 50% (≤ 6.000 UF), 31% (> 6.000 UF)',
                                helperStyle: const TextStyle(color: Colors.white54, fontSize: 11),
                                filled: true,
                                fillColor: const Color(0xFF161A22),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                              items: const [
                                DropdownMenuItem(value: 80.0, child: Text('80% - Ventas ≤ 2.400 UF (Micro y Pequeña Empresa)')),
                                DropdownMenuItem(value: 50.0, child: Text('50% - Ventas 2.401 a 6.000 UF (Mediana Empresa)')),
                                DropdownMenuItem(value: 31.0, child: Text('31% - Ventas > 6.000 UF (Mediana/Gran Empresa)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _recuperacionIepdCtrl.text = val.toStringAsFixed(0);
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'El Remanente Acumulado se descuenta automáticamente del IVA débito mes a mes hasta agotarse.',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // --- SECCIÓN CONTROL DE ACTUALIZACIÓN EN LÍNEA (OTA) ---
              _buildSectionCard(
                title: 'Control de Versiones y Actualización en Línea (OTA)',
                icon: Icons.system_update_alt,
                children: [
                  const Text(
                    'Permite activar y forzar actualizaciones automáticas e inalámbricas en los celulares de todos los choferes.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.verified_outlined, color: Colors.greenAccent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Nueva Versión Lista: v1.1.0 (Build 11)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Incluye: Endurecimiento de reglas de seguridad, radar de tarifas por ruta, deducción IEPD Ley 19.764 y buffer GPS de alta resiliencia.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.link, color: Colors.amber, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Canal Oficial: GitHub Releases (Direct CDN v1.1.0)',
                                  style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_isActivatingOta) ...[
                          const Row(
                            children: [
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                              SizedBox(width: 12),
                              Text('Notificando a la flota... Por favor espera.', style: TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.cloud_done_rounded),
                            label: const Text(
                              'ACTIVAR / FORZAR ACTUALIZACIÓN OTA v1.1.0 EN FLOTA',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: () async {
                              setState(() => _isActivatingOta = true);
                              try {
                                await AppUpdateService.publishAppVersion(
                                  buildNumber: 11,
                                  versionName: '1.1.0',
                                  apkUrl: 'https://github.com/criszz92/bitacora-tms/releases/download/v1.1.0/bitacora-tms-v1.1.0.apk',
                                  releaseNotes: 'Actualización obligatoria v1.1.0: Endurecimiento de seguridad, radar de tarifas, Ley 19.764 y telemetría.',
                                  mandatory: true,
                                );

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✓ Actualización v1.1.0 (Build 11) activada en GitHub Releases para todos los conductores.'),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 5),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error al activar actualización: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isActivatingOta = false);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // --- SECCIÓN PARÁMETROS DE MANTENIMIENTO DE FLOTA ---
              _buildSectionCard(
                title: 'Parámetros de Mantenimiento de Flota',
                icon: Icons.build_circle_outlined,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Define reglas dinámicas para el cálculo del costo de desgaste por kilómetro.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ElevatedButton.icon(
                        onPressed: _addMaintenanceRule,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar Regla'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white),
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_maintenanceRules.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Text('No hay reglas definidas. Agrega Neumáticos, Aceites, etc.', style: TextStyle(color: Colors.white54, fontSize: 13))),
                    )
                  else
                    Column(
                      children: _maintenanceRules.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final rule = entry.value;
                        final costPerKm = (rule['cost'] as double) / (rule['km'] as double);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rule['name'], style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Costo Total: \$${(rule['cost'] as double).toStringAsFixed(0)} | Duración: ${(rule['km'] as double).toStringAsFixed(0)} km', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                              Row(
                                children: [
                                  Text('\$${costPerKm.toStringAsFixed(2)} / km', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(width: 16),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => setState(() => _maintenanceRules.removeAt(idx)),
                                  )
                                ],
                              )
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Costo Total Estimado de Mantenimiento', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        Text('\$${_maintenanceRules.fold(0.0, (total, rule) => total + ((rule['cost'] as double) / (rule['km'] as double))).toStringAsFixed(2)} / km', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                  )
                ],
              ),
              
              const SizedBox(height: 24),
              // ─── SECCIÓN GASTOS FIJOS MENSUALES ────────────────────
              _buildSectionCard(
                title: 'Gastos Fijos Mensuales',
                icon: Icons.repeat_outlined,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text('Define gastos recurrentes que se aplican cada mes (GPS, Seguros, Arriendos, etc.). Estos se pueden aplicar al mes con un solo click desde el Dashboard.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _addRecurringExpense(vehicles),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar Gasto Fijo'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black),
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_recurringExpenses.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Text('No hay gastos fijos definidos. Agrega GPS, Seguros, Arriendos, etc.', style: TextStyle(color: Colors.white54, fontSize: 13))),
                    )
                  else
                    Column(
                      children: _recurringExpenses.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final gasto = entry.value;
                        final vehicleName = gasto.vehicleId != null
                            ? vehicles.where((v) => v.id == gasto.vehicleId).firstOrNull?.patente ?? 'Vehículo'
                            : 'General';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: gasto.activo ? Colors.black26 : Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: gasto.activo ? Colors.orange.withValues(alpha: 0.3) : Colors.white12),
                          ),
                          child: Row(
                            children: [
                              // Toggle activo/inactivo
                              GestureDetector(
                                onTap: () => setState(() {
                                  _recurringExpenses[idx] = gasto.copyWith(activo: !gasto.activo);
                                }),
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: gasto.activo ? Colors.orange.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    gasto.activo ? Icons.check_circle : Icons.pause_circle_outline,
                                    color: gasto.activo ? Colors.orange : Colors.white38,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      gasto.nombre,
                                      style: TextStyle(
                                        color: gasto.activo ? Colors.white : Colors.white38,
                                        fontWeight: FontWeight.bold,
                                        decoration: gasto.activo ? null : TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                          child: Text(gasto.tipo, style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(gasto.vehicleId != null ? Icons.local_shipping : Icons.business, size: 12, color: Colors.white38),
                                        const SizedBox(width: 4),
                                        Text(vehicleName, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '\$${gasto.monto.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: gasto.activo ? Colors.white : Colors.white38,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => setState(() => _recurringExpenses.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  if (_recurringExpenses.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Gastos Fijos Mensuales', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                              Text('${_recurringExpenses.where((g) => g.activo).length} gastos activos de ${_recurringExpenses.length} definidos', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            ],
                          ),
                          Text(
                            '\$${_recurringExpenses.where((g) => g.activo).fold<double>(0, (total, g) => total + g.monto).toStringAsFixed(0)} / mes',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 24),
              // ─── SECCIÓN CENTRO DE IMPORTACIÓN MASIVA (CSV) ─────────
              _buildSectionCard(
                title: 'Centro de Importación Masiva (CSV)',
                icon: Icons.upload_file_outlined,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Importa catálogos completos de Peajes (con tarifas por ejes) y Clientes con sus geocercas.',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'El sistema valida duplicados automáticamente para evitar sobreescrituras innecesarias.',
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => const CsvImporterDialog(),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.file_upload, size: 18),
                        label: const Text('Abrir Importador CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),
              // ─── SECCIÓN DATOS DEL EMISOR (para cotizaciones PDF) ───
              _buildSectionCard(
                title: 'Datos del Emisor (Proformas / Cotizaciones)',
                icon: Icons.business_outlined,
                children: [
                  const Text(
                    'Esta información aparece en el encabezado del PDF de cotizaciones.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: _buildTextField(_razonSocialCtrl, 'Razón Social', 'Ej: Transportes Inostroza SpA')),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField(_rutCtrl, 'RUT Empresa', 'Ej: 76.123.456-7')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(_giroCtrl, 'Giro Comercial', 'Ej: Transporte de Carga por Carretera'),
                  const SizedBox(height: 16),
                  _buildTextField(_direccionCtrl, 'Dirección', 'Ej: Av. Principal 1234, Santiago'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildTextField(_telefonoCtrl, 'Teléfono', 'Ej: +56 9 1234 5678')),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField(_emailCtrl, 'Email de Contacto', 'Ej: contacto@empresa.cl')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Logo
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Preview
                      Container(
                        width: 120,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: _logoPreviewBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(_logoPreviewBytes!, fit: BoxFit.contain),
                              )
                            : const Center(
                                child: Icon(Icons.image_outlined, color: Colors.white24, size: 32),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Logo de Empresa', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 8),
                            const Text(
                              'Máx. 200 KB · PNG o JPEG · Recomendado: 300px de ancho',
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _isUploadingLogo ? null : _pickLogo,
                                  icon: _isUploadingLogo
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                      : const Icon(Icons.upload_outlined, size: 16),
                                  label: const Text('Subir Logo'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                                if (_logoPreviewBytes != null) ...
                                  [
                                    const SizedBox(width: 12),
                                    TextButton.icon(
                                      onPressed: () => setState(() {
                                        _logoBase64 = '';
                                        _logoPreviewBytes = null;
                                      }),
                                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                      label: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                                    ),
                                  ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 40),
              const Divider(color: Colors.white10),
              const SizedBox(height: 20),
              
              SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : _saveConfig,
                  icon: _isSaving 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.save_outlined),
                  label: const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(24),
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
              Icon(icon, color: Colors.orange, size: 20),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRadioOption({required String title, required String subtitle, required String value}) {
    final isSelected = _tipoViatico == value;
    return InkWell(
      onTap: () => setState(() => _tipoViatico = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.orange : Colors.white12),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              activeColor: Colors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isSelected ? Colors.orange : Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}
