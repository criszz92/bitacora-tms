# Plan Maestro de Ingeniería, Estabilización y Auditoría — Bitácora TMS (Chile)

> **Base verificada:** Auditoría línea por línea de los **34 bloques / 102 archivos / ~42.114 líneas / 150 hallazgos** (`docs/AUDITORIA_COMPLETA_34_BLOQUES.md` + `docs/MAPA_MAESTRO_FUNCIONES.md`).  
> **Objetivo:** Convertir Bitácora TMS en un sistema **auditable, trazable y sin duplicación de lógica**, donde una única columna vertebral gobierne operaciones, telemetría, combustible, remuneraciones y tributación chilena (SII / F29 / Ley 19.764).  
> **Regla de continuidad:** Al retomar cualquier sesión de programación, leer primero este documento y `docs/MAPA_MAESTRO_FUNCIONES.md`, trabajar ítem por ítem en orden de fase, verificar con `flutter analyze` y marcar `[x]` con fecha.

---

## FASE 0 — Estabilidad Crítica: Crashes, Pérdida de Datos y Seguridad de Parseo ✅ COMPLETADA (2026-11-25)
*Prioridad Máxima: Eliminar todo punto donde la app o backend puede caerse en runtime o corromper un dato.*

- [x] **0.1 Backend `functions/index.js`:**
  - `functions/index.js:220`: Corregido `ReferenceError` por variable inexistente `vehiclePatente` en `onTripFinished`.
  - `functions/index.js:289`: Corregido `messages.join("\\n")` por `"\n"` en `dailyDocumentCheck`.
- [x] **0.2 Navegación bloqueada en Router (`app_router.dart`):**
  - Verificado que `app_router.dart:54` (`startsWith('/driver')`) ya cubre `'/driver-profile'`.
- [x] **0.3 Parseo seguro de Fechas Firestore (`TmsBackbone.parseDate` / `parseNullableDate`):**
  - Aplicado en `trip_model.dart`, `vehicle_model.dart`, `expense_model.dart`, `incidencia_model.dart`, `shift_model.dart`, `viatico_model.dart`, `invitation_model.dart`, `company_model.dart`.
- [x] **0.4 Parseo numérico chileno y prevención de `RangeError` / `StateError` / división por cero:**
  - Corregido en `ziyu_service.dart`, `fuel_performance_view.dart`, `create_incidencia_dialog.dart`, `csv_importer_dialog.dart`, `viaticos_admin_view.dart`, `liquidaciones_admin_view.dart`, `shift_start_screen.dart`, `monthly_summary_screen.dart`, `cotizador_screen.dart`, `route_elevation_profile_widget.dart`.
- [x] **0.5 Manejo real de errores en lugar de `catch (_)` silenciosos:**
  - `kpi_dashboard_view.dart:885, 1294, 1524`: Muestra error en SnackBar y resetea `isApplying = false` si `profile == null`.

---

## FASE 1 — Columna Vertebral Única (`TmsBackbone`) y Fin de Lógica Duplicada
*Objetivo: Que exista UNA sola implementación por cada regla de negocio y que todas las pantallas lean de ella.*

- [x] **1.1 Núcleo `TmsBackbone` creado** (`lib/core/utils/tms_backbone.dart`) y conectado a `kpi_dashboard_view.dart`, `chilean_financial_calculator.dart`, `analytics_view.dart`, `monthly_reports_view.dart`, `fuel_performance_view.dart`.
- [x] **1.2 Centralizar TODAS las reglas duplicadas en `TmsBackbone` / `ChileanFinancialCalculator`:**
  - **Regla de Viáticos:** Centralizada en `TmsBackbone.calculateTripsViaticos` y conectada en `ChileanFinancialCalculator` y `MonthlySummaryScreen`.
  - **Regla de Comisión del Chofer:** Unificada en `TmsBackbone.tripCommissionableAmount` (incluye `extraCostos + sobreEstadia` en `calculateDriverPayslip` y `MonthlySummaryScreen`).
  - **Regla de Mantenimiento por KM:** Centralizada en `TmsBackbone.resolveMaintenanceCostPerKm`.
- [x] **1.3 Conectar vistas clave al estándar único:**
  - `control_tower_view.dart`: Reemplazados los 4 cálculos fijos de `2.5` por `_estimateLitersForPlate` conectado a `TmsBackbone.resolveVehicleEfficiency`.
  - `ai_analytic_service.dart`: Incluye `totalViaticos` en el CPK enviado a IA.
  - [x] Paginación completa en `modogps_service.dart` (fin del truncamiento a 2.000 mensajes).

---

## FASE 2 — Confiabilidad Total de Datos Reales: Telemetría, Jornadas, Combustible y Métricas Falsas
*Objetivo: Eliminar placeholders inventados ("Road Master Score fake") y cruzar GPS vs Jornadas vs Combustible vs Peajes.*

- [x] **2.1 Reemplazar Placeholders Falsos ("Road Master Score") con datos reales:**
  - Conectado `TmsBackbone.calculateRoadMasterScore` en `driver_profile_screen.dart` y `driver_efficiency_matrix_view.dart`.
- [x] **2.2 Alertas Automáticas de Discrepancias y Fugas en Dashboard:**
  - Implementado `_buildOperationalAuditAlerts` en `kpi_dashboard_view.dart` (viajes finalizados en `0 km` y vehículos con caída de rendimiento > 15%).
- [x] **2.3 Corregir bugs reales de Telemetría y ModoGPS (`modogps_service.dart`):**
  - Corregido `GpsGeofence.contains` en círculos (`type == 3`), reintento de sesión con `idEmpresa` y filtro anti-saltos `< 50 km` en `GpsTripLeg`.

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

## FASE 5 — Peajes en Vivo, Notificaciones Push y Modularización ✅ AVANZADA (2026-11-27)
*Objetivo: Cerrar brechas en ruta y dividir archivos gigantes para evitar futuras regresiones.*

- [x] **5.1 Peajes en vivo y catálogo unificado:**
  - `route_live_monitor.dart`: Aplicado `calculateDistanceToSegmentMeters` en monitoreo en vivo.
- [x] **5.2 Notificaciones Push reales (Chat, Avisos y Triggers):**
  - `push_notification_service.dart`: Eliminada doble escritura de token al iniciar; `fleet_chat_screen.dart`: debounce en `markAsRead` y cancelación de `_playerSub`.
- [x] **5.3 Modularización de Archivos Monolíticos:**
  - Extraídos `end_trip_dialog.dart` (1.025L) y `end_shift_dialog.dart` (420L) desde `driver_dashboard_screen.dart` (reducido de 4.391L a 2.949L).

---

## FASE 6 — Navegador GPS Integrado en Cabina (Solo tras cerrar Fases 0–5)
- [ ] Retomar especificación técnica en `DISENO_NAVEGADOR_CABINA_TMS.md` una vez que las Fases 0 a 5 estén verificadas y estables en producción.
