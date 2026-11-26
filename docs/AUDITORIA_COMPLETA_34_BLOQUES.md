# Auditoría Completa Línea por Línea — 34 Bloques / 102 Archivos (Bitácora TMS)

> **Bloques auditados:** 34 | **Símbolos mapeados:** 394 | **Hallazgos (bugs, duplicados, huérfanos):** 150

---

## 1. Hallazgos por Bloque (Bugs, Lógica Duplicada, Código Huérfano e Inconsistencias)

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart (L1-L1200)
- Lógica duplicada en build(): LocationService.startKeepAlive se invoca tanto dentro de ref.listen(activeShiftProvider) (L44) como dentro de WidgetsBinding.instance.addPostFrameCallback (L61) en cada rebuild.
- Posible spam/duplicación de incidencias: _setupAutoDocumentReportListener (L1170) se llama dentro de activeShiftAsync.when(data: ...) en build() (L174); cada cambio en currentVehicleProvider dispara _triggerAutoReport creando una nueva IncidenciaModel con Uuid().v4() sin deduplicación por documento/fecha visible en este rango.
- En _buildDriverDrawer (L362) se usa ref.read(currentUserProfileProvider) en lugar de ref.watch, por lo que si el perfil carga después de abrir/construir el Drawer no se actualizará reactivamente.
- Versión 'v1.1.0' y URL de APK hardcodeadas en múltiples lugares (L577, L667, L684) en lugar de leerlas de PackageInfo/configuración centralizada.

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart (L1201-L2400)
- Código inalcanzable en _buildActiveTripCard (L1739 vs L1788): if (isIdle) ya captura unit.isRalenti == true, haciendo que final isRalenti = unit.isRalenti en el else (L1788) sea siempre false
- Inconsistencia en _showReportIncidentDialog (L1304): usa vehiclesProvider (comentado en L1215 como uninitialized provider) en lugar de adminRepositoryProvider.watchVehicles, pudiendo dejar vehicleDocId vacío
- Memory leak menor: TextEditingController descCtrl (L1266) y stopCtrl (L2342) no se liberan con dispose()

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart (L2401-L3600)
- Lógica duplicada de creación de _DetectedTollPass dentro del bucle de puntos GPS (L3168-3178) y al cierre del bucle (L3193-3203).
- Fallback teórico de distancia (distanceServiceProvider.lookupKm) duplicado en el else de hTrip (L3097-3104) y en el bloque catch (L3239-3244).
- En _showAddManualTollDialog (L3256-3257), nameCtrl y amountCtrl se crean localmente y no se hace dispose() al cerrar el diálogo.
- En _showEditTripDriverDialog (L2739-2740), guideCtrl y kmCtrl tampoco tienen dispose() explícito.
- En _EndTripDialogState._buildTollsSection (L3402), currencyFmt se declara pero no se utiliza en el fragmento L3401-3600 (a verificar si se usa más abajo).

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart:3601-4391
- Ningún bug evidente, duplicado o código huérfano detectado en este rango.

### lib/features/admin/presentation/widgets/control_tower_view.dart:1-1200
- _syncUnits(units) (L708) se invoca directamente dentro de build() mutando _lastUnits, _selectedPlate, _recentTrails, _motionStates y disparando _animController.forward(from: 0.0) durante el build phase.
- En _showGpsConfigDialog (L284): textController = TextEditingController() se crea dentro del método pero nunca se hace dispose() al cerrar el diálogo.
- En _fetchHistoricalRoute (L206): solo consulta DEM si allAltitudesZero (todos <= 0); si el GPS reporta al menos un punto > 0, no se llama _fetchDemProfileForTrip y _currentDetailedAnalysis / _comparedRouteA no se actualizan.
- En _loadGeofences (L157) y _checkUrlForToken (L144): bloques catch (_) silenciosos que ocultan errores sin logging.

### lib/features/admin/presentation/widgets/control_tower_view.dart (L1201-L2400)
- Doble SizedBox(height: 10) consecutivo en L1978 y L1980.
- Fórmula de combustible estimado (_historicalTrip!.totalDistanceKm / 2.5) duplicada en tres lugares (L1968, L2173, L2210).
- Mutación de estado durante build(): en _buildHistoryPanel (L1673-L1675) se asigna `_selectedPlate = availablePlates.first` directamente sin setState ni post-frame callback.

### lib/features/admin/presentation/widgets/control_tower_view.dart:2401-3448
- En _showCrearEditarPuntoDialog (control_tower_view.dart:3078-3089), los 12 TextEditingController creados localmente nunca se disponen (dispose) al cerrar el diálogo.
- En _showCrearEditarPuntoDialog (control_tower_view.dart:3154-3160), al cambiar el tipo a descanso se asigna subtipo = 'Servicentro', pero no existe sección de formulario para editar campos específicos de descanso (capacidadCamiones, tieneDuchas, tieneSeguridad, combustibleAltoFlujo) que sí se muestran en _showPuntoInfraestructuraDialog (control_tower_view.dart:2994-3002).
- En _showCrearEditarPuntoDialog (control_tower_view.dart:3249, 3258), las etiquetas usan '\\$' (backslash literal antes de $ en string normal de Dart, aunque en Dart single-quoted '\\$' imprime '\$' o '$', es innecesario/inconsistente).

### lib/features/admin/presentation/widgets/kpi_dashboard_view.dart:1-1200
- Error silenciado en _showAddTripDialog: catch (e) { /* Error silenciado */ } sin feedback al usuario (L885)
- _showEditTripDialog recibe parámetro tipado como dynamic t en vez de TripModel (L895)

### lib/features/admin/presentation/widgets/kpi_dashboard_view.dart (L1201-L1842)
- L1294: catch (e) { /* Error silenciado */ } en guardado de edición de viaje; si falla updateTripMap, el diálogo se cierra igual sin notificar error al usuario
- L1284: uso de cast dinámico (t as dynamic).toMap() para serializar el viaje antes de mutar campos
- L1346, L1349, L1352: DropdownButtonFormField usa initialValue en lugar de value (si el estado interno cambia programáticamente, ej. al cambiar vehículo o tipo, puede no reflejarse correctamente según versión de Flutter)
- L1314: ref.read(monthlyTripsProvider).value ?? [] dentro de _showEditExpenseDialog; si el provider está cargando o en error, la lista de viajes para vincular peaje queda vacía sin feedback
- L1524: en _showApplyRecurringExpensesDialog, si profile == null hace return sin resetear isApplying = false (el botón queda bloqueado en estado 'Aplicando...')

### Lote 10 (1 archivo, 1233L): lib/features/admin/domain/services/modogps_service.dart
- Token de Wialon hardcodeado en `_fallbackToken` (`modogps_service.dart:313`)
- En `GpsGeofence.contains` (`modogps_service.dart:71-79`), para círculos (`type == 3`) si `distMeters > maxAllowedDist`, igual cae al `return inBox;` final (devuelve `true` dentro del bounding box rectangular aunque esté fuera del círculo)
- En `fetchFleetData` (`modogps_service.dart:637-639`), cuando `res['error'] == 1` reintenta `_ensureSession()` sin pasar `idEmpresa: idEmpresa` (usa token global/fallback en vez del de la empresa)
- En `fetchTripInterval` (`modogps_service.dart:1067-1130`), el cálculo de distancia/velocidad máxima/promedio de cada tramo (`GpsTripLeg`) está duplicado para los tramos intermedios (`> 5` puntos) y el último tramo (`> 2` puntos), y a diferencia del cálculo global (`segMeters < 50000`), no filtra saltos GPS > 50 km
- En `fetchFleetData` (`modogps_service.dart:725`), `driverName` está hardcodeado como `'Conductor Asignado'`

### Lote 11: lib/features/trips/presentation/screens/trip_form_screen.dart (1-1173)
- En _buildFuzzyField (L894-898), se registra un listener en innerCtrl dentro de fieldViewBuilder en cada rebuild sin remover el anterior, pudiendo acumular listeners duplicados sobre innerCtrl.
- Duplicación de lógica de formateo de miles con puntos: _formatValue (L128-137) y _ThousandsSeparatorFormatter._formatWithDots (L1156-1164) implementan exactamente el mismo bucle, además de usar NumberFormat('#,###', 'es_CL') en _buildValueField (L1030, L1043, L1049-1050).
- En _initializeData (L96-107), al restaurar borrador no se restaura _tipoMovimiento ni _intermediateStopsCtrls (tampoco se guardan en TripDraft en _saveDraft L149-160).
- En _buildPuntoDescargaField (L802-819), la lista fallback de 7 destinos frecuentes está duplicada literalmente en data y orElse del maybeWhen.

### Lote 12 (lib/features/admin/presentation/widgets/config_admin_view.dart:1-1100)
- Memory leak: _ConfigAdminViewState declara 18 TextEditingController (config_admin_view.dart:23-43) pero no implementa dispose() para liberarlos
- Memory leak menor en diálogos: _addMaintenanceRule (211-213) y _addRecurringExpense (258-259) crean TextEditingController locales que no se disponen al cerrar el diálogo
- Versión OTA hardcodeada en UI y llamada (config_admin_view.dart:542, 593, 599-605): v1.1.3 (Build 14) y URL de GitHub Releases están fijas en código, requiriendo recompilar el admin para publicar futuras versiones
- Inconsistencia en validación de logo (config_admin_view.dart:955 vs 120-132): la UI indica 'Máx. 200 KB' pero _pickLogo() solo redimensiona a 300px de ancho sin validar ni limitar el tamaño final en bytes/KB
- Riesgo de división por cero o casteo en _maintenanceRules (config_admin_view.dart:663, 702): asume que rule['cost'] y rule['km'] son double y km > 0 al renderizar; si desde Firestore llega int o km == 0 lanzará TypeError o Infinity/NaN
- Inconsistencia en parsing numérico (config_admin_view.dart:165-176): algunos campos eliminan '.' o reemplazan ',' por '.', mientras umbralKilometrosViatico, tasaSIS, tasaMutual, porcentajeComision, margenObjetivoCotizacion y porcentajeRecuperacionIepd usan double.tryParse directo sin normalizar coma decimal

