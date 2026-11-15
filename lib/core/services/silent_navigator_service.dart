import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../../features/trips/domain/models/trip_model.dart';
import '../../features/trips/presentation/providers/trip_provider.dart';
import '../../features/admin/domain/services/modogps_service.dart';
import '../../features/trips/domain/services/route_mission_service.dart';
import 'push_notification_service.dart';

/// Evento de llegada detectada satelitalmente pendiente de confirmación por el chofer
class PendingArrivalEvent {
  final String tripId;
  final String tramoId;
  final String destino;
  final String? geocerca;
  final DateTime detectedAt;
  final double currentOdometer;

  const PendingArrivalEvent({
    required this.tripId,
    required this.tramoId,
    required this.destino,
    this.geocerca,
    required this.detectedAt,
    this.currentOdometer = 0.0,
  });
}

/// Notifier que mantiene en memoria si hay una confirmación de llegada pendiente
class PendingArrivalNotifier extends Notifier<PendingArrivalEvent?> {
  @override
  PendingArrivalEvent? build() => null;

  void setPendingArrival(PendingArrivalEvent event) {
    state = event;
  }

  void clear() {
    state = null;
  }
}

final pendingArrivalProvider = NotifierProvider<PendingArrivalNotifier, PendingArrivalEvent?>(() {
  return PendingArrivalNotifier();
});

/// Servicio de Navegación Silenciosa (Shadow Navigator)
class SilentNavigatorService {
  final Ref _ref;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Evita disparar múltiples notificaciones para el mismo tramo en una ventana de 30 minutos
  final Map<String, DateTime> _notifiedLegs = {};

  // Buffer de altitudes para cálculo de perfil topográfico en memoria
  final Map<String, List<double>> _altitudesBuffer = {};

  SilentNavigatorService(this._ref);

  /// Evalúa la posición satelital del camión contra el tramo activo del viaje
  void processTelemetry({
    required TripModel activeTrip,
    required GpsUnit unit,
  }) {
    if (activeTrip.tramos == null || activeTrip.tramos!.isEmpty) return;

    final tramo = activeTrip.tramoActual;
    if (tramo == null || tramo['estado'] != 'en_ruta') return;

    final tramoId = tramo['id']?.toString() ?? 'tramo_1';
    final targetDestino = tramo['destino']?.toString() ?? activeTrip.client;
    final targetGeocerca = tramo['geocercaDestino']?.toString() ??
        RouteMissionService.findGeofenceForClient(targetDestino) ??
        RouteMissionService.findGeofenceForDestination(targetDestino);

    // 1. Acumular altitud para perfil topográfico
    if (unit.altitude != null && unit.altitude! > 0) {
      _altitudesBuffer.putIfAbsent(tramoId, () => []);
      _altitudesBuffer[tramoId]!.add(unit.altitude!);
    }

    // 2. Comprobar si el camión ingresó a la geocerca de destino
    final currentGeocerca = unit.currentGeofence?.toUpperCase().trim();
    bool isInTargetGeocerca = false;

    if (currentGeocerca != null && targetGeocerca != null) {
      final cleanTarget = targetGeocerca.toUpperCase().trim();
      isInTargetGeocerca = currentGeocerca == cleanTarget ||
          currentGeocerca.contains(cleanTarget) ||
          cleanTarget.contains(currentGeocerca);
    }

    // Si aún no coincide por nombre exacto, verificar si el camión está en el catálogo de puertos
    if (!isInTargetGeocerca && targetGeocerca != null) {
      for (final dest in RouteMissionService.deliveryCatalog) {
        if (dest.geocercaModoGps.toUpperCase() == targetGeocerca.toUpperCase()) {
          final distM = const Distance().as(
            LengthUnit.Meter,
            unit.position,
            dest.ubicacion,
          );
          if (distM <= 450.0) {
            isInTargetGeocerca = true;
            break;
          }
        }
      }
    }

    if (!isInTargetGeocerca) return;

    // 3. Verificar si ya fue notificado recientemente para no spamear
    final now = DateTime.now();
    final lastNotif = _notifiedLegs[tramoId];
    if (lastNotif != null && now.difference(lastNotif).inMinutes < 25) {
      return;
    }

    _notifiedLegs[tramoId] = now;

    // 4. Disparar Notificación Local (Push sonora con vibración estilo WhatsApp / Waze)
    PushNotificationService.showCustomNotification(
      id: tramoId.hashCode,
      title: '📍 ¡Llegaste a $targetDestino!',
      body: 'Camión detenido en geocerca. Toca aquí para confirmar tu llegada.',
    );

    // 5. Publicar evento en el Notifier para que la pantalla del chofer muestre el banner interactivo
    _ref.read(pendingArrivalProvider.notifier).setPendingArrival(
          PendingArrivalEvent(
            tripId: activeTrip.id,
            tramoId: tramoId,
            destino: targetDestino,
            geocerca: targetGeocerca,
            detectedAt: now,
            currentOdometer: unit.hardwareMileageKm ?? 0.0,
          ),
        );

    debugPrint('[SilentNavigator] ¡Llegada detectada a $targetDestino ($targetGeocerca)!');
  }

