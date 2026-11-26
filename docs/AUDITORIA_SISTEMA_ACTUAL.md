# Auditoría Técnica y Arquitectura Real — Bitácora TMS (Chile)

> **Última actualización:** 2026-11-25  
> **Propósito:** Documentación viva del estado real del proyecto, fuentes de verdad, fórmulas exactas y bugs confirmados. Consultar este archivo al inicio de cualquier sesión para mantener continuidad técnica sin suposiciones.

---

## 1. Telemetría, ModoGPS y Kilometraje (`totalKm`)

### Cómo opera HOY
- **Fuente principal de GPS en la App y Web:** `ModoGpsService` (`lib/features/admin/domain/services/modogps_service.dart`), que consulta directamente la API de Wialon (`https://hst-api.wialon.com/wialon/ajax.html`).
- **`telemetry/{empresa}/raw_positions`, `events`, `trip_summaries` en Firestore:**
  - Los escribe `GpsHarvestService` (`lib/features/admin/domain/services/gps_harvest_service.dart`) **únicamente cuando un Administrador tiene abierta la vista "Torre de Control"** (`control_tower_view.dart`).
  - Cada ~15s (1 de cada 3 ciclos de 5s) guarda una posición en `raw_positions`.
  - **NO se usan** para calcular los kilómetros de los viajes ni en *Editar Viaje*. Solo se consultan para contexto de IA (`getRecentTripSummariesForAi`).
  - **Impacto:** Consume escrituras/lecturas en Firestore innecesariamente si no se usa como fuente de verdad.
- **`gps_monitor` en Firestore:**
  - Lo escribe la Cloud Function `syncLiotGps` (`functions/index.js:58-107`) cada 2 minutos consultando `http://liot.cl:8082/api`.
  - **No se lee en ningún archivo de `lib/`.**
- **`viajes/{tripId}/puntos` (GPS del celular):**
  - `LocationService.startTracking` / `stopTracking` (`lib/core/services/location_service.dart:265-290`) es código huérfano que no se llama desde ninguna pantalla.

### Bugs Críticos Confirmados (Caso Real: Viaje 23–25 Nov `VIAJE-1795474050849`)
1. **Truncamiento en `loadCount: 2000` (`modogps_service.dart:804`):**
   - `fetchTripInterval` pide `messages/load_interval` con `loadCount: 2000` y **sin paginación**.
   - En viajes largos o multi-día (ej. `2026-11-23 19:47` a `2026-11-25 10:27`), Wialon devuelve solo los primeros 2.000 mensajes (cortando el registro el `24/11` a las `20:56`, ~25h 3m después).
   - Resultado: registró `1008.0 km` cuando el recorrido completo en ModoGPS fue `1354.07 km` (faltan ~346 km del 24/11 20:56 al 25/11 10:27).
2. **Horas sin fecha en UI (`kpi_dashboard_view.dart:911, 1595, 1710`):**
   - Usa `DateFormat('HH:mm')`, ocultando el día/mes. Muestra `19:52 - 20:56` con duración `25h 3m`.
3. **Fallback peligroso a otro camión (`modogps_service.dart:788`):**
   - `matchedItem ??= items.first;` — si no encuentra coincidencia exacta de patente, asigna los KM y horarios del primer camión de la flota.
4. **Falta `idEmpresa` en llamada desde Editar Viaje (`kpi_dashboard_view.dart:1039-1043`):**
   - No pasa `idEmpresa` a `fetchTripInterval`, usando el token global/fallback en vez del de la empresa.
5. **Trigger `onTripFinished` roto (`functions/index.js:196`):**
   - Lee `after.patenteCamion`, pero `TripModel` guarda el campo `vehicleId` (ej. `VEH-1787795991810`). Nunca actualiza `currentOdometer` en `vehiculos`.

---

## 2. Combustible, Rendimiento y Analítica Financiera