### Lote 13 (cotizador_screen.dart, 1074L)
- Posible NullPointerException en config!: CotizacionPdfService.generarProformaPdf(..., config: config!) tras guardar cotización si companyConfigProvider.value es null (cotizador_screen.dart:159); en cambio en el historial sí valida if (config == null) return; (cotizador_screen.dart:844).
- En _guardarCotizacion (cotizador_screen.dart:141, 143) al actualizar una cotización existente se fuerza estado: 'borrador' y createdAt: DateTime.now() en lugar de preservar los originales.
- _fmt(double amount) (cotizador_screen.dart:1063-1073) implementa formateo CLP manual duplicado ("idéntico al del dashboard") en lugar de reutilizar un helper compartido.
- En _buildNumField para 'Días del Viaje' (cotizador_screen.dart:424) se usa DecimalTextInputFormatter() permitiendo decimales aunque luego se parsea con int.tryParse(_diasCtrl.text) ?? 1 (cotizador_screen.dart:85).

### Lote 14 (1 archivo, 1031L) - fuel_performance_view.dart
- L106: `vehicles.firstWhere((v) => v.id == _selectedVehicleId, orElse: () => vehicles.first)` lanzará StateError si `vehicles` está vacío mientras `_selectedVehicleId != null` (por ejemplo, durante carga inicial o si se elimina el único vehículo).
- L576: `100.0 / vehicle.rendimientoKmPorLitro` sin guarda explícita contra `rendimientoKmPorLitro == 0` (produciría `Infinity`).
- L1014: dentro de `_showCalibrationDialog`, tras `await ref.read(adminRepositoryProvider).updateVehicle(...)`, se verifica `if (ctx.mounted)` pero se usa `ScaffoldMessenger.of(context)` (contexto del widget padre, no `ctx`) sin verificar `mounted` del State.
- L882-892: `TextEditingController` (`odoController`, `capacityController`, `computerController`) creados en `_showCalibrationDialog` no se disponen (`dispose()`) al cerrar el diálogo.

### Lote 15 (1 archivo, 982L): lib/features/driver/presentation/screens/monthly_summary_screen.dart
- Lógica de resolución de patente duplicada entre _tripItem (lines 277-283) y _showTripDetailSheet (lines 658-662).
- Cálculo de viático individual (isLong y viatico) duplicado entre _tripItem (lines 269-271) y _showTripDetailSheet (lines 601-603).
- Lista hardcoded de meses duplicada entre _buildMonthHeader (line 224) y _shareViaWhatsApp (line 909).
- Uso de operador bang (!) en config! (lines 162, 179): si companyConfigProvider emite null, lanzará excepción en runtime.
- En _showEditTripDriverDialog (lines 796-799), los TextEditingController (guideCtrl, kmCtrl) se crean localmente y no se hace dispose() al cerrar el diálogo.
- FutureBuilder en build() (line 59) ejecuta adminRepositoryProvider.getTripsForMonth en cada rebuild del widget, sin cacheo de Future en estado.
- En _buildMonthHeader (line 237), se muestra un Icon(Icons.arrow_forward_ios) pero el contenedor no tiene GestureDetector/InkWell ni onTap para abrir _selectMonth.

### Lote 16: lib/features/admin/presentation/widgets/monthly_reports_view.dart (840L)
- El filtro _filterVehicleId solo filtra routeStats (Matriz de Rutas); no filtra summary (Resumen), vehicleStats (Radiografía por Unidad), incidencias ni los datos pasados a exportMonthlyReportPdf/exportMonthlyReportExcel
- Inconsistencia en matching de vehículo: routeStats usa TmsBackbone.canonicalVehicleKey(..., vehicles), mientras _calculateVehicleStats usa comparación directa t.vehicleId == v.id || t.vehicleId == v.patente (y lo mismo para expenses/incidencias)
- _calculate3MonthsHistory inicia remanenteArrastre con config.remanenteCreditoFiscalAcumulado (el acumulado actual) aplicado al mes más antiguo (t-2) y lo arrastra hacia el mes actual, lo que puede duplicar o desfasar el remanente histórico si remanenteCreditoFiscalAcumulado corresponde al mes vigente
- _calculateVehicleStats recibe CompanyConfigModel config como parámetro pero no lo utiliza

### Lote 17 (2 archivos, 1529L): mantenimiento_admin_view.dart (773L), csv_importer_dialog.dart (756L)
- Inconsistencia de deduplicación en CsvImporterDialog: peajes deduplica contra infraestructuraRepositoryProvider.getPuntos() (csv_importer_dialog.dart:449), mientras clientes deduplica contra modoGpsServiceProvider.fetchGeofences() (csv_importer_dialog.dart:652) pero luego guarda en infraestructuraRepositoryProvider.guardarPunto() (csv_importer_dialog.dart:717); si ya se importaron clientes antes en infraestructura sin estar en ModoGPS, se volverán a duplicar.
- En _pickAndParsePeajesCsv (csv_importer_dialog.dart:480), si idxLat o idxLng es -1 (columna faltante en CSV tabular), cols[idxLat] lanzará RangeError antes o después según longitud.
- En _showEditMaintenanceDialog (mantenimiento_admin_view.dart:410-415), los TextEditingController (lastServiceCtrl, odometerCtrl, intervalCtrl) y en _showConvertToExpenseDialog (mantenimiento_admin_view.dart:725) amountCtrl se crean sin dispose().

### Lote 18 (chilean_financial_calculator.dart + conductores_view.dart)
- Discrepancia en comisión: calculateMonthlyEmployerCost (:25) y calculateRouteProfitability (:512,564) suman trip.value + extraCostos + sobreEstadia, mientras calculateDriverPayslip (:130) solo usa trip.value.
- Lógica duplicada de viáticos (POR_VIAJE vs por día) en calculateMonthlyEmployerCost (:65-89), calculateDriverPayslip (:153-177) y calculateRouteProfitability (:476-504).
- Lógica duplicada de costoGlobalMantenimientoPorKm en calculateCompanySummary (:253-258), calculateRouteProfitability (:523-528) y calculateTripQuote (:668-672).
- conductores_view.dart:476,719 - _input fuerza TextInputType.number también para el campo RUT, impidiendo ingresar 'K' o guion en teclados numéricos.
- conductores_view.dart:428-437 - Los TextEditingController de _DriverEditFormState no implementan dispose().

### Lote 19 (expense_form_screen.dart + route_mission_service.dart)
- expense_form_screen.dart:212-220: en build() se sobreescribe _odometerController.text y _horometroController.text si están vacíos; si el usuario borra el campo manualmente para editarlo, el siguiente rebuild lo vuelve a rellenar.
- expense_form_screen.dart:177-179: catch (_) silencioso al actualizar vehículo en adminRepositoryProvider.updateVehicle, oculta errores de red o permisos sin logging.
- route_mission_service.dart:432-444: en analyzeDetailedTopography el comentario dice 'Interpolar linealmente' pero en realidad asigna el valor del punto muestreado más cercano (nearest-neighbor), generando perfil escalonado entre muestras.
- route_mission_service.dart:329-334: en detectCorridor el comentario dice lng -72.60 a -72.95 pero el código usa -72.95 a -72.30, y exige lat < -36.65 dejando fuera el rango -36.65..-36.58.
- route_mission_service.dart:584-644: fetchDemElevationProfile duplica la consulta a Open-Meteo DEM y el cálculo de ascenso/descenso ya presentes en analyzeDetailedTopography (con distinto umbral de ruido: 3m vs 1.5m/2m).

### Lote 20 (2 archivos, 1263L): admin_repository.dart y fleet_chat_screen.dart
- admin_repository.dart:181-182: comentario dice 'Fecha: primer día del mes' pero el código usa DateTime(month.year, month.month, 15) (día 15).
- admin_repository.dart:117-142 (getLatestOdometerForVehicle): captura cualquier excepción en catch(e) y retorna null silenciosamente sin logging.
- fleet_chat_screen.dart:462-466: cada tap en play crea una nueva suscripción a voiceService.player.playerStateStream sin cancelarla ni guardarla en dispose(), generando potential memory leak y múltiples callbacks acumulados.
- fleet_chat_screen.dart:161-165: llama a markAsRead dentro de itemBuilder vía addPostFrameCallback cada vez que se reconstruye la lista si !isRead, pudiendo disparar múltiples escrituras redundantes antes de que el stream actualice readBy.
- fleet_chat_screen.dart:625-629: clase helper BoxInsets con método allShadow definida localmente al final del archivo de pantalla.

### Lote 21 (2 archivos, 1183L)
- driver_profile_screen.dart:80,444-448: tripsAsync (activeTripsProvider) se observa en build y se pasa a _buildRoadMasterScoreCard(tripsAsync), pero el parámetro no se usa; los puntajes del Road Master Score están completamente hardcodeados (94, 38, 28, 28).
- driver_profile_screen.dart:36-38: bloque else vacío en _loadLocalProfilePhoto() cuando user == null.
- retro_trip_form_screen.dart:331-334: en _buildVehicleSelector(), fieldViewBuilder usa el controller interno `ctrl` de Autocomplete y solo asigna `_patenteCtrl.text = selection` en `onSelected`; si el usuario escribe una patente manualmente sin seleccionar una opción de la lista, `_patenteCtrl.text` queda vacío al hacer `_submit()` (a diferencia de `_buildFuzzyField`, que sí sincroniza `innerCtrl` con `controller` mediante `addListener`).
- retro_trip_form_screen.dart:419-421: en _buildFuzzyField(), se agrega un listener a `innerCtrl` dentro de `fieldViewBuilder` en cada rebuild sin removerlo, lo que puede acumular listeners repetidos.
- retro_trip_form_screen.dart:563: el comentario dice 'Opcional en retroactivo', pero depende de lo que retorne ContainerValidator.validate cuando está vacío.