  /// Confirma la llegada al destino del tramo y avanza al siguiente tramo de la misión
  Future<void> confirmLegArrival({
    required TripModel trip,
    required String tramoId,
  }) async {
    if (trip.tramos == null || trip.tramos!.isEmpty) return;

    final nowStr = DateTime.now().toIso8601String();
    final updatedTramos = List<Map<String, dynamic>>.from(trip.tramos!);
    final currentIdx = updatedTramos.indexWhere((t) => t['id'] == tramoId);
    if (currentIdx < 0) return;

    // Calcular perfil topográfico acumulado en este tramo
    final altitudes = _altitudesBuffer[tramoId] ?? [];
    final elevation = RouteMissionService.computeElevationProfile(altitudes);

    // Marcar tramo actual como COMPLETADO
    final currentLeg = Map<String, dynamic>.from(updatedTramos[currentIdx]);
    currentLeg['estado'] = 'completado';
    currentLeg['horaFin'] = nowStr;
    currentLeg['desnivelPositivoM'] = elevation['ascentMeters'];
    currentLeg['desnivelNegativoM'] = elevation['descentMeters'];
    updatedTramos[currentIdx] = currentLeg;

    // Determinar siguiente hito operativo sugerido
    String nuevoHito = trip.hitoActual ?? 'En Tránsito';

    // Si hay un siguiente tramo en la misión, pasarlo a EN RUTA
    if (currentIdx + 1 < updatedTramos.length) {
      final nextLeg = Map<String, dynamic>.from(updatedTramos[currentIdx + 1]);
      nextLeg['estado'] = 'en_ruta';
      nextLeg['horaInicio'] = nowStr;
      updatedTramos[currentIdx + 1] = nextLeg;

      if (currentLeg['tipo'] == 'posicionamiento_vacio') {
        nuevoHito = 'En Planta / Esperando Carga';
      } else {
        nuevoHito = 'En Ruta a ${nextLeg['destino']}';
      }
    } else {
      // Era el último tramo de la misión
      nuevoHito = 'En Destino Final / Puerto';
    }

    // Registrar hito en el historial del viaje
    final hitos = List<Map<String, dynamic>>.from(trip.hitos ?? []);
    hitos.add({
      'hito': nuevoHito,
      'timestamp': nowStr,
      'origen': 'navegador_silencioso_confirmado',
      'tramoId': tramoId,
    });

    // Actualizar en Firestore
    await _firestore.collection('viajes').doc(trip.id).update({
      'tramos': updatedTramos,
      'hitoActual': nuevoHito,
      'hitos': hitos,
    });

    // Limpiar evento pendiente
    _ref.read(pendingArrivalProvider.notifier).clear();
    _altitudesBuffer.remove(tramoId);
  }
}

/// Provider que mantiene la instancia del navegador silencioso
final silentNavigatorServiceProvider = Provider<SilentNavigatorService>((ref) {
  return SilentNavigatorService(ref);
});

/// Listener reactivo que monitorea en background la telemetría del camión respecto al viaje activo
final silentNavigatorObserverProvider = Provider.autoDispose.family<void, String>((ref, plate) {
  final activeTrip = ref.watch(currentShiftTripsProvider).value?.where((t) => t.status == 'En Ruta').firstOrNull;
  if (activeTrip == null) return;

  ref.listen<AsyncValue<GpsUnit?>>(
    singleVehicleGpsProvider(plate),
    (previous, next) {
      final unit = next.value;
      if (unit != null) {
        ref.read(silentNavigatorServiceProvider).processTelemetry(
              activeTrip: activeTrip,
              unit: unit,
            );
      }
    },
  );
});

