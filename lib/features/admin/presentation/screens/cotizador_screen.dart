import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../providers/cotizador_provider.dart';
import '../providers/admin_provider.dart';
import '../../domain/services/cotizacion_pdf_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../domain/models/cotizacion_model.dart';
import '../../../../core/utils/number_utils.dart';
import 'package:intl/intl.dart';

class CotizadorScreen extends ConsumerStatefulWidget {
  const CotizadorScreen({super.key});

  @override
  ConsumerState<CotizadorScreen> createState() => _CotizadorScreenState();
}

class _CotizadorScreenState extends ConsumerState<CotizadorScreen> {
  final _origenCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  
  final _clienteNombreCtrl = TextEditingController();
  final _clienteRutCtrl = TextEditingController();
  final _clienteContactoCtrl = TextEditingController();
  
  final _kmPosicionamientoCtrl = TextEditingController(text: '0');
  final _kmRutaCtrl = TextEditingController(text: '0');
  final _tarifaCtrl = TextEditingController(text: '0');
  final _dieselCtrl = TextEditingController();
  final _peajesCtrl = TextEditingController(text: '0');
  final _viaticoCtrl = TextEditingController(text: '0');
  final _diasCtrl = TextEditingController(text: '1');
  final _margenCtrl = TextEditingController();