### Lote 22 (2 archivos, 1127L)
- analytics_view.dart:278-284,418-427: `getTitlesWidget` en `LineChart` y `BarChart` usa `data[val.toInt()]` sin verificar si `val` es entero (aunque `val < 0 || val >= data.length` protege contra out-of-bounds).
- register_profile_screen.dart:36,90,443: `_empresaDelCodigo` se comenta como "nombre de empresa que retorna la validación", pero se le asigna `invitation.idEmpresa` (el ID de empresa, no necesariamente el nombre legible).
- register_profile_screen.dart:514-515: En `_buildPrimaryButton`, cuando `color` es `0xFFE0E0E0` (botón Admin), `foregroundColor` cae en `Colors.white` (texto blanco sobre fondo gris claro `#E0E0E0`, bajo contraste), y el `CircularProgressIndicator` usa `color: Colors.white` fijo (invisible si `color == 0xFFFFFFFF`).
- register_profile_screen.dart:110-117: `_crearPerfilChofer` vuelve a llamar `validateInvitationCode` antes de `createChoferProfile` (doble validación sin transacción atómica en UI).

### Lote 23 (3 archivos, 1562L)
- ziyu_service.dart:13-14: comentario doc duplicado en parseFile.
- ziyu_service.dart:102-104: comentario de sección duplicado (Parseo de PDF Experimental / Mejorado).
- ziyu_service.dart:161-166: rama else if (inTarifaSection && orderedContainers.isNotEmpty) vacía (solo comentarios).
- ziyu_service.dart:360-362: en _parseRow (Excel/CSV), valueStr.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.') no elimina separadores de miles '.' antes de parsear (a diferencia de _extractLastValue en PDF), lo que puede fallar o truncar montos chilenos como '20.000'.
- driver_efficiency_matrix_view.dart:280,411: Road Master Score es un placeholder visual (90 + (c.nombre.hashCode % 9)) y no un cálculo real de eficiencia/combustible.
- viaticos_admin_view.dart:96: v.idChofer.substring(0,8) en fallback puede lanzar RangeError si idChofer tiene menos de 8 caracteres.
- viaticos_admin_view.dart:201-235 vs 383-400: lógica de cálculo de viáticos (POR_JORNADA vs POR_VIAJE, umbralKilometrosViatico, fallbacks 10000/6500) duplicada entre _showViaticoDetails y _marcarPagado.
- viaticos_admin_view.dart:410: SnackBar de confirmación usa backgroundColor: Color(0xFFFFFFFF) (blanco) con texto por defecto claro, pudiendo quedar ilegible.

### Lote 24 (3 archivos, 1449L)
- flota_admin_view.dart:185,417-427: memory leak menor: costoMantenimientoCtrl se crea en _showAddDialog pero nunca se llama a .dispose() al final del método (sí se hace dispose de los otros 11 TextEditingController)
- flota_admin_view.dart:142: en _buildVehicleCard se muestra v.rendimientoKmPorLitro sin toStringAsFixed, mientras que en el diálogo se formatea a 1 decimal
- admin_provider.dart:423-430: trendProvider llama a ChileanFinancialCalculator.calculateCompanySummary sin pasar vehicles ni customRemanenteAnterior, a diferencia de financialSummaryProvider (líneas 331-340)
- admin_provider.dart:288-329: financialSummaryProvider recalcula mes a mes desde el primer registro histórico en cada emisión de allTripsProvider/allExpensesProvider (O(M * N) en memoria)
- trip_repository.dart:255-257: getTripsByDateRange descarga TODOS los viajes del chofer desde el servidor (Source.server) y filtra fechas en memoria con +-1 día de margen

### Lote 25
- ziyu_conciliation_view.dart:19 (_referenciaController) y liquidaciones_admin_view.dart:15 (_facturaController): TextEditingController instanciados sin método dispose().
- ziyu_conciliation_view.dart:38: pasa '' (string vacío) como fileName a setResults('', ...), pero en línea 228 evalúa `state.fileName == null && state.results != null`, condición que nunca se cumple cuando fileName es ''.
- ziyu_conciliation_view.dart:172 y liquidaciones_admin_view.dart:59,90 y viaticos_request_screen.dart:92: SnackBar con backgroundColor: Color(0xFFFFFFFF) (blanco) y texto por defecto blanco (en ziyu_conciliation_view.dart y liquidaciones_admin_view.dart no se especifica color negro en el Text, haciéndolo ilegible).
- liquidaciones_admin_view.dart:47-49: botón 'Vincular' tiene backgroundColor Color(0xFFE0E0E0) (gris claro) y texto blanco (Colors.white), bajo contraste.
- liquidaciones_admin_view.dart:269 y 401: liq.id.substring(0, 6) podría lanzar RangeError si liq.id tuviera menos de 6 caracteres.
- viaticos_request_screen.dart:352: `color: isPendiente ? Colors.black : Colors.black` (expresión ternaria redundante, ambas ramas retornan Colors.black).

### Lote 26
- GpsHarvestService._UnitState.haversineKm (líneas 122-138): reimplementa sin, cos, sqrt y asin mediante series de Taylor/Newton en lugar de usar dart:math.
- GpsHarvestService.ingest (líneas 258-284): al cerrar el viaje no se genera ni guarda evento 'trip_end', aunque GpsEvent (línea 12) y getRecentEventsForAi (línea 341) lo contemplan como tipo de evento.
- GpsHarvestService.ingest (línea 189-194): las métricas de velocidad (speedSum, speedSamples, maxSpeed) se acumulan antes de verificar/iniciar el viaje, y si el viaje inicia en ese mismo ciclo (línea 198), st.reset() borra esas muestras del primer punto.
- GpsHarvestService.getFleetStats (línea 389): si un documento tiene plate nulo o vacío, se agrega '' al Set plates, inflando active_trucks.
- RouteElevationProfileWidget._ElevationCurvePainter.paint (línea 353): si points.length == 1, (i / (points.length - 1)) produce división por cero (0 / 0 = NaN).

### Lote 27 (4 archivos, 1535L)
- functions/index.js:220 - BUG: ReferenceError en onTripFinished: usa variable no definida `vehiclePatente` en `El camión ${vehiclePatente} está a...` (debería ser `vehicleData.patente || vehicleRefId`).
- functions/index.js:289 - BUG menor: `messages.join("\\n")` usa doble backslash literal en lugar de salto de línea `\n`.
- lib/features/admin/presentation/widgets/monthly_report_exporter.dart:23,26 - Parámetros no utilizados en exportMonthlyReportPdf: `monthlyExpenses` y `drivers` son required pero nunca se leen.
- lib/features/admin/presentation/widgets/monthly_report_exporter.dart:309-311 - Parámetros no utilizados en exportMonthlyReportExcel: `monthlyExpenses`, `vehicles` e `incidencias` son required pero nunca se leen.
- lib/features/trips/domain/services/route_tariff_baseline_service.dart:34 - `RouteTariffAnomaly.severity` es `dynamic` (mezcla Strings como 'normal', 'advertencia', 'fraude_sospecha', 'incompleto', 'nuevo' con enum `AnomalySeverity`).

### Lote 28 (4 archivos, 1415L)
- create_incidencia_dialog.dart:27-30: si `vehicles` está vacío, `vehicles.first` lanza StateError antes de abrir el diálogo (y `selectedVehicleId` es null).
- create_incidencia_dialog.dart:292: `double.tryParse(costoCtrl.text)` no limpia puntos/separadores de miles (a diferencia de service_requests_inbox_view.dart:325 que hace `.replaceAll('.', '')`).
- location_service.dart:195 & 214: en `pointsBuffer.add` se guarda `timestamp: DateTime.now().toIso8601String()`, pero al hacer `batch.set` se sobreescribe con `FieldValue.serverTimestamp()` (se pierde la hora real de captura cuando hay buffer offline).
- location_service.dart:314-318: `stopTracking()` limpia 5 keys de SharedPreferences pero NO remueve `_currentEmpresaIdKey` ('current_empresa_id').
- push_notification_service.dart:135 & 146: en `initialize()` se escucha `authStateChanges()` y además se llama `getToken()` inmediatamente, pudiendo ejecutar `_saveTokenToFirestore` dos veces seguidas al iniciar con sesión activa.

### Lote 29 (5 archivos, 1563L)
- shift_start_screen.dart:18-19,283-285: _plateCtrl y _odometerCtrl no se liberan en dispose(); fieldViewBuilder registra controller.addListener(...) en cada rebuild sin removerlo
- shift_start_screen.dart:37,168: int.parse(_odometerCtrl.text) sin tryParse ni validación numérica en el validator (solo valida isEmpty)
- fuel_performance_service.dart:129,212: cargas auxiliares (auxExpenses) se filtran contra baseFecha del camión principal (ultimoLlenadoFecha) en lugar de una fecha propia del auxiliar
- admin_dashboard_screen.dart:204-225: IndexedStack mantiene instanciadas las 17 vistas del panel simultáneamente

### Lote 30 (6 archivos, 1597L)
- TripModel.fromMap (trip_model.dart:179) y VehicleModel.fromMap (vehicle_model.dart:129-131, 137) usan DateTime.parse() sin tryParse ni soporte para Timestamp de Firestore (a diferencia de CotizacionModel y PuntoInfraestructuraModel).
- AppUpdateDialog._startUpdate (app_update_dialog.dart:40): no almacena ni cancela en dispose() la StreamSubscription retornada por AppUpdateService.executeOtaUpdate().
- VehicleModel.getExpiringDocuments (vehicle_model.dart:236, 247): threshold usa medianoche (DateTime(now.year, now.month, now.day)) mientras remainingDays usa date.difference(now).inDays con hora actual, pudiendo desfasar el conteo de días restantes.

