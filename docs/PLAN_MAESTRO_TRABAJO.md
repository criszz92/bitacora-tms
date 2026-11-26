# Plan Maestro de Ingeniería, Estabilización y Auditoría — Bitácora TMS (Chile)

> **Base verificada:** Auditoría línea por línea de los **34 bloques / 102 archivos / ~42.114 líneas / 150 hallazgos** (`docs/AUDITORIA_COMPLETA_34_BLOQUES.md` + `docs/MAPA_MAESTRO_FUNCIONES.md`).  
> **Objetivo:** Convertir Bitácora TMS en un sistema **auditable, trazable y sin duplicación de lógica**, donde una única columna vertebral gobierne operaciones, telemetría, combustible, remuneraciones y tributación chilena (SII / F29 / Ley 19.764).  
> **Regla de continuidad:** Al retomar cualquier sesión de programación, leer primero este documento y `docs/MAPA_MAESTRO_FUNCIONES.md`, trabajar ítem por ítem en orden de fase, verificar con `flutter analyze` y marcar `[x]` con fecha.

---

## FASE 0 — Estabilidad Crítica: Crashes, Pérdida de Datos y Seguridad de Parseo
*Prioridad Máxima: Eliminar todo punto donde la app o backend puede caerse en runtime o corromper un dato.*

- [ ] **0.1 Backend `functions/index.js`:**
  - `functions/index.js:220`: Corregir `ReferenceError` por variable inexistente `vehiclePatente` en `onTripFinished` (usar `vehicleData.patente || vehicleRefId`).
  - `functions/index.js:289`: Corregir `messages.join("\\n")` por `"\n"` en `dailyDocumentCheck`.
- [ ] **0.2 Navegación bloqueada en Router (`app_router.dart`):**
  - `app_router.dart:54-61, 131`: Agregar `'/driver-profile'` a `isDriverPath` para evitar redirección forzada al entrar a la Ficha del Conductor.
- [ ] **0.3 Parseo seguro de Fechas Firestore (`DateTime.parse` -> helper seguro `Timestamp | String | null`):**
  - Crear helper único en `TmsBackbone.parseDate(dynamic val, {DateTime? fallback})` y aplicarlo en:
    - `trip_model.dart:179`, `vehicle_model.dart:129-137`, `expense_model.dart:93`, `incidencia_model.dart:65`, `shift_model.dart:62`, `viatico_model.dart:47-50`, `invitation_model.dart:34`, `company_model.dart:27`, `service_request_model.dart:39,52`, `audit_log_model.dart` (agregar `fromMap`).
- [ ] **0.4 Parseo numérico chileno y prevención de `RangeError` / `StateError` / división por cero:**
  - `ziyu_service.dart:360-362`: Limpiar separadores de miles `.` en `_parseRow` Excel/CSV igual que en PDF (evita truncar montos chilenos como `"20.000"`).
  - `config_admin_view.dart:165-176, 663, 702`: Unificar parsing numérico con `NumberUtils.tryParseDouble` y proteger `rule['km'] <= 0` contra `Infinity`/`NaN`.
  - `create_incidencia_dialog.dart:27-30, 292`: Proteger `vehicles.isEmpty` y normalizar `.` en `costoCtrl`.
  - `fuel_performance_view.dart:106, 576`: Proteger `vehicles.isEmpty` y `rendimientoKmPorLitro <= 0`.
  - `csv_importer_dialog.dart:480`: Validar `idxLat >= 0 && idxLng >= 0` antes de indexar `cols`.
  - `viaticos_admin_view.dart:96` y `liquidaciones_admin_view.dart:269, 401`: Proteger `.substring(...)` cuando el ID tenga longitud menor a 6/8 chars.
  - `shift_start_screen.dart:37, 168`: Cambiar `int.parse` por `int.tryParse` + validación numérica real.
  - `monthly_summary_screen.dart:162, 179` y `cotizador_screen.dart:159`: Eliminar `config!` forzado cuando `companyConfigProvider` aún carga.
  - `route_elevation_profile_widget.dart:353`: Proteger `points.length <= 1` contra división `0 / 0 = NaN`.
  - `retro_trip_form_screen.dart:331-334`: Sincronizar `_patenteCtrl` si el chofer escribe la patente sin hacer tap en el autocomplete.
