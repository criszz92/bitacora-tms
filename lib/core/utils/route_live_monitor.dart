import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../features/admin/domain/models/infraestructura_vial_model.dart';
import '../../features/admin/data/repositories/infraestructura_repository.dart';
import '../../features/admin/domain/services/modogps_service.dart';
import '../services/push_notification_service.dart';
import 'road_infrastructure_detector.dart';

/// Alerta activa generada en ruta para advertir al conductor
class RouteAlert {
  final String id;
  final String title;
  final String message;
  final TipoPuntoInfraestructura tipo;
  final DateTime timestamp;
  final double distanceMeters;
  final String? puntoId;

  RouteAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.tipo,
    required this.timestamp,
    required this.distanceMeters,
    this.puntoId,
  });
}

/// Estado del monitor de ruta en vivo
class RouteMonitorState {
  final List<RouteAlert> activeAlerts;
  final List<PuntoInfraestructuraModel> passedTolls;
  final double estimatedTollsTotal;
  final DateTime? lastCheckTime;

  RouteMonitorState({
    this.activeAlerts = const [],
    this.passedTolls = const [],
    this.estimatedTollsTotal = 0.0,
    this.lastCheckTime,
  });

  RouteMonitorState copyWith({
    List<RouteAlert>? activeAlerts,
    List<PuntoInfraestructuraModel>? passedTolls,
    double? estimatedTollsTotal,
    DateTime? lastCheckTime,
  }) {
    return RouteMonitorState(
      activeAlerts: activeAlerts ?? this.activeAlerts,
      passedTolls: passedTolls ?? this.passedTolls,
      estimatedTollsTotal: estimatedTollsTotal ?? this.estimatedTollsTotal,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
    );
  }
}

/// StreamProvider.family que emite el estado del monitor de ruta actualizado en vivo
final routeMonitorStreamProvider = StreamProvider.autoDispose.family<RouteMonitorState, String>((ref, targetPlate) async* {
  var currentState = RouteMonitorState();
  final Map<String, DateTime> recentlyNotified = {};

  final controller = StreamController<RouteMonitorState>();
  controller.add(currentState);

  // Escuchar la telemetría en vivo del camión (antena satelital ModoGPS)
  ref.listen<AsyncValue<GpsUnit?>>(
    singleVehicleGpsProvider(targetPlate),
    (previous, next) {
      final unit = next.value;
      if (unit == null) return;

      final puntosAsync = ref.read(puntosInfraestructuraProvider);
      final puntos = puntosAsync.value ?? [];
      if (puntos.isEmpty) return;

      final now = DateTime.now();
      final truckPos = unit.position;
      final truckHeading = unit.course;

      final newAlerts = <RouteAlert>[];
      final currentPassed = List<PuntoInfraestructuraModel>.from(currentState.passedTolls);
      double tollsSum = currentState.estimatedTollsTotal;

      for (final punto in puntos) {
        if (!punto.activo) continue;

        final puntoPos = LatLng(punto.lat, punto.lng);
        final distM = RoadInfrastructureDetector.calculateDistanceMeters(truckPos, puntoPos);

        // 1. Validar sentido / dirección (Norte a Sur vs Sur a Norte)
        final bool matchesDir = RoadInfrastructureDetector.matchesDirection(
          truckHeading: truckHeading,
          sentidoPunto: punto.sentido,
        );

        if (!matchesDir) continue;

        // ─── A) EVALUAR ROMANAS / PESAJE (Alerta preventiva a 1.5 - 2.5 km) ───
        if (punto.tipo == TipoPuntoInfraestructura.romana) {
          if (distM <= 2500 && distM >= 100) {
            final alertId = 'romana-${punto.id}';
            final lastAlert = recentlyNotified[alertId];

            if (lastAlert == null || now.difference(lastAlert).inMinutes >= 20) {
              final distKmStr = (distM / 1000.0).toStringAsFixed(1);
              final title = '⚠️ PRECAUCIÓN: Romana a $distKmStr km';
              final body = '${punto.nombre} (${punto.ruta}) • Control de pesaje obligatorio.';

              PushNotificationService.showCustomNotification(
                id: punto.id.hashCode,
                title: title,
                body: body,
              );

              recentlyNotified[alertId] = now;
              newAlerts.add(RouteAlert(
                id: alertId,
                title: title,
                message: body,
                tipo: TipoPuntoInfraestructura.romana,
                timestamp: now,
                distanceMeters: distM,
                puntoId: punto.id,
              ));
            }
          }
        }

        // ─── B) EVALUAR RESTRICCIONES HORARIAS ───
        if (punto.tipo == TipoPuntoInfraestructura.restriccion) {
          if (distM <= 4000) {
            final res = RoadInfrastructureDetector.checkTimeRestriction(
              horarioStr: punto.horarioRestriccion,
              checkTime: now,
              marginMinutes: 25,
            );

            if (res['applies'] == true) {
              final alertId = 'restriccion-${punto.id}';
              final lastAlert = recentlyNotified[alertId];

              if (lastAlert == null || now.difference(lastAlert).inMinutes >= 30) {
                final title = '⛔ ALERTA: Restricción Horaria';
                final body = '${punto.nombre}: ${res['detail']}';

                PushNotificationService.showCustomNotification(
                  id: punto.id.hashCode,
                  title: title,
                  body: body,
                );

                recentlyNotified[alertId] = now;
                newAlerts.add(RouteAlert(
                  id: alertId,
                  title: title,
                  message: body,
                  tipo: TipoPuntoInfraestructura.restriccion,
                  timestamp: now,
                  distanceMeters: distM,
                  puntoId: punto.id,
                ));
              }
            }
          }
        }

        // ─── C) EVALUAR PEAJES (Cruce efectivo y suma en tiempo real) ───
        if (punto.tipo == TipoPuntoInfraestructura.peaje) {
          final detectionRadius = RoadInfrastructureDetector.getOptimalDetectionRadius(
            tipoCode: punto.tipo.code,
            subtipo: punto.subtipo,
            radioConfigurado: punto.radioMetros,
          );
          
          if (distM <= detectionRadius) {
            final passId = 'peaje-${punto.id}';
            final lastPass = recentlyNotified[passId];

            if (lastPass == null || now.difference(lastPass).inMinutes >= 15) {
              recentlyNotified[passId] = now;
              currentPassed.add(punto);

              final rate = punto.tarifaCamionPesado ?? punto.tarifaCamionSimple ?? 0.0;
              tollsSum += rate;

              final title = '🛣️ Peaje Detectado: ${punto.nombre}';
              final body = 'Sentido: ${punto.sentido} • Tarifa estimada: \$${rate.toInt()}';

              PushNotificationService.showCustomNotification(
                id: punto.id.hashCode,
                title: title,
                body: body,
              );

              newAlerts.add(RouteAlert(
                id: passId,
                title: title,
                message: body,
                tipo: TipoPuntoInfraestructura.peaje,
                timestamp: now,
                distanceMeters: distM,
                puntoId: punto.id,
              ));
            }
          }
        }
      }

      currentState = currentState.copyWith(
        activeAlerts: [...newAlerts, ...currentState.activeAlerts].take(5).toList(),
        passedTolls: currentPassed,
        estimatedTollsTotal: tollsSum,
        lastCheckTime: now,
      );

      if (!controller.isClosed) {
        controller.add(currentState);
      }
    },
  );

  ref.onDispose(() {
    controller.close();
  });

  yield* controller.stream;
});