### Lote 31 (7 archivos, 1529L)
- `SilentNavigatorService`: comentario en línea 54 dice ventana de 30 minutos, pero el código en línea 117 valida `inMinutes < 25`.
- `RoadInfrastructureDetector.getOptimalDetectionRadius`: comentario en línea 82 dice "Radio estricto de 16m" para peajes laterales y "45m" para troncales, pero el código retorna `24.0` y `50.0` (`road_infrastructure_detector.dart:94,101`). Además el parámetro `tipoCode` no se usa dentro del método.
- `RoadInfrastructureDetector.calculateDistanceToSegmentMeters` y `calculateBearing` no son llamados en `route_live_monitor.dart` (el monitor usa solo distancia punto-a-punto `calculateDistanceMeters`).
- `CotizadorFormState.copyWith` (`cotizador_provider.dart:57-96`): usa `??`, por lo que `updateField` no puede resetear a `null` los campos opcionales (`editandoId`, `precioDieselNetoManual`, `margenObjetivoManual`) una vez asignados (solo `reset()` los limpia).
- `RemuneracionesView._buildMonthSelector` (`remuneraciones_view.dart:115-116`): genera solo los últimos 6 meses; si `selectedMonthProvider` tuviera un mes fuera de ese rango, `DropdownButton(value: ...)` lanzaría error de aserción.

### Lote 32 (10 archivos, 1519L)
- login_screen.dart:13-14: `_emailCtrl` y `_passCtrl` (`TextEditingController`) nunca se liberan en `dispose()` (memory leak)
- operational_chat_widget.dart:13-14: `_controller` (`TextEditingController`) y `_scrollController` (`ScrollController`) nunca se liberan en `dispose()` (memory leak)
- operational_chat_widget.dart:74: `_scrollToBottom()` se invoca dentro de `build()` en cada reconstrucción cuando `messages.isNotEmpty`
- audio_voice_service.dart:111-113: `playAudio` crea archivos temporales `playback_<timestamp>.m4a` en `getTemporaryDirectory()` al reproducir Base64 pero nunca los elimina tras finalizar
- app_router.dart:54-61,131-133: La ruta `/driver-profile` está definida en `routes` (:131), pero NO está incluida en `isDriverPath` (:54-61) ni en `isAdminPath` (:62), por lo que un usuario con rol `CHOFER` que navegue a `/driver-profile` será redirigido a `/driver` (:74) y un `ADMIN` también será redirigido a `/admin` o `/driver` (:67-71)
- ai_analytic_service.dart:173: `history` (`List<Map<String, String>>`) se pasa directo a `messages` sin validar/sanitizar roles ni longitud máxima

### Lote 33 (17 archivos, 1591L)
- ContainerValidator:8-13: comentario dice 'Nótese que I, O, T no existen para evitar confusión con 1, 0, T', pero el mapa _letterValues SÍ incluye 'I': 19, 'O': 26, 'T': 31 (y salta 11, 22, 33 correctamente según ISO 6346)
- FleetMessageModel:20 vs FleetChatRepository:102: comentario en FleetMessageModel dice 'URL de Storage para audio', pero FleetChatRepository guarda Base64 directamente en content sin usar Storage
- ExpenseModel:93, IncidenciaModel:65, ShiftModel:62: DateTime.parse sin tryParse ni fallback ante strings nulos/inválidos (a diferencia de LiquidacionModel:58-63 que sí maneja Timestamp/String)
- ServiceRequest:39,52: cast directo `doc.data() as Map<String, dynamic>` y `(data['createdAt'] as Timestamp).toDate()` sin null-safety

### Lote 34 (15 archivos, 560L)
- `file_downloader.dart:7-18`: rama `if (kIsWeb)` y `else` ejecutan exactamente el mismo código (`Printing.sharePdf(...)`); además `Printing.sharePdf` se usa para descargar CSVs.
- `viatico_model.dart:47,48,50`, `invitation_model.dart:34`, `company_model.dart:27`: usan `DateTime.parse(...)` directamente sin manejo de `null` ni `Timestamp`, lo que lanzaría excepción si el campo falta o viene como `Timestamp` de Firestore.
- `audit_log_model.dart:26-38`: solo implementa `toMap()` (usa `Timestamp.fromDate(fecha)`), sin `fromMap()`.

---
## 2. Fórmulas y Constantes Detectadas por Módulo

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart (L1-L1200)
- Cálculo de KM de jornada: completedTrips.fold(0.0, (acc, t) => acc + (t.totalKm ?? 0.0)) (L814), donde completedTrips = trips.where((t) => t.status != 'En Ruta').
- Umbral de alerta de documentación en banner: vehicle.getExpiringDocuments(7) (7 días, L1126).
- Umbral de reporte automático de documentación: vehicle.getExpiringDocuments(1) (1 día o menos, L1176).
- Versión hardcodeada en tarjeta de plataforma del Drawer: 'v1.1.0' y URL de descarga APK 'https://github.com/criszz92/bitacora-tms/releases/download/v1.1.0/bitacora-tms-v1.1.0.apk' (L577, L667, L684).

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart (L1201-L2400)
- remaining = nextService - vehicle.currentOdometer (L1234); alerta roja si remaining <= 500 km (L1250)
- Umbral de movimiento GPS: unit.speed > 2.0 km/h (L1813)
- Límite de alertas de infraestructura en tarjeta activa: monitorState.activeAlerts.take(2) (L1656)

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart (L2401-L3600)
- Radio adaptativo de detección de peajes vía RoadInfrastructureDetector.getOptimalDetectionRadius (L3121-3125; comentario indica ~18m laterales, ~45m troncales)
- Umbral mínimo de distancia entre puntos GPS para calcular rumbo (evitar jitter): >= 15.0 metros (L3146, L3154)
- Ventana de agrupación de pasadas por un mismo peaje: > 20 minutos (L3166)
- Ventana de desempate de casillas paralelas (Nearest Gate Competition): < 180 segundos (3 minutos), reteniendo el candidato con menor distanceMeters (L3214-3224)
- Tarifa por defecto de peaje: peaje.tarifaCamionPesado ?? peaje.tarifaCamionSimple ?? 0.0 (L3168, L3193, L3312)
- Conversión de monto en _DetectedTollPass.amount: reemplaza '.' por '' y ',' por '.' antes de double.tryParse (L2978)

### lib/features/driver/presentation/screens/driver_dashboard_screen.dart:3601-4391
- Bucket de 10 minutos para ID determinístico de peaje: bucket10m = toll.passTime.millisecondsSinceEpoch ~/ 600000; expenseId = 'EXP-TOLL-${widget.trip.id}-${toll.peaje.id}-$bucket10m' (L3924-3925)
- Odómetro sugerido al cargar GPS en cierre de jornada: widget.shift.startOdometer + dist.round() (L4036)
- Delta odómetro: deltaOdo = enteredOdo - widget.shift.startOdometer (L4054)
- KM no registrados (km muertos): unregisteredKm = (hasValidOdo && deltaOdo > tripsKm) ? (deltaOdo - tripsKm) : 0.0 (L4055)
- Umbral de alerta y justificación de KM no registrados: > 2.0 KM (L4192, L4346)
- Porcentaje de variación Tablero vs GPS: variationPercent = ((deltaOdo - _gpsTotalKm!).abs() / deltaOdo) * 100.0 (L4059)
- Umbrales de variación Tablero vs GPS: <= 3.0% (verde/óptimo), <= 8.0% (ámbar/tolerancia normal), > 8.0% (rojo/variación alta) (L4248-4287)
- Opciones por defecto de _reasonOptions: ['Retorno a Base vacío', 'Traslado a Taller / Mantención', 'Carga de Combustible / Servicios', 'Movimiento Operacional en Patio', 'Otro movimiento autorizado'] (L4000-4006)

### lib/features/admin/presentation/widgets/control_tower_view.dart:1-1200
- Polling flota en vivo: cada 5 segundos (Duration(seconds: 5)) en fleetStreamProvider (L44)
- Animación de interpolación (lerp): 3800 ms con Curves.easeInOutCubic (L107-L109)
- Estela reciente (_recentTrails): máximo 10 puntos por unidad (L619-L621)
- Umbral de cambio de movimiento: dist > 0.00001 grados o |currentHeading - targetHeading| > 0.5 grados (L640)
- Menor ángulo de giro: ((targetHeading - startHeading + 540) % 360) - 180 (L671)
- Consumo estimado de combustible en Ruta A: trip.totalDistanceKm / 2.5 litros (L268)
- Centro inicial por defecto del mapa: LatLng(-36.9840, -73.1774), zoom 14 (L725-L726)
- Flechas direccionales en ruta histórica: cada max(12, pts.length ~/ 15) puntos con speed > 8.0 (L874-L878)

### lib/features/admin/presentation/widgets/control_tower_view.dart (L1201-L2400)
- Rendimiento de combustible estimado: _historicalTrip!.totalDistanceKm / 2.5 Lts (2.5 km/L) en L1968, L2173 y L2210.
- Zoom de mapa al seleccionar unidad: 15 (L1579); al seleccionar tramo: 13 (L2298); al seleccionar parada: 16 (L2342).
- Rango de fecha mínimo en DatePicker de historial: DateTime(2024, 1) hasta DateTime.now() (L1732-L1733).
- Modos de vista (_viewMode): 0 = En Vivo, 1 = Historial, 2 = Comparador (L1426-L1506, L1517-L1542).
- Ancho del panel lateral: 360 px (L1346).