- [ ] **0.5 Manejo real de errores en lugar de `catch (_)` silenciosos:**
  - `kpi_dashboard_view.dart:885, 1294, 1524`: Mostrar error real en SnackBar si falla guardar viaje/gasto, y resetear `isApplying = false` en `finally` (elimina botón bloqueado si `profile == null`).
  - `admin_repository.dart:117-142` y `expense_form_screen.dart:177-179`: Loguear y manejar errores en actualización de vehículo/odómetro.

---

## FASE 1 — Columna Vertebral Única (`TmsBackbone`) y Fin de Lógica Duplicada
*Objetivo: Que exista UNA sola implementación por cada regla de negocio y que todas las pantallas lean de ella.*

- [x] **1.1 Núcleo `TmsBackbone` creado** (`lib/core/utils/tms_backbone.dart`) y conectado a `kpi_dashboard_view.dart`, `chilean_financial_calculator.dart`, `analytics_view.dart`, `monthly_reports_view.dart`, `fuel_performance_view.dart`.
- [ ] **1.2 Centralizar TODAS las reglas duplicadas en `TmsBackbone` / `ChileanFinancialCalculator`:**
  - **Regla de Viáticos (hoy duplicada en 7 lugares):** Centralizar cálculo de viático por viaje y por jornada (`POR_VIAJE` vs `POR_JORNADA`, `umbralKilometrosViatico`, `montoViaticoLocal`/`Largo`) en un solo método consumido por `ChileanFinancialCalculator` (3 métodos), `viaticos_admin_view.dart` (2 métodos), `monthly_summary_screen.dart` (2 métodos) y `pdf_service.dart`.
  - **Regla de Comisión del Chofer (INCONSISTENCIA GRAVE):** Hoy `calculateMonthlyEmployerCost` y `calculateRouteProfitability` comisionan sobre `value + extraCostos + sobreEstadia`, mientras **`calculateDriverPayslip:130` y `monthly_summary_screen:66-72` solo usan `value`**. Definir si `extraCostos`/`sobreEstadia` son comisionables y aplicarlo **en los 4 lugares igual**.
  - **Regla de Mantenimiento por KM (hoy en 4 lugares):** Centralizar `resolveMaintenanceCostPerKm(vehicle, config)` (`vehicle.costoMantenimientoPorKm ?? suma(config.maintenanceRules)`) y conectarlo en `calculateCompanySummary`, `calculateRouteProfitability`, `calculateTripQuote` y `monthly_reports_view.dart` (eliminar fallback duro `49.0`).
  - **Formateo y parsing CLP único:** Eliminar `_fmt` duplicados en `kpi_dashboard_view:1606`, `cotizador_screen:1063`, `monthly_summary_screen:891` y `_formatValue` en `trip_form_screen:128` / `retro_trip_form_screen:568`; usar exclusivamente `NumberUtils`.
- [ ] **1.3 Conectar todas las vistas faltantes al estándar único (`INICIO ➔ CLIENTE(S) ➔ DESTINO`, vehículo canónico y precio/rendimiento real):**
  - `control_tower_view.dart:268, 1968, 2173, 2210`: Eliminar los 4 lugares con `totalDistanceKm / 2.5` fijo y usar `TmsBackbone.resolveVehicleEfficiency` + `canonicalRoute`.
  - `monthly_summary_screen.dart:277, 658`: Usar `TmsBackbone.findVehicle` y `TmsBackbone.canonicalRoute` (elimina resolución duplicada de patente).
  - `monthly_report_exporter.dart:23, 26, 309-311`: Limpiar parámetros sin uso o conectar PDF/Excel directamente a los datos filtrados de `MonthlyReportsView`.
  - `ai_analytic_service.dart:109, 153`: Incluir `totalViaticos` en el CPK enviado a la IA para que coincida 100% con `analytics_view.dart:501`.
  - Estandarizar guardado de `vehicleId` canónico (`VEH-...`) al crear viajes/gastos en `trip_form_screen`, `retro_trip_form_screen`, `expense_form_screen` y `driver_dashboard_screen`.