  bool _showAdvanced = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final config = ref.read(companyConfigProvider).value;
      if (config != null) {
        _dieselCtrl.text = config.precioDieselNeto.toStringAsFixed(0);
        _margenCtrl.text = config.margenObjetivoCotizacion.toString();
      }
    });
  }

  @override
  void dispose() {
    _origenCtrl.dispose();
    _destinoCtrl.dispose();
    _clienteNombreCtrl.dispose();
    _clienteRutCtrl.dispose();
    _clienteContactoCtrl.dispose();
    _kmPosicionamientoCtrl.dispose();
    _kmRutaCtrl.dispose();
    _tarifaCtrl.dispose();
    _dieselCtrl.dispose();
    _peajesCtrl.dispose();
    _viaticoCtrl.dispose();
    _diasCtrl.dispose();
    _margenCtrl.dispose();
    super.dispose();
  }

  void _syncFormToProvider() {
    final notifier = ref.read(cotizadorFormProvider.notifier);
    notifier.updateField(
      origen: _origenCtrl.text,
      destino: _destinoCtrl.text,
      clienteNombre: _clienteNombreCtrl.text,
      clienteRut: _clienteRutCtrl.text,
      clienteContacto: _clienteContactoCtrl.text,
      kmPosicionamiento: NumberUtils.tryParseDouble(_kmPosicionamientoCtrl.text) ?? 0,
      kmRuta: NumberUtils.tryParseDouble(_kmRutaCtrl.text) ?? 0,
      tarifaPropuesta: NumberUtils.tryParseDouble(_tarifaCtrl.text) ?? 0,
      precioDieselNetoManual: NumberUtils.tryParseDouble(_dieselCtrl.text),
      peajes: NumberUtils.tryParseDouble(_peajesCtrl.text) ?? 0,
      viaticoManual: NumberUtils.tryParseDouble(_viaticoCtrl.text) ?? 0,
      diasViaje: int.tryParse(_diasCtrl.text) ?? 1,
      margenObjetivoManual: NumberUtils.tryParseDouble(_margenCtrl.text),
    );
  }

  Future<void> _guardarCotizacion() async {
    final formState = ref.read(cotizadorFormProvider);
    final result = ref.read(cotizadorResultProvider);
    final user = ref.read(currentUserProfileProvider).value;

    if (user == null || formState.driver == null || formState.vehicle == null || result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos antes de guardar.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final config = ref.read(companyConfigProvider).value;
      final cotizacion = CotizacionModel(
        id: formState.editandoId ?? '',
        idEmpresa: user.idEmpresa,
        origen: formState.origen,
        destino: formState.destino,
        clienteNombre: formState.clienteNombre,
        clienteRut: formState.clienteRut,
        clienteContacto: formState.clienteContacto,
        vehicleId: formState.vehicle!.id,
        vehiclePatente: formState.vehicle!.patente,
        idChofer: formState.driver!.uid,
        nombreChofer: formState.driver!.nombre,
        kmPosicionamiento: formState.kmPosicionamiento,
        kmRuta: formState.kmRuta,
        tarifaPropuesta: formState.tarifaPropuesta,
        precioDieselNeto: formState.precioDieselNetoManual ?? config?.precioDieselNeto ?? 800,
        peajes: formState.peajes,
        viaticoManual: formState.viaticoManual,
        diasViaje: formState.diasViaje,
        margenObjetivo: formState.margenObjetivoManual ?? config?.margenObjetivoCotizacion ?? 25.0,
        idaYVuelta: formState.idaYVuelta,
        kmTotal: result['kmTotal'] ?? 0,
        litrosConsumidos: result['litrosConsumidos'] ?? 0,
        combustibleNeto: result['combustibleNeto'] ?? 0,
        combustibleBruto: result['combustibleBruto'] ?? 0,
        comision: result['comision'] ?? 0,
        mantenimiento: result['mantenimiento'] ?? 0,
        costoFijoChofer: result['costoFijoChofer'] ?? 0,
        creditoIvaCombustible: result['creditoIvaCombustible'] ?? 0,
        recuperacionLey19764: result['recuperacionLey19764'] ?? 0,
        ivaDebito: result['ivaDebito'] ?? 0,
        costoTotalReal: result['costoTotalReal'] ?? 0,
        margenNetoReal: result['margenNetoReal'] ?? 0,
        margenPorcentaje: result['margenPorcentaje'] ?? 0,
        cpk: result['cpk'] ?? 0,
        tarifaMinimaSugerida: result['tarifaMinimaSugerida'] ?? 0,
        estado: 'borrador',
        creadoPor: user.uid,
        createdAt: DateTime.now(),
      );

      if (formState.editandoId == null) {
        final savedCotizacion = await ref.read(adminRepositoryProvider).saveCotizacion(cotizacion);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Cotización guardada correctamente (${savedCotizacion.numeroCotizacion})'),
              action: SnackBarAction(
                label: 'Generar PDF',
                textColor: Colors.orange,
                onPressed: () async {
                  try {
                    final bytes = await CotizacionPdfService.generarProformaPdf(
                      cotizacion: savedCotizacion,
                      config: config!,
                    );
                    await Printing.sharePdf(bytes: bytes, filename: '${savedCotizacion.numeroCotizacion}.pdf');
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
              ),
            ),
          );
          _limpiar();
        }
      } else {
        await ref.read(adminRepositoryProvider).updateCotizacion(cotizacion);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Cotización actualizada correctamente')),
          );
          _limpiar();
        }
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

  void _limpiar() {
    _origenCtrl.clear();
    _destinoCtrl.clear();
    _clienteNombreCtrl.clear();
    _clienteRutCtrl.clear();
    _clienteContactoCtrl.clear();
    _kmPosicionamientoCtrl.text = '0';
    _kmRutaCtrl.text = '0';
    _tarifaCtrl.text = '0';
    _peajesCtrl.text = '0';
    _viaticoCtrl.text = '0';
    _diasCtrl.text = '1';
    final config = ref.read(companyConfigProvider).value;
    _dieselCtrl.text = config?.precioDieselNeto.toStringAsFixed(0) ?? '800';
    _margenCtrl.text = config?.margenObjetivoCotizacion.toString() ?? '25.0';
    ref.read(cotizadorFormProvider.notifier).reset();
    setState(() {});
  }

  void _cargarParaEdicion(CotizacionModel c, List<VehicleModel> vehicles, List<UserModel> choferes) {
    _origenCtrl.text = c.origen;
    _destinoCtrl.text = c.destino;
    _clienteNombreCtrl.text = c.clienteNombre;
    _clienteRutCtrl.text = c.clienteRut;
    _clienteContactoCtrl.text = c.clienteContacto;
    _kmPosicionamientoCtrl.text = c.kmPosicionamiento.toStringAsFixed(0);
    _kmRutaCtrl.text = c.kmRuta.toStringAsFixed(0);
    _tarifaCtrl.text = c.tarifaPropuesta.toStringAsFixed(0);
    _peajesCtrl.text = c.peajes.toStringAsFixed(0);
    _viaticoCtrl.text = c.viaticoManual.toStringAsFixed(0);
    _diasCtrl.text = c.diasViaje.toString();
    _dieselCtrl.text = c.precioDieselNeto.toStringAsFixed(0);
    _margenCtrl.text = c.margenObjetivo.toString();
    
    ref.read(cotizadorFormProvider.notifier).loadCotizacionParaEdicion(c, vehicles, choferes);
    
    // Scroll to top
    PrimaryScrollController.of(context).animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final choferesAsync = ref.watch(choferesProvider);
    final formState = ref.watch(cotizadorFormProvider);
    final result = ref.watch(cotizadorResultProvider);
    final cotizacionesAsync = ref.watch(cotizacionesProvider);
    final isMobile = MediaQuery.of(context).size.width < 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(formState.editandoId == null ? 'Cotizador de Rutas' : 'Editando Cotización',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          const Text('Calcula la rentabilidad real de un servicio antes de aceptarlo.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 32),

          // Main content: Form + Results
          isMobile
              ? Column(children: [
                  _buildFormColumn(vehiclesAsync, choferesAsync, formState),
                  const SizedBox(height: 24),
                  _buildResultsColumn(result, formState),
                ])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildFormColumn(vehiclesAsync, choferesAsync, formState)),
                    const SizedBox(width: 24),
                    Expanded(flex: 7, child: _buildResultsColumn(result, formState)),
                  ],
                ),

          // Historial
          const SizedBox(height: 48),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          const Text('Historial de Cotizaciones',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          _buildHistorial(cotizacionesAsync, vehiclesAsync.value ?? [], choferesAsync.value ?? []),
        ],
      ),
    );
  }

  // ─── COLUMNA IZQUIERDA: FORMULARIO ─────────────────────────────────────────

  Widget _buildFormColumn(AsyncValue<List<VehicleModel>> vehiclesAsync, AsyncValue<List<UserModel>> choferesAsync, CotizadorFormState formState) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.edit_note, color: Colors.orange, size: 22),
            const SizedBox(width: 12),
            const Text('DATOS DEL SERVICIO', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 24),

          _buildInputField(_origenCtrl, 'Origen', Icons.location_on_outlined),
          const SizedBox(height: 16),
          _buildInputField(_destinoCtrl, 'Destino', Icons.flag_outlined),
          const SizedBox(height: 24),

          Row(children: [
            const Icon(Icons.business_center_outlined, color: Colors.orange, size: 22),
            const SizedBox(width: 12),
            const Text('DATOS DEL CLIENTE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 16),
          
          _buildInputField(_clienteNombreCtrl, 'Nombre del Cliente', Icons.person_outline),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _buildInputField(_clienteRutCtrl, 'RUT', Icons.badge_outlined)),
            const SizedBox(width: 12),
            Expanded(child: _buildInputField(_clienteContactoCtrl, 'Contacto/Teléfono', Icons.contact_phone_outlined)),
          ]),
          const SizedBox(height: 24),

          Row(children: [
            const Icon(Icons.local_shipping_outlined, color: Colors.orange, size: 22),
            const SizedBox(width: 12),
            const Text('DATOS OPERATIVOS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 16),

          // Dropdown Camión
          vehiclesAsync.when(
            loading: () => const LinearProgressIndicator(color: Colors.orange),
            error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
            data: (vehicles) => _buildDropdown<VehicleModel>(
              label: 'Camión',
              icon: Icons.local_shipping_outlined,
              value: formState.vehicle,
              items: vehicles,
              displayFn: (v) => '${v.patente} · ${v.rendimientoKmPorLitro} km/L',
              onChanged: (v) {
                ref.read(cotizadorFormProvider.notifier).updateField(vehicle: v);
              },
            ),
          ),
          const SizedBox(height: 16),

          // Dropdown Chofer
          choferesAsync.when(
            loading: () => const LinearProgressIndicator(color: Colors.orange),
            error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
            data: (choferes) => _buildDropdown<UserModel>(
              label: 'Chofer',
              icon: Icons.person_outline,
              value: formState.driver,
              items: choferes,
              displayFn: (d) => d.nombre,
              onChanged: (d) {
                ref.read(cotizadorFormProvider.notifier).updateField(driver: d);
              },
            ),
          ),
          const SizedBox(height: 16),

          Row(children: [
            Expanded(child: _buildNumField(_kmPosicionamientoCtrl, 'KM Posicionamiento')),
            const SizedBox(width: 12),
            Expanded(child: _buildNumField(_kmRutaCtrl, 'KM Ruta')),
          ]),
          const SizedBox(height: 12),
          
          SwitchListTile(
            title: const Text('Ida y vuelta', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text('Duplica los km de ruta y los peajes. No afecta el posicionamiento.', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
            value: formState.idaYVuelta,
            activeTrackColor: Colors.orange,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              ref.read(cotizadorFormProvider.notifier).updateField(idaYVuelta: val);
            },
          ),
          const SizedBox(height: 16),

          // Tarifa destacada
          _buildTarifaField(),
          const SizedBox(height: 24),

          // Sección avanzada colapsable
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Avanzado / Opcionales', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, color: Colors.grey, size: 18),
                ],
              ),
            ),
          ),

          if (_showAdvanced) ...[
            const SizedBox(height: 16),
            _buildNumField(_dieselCtrl, 'Precio Diésel Neto (\$)'),
            const SizedBox(height: 12),
            _buildNumField(_peajesCtrl, 'Peajes (\$)'),
            const SizedBox(height: 12),
            _buildNumField(_viaticoCtrl, 'Viático Total del Viaje (\$)'),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text('Ingrese el viático total. Ej: 2 días con pernoctación = 2 × viático largo.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
            ),
            const SizedBox(height: 12),
            _buildNumField(_diasCtrl, 'Días del Viaje'),
            const SizedBox(height: 12),
            _buildNumField(_margenCtrl, 'Margen Objetivo (%)'),
          ],

          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSaving ? null : _guardarCotizacion,
                icon: _isSaving 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
                label: Text(formState.editandoId == null ? 'Guardar Cotización' : 'Actualizar Cotización', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            if (formState.editandoId != null) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _limpiar,
                icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                label: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
            ],
            if (formState.editandoId == null) ...[
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Limpiar formulario',
                onPressed: _limpiar,
                icon: const Icon(Icons.refresh, color: Colors.grey),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  // ─── COLUMNA DERECHA: RESULTADOS EN VIVO ───────────────────────────────────

  Widget _buildResultsColumn(Map<String, double>? result, CotizadorFormState formState) {
    if (result == null) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calculate_outlined, size: 48, color: Colors.white10),
              SizedBox(height: 12),
              Text('Selecciona camión y chofer para calcular',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final margenPct = result['margenPorcentaje'] ?? 0;
    final margenNeto = result['margenNetoReal'] ?? 0;
    final tarifaMinima = result['tarifaMinimaSugerida'] ?? 0;
    final tarifa = formState.tarifaPropuesta;
    final config = ref.read(companyConfigProvider).value;
    final margenObj = formState.margenObjetivoManual ?? config?.margenObjetivoCotizacion ?? 25.0;

    // Semáforo
    Color semaforoColor;
    String semaforoEmoji;
    if (margenPct >= 25) {
      semaforoColor = Colors.greenAccent;
      semaforoEmoji = '🟢';
    } else if (margenPct >= 10) {
      semaforoColor = Colors.orangeAccent;
      semaforoEmoji = '🟡';
    } else {
      semaforoColor = Colors.redAccent;
      semaforoEmoji = '🔴';
    }

    return Column(
      children: [
        // Tarjeta grande: Margen Neto Real
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: semaforoColor.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            children: [
              Text('$semaforoEmoji  MARGEN NETO REAL',
                  style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Text(_fmt(margenNeto),
                  style: TextStyle(color: margenNeto >= 0 ? Colors.white : Colors.redAccent, fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('${margenPct.toStringAsFixed(1)}% de la tarifa',
                  style: TextStyle(color: semaforoColor, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Tarifa mínima sugerida
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tarifa Mínima Sugerida (margen ${margenObj.toStringAsFixed(0)}%)',
                        style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_fmt(tarifaMinima),
                        style: const TextStyle(color: Colors.orange, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: tarifa >= tarifaMinima
                      ? Colors.greenAccent.withValues(alpha: 0.1)
                      : Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: tarifa >= tarifaMinima
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  tarifa >= tarifaMinima ? 'Tarifa rentable ✓' : 'Bajo el mínimo ✗',
                  style: TextStyle(
                    color: tarifa >= tarifaMinima ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Desglose quirúrgico
        _buildDesglosePanel(result),
        const SizedBox(height: 16),

        // Resumen Comercial
        _buildResumenComercial(tarifa),
        const SizedBox(height: 16),

        // Indicadores secundarios
        _buildIndicadoresSecundarios(result),
      ],
    );
  }

  Widget _buildDesglosePanel(Map<String, double> r) {

    final formState = ref.read(cotizadorFormProvider);
    final tarifaPropuesta = formState.tarifaPropuesta;
    final peajesEfectivos = formState.idaYVuelta ? formState.peajes * 2 : formState.peajes;
    final viatico = formState.viaticoManual;
    final resultadoOperacional = tarifaPropuesta - (r['costoTotalReal'] ?? 0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.analytics_outlined, color: Colors.orange, size: 20),
            const SizedBox(width: 12),
            const Text('DESGLOSE QUIRÚRGICO', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 20),

          _desgloseRow('Ingreso Neto (tarifa)', tarifaPropuesta, isPositive: true),
          const SizedBox(height: 4),
          _desgloseRow('(–) Combustible neto', -(r['combustibleNeto'] ?? 0), isNegative: true),
          _desgloseRow('(–) Peajes', -peajesEfectivos, isNegative: true),
          _desgloseRow('(–) Comisión chofer', -(r['comision'] ?? 0), isNegative: true),
          _desgloseRow('(–) Viático', -viatico, isNegative: true),
          _desgloseRow('(–) Mantenimiento (provisión)', -(r['mantenimiento'] ?? 0), isNegative: true),
          _desgloseRow('(–) Costo fijo chofer (${ref.read(cotizadorFormProvider).diasViaje}d)', -(r['costoFijoChofer'] ?? 0), isNegative: true),
          const Divider(color: Colors.white10, height: 24),
          _desgloseRow('= Resultado Operacional', resultadoOperacional, isBold: true),
          const SizedBox(height: 8),
          _desgloseRow('(+) Crédito IVA combustible', r['creditoIvaCombustible'] ?? 0, isHighlight: true),
          _desgloseRow('(+) Recuperación Ley 19.764', r['recuperacionLey19764'] ?? 0, isHighlight: true),
          _desgloseRow('(–) IVA Débito', -(r['ivaDebito'] ?? 0), isNegative: true),
          const Divider(color: Colors.orange, height: 24, thickness: 0.5),
          _desgloseRow('= Margen Neto Real (al bolsillo)', r['margenNetoReal'] ?? 0, isBold: true,
              customColor: (r['margenNetoReal'] ?? 0) >= 0 ? Colors.greenAccent : Colors.redAccent),
        ],
      ),
    );
  }

  Widget _desgloseRow(String label, double value, {bool isNegative = false, bool isPositive = false, bool isHighlight = false, bool isBold = false, Color? customColor}) {
    Color textColor = Colors.white;
    if (isNegative) textColor = Colors.redAccent;
    if (isPositive) textColor = Colors.white;
    if (isHighlight) textColor = Colors.orange;
    if (customColor != null) textColor = customColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            color: isHighlight ? Colors.orange : Colors.grey,
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
          Text(_fmt(value), style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
        ],
      ),
    );
  }

  Widget _buildResumenComercial(double tarifaPropuesta) {
    final iva = tarifaPropuesta * 0.19;
    final total = tarifaPropuesta + iva;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.orange, size: 20),
            const SizedBox(width: 12),
            const Text('RESUMEN COMERCIAL (lo que ve el cliente)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 20),
          
          _resumenComercialRow('Tarifa Neta', tarifaPropuesta),
          _resumenComercialRow('IVA (19%)', iva),
          const Divider(color: Colors.white10, height: 24),
          _resumenComercialRow('TOTAL AL CLIENTE', total, isBold: true, customColor: Colors.orange),
        ],
      ),
    );
  }

  Widget _resumenComercialRow(String label, double value, {bool isBold = false, Color? customColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            color: Colors.grey,
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
          Text(_fmt(value), style: TextStyle(
            color: customColor ?? Colors.white,
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
        ],
      ),
    );
  }

  Widget _buildIndicadoresSecundarios(Map<String, double> r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          _indicador('KM Total', '${(r['kmTotal'] ?? 0).toStringAsFixed(0)} km'),
          _indicadorDivider(),
          _indicador('Litros', '${(r['litrosConsumidos'] ?? 0).toStringAsFixed(1)} L'),
          _indicadorDivider(),
          _indicador('CPK', _fmt(r['cpk'] ?? 0)),
        ],
      ),
    );
  }

  Widget _indicador(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _indicadorDivider() {
    return Container(width: 1, height: 30, color: Colors.white10);
  }

  // ─── HISTORIAL ──────────────────────────────────────────────────────────────

  Widget _buildHistorial(AsyncValue<List<CotizacionModel>> cotizacionesAsync, List<VehicleModel> vehicles, List<UserModel> choferes) {
    return cotizacionesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.orange)),
      error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
      data: (cotizaciones) {
        if (cotizaciones.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('No hay cotizaciones guardadas.', style: TextStyle(color: Colors.grey, fontSize: 13))),
          );
        }
        return Column(
          children: cotizaciones.take(20).map((c) {
            final margenColor = c.margenPorcentaje >= 25 ? Colors.greenAccent
                : c.margenPorcentaje >= 10 ? Colors.orangeAccent
                : Colors.redAccent;
                
            final bool anulada = c.eliminada;

            return Opacity(
              opacity: anulada ? 0.5 : 1.0,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: anulada ? Colors.grey : margenColor, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.numeroCotizacion.isNotEmpty ? '${c.numeroCotizacion} · ${c.origen} → ${c.destino}' : '${c.origen} → ${c.destino}', 
                          style: TextStyle(
                            fontWeight: FontWeight.w500, 
                            fontSize: 13,
                            decoration: anulada ? TextDecoration.lineThrough : null,
                            color: anulada ? Colors.grey : Colors.white,
                          )
                        ),
                        if (c.clienteNombre.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Cliente: ${c.clienteNombre}${c.clienteRut.isNotEmpty ? ' · ${c.clienteRut}' : ''}',
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ),
                        Text('${DateFormat('dd/MM/yyyy').format(c.createdAt)} · ${c.vehiclePatente} · ${c.nombreChofer}',
                            style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    )),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_fmt(c.tarifaPropuesta), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${c.margenPorcentaje.toStringAsFixed(1)}%', style: TextStyle(color: anulada ? Colors.grey : margenColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(width: 12),
                    
                    if (anulada)
                      _badgeAnulada()
                    else
                      _estadoBadgeInteractable(c),
                      
                    const SizedBox(width: 8),
                    
                      // Acciones (solo si no está anulada)
                    if (!anulada) ...[
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.orange, size: 18),
                        tooltip: 'Descargar Proforma PDF',
                        onPressed: () async {
                          final config = ref.read(companyConfigProvider).value;
                          if (config == null) return;
                          try {
                            final bytes = await CotizacionPdfService.generarProformaPdf(cotizacion: c, config: config);
                            await Printing.sharePdf(bytes: bytes, filename: '${c.numeroCotizacion.isNotEmpty ? c.numeroCotizacion : 'Cotizacion'}.pdf');
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.red));
                            }
                          }
                        },
                      ),
                      if (c.estado == 'borrador')
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
                          tooltip: 'Editar cotización',
                          onPressed: () => _cargarParaEdicion(c, vehicles, choferes),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        tooltip: 'Anular cotización',
                        onPressed: () => _confirmarEliminacion(c),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _badgeAnulada() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: const Text('ANULADA', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _estadoBadgeInteractable(CotizacionModel c) {
    Color color;
    switch (c.estado) {
      case 'aceptada': color = Colors.greenAccent; break;
      case 'rechazada': color = Colors.redAccent; break;
      case 'enviada': color = Colors.blue; break;
      default: color = Colors.grey;
    }
    
    return PopupMenuButton<String>(
      tooltip: 'Cambiar estado',
      onSelected: (nuevoEstado) async {
        if (nuevoEstado != c.estado) {
          await ref.read(adminRepositoryProvider).updateCotizacionStatus(c.id, nuevoEstado);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'borrador',
          child: Text('Borrador', style: TextStyle(fontSize: 13)),
        ),
        const PopupMenuItem<String>(
          value: 'enviada',
          child: Text('Enviada', style: TextStyle(fontSize: 13)),
        ),
        const PopupMenuItem<String>(
          value: 'aceptada',
          child: Text('Aceptada', style: TextStyle(fontSize: 13)),
        ),
        const PopupMenuItem<String>(
          value: 'rechazada',
          child: Text('Rechazada', style: TextStyle(fontSize: 13)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(c.estado, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: color, size: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEliminacion(CotizacionModel c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('¿Anular cotización?', style: TextStyle(color: Colors.white)),
        content: Text('La cotización ${c.numeroCotizacion} quedará anulada pero conservada en el historial.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, anular', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await ref.read(adminRepositoryProvider).softDeleteCotizacion(c.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cotización anulada')));
          // Si estaba editando esa misma, la limpiamos del form
          if (ref.read(cotizadorFormProvider).editandoId == c.id) {
            _limpiar();
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  // ─── WIDGETS AUXILIARES ─────────────────────────────────────────────────────

  Widget _buildInputField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      onChanged: (_) => _syncFormToProvider(),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey, size: 18),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildNumField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [DecimalTextInputFormatter()],
      onChanged: (_) => _syncFormToProvider(),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildTarifaField() {
    return TextField(
      controller: _tarifaCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [DecimalTextInputFormatter()],
      onChanged: (_) => _syncFormToProvider(),
      style: const TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: 'Tarifa Propuesta sin IVA (\$)',
        labelStyle: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold),
        prefixIcon: const Icon(Icons.attach_money, color: Colors.orange, size: 22),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required List<T> items,
    required String Function(T) displayFn,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey(value),
      initialValue: items.contains(value) ? value : null,
      dropdownColor: const Color(0xFF1E1E1E),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey, size: 18),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      items: items.map((item) => DropdownMenuItem<T>(value: item, child: Text(displayFn(item)))).toList(),
      onChanged: (val) {
        onChanged(val);
        _syncFormToProvider();
      },
    );
  }

  // Formateador CLP idéntico al del dashboard
  String _fmt(double amount) {
    final isNeg = amount < 0;
    final abs = amount.abs();
    final parts = abs.toStringAsFixed(0).split('');
    final buf = StringBuffer(isNeg ? '-\$' : '\$');
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buf.write('.');
      buf.write(parts[i]);
    }
    return buf.toString();
  }
}