### lib/features/admin/presentation/widgets/control_tower_view.dart:2401-3448
- Coordenadas por defecto al crear punto vial sin initialPos: lat = -36.9840, lng = -73.1774 (control_tower_view.dart:3081-3082)
- Umbral de primer movimiento mostrado en UI: >3 km/h (control_tower_view.dart:2576)
- Cálculo de demora de inicio: firstMotionTime.difference(firstGpsTime).inMinutes (control_tower_view.dart:2442)
- Cálculo de confianza de inicio: ALTA si firstMotionTime != null && engineOnAtStart; MEDIA si firstMotionTime != null; BAJA en otro caso (control_tower_view.dart:2456-2465)
- Formato de duración de jornada: '${dur.inHours}h ${dur.inMinutes % 60}m' (control_tower_view.dart:2707)
- Usuario creador por defecto si userProfile?.uid es null: 'MAESTRO' (control_tower_view.dart:3411)
- Entidad fiscalizadora por defecto para romanas: 'MOP / Vialidad' (control_tower_view.dart:2984, 3086)

### lib/features/admin/presentation/widgets/kpi_dashboard_view.dart:1-1200
- UTM por defecto: 65000.0 (L30)
- Precio diésel neto por defecto: 800.0 (L35)
- Recuperación IEPD por defecto: 80.0% (L224)
- Tasa PPM por defecto: 1.5% (L294)
- IVA: 19% (L289, L725)
- Total viaje en lista: t.value + (t.extraCostos ?? 0) + (t.sobreEstadia ?? 0) (L617)
- Consumo ralentí por defecto: 2.0 L/h (L1073)
- Estimación combustible en viaje: idleLts = (idleMin / 60.0) * ralentiLh; litrosRuta = kmCalculados / rendimientoVigente; litrosEstimados = litrosRuta + idleLts; costoCombustibleEstimado = litrosEstimados * precioDieselNeto (L1074-L1077)
- Umbral sugerencia aplicar KM GPS: diferencia > 0.5 km (L1159)

### lib/features/admin/presentation/widgets/kpi_dashboard_view.dart (L1201-L1842)
- _fmt(double amount) (L1606): formateo manual de moneda CLP sin decimales con separador de miles '.' y prefijo '$' o '-$'
- Confianza de inicio de jornada GPS (_buildDashboardJourneyStartCard, L1616-L1625): ALTA si firstMotionTime != null && engineOnAtStart; MEDIA si firstMotionTime != null; BAJA en caso contrario
- Duración de jornada (_buildDashboardJourneyEndCard, L1728-L1729): dur = end.totalDuration, formato '${dur.inHours}h ${dur.inMinutes % 60}m' si inHours > 0, sino '${dur.inMinutes}m'
- Total gastos fijos (_showApplyRecurringExpensesDialog, L1393): suma de g.monto sobre gastosFijos
- Tipos de gasto hardcodeados en _showEditExpenseDialog (L1346): ['Combustible', 'Peaje', 'Mantención', 'Seguro', 'Sueldo', 'Otros']
- Rango de DatePicker en _showEditExpenseDialog (L1340): firstDate: DateTime(2020), lastDate: DateTime(2100)

### Lote 10 (1 archivo, 1233L): lib/features/admin/domain/services/modogps_service.dart
- `_defaultHost = 'https://hst-api.wialon.com'`; `_fallbackToken` hardcodeado en `:313`
- Polling `singleVehicleGpsProvider`: cada `8s`; caché de sesión `_cachedEid`: `2 horas`; caché de geocercas: `15 min`; caché de flota: `3s`
- `GpsGeofence.contains`: margen bounding box `latMargin = 0.00035`, `lngMargin = 0.00045` (~38m); radio mínimo círculo `80.0 m` o `radiusMeters * 1.25`; Haversine `r = 6371000.0`
- `_loadLocalClientGeofences`: radio `250.0 m` si confianza == `'alta'`, sino `350.0 m`; deduplicación contra geocercas Wialon por nombre normalizado o distancia `< 400.0 m`; `pseudoId` desde `900001`
- `GpsUnit`: `isRalenti` (`isIgnitionOn == true && speed < 2.0`), `isMoving` (`isIgnitionOn == true && speed >= 2.0`), `hardwareMileageKm = mileageM / 1000.0`, `status = 'online'` si `netconn == 1 && speed > 2.0`, `'detenido'` si `netconn == 1 && speed <= 2.0`, `'offline'` si `netconn != 1`
- `fetchTripInterval`: paginación `batchSize = 2000`, `maxBatches = 25` (hasta 50,000 mensajes); filtro saltos GPS `segMeters < 50000` (50 km); primer movimiento `speed > 3.0` km/h; ralentí si `acc > 0 && speed <= 3.0 && 0 < dtSec <= 600`; estadía en geocerca `durMin >= 3` min; parada/corte de tramo `speed < 3.0` por `>= 8` min; consumo ralentí base `(idleSeconds / 3600.0) * 2.0` L/h

### Lote 11: lib/features/trips/presentation/screens/trip_form_screen.dart (1-1173)
- ID de viaje generado: 'VIAJE-${DateTime.now().millisecondsSinceEpoch}' (L233)
- Mandante por defecto en pre-asignación y retiro anticipado: 'MEDLOG TRUCK' (L120, L210, L873); en mantenimiento: 'MANTENIMIENTO' (L210)
- Valor de viaje: 0.0 para movimientos no operativos (L202); en operativos se parsea eliminando '.' (L202). Hint por defecto: '1.200.000' (L1030)
- Umbral de frecuencia para mostrar etiqueta 'Regla:' en tarifa sugerida: frequencyCount >= 3 (L1048); umbral rawVal >= 10000 para mostrar badge de tarifa normal verificada (L1059)
- Contenedor ISO 6346: longitud exacta 11 caracteres alfanuméricos sin guión (L141, L924, L945-947)
- Destinos frecuentes fallback hardcodeados (L802-819): 'Puerto Coronel', 'DP World Lirquén', 'Puerto SVTI', 'Medlog Coronel', 'Sitrans San Vicente', 'D&C San Vicente', 'Contopsa San Vicente'

### Lote 12 (lib/features/admin/presentation/widgets/config_admin_view.dart:1-1100)
- Valores por defecto al parsear en _saveConfig (config_admin_view.dart:164-176): sueldoMinimo=539000, umbralKilometrosViatico=100, tasaSIS=1.49, tasaMutual=0.90, porcentajeComision=10.0, valorUTM=65000, precioDieselNeto=800, diasLaboralesMes=22, margenObjetivoCotizacion=25.0, tasaPPM=1.5, remanenteCreditoFiscalAcumulado=0.0, porcentajeRecuperacionIepd=80.0
- Tramos Recuperación Diésel Ley 19.764 (config_admin_view.dart:476-494): 80.0% (Ventas <= 2.400 UF), 50.0% (2.401 a 6.000 UF), 31.0% (> 6.000 UF)
- Fórmula costo mantenimiento por km (config_admin_view.dart:663, 702): costPerKm = rule['cost'] / rule['km']; total = sum(rule['cost'] / rule['km'])
- Fórmula total gastos fijos mensuales activos (config_admin_view.dart:837): sum(g.monto) donde g.activo == true
- Procesamiento de logo (config_admin_view.dart:121-126): redimensionado a ancho máximo 300px manteniendo proporción y re-codificado como PNG Base64
- Constantes OTA hardcodeadas (config_admin_view.dart:542, 599-605): buildNumber=14, versionName='1.1.3', apkUrl='https://github.com/criszz92/bitacora-tms/releases/download/v1.1.3/bitacora-tms-v1.1.3.apk', mandatory=true

### Lote 13 (cotizador_screen.dart, 1074L)
- Valores iniciales de formulario: kmPosicionamiento='0', kmRuta='0', tarifa='0', peajes='0', viatico='0', dias='1' (cotizador_screen.dart:29-35)
- Defaults de configuración en guardado/limpieza: precioDieselNeto = 800, margenObjetivo = 25.0 (cotizador_screen.dart:120, 124, 208-209)
- Semáforo de margenPorcentaje: >= 25 verde, >= 10 naranja, < 10 rojo (cotizador_screen.dart:503-512, 781-783)
- Resultado operacional mostrado = tarifaPropuesta - (r['costoTotalReal'] ?? 0) (cotizador_screen.dart:610)
- Peajes efectivos = formState.idaYVuelta ? formState.peajes * 2 : formState.peajes (cotizador_screen.dart:608)
- Resumen comercial: iva = tarifaPropuesta * 0.19; total = tarifaPropuesta + iva (cotizador_screen.dart:679-680)
- Breakpoint responsive: isMobile = MediaQuery.of(context).size.width < 900 (cotizador_screen.dart:242)
- Historial limitado a cotizaciones.take(20) (cotizador_screen.dart:780)

### Lote 14 (1 archivo, 1031L) - fuel_performance_view.dart
- Precio diésel neto resuelto vía TmsBackbone.resolveDieselNetoPrice(...) (L29-35)
- Resumen de flota vía FuelPerformanceService.calculateFleetSummary(...) (L123-127) y por vehículo vía FuelPerformanceService.calculateVehicleTankState(...) (L195-200, L316-321)
- Conversión L/100km: 100.0 / vehicle.rendimientoKmPorLitro (L576) y 100.0 / newKmPerLiter (L872)
- Umbrales visuales de nivel/alerta: flota <30% rojo (L149); unidad no calibrada barra fija en 0.05 (L262, L418); porcentaje <25% rojo, <50% ámbar, >=50% verde (L267-271, L423-427); diferencia computador a bordo <=5.0% verde / >5.0% ámbar (L652-661); botón aplicar nuevo rendimiento base visible si abs(lastRealRendimiento - rendimientoKmPorLitro) > 0.05 (L610)