---

## FASE 2 — Confiabilidad Total de Datos Reales: Telemetría, Jornadas, Combustible y Métricas Falsas
*Objetivo: Eliminar placeholders inventados ("Road Master Score fake") y cruzar GPS vs Jornadas vs Combustible vs Peajes.*

- [ ] **2.1 Reemplazar Placeholders Falsos ("Road Master Score") con datos reales:**
  - `driver_profile_screen.dart:445-448`: Hoy muestra **hardcodeado `94 / 100` (`38/40`, `28/30`, `28/30`)** ignorando `tripsAsync`.
  - `driver_efficiency_matrix_view.dart:280, 411`: Hoy calcula **`90 + (c.nombre.hashCode % 9)`**.
  - **Solución:** Construir calculadora real de puntaje en `TmsBackbone` usando datos trazables: cumplimiento de hitos reales, variación odómetro vs GPS de jornadas cerradas, rendimiento real vs esperado del camión y exceso de ralentí.
- [ ] **2.2 Cuadratura Automática de Jornadas vs Viajes y Alertas de Fugas/Discrepancias:**
  - Exponer en Dashboard Admin (`kpi_dashboard_view.dart`) los datos que la app chofer ya calcula al cerrar jornada (`driver_dashboard_screen.dart:4054-4060`: `deltaOdo`, `unregisteredKm`, `variationPercent` Tablero vs GPS).
  - Emitir alerta automática visible en Dashboard cuando:
    1. `|Jornada.totalKm - Suma(Viajes.totalKm)| > 15 km` o existan viajes finalizados con `0 km`.
    2. El consumo/rendimiento real de combustible entre Full Tanks caiga > 15% respecto al esperado del camión (alerta de posible fuga/robo).
    3. Los minutos de ralentí (`idleMinutes` de `ModoGpsService`) superen `matchedVehicle.maxMinutosRalentiAlerta`.
- [ ] **2.3 Corregir bugs reales de Telemetría y ModoGPS (`modogps_service.dart`, `route_mission_service.dart`, `gps_harvest_service.dart`):**
  - `modogps_service.dart:71-79`: Corregir `GpsGeofence.contains` en círculos (`type == 3`) que hoy retorna `inBox` cuando está fuera del radio circular.
  - `modogps_service.dart:637-639, 725`: Pasar `idEmpresa` al reintentar sesión en `fetchFleetData` y resolver nombre de conductor real en vez de `'Conductor Asignado'`.
  - `modogps_service.dart:1067-1130`: Unificar el cálculo de `GpsTripLeg` y aplicarle también el filtro anti-saltos `segMeters < 50000`.
  - `control_tower_view.dart:206`: Corregir condición `allAltitudesZero` para que actualice el perfil DEM y el comparador aunque el GPS reporte altitudes `> 0`.
  - `route_mission_service.dart:329-334, 432-444, 584-644`: Corregir bounding box de Ruta Itata (`-36.65`), usar interpolación lineal real en topografía y unificar `fetchDemElevationProfile` con `analyzeDetailedTopography`.
  - `fuel_performance_service.dart:129, 212` y `fuel_performance_view.dart:22`: Usar ventana de 60–90 días (desde el último Full Tank real) en vez de solo el mes seleccionado, y separar fecha base del equipo auxiliar (`auxExpenses`) respecto al estanque principal.

---

## FASE 3 — Auditoría Contable y Tributaria Chile (Cero Descuadres en F29, Caja y Costos)
*Objetivo: Cuadratura peso a peso entre Dashboard Ejecutivo, Informes Mensuales, Analítica, Ziyu y Liquidaciones.*

