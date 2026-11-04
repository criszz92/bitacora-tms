import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bitacora/features/admin/presentation/providers/admin_provider.dart';
import 'package:bitacora/features/auth/presentation/providers/auth_provider.dart';
import 'package:bitacora/features/trips/domain/models/vehicle_model.dart';

/// Vista de gestión de flota para el Admin.
/// Permite agregar, editar y eliminar camiones, configurar capacidad de estanques
/// y vincular equipos auxiliares de frío (Thermo King / Genset).
class FlotaAdminView extends ConsumerWidget {
  const FlotaAdminView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final user = ref.watch(currentUserProfileProvider).value;

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gestión de Flota',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 4),
                  Text('Configuración de unidades, capacidad de estanques y equipos de refrigeración auxiliar.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFFFF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: user == null ? null : () => _showAddDialog(context, ref, user.idEmpresa),
                icon: const Icon(Icons.add),
                label: const Text('Agregar Camión', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: vehiclesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFFFFF))),
              error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
              data: (vehicles) => vehicles.isEmpty
                  ? _buildEmpty()
                  : _buildGrid(context, ref, vehicles),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        childAspectRatio: 1.25,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: vehicles.length,
      itemBuilder: (ctx, i) => _buildVehicleCard(context, ref, vehicles[i]),
    );
  }

  Widget _buildVehicleCard(BuildContext context, WidgetRef ref, VehicleModel v) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  v.patente,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.black,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.grey, size: 20),
                    tooltip: 'Editar unidad y estanque',
                    onPressed: () => _showAddDialog(context, ref, v.idEmpresa, vehiculoAEditar: v),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmDelete(context, ref, v),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (v.marca != null || v.modelo != null || v.anio != null)
                Text(
                  [v.marca, v.modelo, if (v.anio != null) v.anio.toString()]
                      .whereType<String>()
                      .join(' '),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                )
              else
                const Text('Sin detalles registrados', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.local_gas_station, size: 15, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Estanque: ${v.capacidadEstanqueLitros.toStringAsFixed(0)} Lts (${v.rendimientoKmPorLitro} km/L)',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: Colors.orangeAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Ralentí: ${v.consumoRalentiLitrosHora.toStringAsFixed(1)} L/h (Alerta >${v.maxMinutosRalentiAlerta} min)',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ],
              ),
              if (v.tieneEquipoAuxiliar) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.ac_unit, size: 14, color: Colors.cyanAccent),
                    const SizedBox(width: 6),
                    Text(
                      'Auxiliar: ${v.identificadorAuxiliar ?? 'Thermo'} (${v.capacidadEstanqueAuxiliar?.toStringAsFixed(0) ?? '200'} Lts)',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref, String idEmpresa, {VehicleModel? vehiculoAEditar}) async {
    final patenteCtrl = TextEditingController(text: vehiculoAEditar?.patente);
    final marcaCtrl = TextEditingController(text: vehiculoAEditar?.marca);
    final modeloCtrl = TextEditingController(text: vehiculoAEditar?.modelo);
    final anioCtrl = TextEditingController(text: vehiculoAEditar?.anio?.toString());
    final estanqueCtrl = TextEditingController(text: (vehiculoAEditar?.capacidadEstanqueLitros ?? 600.0).toStringAsFixed(0));
    final rendimientoCtrl = TextEditingController(text: (vehiculoAEditar?.rendimientoKmPorLitro ?? 2.5).toStringAsFixed(1));
    final costoMantenimientoCtrl = TextEditingController(
      text: vehiculoAEditar?.costoMantenimientoPorKm != null ? vehiculoAEditar!.costoMantenimientoPorKm!.toStringAsFixed(0) : '',
    );
    final ralentiConsumoCtrl = TextEditingController(text: (vehiculoAEditar?.consumoRalentiLitrosHora ?? 2.0).toStringAsFixed(1));
    final ralentiAlertaCtrl = TextEditingController(text: (vehiculoAEditar?.maxMinutosRalentiAlerta ?? 20).toString());
    
    // Auxiliar
    bool tieneAuxiliar = vehiculoAEditar?.tieneEquipoAuxiliar ?? false;
    final idAuxiliarCtrl = TextEditingController(text: vehiculoAEditar?.identificadorAuxiliar ?? 'THERMO-01');
    final capAuxiliarCtrl = TextEditingController(text: (vehiculoAEditar?.capacidadEstanqueAuxiliar ?? 200.0).toStringAsFixed(0));
    final consumoAuxCtrl = TextEditingController(text: (vehiculoAEditar?.consumoHoraAuxiliar ?? 2.5).toStringAsFixed(1));

    String selectedCategoria = vehiculoAEditar?.categoriaPeaje ?? 'camion_mas_2_ejes';
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          vehiculoAEditar == null ? 'Agregar Camión & Estanque' : 'Editar Camión & Estanque',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 440,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dialogField(patenteCtrl, 'Patente *', TextCapitalization.characters, true),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _dialogField(marcaCtrl, 'Marca', TextCapitalization.words, false)),
                          const SizedBox(width: 10),
                          Expanded(child: _dialogField(modeloCtrl, 'Modelo', TextCapitalization.words, false)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(anioCtrl, 'Año', TextCapitalization.none, false, inputType: TextInputType.number),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedCategoria,
                              decoration: InputDecoration(
                                labelText: 'Categoría Ejes',
                                filled: true,
                                fillColor: const Color(0xFF2A2A2A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                isDense: true,
                              ),
                              dropdownColor: const Color(0xFF2A2A2A),
                              items: const [
                                DropdownMenuItem(value: 'camion_2_ejes', child: Text('2 ejes')),
                                DropdownMenuItem(value: 'camion_mas_2_ejes', child: Text('+2 ejes')),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => selectedCategoria = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Estanque Principal del Camión', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(estanqueCtrl, 'Capacidad Estanque (Lts)', TextCapitalization.none, true, inputType: TextInputType.number),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dialogField(rendimientoCtrl, 'Rendimiento (km/L)', TextCapitalization.none, true, inputType: const TextInputType.numberWithOptions(decimal: true)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _dialogField(
                        costoMantenimientoCtrl,
                        'Costo Desgaste (\$ / KM) - Opcional',
                        TextCapitalization.none,
                        false,
                        inputType: TextInputType.number,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 4, top: 2),
                        child: Text(
                          'Dejar vacío para usar la regla global de la empresa (CLP por km). Si se especifica, tendrá prioridad en el cotizador y provisión.',
                          style: TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Consumo en Ralentí & Cuidado de Turbo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(ralentiConsumoCtrl, 'Consumo Ralentí (Lts/Hr)', TextCapitalization.none, true, inputType: const TextInputType.numberWithOptions(decimal: true)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dialogField(ralentiAlertaCtrl, 'Alerta Ralentí Excesivo (Min)', TextCapitalization.none, true, inputType: TextInputType.number),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // SECCIÓN EQUIPO DE FRÍO AUXILIAR
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.ac_unit, color: Colors.cyanAccent, size: 18),
                                    SizedBox(width: 8),
                                    Text('Equipo de Frío / Auxiliar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                Switch(
                                  value: tieneAuxiliar,
                                  activeThumbColor: Colors.cyanAccent,
                                  onChanged: (val) => setState(() => tieneAuxiliar = val),
                                ),
                              ],
                            ),
                            if (tieneAuxiliar) ...[
                              const SizedBox(height: 10),
                              _dialogField(idAuxiliarCtrl, 'Código / N° Serie (ej: GEN-04)', TextCapitalization.characters, false),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _dialogField(capAuxiliarCtrl, 'Capacidad (Lts)', TextCapitalization.none, false, inputType: TextInputType.number),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _dialogField(consumoAuxCtrl, 'Consumo (Lts/Hr)', TextCapitalization.none, false, inputType: const TextInputType.numberWithOptions(decimal: true)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFFFFF),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final capEstanque = double.tryParse(estanqueCtrl.text.trim()) ?? 600.0;
              final rendKm = double.tryParse(rendimientoCtrl.text.trim()) ?? 2.5;
              final ralentiConsumo = double.tryParse(ralentiConsumoCtrl.text.trim()) ?? 2.0;
              final ralentiAlerta = int.tryParse(ralentiAlertaCtrl.text.trim()) ?? 20;
              final capAux = tieneAuxiliar ? double.tryParse(capAuxiliarCtrl.text.trim()) : null;
              final consumoAux = tieneAuxiliar ? (double.tryParse(consumoAuxCtrl.text.trim()) ?? 2.5) : 2.5;

              final vehicle = VehicleModel(
                id: vehiculoAEditar?.id ?? 'VEH-${DateTime.now().millisecondsSinceEpoch}',
                idEmpresa: idEmpresa,
                patente: patenteCtrl.text.trim().toUpperCase(),
                marca: marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
                modelo: modeloCtrl.text.trim().isEmpty ? null : modeloCtrl.text.trim(),
                anio: int.tryParse(anioCtrl.text.trim()),
                categoriaPeaje: selectedCategoria,
                currentOdometer: vehiculoAEditar?.currentOdometer ?? 0.0,
                nextOilChangeKm: vehiculoAEditar?.nextOilChangeKm,
                rtExpirationDate: vehiculoAEditar?.rtExpirationDate,
                soapExpirationDate: vehiculoAEditar?.soapExpirationDate,
                permisoExpirationDate: vehiculoAEditar?.permisoExpirationDate,
                rendimientoKmPorLitro: rendKm,
                costoMantenimientoPorKm: double.tryParse(costoMantenimientoCtrl.text.trim()),
                capacidadEstanqueLitros: capEstanque,
                tanqueCalibrado: vehiculoAEditar?.tanqueCalibrado ?? false,
                ultimoLlenadoKm: vehiculoAEditar?.ultimoLlenadoKm,
                ultimoLlenadoFecha: vehiculoAEditar?.ultimoLlenadoFecha,
                tieneEquipoAuxiliar: tieneAuxiliar,
                tipoEquipoAuxiliar: tieneAuxiliar ? 'Thermo King / Reefer' : null,
                identificadorAuxiliar: tieneAuxiliar ? idAuxiliarCtrl.text.trim() : null,
                capacidadEstanqueAuxiliar: capAux,
                consumoHoraAuxiliar: consumoAux,
                horometroActualAuxiliar: vehiculoAEditar?.horometroActualAuxiliar,
                ultimoLlenadoHorometroAux: vehiculoAEditar?.ultimoLlenadoHorometroAux,
                consumoRalentiLitrosHora: ralentiConsumo,
                maxMinutosRalentiAlerta: ralentiAlerta,
              );

              if (vehiculoAEditar == null) {
                await ref.read(adminRepositoryProvider).addVehicle(vehicle);
              } else {
                await ref.read(adminRepositoryProvider).updateVehicle(vehicle);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    patenteCtrl.dispose();
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    anioCtrl.dispose();
    estanqueCtrl.dispose();
    rendimientoCtrl.dispose();
    ralentiConsumoCtrl.dispose();
    ralentiAlertaCtrl.dispose();
    idAuxiliarCtrl.dispose();
    capAuxiliarCtrl.dispose();
    consumoAuxCtrl.dispose();
  }

  TextFormField _dialogField(
    TextEditingController ctrl, String label,
    TextCapitalization cap, bool required, {
    TextInputType? inputType,
  }) {
    return TextFormField(
      controller: ctrl,
      textCapitalization: cap,
      keyboardType: inputType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        isDense: true,
      ),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'Requerido' : null : null,
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, VehicleModel v) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Eliminar Vehículo'),
        content: Text('¿Seguro que deseas eliminar el camión ${v.patente}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await ref.read(adminRepositoryProvider).deleteVehicle(v.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('No hay camiones registrados', style: TextStyle(color: Colors.grey, fontSize: 16)),
          SizedBox(height: 8),
          Text('Agrega tu primer camión con el botón superior.', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}