### Lote 15 (1 archivo, 982L): lib/features/driver/presentation/screens/monthly_summary_screen.dart
- Comisión: totalFacturacion * ((config?.porcentajeComision ?? 0) / 100), donde totalFacturacion suma t.value solo de viajes con t.isOperativo - monthly_summary_screen.dart:66-72
- Viáticos por jornada (1 por día con al menos un viaje operativo): si algún viaje operativo del día tiene (t.totalKm ?? 0) >= (config?.umbralKilometrosViatico ?? 100), suma driver.montoViaticoLargo ?? 10000; si no, driver.montoViaticoLocal ?? 6500 - monthly_summary_screen.dart:77-88,270-271,602-603
- Total KM: suma de (t.totalKm ?? 0).toInt() de todos los viajes (operativos y no operativos) - monthly_summary_screen.dart:104-107
- Facturación por cliente: suma de t.value agrupada por t.client solo para viajes con t.isOperativo && t.client.isNotEmpty - monthly_summary_screen.dart:108-110
- Formato moneda: es_CL, símbolo '$', 0 decimales (_fmt) - monthly_summary_screen.dart:891
- Rango selector de fecha: firstDate: DateTime(2024), lastDate: DateTime.now() - monthly_summary_screen.dart:899-900

### Lote 16: lib/features/admin/presentation/widgets/monthly_reports_view.dart (840L)
- costoMantenimientoPorKm por defecto: 49.0 (v.costoMantenimientoPorKm ?? 49.0)
- desgasteTeorico = km * costoKm
- saldoMantenimiento = desgasteTeorico - gastoTallerReal
- diasOperativos = (diasHabilesTotalesMes - diasTaller).clamp(0, diasHabilesTotalesMes)
- tasaDisponibilidad = diasHabilesTotalesMes > 0 ? (diasOperativos / diasHabilesTotalesMes) * 100 : 100.0 (umbral visual verde >= 90%)
- costoDirecto (ruta) = totalFuelCost + totalTolls + totalViaticos + totalPersonal + totalMaintenance
- rentabilidad (ruta) = totalIncome > 0 ? (netMargin / totalIncome) * 100 : 0.0 (umbral visual verde >= 25%)
- Historial 3 meses: arrastre de remanenteCreditoFiscalAcumulado entre los 3 meses usando ChileanFinancialCalculator.calculateCompanySummary y config.utmHistory / config.dieselHistory

### Lote 17 (2 archivos, 1529L): mantenimiento_admin_view.dart (773L), csv_importer_dialog.dart (756L)
- Umbrales de estado de mantenimiento por km restantes (remaining = nextService - currentOdometer): >2000 'Óptimo', >1000 'Planificar', >500 'Próximo', >0 'Crítico', <=0 'Vencido' (mantenimiento_admin_view.dart:128,138-158)
- Progreso barra cambio de aceite: (currentOdometer - lastService) / (nextService - lastService) clamped [0.0, 1.0] (mantenimiento_admin_view.dart:164-170); marcas visuales de zona en 50%, 75%, 90% (mantenimiento_admin_view.dart:334-349)
- Intervalo por defecto para próximo cambio de aceite: 15000 km; cálculo automático nextKm = lastService + interval (mantenimiento_admin_view.dart:414,426-427,522-523)
- Rango de DatePicker documentación vehículo: firstDate 2020, lastDate 2032 (mantenimiento_admin_view.dart:590-591)
- Deduplicación peajes: clave '${nombre.toUpperCase()}_${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}' (csv_importer_dialog.dart:453,491,541)
- Peajes en bloque vertical: tarifa2Ejes fallback = tarifaMas2Ejes * 0.55 si t2 == 0; filtro numérico de tarifas > 500 (csv_importer_dialog.dart:531,552)
- Peajes guardados: radioMetros = 120.0, sentido = 'Bidireccional', admiteTag = true, origenDato = 'csv_masivo', tipo = TipoPuntoInfraestructura.peaje (csv_importer_dialog.dart:587-601)
- Clientes guardados: radioMetros = 250.0 si confianza == 'alta' else 350.0, origenDato = 'csv_clientes', tipo = TipoPuntoInfraestructura.descanso (csv_importer_dialog.dart:708-715)
- Fallback creadoPor: 'Administrador TMS' (csv_importer_dialog.dart:581,702)

### Lote 18 (chilean_financial_calculator.dart + conductores_view.dart)
- chilean_financial_calculator.dart:33-34,137-138 - Gratificación Legal: ((sueldoBase + comision) * 0.25).clamp(0, (config.sueldoMinimo * 4.75) / 12).
- chilean_financial_calculator.dart:59,105,196 - Seguro Cesantía: Empleador 3.0% (Plazo Fijo) / 2.4% (Indefinido); Trabajador 0.6% (si != Plazo Fijo).
- chilean_financial_calculator.dart:71-72,96,100 - Defaults chofer: viático largo 10000, viático local 6500, AFP 10.58%, Salud 7.0%.
- chilean_financial_calculator.dart:250,340-346,660 - IVA 19% (0.19 / 1.19); Ley 19.764 Diésel: litros * (1.5 * utmToUse / 1000.0) * pctRecup (fallback 0.80); F29: balanceIva = ivaDebito - ivaCredito - recuperacionDiesel - remanenteAnterior.
- chilean_financial_calculator.dart:720 - Cotizador tarifaMinimaSugerida = costoTotalReal / (1 - margenObjetivo / 100).
- conductores_view.dart:27,191-200 - Breakpoints: mobile < 900px; grid 1 col (<600), 2 cols (<1200), 3 cols (>=1200).
- conductores_view.dart:315-324 - Alerta vencimiento documentos: < 0 días VENCIDO, <= 30 días por vencer.
- conductores_view.dart:449-457 - Defaults formulario: sueldoMinimo 539000, viático local 6500, largo 10000, AFP '10.58', Salud '7.0', contrato 'Indefinido', baseImponible 'Total'.

### Lote 19 (expense_form_screen.dart + route_mission_service.dart)
- Tipos de gasto: ['Peaje', 'Combustible', 'Mantenimiento / Taller', 'Repuesto / Insumo', 'Otros']; Peaje es exento por defecto (_isExento = true), otros afectos a IVA 19% (expense_form_screen.dart:33,266-270,303)
- Rendimiento Full Tank: kmRecorridos = odoValue - matchedVehicle.ultimoLlenadoKm; totalLiters = intermediateLiters + litrosValue; rendimientoTramo = (kmRecorridos / totalLiters) redondeado a 2 decimales (expense_form_screen.dart:96-117)
- Comparación computador a bordo: computerKmPorLitro = 100.0 / computerL100km; variacionComputadorPct = ((rendimientoTramo - computerKmPorLitro) / computerKmPorLitro) * 100.0 (1 decimal); factorCorreccionComputador = rendimientoTramo / (100.0 / computerL100km) (3 decimales) (expense_form_screen.dart:120-124,171-172)
- Catálogo estático deliveryCatalog: 12 destinos (3 puertos marítimos, 9 depósitos extraportuarios/frigoríficos) en Biobío/Ñuble con coordenadas LatLng y geocercas ModoGPS (route_mission_service.dart:112-212)
- Corredores detectados por bounding box: Ruta 152 Itata (lat -36.78..-36.58 con lat < -36.65, lng -72.95..-72.30), Ruta 146 Cabrero (lat -37.10..-36.80, lng -72.95..-72.40), Ruta 5 Sur (lat -37.45..-36.45, lng -72.40..-72.05) (route_mission_service.dart:326-349)
- Cálculo topográfico computeElevationProfile: umbral de ruido > 2.0m / < -2.0m (route_mission_service.dart:364-368)
- Análisis detallado analyzeDetailedTopography: muestreo ~50 puntos (timeout 7s), pendiente = (deltaH / distMeters) * 100.0 para distMeters > 5.0m con clamp(-18.0, 18.0), umbral desnivel > 1.5m / < -1.5m; categorías: steepClimb > 3.5%, moderateClimb 1.5%..3.5%, flat -1.5%..1.5%, descent < -1.5%; rampa crítica si rampLen >= 0.4km y elevationGain >= 12.0m (route_mission_service.dart:409-564)
- fetchDemElevationProfile: muestreo ~40-45 puntos (timeout 6s), umbral desnivel > 3.0m / < -3.0m (route_mission_service.dart:591-630)

### Lote 20 (2 archivos, 1263L): admin_repository.dart y fleet_chat_screen.dart
- applyRecurringExpenses: asigna fecha fija día 15 del mes (DateTime(month.year, month.month, 15)) y idJornada: 'GASTO_FIJO' (admin_repository.dart:182,193)
- saveCotizacion: formato correlativo 'COT-$year-${newSeq.toString().padLeft(3, '0')}' en transacción usando contadores/cotizaciones_${idEmpresa}_$year (admin_repository.dart:562,579)
- convertIncidenciaToExpense: crea gasto tipo 'Mantención', idJornada: 'ReporteAdmin', isExento: false, estado incidencia -> 'Solucionado' (admin_repository.dart:425-439)
- getTripsForViatico: rango de fechas con margen +-1 día (start.subtract(1d) .. end.add(1d)) (admin_repository.dart:253-254)
- FleetChatScreen: duración mínima de audio PTT >= 1 segundo para enviar (fleet_chat_screen.dart:518)
- FleetChatScreen: etiqueta de audio hardcodeada '16kbps Opus' (fleet_chat_screen.dart:479)