- [ ] **3.1 Arreglar Historial de 3 Meses y Filtros en Informes Mensuales (`monthly_reports_view.dart`):**
  - `monthly_reports_view.dart:560+` (Lote 16): Corregir arrastre de `remanenteCreditoFiscalAcumulado` en `_calculate3MonthsHistory` (hoy toma el remanente vigente actual y lo aplica al mes `t-2` desfasando los 3 meses).
  - Hacer que `_filterVehicleId` filtre **todas** las pestañas (Resumen, Radiografía por Unidad, Matriz de Rutas, Incidencias) y las exportaciones PDF/Excel, usando `TmsBackbone.canonicalVehicleKey`.
- [ ] **3.2 Coherencia de Tendencias y Desgloses (`admin_provider.dart`):**
  - `admin_provider.dart:423-430`: Pasar `vehicles` y remanente correcto en `trendProvider` para que las gráficas históricas coincidan con el Dashboard del mes.
  - `admin_provider.dart:362-364`: Hacer que `expenseBreakdownProvider` respete `exp.customIva` y `exp.isExento` igual que `calculateCompanySummary` (hoy asume `1.19` para todo lo que no sea peaje).
- [ ] **3.3 Seguridad de datos en `trip_form_screen.dart` y `ziyu_service.dart`:**
  - `trip_form_screen.dart:96-107, 149-160`: Guardar y restaurar `_tipoMovimiento` e `_intermediateStopsCtrls` en `TripDraft`.
  - `cotizador_screen.dart:141, 143` y `cotizador_provider.dart:57-96`: Preservar `estado` y `createdAt` al editar cotización existente, y permitir limpiar a `null` campos manuales en `copyWith`.
  - `ziyu_service.dart:161-166`: Limpiar rama vacía en parsing PDF y verificar conciliación de viajes con `OS`.

---

## FASE 4 — Limpieza de Arquitectura, Colecciones Fantasma, UX y Performance
*Objetivo: Eliminar código muerto, fugas de memoria y pantallas ilegibles.*

- [ ] **4.1 Eliminación de Código Huérfano y Colecciones Duplicadas/Sin Uso:**
  - Eliminar `lib/features/admin/presentation/widgets/operational_chat_widget.dart` (155L, 0 usos).
  - Unificar `config_empresas` vs `configuraciones_empresa` en Firestore (`config_empresas` / `configuraciones_empresa`).
  - Definir y limpiar colecciones fantasma: `gps_monitor` (cron LioT cada 2 min que nadie lee) y `telemetry/{empresa}/raw_positions` (evaluar apagar cron/cosecha o unificarla; si se conserva `GpsHarvestService`, corregir `math`, guardar `trip_end`, corregir `st.reset()` en primer ciclo y evitar `plate == ''` en `getFleetStats`).
  - Limpiar `location_service.dart` (`startTracking`/`stopTracking` huérfanos, limpiar `current_empresa_id` al cerrar, respetar timestamp original en buffer offline).
  - Corregir `file_downloader.dart` (ramas Web/Mobile idénticas usando `Printing.sharePdf` hasta para CSV).
- [ ] **4.2 Corregir UI rota / ilegible:**
  - `register_profile_screen.dart:514-515` y `liquidaciones_admin_view.dart:47-49`: Botones `#E0E0E0` con texto blanco (contraste ilegible) -> usar texto oscuro `#121212`.
  - `viaticos_admin_view.dart:410`, `ziyu_conciliation_view.dart:172`, `liquidaciones_admin_view.dart:59, 90`: `SnackBar` fondo blanco con texto blanco -> usar fondo oscuro/verde legible.
  - `conductores_view.dart:476, 719`: Cambiar teclado de RUT de `TextInputType.number` a `TextInputType.text` para permitir `'K'` y `'-'`.
  - `monthly_summary_screen.dart:237`: Conectar `onTap` al header de mes para que abra `_selectMonth` y sacar `getTripsForMonth` fuera de `build()`.
  - `ziyu_conciliation_view.dart:38, 228`: Pasar `fileName` real (o `null` cuando vacío) para destrabar el flujo.
  - `control_tower_view.dart:3154-3160` y `csv_importer_dialog.dart:652,717`: Agregar campos de descanso al form de puntos de infraestructura y deduplicar clientes contra `infraestructura_vial` además de ModoGPS.
  - `remuneraciones_view.dart:115-116`: Garantizar que `selectedMonth` siempre exista en las opciones del `DropdownButton`.
