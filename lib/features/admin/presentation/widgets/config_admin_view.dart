import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../domain/models/company_config_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

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

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final config = ref.read(companyConfigProvider).value;
      if (config != null) _loadConfig(config);
    });
  }

  void _loadConfig(CompanyConfigModel config) {
    _sueldoMinimoCtrl.text = config.sueldoMinimo.toStringAsFixed(0);
    _umbralKmCtrl.text = config.umbralKilometrosViatico.toStringAsFixed(0);
    _tasaSISCtrl.text = config.tasaSIS.toString();
    _tasaMutualCtrl.text = config.tasaMutual.toString();
    _comisionCtrl.text = config.porcentajeComision.toString();
    _utmCtrl.text = config.valorUTM.toStringAsFixed(0);
    _dieselNetoCtrl.text = config.precioDieselNeto.toStringAsFixed(0);
    _diasLaboralesCtrl.text = config.diasLaboralesMes.toString();
    _margenObjetivoCtrl.text = config.margenObjetivoCotizacion.toStringAsFixed(1);
    _razonSocialCtrl.text = config.emisorRazonSocial;
    _rutCtrl.text = config.emisorRut;
    _giroCtrl.text = config.emisorGiro;
    _direccionCtrl.text = config.emisorDireccion;
    _telefonoCtrl.text = config.emisorTelefono;
    _emailCtrl.text = config.emisorEmail;
    setState(() {
      _tipoViatico = config.tipoViatico;
      _logoBase64 = config.emisorLogoBase64;
      _logoPreviewBytes = config.emisorLogoBase64.isNotEmpty
          ? base64Decode(config.emisorLogoBase64)
          : null;
      _maintenanceRules = List<Map<String, dynamic>>.from(config.maintenanceRules.map((e) => Map<String, dynamic>.from(e)));
    });
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
        maintenanceRules: _maintenanceRules,
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

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(companyConfigProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
      error: (e, s) => Center(child: Text('Error: $e')),
      data: (config) {
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
                          ],
                        ),
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
                        Text('\$${_maintenanceRules.fold(0.0, (sum, rule) => sum + ((rule['cost'] as double) / (rule['km'] as double))).toStringAsFixed(2)} / km', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                  )
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