### Lote 21 (2 archivos, 1183L)
- Rango de fecha retroactiva: hasta 30 días hacia atrás desde DateTime.now() (retro_trip_form_screen.dart:71-72).
- Valores por defecto de TripModel retroactivo: id 'RETRO-${DateTime.now().millisecondsSinceEpoch}', idJornada 'RETROACTIVO', cargoType 'completo', status 'Finalizado', billingType '_isZiyu ? OS : OT', comments 'Registro retroactivo' (retro_trip_form_screen.dart:98-119).
- Parseo de valor monetario: double.tryParse(_valueCtrl.text.replaceAll('.', '')) ?? 0.0 con formateador de miles con puntos (_ThousandsSeparatorFormatter) (retro_trip_form_screen.dart:96,568-588).
- Mandante fijado por defecto en sugerencias: 'MEDLOG TRUCK' cuando alwaysPinMedlog == true (retro_trip_form_screen.dart:404-413).
- Validación de contenedor ISO 6346: longitud 11 caracteres alfanuméricos sin guión, validado y formateado vía ContainerValidator (retro_trip_form_screen.dart:44-49,500-564).
- Alertas de documentación (driver_profile_screen.dart:297-315): vencida si date.difference(DateTime.now()).inDays < 0; por vencer si diff <= 30 días.
- Road Master Score hardcodeado (driver_profile_screen.dart:445-448): totalScore = 94 / 100 (hitosScore = 38/40, combustibleScore = 28/30, jornadaScore = 28/30).

### Lote 22 (2 archivos, 1127L)
- analytics_view.dart:501-502: `totalCosts = route.totalFuelCost + route.totalTolls + route.totalViaticos + route.totalPersonal + route.totalMaintenance`; `cpk = route.totalKm > 0 ? totalCosts / route.totalKm : 0.0` (Costo por KM).
- analytics_view.dart:271: `horizontalInterval: 500000` en `FlGridData`; eje Y formateado en millones `(val/1000000).toStringAsFixed(1)M` (L293).
- analytics_view.dart:337: Paleta de 5 colores para gráfico de gastos (`[Colors.white, Colors.orange, Colors.blue, Colors.green, Colors.purple]`).
- register_profile_screen.dart:171,173: `maxWidth: 420` para el formulario; `AnimatedSwitcher` con `Duration(milliseconds: 300)`.
- register_profile_screen.dart:383: Hint de código de invitación `'BIT-XXXX'`.

### Lote 23 (3 archivos, 1562L)
- ziyu_service.dart:117: regex OS/OT PDF r'\b(O[ST][0-9]{5,8})\b'.
- ziyu_service.dart:127: regex Contenedor PDF r'\b([A-Z]{4}[0-9]{7})\b'.
- ziyu_service.dart:133: regex Valor monetario chileno PDF r'\b(\d{1,3}(?:\.\d{3})*(?:,\d{2})?)\b' (limpieza '.' -> '' y ',' -> '.').
- ziyu_service.dart:190: regex Guía fallback PDF r'\b([0-9]{6,10})\b'.
- ziyu_service.dart:275,293: búsqueda de encabezados en primeras 100 filas, score mínimo >= 3 keywords; celdas > 40 chars ignoradas.
- ziyu_service.dart:333-338: keywords <= 3 chars ('os', 'bl', 'to', 'rut', 'dia') requieren match de palabra completa (\b).
- ziyu_service.dart:405-407: filtro de viajes OS conciliables: billingType == 'OS' && status != 'En Ruta' && value > 0 && !isRetiroAnticipado && tipoMovimiento != 'retiro_anticipado' && tipoMovimiento != 'traslado_mantenimiento'.
- ziyu_service.dart:467: diferencia = match.value - ziyuVal.
- driver_efficiency_matrix_view.dart:24: breakpoint móvil width < 900.
- driver_efficiency_matrix_view.dart:135,500: alerta de vencimiento de licencia/cédula <= 30 días.
- driver_efficiency_matrix_view.dart:280,411: Road Master Score hardcodeado/demostrativo: 90 + (c.nombre.hashCode % 9).
- viaticos_admin_view.dart:206,217,222,386-387,396-397: cálculo de viático: si totalKm >= config.umbralKilometrosViatico usa chofer.montoViaticoLargo ?? 10000, sino chofer.montoViaticoLocal ?? 6500. Modo POR_JORNADA paga máximo 1 viático por día (priorizando largo si algún viaje del día supera el umbral).

### Lote 24 (3 archivos, 1449L)
- flota_admin_view.dart:183-197: valores por defecto en diálogo de vehículo: capacidadEstanqueLitros=600.0, rendimientoKmPorLitro=2.5, consumoRalentiLitrosHora=2.0, maxMinutosRalentiAlerta=20, identificadorAuxiliar='THERMO-01', capacidadEstanqueAuxiliar=200.0, consumoHoraAuxiliar=2.5, categoriaPeaje='camion_mas_2_ejes', tipoEquipoAuxiliar='Thermo King / Reefer'
- flota_admin_view.dart:375: ID generado como 'VEH-${DateTime.now().millisecondsSinceEpoch}'
- admin_provider.dart:362-364: expenseBreakdownProvider calcula monto neto dividiendo por 1.19 (IVA 19%) excepto cuando e.type.toLowerCase() == 'peaje'
- admin_provider.dart:415: trendProvider consulta los últimos 6 meses (i = 5 hasta 0)
- trip_repository.dart:268: watchRecentExpenses limita a 50 documentos ordenados por date descendente
- trip_repository.dart:141: getFrequentDestinations excluye 'Retiro Anticipado' y 'Mantenimiento' y retorna top 5 por defecto

### Lote 25
- ID de Liquidación: DateTime.now().millisecondsSinceEpoch.toString() (ziyu_conciliation_view.dart:152)
- montoTotal de liquidación: suma de r.ziyuRecord?.value ?? 0.0 sobre matchedResults (ziyu_conciliation_view.dart:140)
- Estado inicial de liquidación: 'pendiente' (ziyu_conciliation_view.dart:158)
- Referencia por defecto si no hay osNumber: 'Liq ${DateTime.now().day}/${DateTime.now().month}' (ziyu_conciliation_view.dart:93)
- Selector de meses en LiquidacionesAdminView: últimos 6 meses desde DateTime.now() (liquidaciones_admin_view.dart:210-211)
- Formato moneda: NumberFormat.currency(locale: 'es_CL', symbol: '$', decimalDigits: 0) (liquidaciones_admin_view.dart:259,371)
- ID de Viático: 'VIAT-${DateTime.now().millisecondsSinceEpoch}' (viaticos_request_screen.dart:75)
- Estado inicial de Viático: 'pendiente' (viaticos_request_screen.dart:80)
- Validación de superposición de fechas de viáticos: sA.isBefore(eB.add(Duration(days: 1))) && eA.isAfter(sB.subtract(Duration(days: 1))) usando DateUtils.dateOnly (viaticos_request_screen.dart:50-55)
- Cálculo de días seleccionados: _selectedRange!.duration.inDays + 1 (viaticos_request_screen.dart:185)

### Lote 26
- ViaticosCalendarPickerModal: grid de 7 columnas, offset (weekday - 1) para iniciar en Lunes; bloquea selección de fechas futuras (> today) y rangos que contengan días con viático existente; navegación hacia adelante limitada hasta DateTime(now.year, now.month + 1, 1).
- RouteElevationProfileWidget: pendiente crítica > 3.5% (rojo) y bajada < -3.5% (naranja); rango de altitud efectivo con padding del 8% arriba/abajo y mínimo de 15.0m (math.max(15.0, maxAlt - minAlt)); altura fija de gráfico 130px.
- GpsHarvestService: _speedingThreshold = 90.0 km/h; _minStopDuration = 2 min; _rawSampleEvery = 3 ciclos; umbral movimiento/ralentí speed > 2 / speed < 2; cooldown de alerta speeding = 5 min; cierre de viaje requiere positions.length >= 3 y durMin >= 3 min; radio terrestre Haversine r = 6371.0 km.
- GpsHarvestService.getFleetStats: límite 100 documentos en trip_summaries y 500 en events (type == 'speeding').

### Lote 27 (4 archivos, 1535L)
- functions/index.js:58 - Cron syncLiotGps cada 2 minutos ('every 2 minutes')
- functions/index.js:136-138,165-167 - Canal Android FCM 'bitacora_binaural_v4', sonido 'bitacora_alert', priority 'max'
- functions/index.js:218 - Umbral de alerta mantenimiento preventivo: (nextOilChangeKm - newOdometer) <= 500 km
- functions/index.js:250,256 - Cron dailyDocumentCheck a las 08:00; umbral de alerta documentación por vencer: +7 días
- functions/index.js:354-358 - Valores por defecto publishAppUpdate: buildNumber=11, versionName='1.1.0', mandatory=false
- lib/features/trips/domain/services/route_tariff_baseline_service.dart:171 - Redondeo de tarifas a la centena más cercana: (val / 100.0).roundToDouble() * 100.0
- lib/features/trips/domain/services/route_tariff_baseline_service.dart:188-195 - Regla Maestra de Moda Ponderada: usa moda si maxFreq >= 3 o (total >= 4 && maxFreq / total >= 0.4); si no, usa mediana
- lib/features/trips/domain/services/route_tariff_baseline_service.dart:228,234,271,285 - evaluateTariff: enteredValue < 10000 -> 'incompleto'; tolerancePercent por defecto 25.0%; desviación > 50.0% -> 'fraude_sospecha' (critical); entre 25% y 50% -> 'advertencia' (warning)
- lib/features/trips/domain/services/route_tariff_baseline_service.dart:325-350 - Jerarquía de búsqueda en getSuggestedStats: 1) MANDANTE+CLIENTE+DESTINO, 2) CLIENTE+DESTINO, 3) O ➔ C ➔ D, 4) CLIENTE exacto, 5) CLIENTE parcial (c.length >= 4)

### Lote 28 (4 archivos, 1415L)
- Canales Android FCM/Local: 'bitacora_binaural_v4', 'bitacora_binaural_v3' (legacy), 'bitacora_general_alerts' (fallback); sonido 'bitacora_alert'; vibración [0, 250, 150, 400] (push_notification_service.dart:76,90,291,299,326)
- Días detenidos hábiles (Lun-Sáb, sin feriados): ChileanHolidays.getDiasDetenidosHabiles(fechaIngreso, fechaSalida) (create_incidencia_dialog.dart:32)
- Canal telemetría Android: 'telemetry_service', foregroundServiceNotificationId: 888 (location_service.dart:77,97)
- GPS stream: LocationAccuracy.high, distanceFilter: 30m, enableWakeLock: true (location_service.dart:156-161)
- Cálculo de distancia: traveled en metros via latlong2 Distance; filtro 5 < traveled < 50000 m; acumula traveled / 1000 en km (location_service.dart:176-184)
- Batch Firestore GPS: commit cada >= 25 puntos; buffer offline máximo 2500 puntos (si excede, removeRange(0, 100)) (location_service.dart:201,223-224)