### Cómo opera HOY y dónde están las inconsistencias
1. **Diálogo "Editar Viaje" (`kpi_dashboard_view.dart:1061-1062`) y Torre de Control (`control_tower_view.dart:268`):**
   - **Hardcodeado:** `litrosEstimados = kmCalculados / 2.5` y `costoCombustibleEstimado = litrosEstimados * 850.0`.
   - Ignora el rendimiento real del camión (`rendimientoKmPorLitro` / `ultimoRendimientoReal`) y el precio real del diésel de la empresa (`precioDieselNeto` / `dieselHistory`).
2. **Cuatro precios de diésel distintos en la app:**
   - `_showEditTripDialog`: **$850** fijo.
   - `CompanyConfigModel` / Dashboard badge fallback: **$800**.
   - `FuelPerformanceView` (`fuel_performance_view.dart:28`): **$1050** (e ignora `getDieselManualForMonth`).
   - `ChileanFinancialCalculator.calculateCompanySummary`: usa gastos reales de `gastos`.
3. **Inconsistencia `vehicleId` vs `patente` en `gastos` vs `viajes` (Confirmado en Firestore):**
   - En Firestore real: los gastos de combustible (`COPEC Lomas`, `COPEC CABRERO`) tienen `vehicleId: "VEH-1787795991810"`, mientras los peajes tienen `vehicleId: "JHBZ64"`.
   - `calculateRouteProfitability` (`chilean_financial_calculator.dart:425-430`) **NO normaliza** `vehicleId` vs `patente` (a diferencia de `financialSummaryProvider`). Si no coinciden exactamente, el combustible prorrateado por ruta da **$0**.
   - Además, `calculateRouteProfitability` siempre divide `fuelCost / 1.19` ignorando `customIva` y `isExento`, ignora `vehicle.costoMantenimientoPorKm`, y la tabla en `analytics_view.dart:516-522` **oculta los Viáticos** en el desglose aunque sí los resta en el Margen Neto y los suma en CPK.
4. **Estanque Digital (`fuel_performance_view.dart:22`):**
   - Solo lee gastos del mes seleccionado (`monthlyExpensesProvider`), perdiendo cargas/Full Tank del mes anterior aunque el odómetro sea actual.

---

## 3. Detección Automática de Peajes

### Cómo opera HOY
- **En vivo (`route_live_monitor.dart`):** usa `singleVehicleGpsProvider` (solo alertas en cabina, no guarda en Firestore). Cooldown `>= 15 min`. Sin desempate *Nearest Gate*.
- **Al finalizar viaje (`driver_dashboard_screen.dart:2955-3238`):** consulta `fetchTripInterval` y compara puntos contra `infraestructura_vial`. Cooldown `> 8 min`.
- **Radios actuales (`road_infrastructure_detector.dart:47-67`):**
  - Laterales/Ramal/Salida: **18.0 m** fijos.
  - Troncales/TAG/Pórtico: **45.0 m** (o `35..60m` si está en rango).
  - General: **100.0 m** (default del modelo).

### Por qué falla u omite peajes y por qué los duplica
1. **Sin detección ortogonal al segmento:** Solo mide distancia a los puntos GPS discretos. A 85 km/h (~24 m/s) con reportes cada 15–60s, el camión avanza 350–1400 m entre puntos y salta fácilmente un radio de 18 m o 45 m. Se requiere **distancia mínima del punto del peaje al segmento entre `P(i)` y `P(i+1)`**.
2. **Truncamiento de 2.000 mensajes (`loadCount: 2000`):** Si el viaje excede 2.000 mensajes GPS, los peajes del tramo final (como el regreso) nunca se analizan.
3. **Duplicados al finalizar viaje:** Ventana de 8 minutos demasiado corta en colas/maniobras; `isAlreadySaved` solo revisa texto de descripción en el mismo `tripId`; IDs no determinísticos (`EXP-TOLL-${timestamp}-${idx}`).

---

## 4. Notificaciones Push (FCM)

### Por qué llegan las pruebas pero fallan las alertas reales
1. **Discrepancia de `channelId` (`v3` vs `v4`):**
   - La app Android (`AndroidManifest.xml` y `push_notification_service.dart`) solo crea y escucha **`bitacora_binaural_v4`**.
   - `functions/index.js` (`notifyAdmins` L136 y `notifyDriver` L164) envía **`bitacora_binaural_v3`**.
   - En Android 8+, si el `channelId` del payload no existe en el teléfono, el sistema **silencia o descarta** la notificación en segundo plano.
   - La prueba manual funciona porque no pasa por FCM: llama directo a `showCustomNotification()` usando `bitacora_binaural_v4`.
