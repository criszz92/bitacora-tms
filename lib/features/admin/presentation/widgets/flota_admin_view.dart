import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../trips/domain/models/vehicle_model.dart';

/// Vista de gestión de flota para el Admin.
/// Permite agregar y eliminar camiones. Las patentes aparecen en el autocompletado
/// de los conductores al iniciar jornada.
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
                  Text('Los camiones registrados aquí aparecen en el autocomplete de los conductores.',
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
        maxCrossAxisExtent: 320,
        childAspectRatio: 1.6,
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping, color: Color(0xFFFFFFFF), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.patente,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 1.5)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.orange, size: 20),
                    tooltip: 'Editar camión',
                    onPressed: () => _showAddDialog(context, ref, v.idEmpresa, vehiculoAEditar: v),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    tooltip: 'Eliminar camión',
                    onPressed: () => _confirmDelete(context, ref, v),
                  ),
                ],
              ),
            ],
          ),
          if (v.marca != null || v.modelo != null || v.anio != null)
            Text(
              [v.marca, v.modelo, if (v.anio != null) v.anio.toString()]
                  .whereType<String>()
                  .join(' '),
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            )
          else
            const Text('Sin detalles registrados',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref, String idEmpresa, {VehicleModel? vehiculoAEditar}) async {
    final patenteCtrl = TextEditingController(text: vehiculoAEditar?.patente);
    final marcaCtrl = TextEditingController(text: vehiculoAEditar?.marca);
    final modeloCtrl = TextEditingController(text: vehiculoAEditar?.modelo);
    final anioCtrl = TextEditingController(text: vehiculoAEditar?.anio?.toString());
    String selectedCategoria = vehiculoAEditar?.categoriaPeaje ?? 'camion_mas_2_ejes';
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(vehiculoAEditar == null ? 'Agregar Camión' : 'Editar Camión', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 360,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _dialogField(patenteCtrl, 'Patente *', TextCapitalization.characters, true),
                const SizedBox(height: 12),
                _dialogField(marcaCtrl, 'Marca (opcional)', TextCapitalization.words, false),
                const SizedBox(height: 12),
                _dialogField(modeloCtrl, 'Modelo (opcional)', TextCapitalization.words, false),
                const SizedBox(height: 12),
                _dialogField(anioCtrl, 'Año (opcional)', TextCapitalization.none, false,
                    inputType: TextInputType.number),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategoria,
                  decoration: InputDecoration(
                    labelText: 'Categoría de Peaje',
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    isDense: true,
                  ),
                  dropdownColor: const Color(0xFF2A2A2A),
                  items: const [
                    DropdownMenuItem(value: 'camion_2_ejes', child: Text('Equipo de 2 ejes')),
                    DropdownMenuItem(value: 'camion_mas_2_ejes', child: Text('Equipo de más de 2 ejes')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        selectedCategoria = v;
                      });
                    }
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Considera el total de ejes del equipo completo (cabeza tractora + remolque/semirremolque), no solo la cabeza tractora.',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
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
                backgroundColor: const Color(0xFFFFFFFF), foregroundColor: Colors.black),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
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
                rendimientoKmPorLitro: vehiculoAEditar?.rendimientoKmPorLitro ?? 2.5,
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
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null
          : null,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, VehicleModel v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Eliminar Camión'),
        content: Text('¿Seguro que deseas eliminar el camión ${v.patente}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(adminRepositoryProvider).deleteVehicle(v.id);
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined, size: 72, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No hay camiones registrados.',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Agrega camiones para que los conductores puedan seleccionarlos al iniciar jornada.',
              style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