### Lote 29 (5 archivos, 1563L)
- fuel_performance_service.dart:106-107,195,201: defaults capacidad camión 600.0 L, rendimiento 2.5 km/L, auxiliar 200.0 L, consumo auxiliar 2.5 L/h
- fuel_performance_service.dart:21-38,164: conversiones L/100km <-> km/L (100.0 / x); factorCorreccion = (ultimoRendimientoReal / compKmPorLitro) a 3 decimales
- fuel_performance_service.dart:178-191: rendimientoEfectivo = ultimoRendimientoReal * 0.7 + expectedRendimiento * 0.3; litrosActuales = (capacity + cargasParcialesLitros - kmRecorridos / rendimientoEfectivo) clamped [0, capacity]; fuelValue = litrosActuales * currentDieselNeto
- fuel_performance_service.dart:223: alerta combustible auxiliar si auxCur <= auxCap * 0.2 (20%)
- admin_dashboard_screen.dart:54,59: ventana de documentos por vencer = 30 días; breakpoint móvil < 900 px
- route_comparator_widget.dart:235,292: umbral subida fuerte >3.5% y referencia camión cargado 45 ton en textos

### Lote 30 (6 archivos, 1597L)
- CotizacionModel (cotizacion_model.dart:90-92, 126-127): diasViaje=1, margenObjetivo=25.0, estado='borrador', idaYVuelta=false, eliminada=false.
- TripModel (trip_model.dart:126, 181, 188): tipoMovimiento='operativo', billingType='OS', cargoType fallback 'completo' si containerNumber!=null sino 'suelta'.
- PuntoInfraestructuraModel (infraestructura_vial_model.dart:105, 110-111, 130): radioMetros=100.0, sentido='Bidireccional', subtipo='General', origenDato='maestro'.
- VehicleModel (vehicle_model.dart:40, 60-75, 252, 260): rendimientoKmPorLitro=2.5, categoriaPeaje='camion_mas_2_ejes', capacidadEstanqueLitros=600.0, litrosReservaAlerta=120.0, consumoHoraAuxiliar=2.5, consumoRalentiLitrosHora=2.0, maxMinutosRalentiAlerta=20, costoMantenimientoPorKm fallback global comentado $49/km, hasExpiringDocs umbral 7 días, esCritico si remainingDays <= 1.
- CompanyConfigModel (company_config_model.dart:39-55): sueldoMinimo=539000, umbralKilometrosViatico=100, tasaMutual=0.90, tasaSIS=1.49, porcentajeComision=0.0, tipoViatico='POR_JORNADA', valorUTM=65000, precioDieselNeto=800, diasLaboralesMes=22, margenObjetivoCotizacion=25.0, tasaPPM=1.5, porcentajeRecuperacionIepd=80.0.

### Lote 31 (7 archivos, 1529L)
- IVA 19%: `iva = tarifaNeta * 0.19; total = tarifaNeta + iva` (`cotizacion_pdf_service.dart:44-45`). Validez cotización: 15 días (`cotizacion_pdf_service.dart:185`).
- Viáticos por defecto en `PdfService`: `montoViaticoLargo ?? 10000`, `montoViaticoLocal ?? 6500`, umbral `config.umbralKilometrosViatico`, regla `POR_JORNADA` (1 viático por día, `pdf_service.dart:29-31,134-144`).
- Haversine (`earthRadius = 6371000` m) y proyección equirectangular local (`metersPerDegLat = 111320.0`, `metersPerDegLng = 111320.0 * cosLat`) (`road_infrastructure_detector.dart:12,41-42`).
- Radios de detección: `SilentNavigatorService` catálogo puertos <= `450.0` m (`silent_navigator_service.dart:104`); `RoadInfrastructureDetector.getOptimalDetectionRadius`: lateral/ramal/salida = `24.0` m, troncal/tag/portico = `radioConfigurado` si está en `[35.0, 65.0]` sino `50.0`, otros = `radioConfigurado > 0 ? radioConfigurado : 50.0` (`road_infrastructure_detector.dart:93-105`).
- Conos de rumbo (`matchesDirection`, tolerancia ±75° respecto al eje): Norte-Sur `[105°, 255°]`, Sur-Norte `>= 285° || <= 75°`, Oriente-Poniente `[195°, 345°]`, Poniente-Oriente `[15°, 165°]` (`road_infrastructure_detector.dart:125-153`).
- Ventanas/cooldowns de monitoreo en `route_live_monitor.dart`: Romana `100 <= distM <= 2500` m (cooldown 20 min); Restricción horaria `distM <= 4000` m con `marginMinutes: 25` (cooldown 30 min); Peaje `distM <= detectionRadius` (cooldown 15 min); `activeAlerts` truncado a 5 (`take(5)`). En `silent_navigator_service.dart`: cooldown notificación tramo 25 min (`inMinutes < 25`).
- Valores por defecto `CotizadorFormState`: `diasViaje = 1`, `idaYVuelta = false`, resto `0.0` / `''` / `null` (`cotizador_provider.dart:38-55`).

### Lote 32 (10 archivos, 1519L)
- ai_analytic_service.dart:43-48: Modelos Groq candidatos en orden: `[preferredModel, 'llama-3.1-8b-instant', 'llama-3.3-70b-versatile', 'openai/gpt-oss-120b']`; temperatura `0.7` en `analyzeRouteProfitability` (:133) y `0.3` en `askOperationalAssistant` (:181)
- ai_analytic_service.dart:109,153: CPK = `(totalFuelCost + totalTolls + totalPersonal + totalMaintenance) / totalKm` (0 si `totalKm <= 0`)
- tms_backbone.dart:148: Precio diésel neto por defecto = `800.0` CLP/L cuando no hay cargas ni `CompanyConfigModel`
- tms_backbone.dart:151-162: `_netPricePerLiter`: si `isExento` -> `amount / litros`; si `customIva > 0` -> `(amount - customIva).clamp(0.0, amount) / litros`; si no -> `(amount / 1.19) / litros` (IVA 19%)
- tms_backbone.dart:167-178: `resolveVehicleEfficiency`: prioriza `ultimoRendimientoReal > 0.5`, luego `rendimientoKmPorLitro > 0.5`, fallback `2.5` Km/L
- auth_repository.dart:164-171: Código de invitación `BIT-XXXX` (4 chars alfanuméricos `A-Z0-9` con `Random.secure()`); sufijo empresa también de 4 chars alfanuméricos
- glass_container.dart:31-45: `blur = 14.0`, `backgroundOpacity = 0.65` (`0.75` si `isActive`), `borderRadius = 20.0`, `borderWidth = 1.0`
- audio_voice_service.dart:39-44: Grabación `AudioEncoder.aacLc`, `bitRate: 16000` (16 kbps), `sampleRate: 16000`, `numChannels: 1`; duración mínima válida `>= 1` segundo (:70)
- user_model.dart:35-40: `isSuperAdmin` = `rol == 'SUPER_ADMIN'` o `(rol == 'ADMIN' && (email contiene 'inostroza' o 'heirlog' || idEmpresa == 'heirlog'))`

### Lote 33 (17 archivos, 1591L)
- FleetChatRepository:38: límite de 35 mensajes en watchMessages; audio PTT en Base64 directo en Firestore (comentario: 10s AAC 16kbps ~18KB -> ~24KB Base64, límite doc 1MB)
- ExpenseModel:106: isExento por defecto false, o true si type.toLowerCase() == 'peaje'
- ChileanHolidays:5-59,68-71: feriados oficiales Chile 2025-2027; día hábil transporte = Lunes a Sábado excluyendo Domingos y feriados
- ContainerValidator:9-14,66-80: ISO 6346 (11 chars, 4to char 'U', 6 dígitos serie, dígito verificador: sum(val * 2^i) % 11, si remainder == 10 entonces 0)
- FuzzySearchService:49-53,65: scoring +10 si empieza con token o ' $token', +token.length; retorna top 10 resultados
- DistanceService:15-32,56-78: _portAliases (San Antonio, Valparaíso, San Vicente, Coronel, Lirquén, Antofagasta); fallback a kmMinimo si no hay puerto específico
- ZiyuRecord:41-65: isSmartMatch compara normalizado, solo dígitos si length >= 5, elimina prefijos ^(GUIA|GUI|G|VIAJE|OS|OT|REF), o substring si length >= 5
- ShiftModel:17-19: deltaOdometer = (endOdometer != null && endOdometer! >= startOdometer) ? (endOdometer! - startOdometer) : 0

### Lote 34 (15 archivos, 560L)
- Locale de fechas: `es_CL` (`main.dart:17`). Título app: `HEIRLOG-TMS` (`main.dart:61`).
- `NumberUtils.formatCurrency`: redondea (`round()`) y formatea con separador de miles `.` (formato chileno), retorna `'0'` si es `null` (`number_utils.dart:21-33`).
- `NumberUtils.tryParseDouble`: reemplaza `,` por `.` y elimina todo carácter fuera de `[0-9.]` (`number_utils.dart:9-14`).
- `RecurringExpenseModel`: `tipo` por defecto `'Otros'`, `monto` por defecto `0.0`, `activo` por defecto `true` (`recurring_expense_model.dart:24-27`).
- `ViaticoModel`: `estado` por defecto `'pendiente'` (`viatico_model.dart:49`).
- `InvitationModel`: `usada` por defecto `false` (`invitation_model.dart:33`).