- [ ] **4.3 Corregir Fugas de Memoria (`dispose()`), Mutaciones en `build()` y Rendimiento:**
  - Implementar `dispose()` en todos los `TextEditingController`, `ScrollController` y `StreamSubscription` detectados (`config_admin_view.dart` x18, `control_tower_view.dart` x13, `driver_dashboard_screen.dart`, `conductores_view.dart`, `mantenimiento_admin_view.dart`, `fuel_performance_view.dart`, `flota_admin_view.dart`, `monthly_summary_screen.dart`, `login_screen.dart`, `shift_start_screen.dart`, `ziyu_conciliation_view.dart`, `liquidaciones_admin_view.dart`, `app_update_dialog.dart`, `fleet_chat_screen.dart` + borrar `playback_*.m4a` temporales).
  - Mover `_syncUnits`, `_selectedPlate = availablePlates.first`, `addListener` repetidos en `fieldViewBuilder` (`trip_form_screen`, `retro_trip_form_screen`, `shift_start_screen`) y `_odometerController` en `expense_form_screen` fuera de `build()`.
  - Optimizar `admin_provider.dart` (`O(M * N)` en `financialSummaryProvider`), `trip_repository.getTripsByDateRange` (filtrar fechas en query Firestore, no descargando todo desde servidor), y reemplazar `IndexedStack` de 17 vistas vivas en `admin_dashboard_screen.dart` o diferir carga hasta abrir la pestaña.

---

## FASE 5 — Peajes en Vivo, Notificaciones Push y Modularización
*Objetivo: Cerrar brechas en ruta y dividir archivos gigantes para evitar futuras regresiones.*

- [ ] **5.1 Peajes en vivo y catálogo unificado:**
  - `route_live_monitor.dart`: Aplicar también `calculateDistanceToSegmentMeters` y desempate *Nearest Gate* en vivo (`RoadInfrastructureDetector`), y limpiar parámetro `tipoCode` / comentarios desfasados.
  - `config_admin_view.dart:542, 599-605`: Leer versión actual dinámicamente (`PackageInfo`) en vez de hardcodear `v1.1.3` / URL fija en el panel admin.
- [ ] **5.2 Notificaciones Push reales (Chat, Avisos y Triggers):**
  - Corregir `push_notification_service.dart:135, 146` (doble escritura de token al iniciar) y `fleet_chat_screen.dart:161` (debouncing de `markAsRead` para no disparar múltiples escrituras en rebuilds).
  - Definir estrategia de envío Push real para Avisos Masivos y Chat de Flota dentro del plan gratuito (o al escalar a Blaze para desplegar `functions/index.js`).
- [ ] **5.3 Modularización de Archivos Monolíticos:**
  - Dividir `driver_dashboard_screen.dart` (4.391L) en widgets y controladores separados (`active_trip_card.dart`, `end_trip_dialog.dart`, `end_shift_dialog.dart`, `driver_drawer.dart`).
  - Dividir `control_tower_view.dart` (3.448L) en `live_map_panel.dart`, `history_route_panel.dart`, `route_comparator_panel.dart`, `infrastructure_editor_dialog.dart`.

---

## FASE 6 — Navegador GPS Integrado en Cabina (Solo tras cerrar Fases 0–5)
- [ ] Retomar especificación técnica en `DISENO_NAVEGADOR_CABINA_TMS.md` una vez que las Fases 0 a 5 estén verificadas y estables en producción.