2. **Sobrescritura de `fcmToken`:** `usuarios/{uid}` guarda un solo `fcmToken`. Si el usuario abre Web/PWA, sobrescribe el token del celular.
3. **Bugs en `onViaticoUpdated` (`functions/index.js:327-334`):** Lee `after.monto` (el modelo usa `montoTotal`) y busca `'aprobado'`/`'rechazado'` (el modelo usa `'pagado'`).
4. **Chat / Avisos Masivos sin FCM:** No existe trigger desplegado (y Plan Spark no permite desplegar nuevas Cloud Functions sin Blaze).

---

## 5. Registro de Correcciones Aplicadas (Columna Vertebral v1.1.5)

1. **Columna Vertebral Única (`lib/core/utils/tms_backbone.dart`):**
   - `TmsBackbone.canonicalVehicleKey` / `findVehicle`: normaliza `VEH-...` y patentes (`JHBZ64`, `JH-BZ-64`) en todo el proyecto.
   - `TmsBackbone.canonicalRoute`: formato único `INICIO ➔ CLIENTE(S) ➔ DESTINO`, unificando espacios (`BASE //CASA` vs `BASE//CASA`).
   - `TmsBackbone.resolveDieselNetoPrice`: resuelve precio neto real desde la última carga de combustible del mismo camión anterior o igual a la fecha del viaje (respetando cambios semanales de precio y estanque anterior), con fallback a `CompanyConfigModel.getDieselManualForMonth`.
   - `TmsBackbone.resolveVehicleEfficiency`: usa `ultimoRendimientoReal` medido entre estanques llenos o `rendimientoKmPorLitro` del camión.
2. **ModoGPS sin truncamiento (`lib/features/admin/domain/services/modogps_service.dart`):**
   - Paginación por lotes de 2.000 mensajes (hasta 50.000 mensajes) en `fetchTripInterval`.
   - Eliminado el fallback peligroso `matchedItem ??= items.first`.
   - Flags `257` (`1` + `256`) y filtro anti-saltos `> 50 km`.
3. **Editar Viaje, Analítica e Informes Mensuales (`kpi_dashboard_view.dart`, `chilean_financial_calculator.dart`, `admin_provider.dart`, `analytics_view.dart`, `monthly_reports_view.dart`, `fuel_performance_view.dart`):**
   - *Editar Viaje* muestra fechas completas (`dd/MM HH:mm`), pasa `idEmpresa`, usa `TmsBackbone` para diésel/rendimiento real y permite aplicar el KM GPS corregido cuando difiere del guardado.
   - *Analítica* e *Informes Mensuales -> Matriz de Rutas* leen del mismo motor (`calculateRouteProfitability`), normalizan `vehicleId` vs `patente`, muestran `INICIO ➔ CLIENTE(S) ➔ DESTINO` y viáticos, y eliminan el `$650/km` ficticio.
   - *Informes Mensuales -> Radiografía por Unidad* usa el rendimiento vigente real en vez de dividir KM por litros comprados sin consumir.
4. **Detección de Peajes (`road_infrastructure_detector.dart`, `driver_dashboard_screen.dart`):**
   - Distancia ortogonal punto-a-segmento (`calculateDistanceToSegmentMeters`) para no saltar pórticos entre reportes GPS.
   - Radio lateral ajustado a `24 m`, troncal a `50 m`, bearing sin jitter (`>= 15 m`), cooldown `20 min`, IDs determinísticos anti-duplicados.
5. **Notificaciones Push (`push_notification_service.dart`, `functions/index.js`):**
   - Soporte dual `bitacora_binaural_v4` + canal legacy `bitacora_binaural_v3` en Android.
   - Token Web separado (`fcmTokenWeb`) para no sobrescribir el token móvil (`fcmToken`).
   - Corregido `onTripFinished` (`vehicleId` o `patenteCamion`) y `onViaticoUpdated` (`montoTotal` y `'pagado'`).

