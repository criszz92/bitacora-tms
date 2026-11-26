# Mapa Maestro de Funciones, Modelos y Colecciones — Bitácora TMS

> **Generado automáticamente por análisis estático** sobre **102 archivos** (**42,114 líneas**).

---

## 1. Archivos Huérfanos Detectados (0 imports en todo el proyecto)

- `lib/features/admin/presentation/widgets/operational_chat_widget.dart` (155 líneas) — Clases: OperationalChatWidget:L5, _OperationalChatWidgetState:L12

---
## 2. Mapa de Colecciones Firestore (Quién lee/escribe cada colección)

- **`app_version`** (1 archivos): `functions/index.js`
- **`auditoria`** (1 archivos): `lib/features/trips/data/repositories/trip_repository.dart`
- **`config_empresas`** (1 archivos): `lib/features/admin/domain/services/modogps_service.dart`
- **`configuraciones_empresa`** (1 archivos): `lib/features/admin/data/repositories/admin_repository.dart`
- **`contadores`** (1 archivos): `lib/features/admin/data/repositories/admin_repository.dart`
- **`cotizaciones`** (1 archivos): `lib/features/admin/data/repositories/admin_repository.dart`
- **`empresas`** (2 archivos): `lib/features/auth/data/repositories/auth_repository.dart`, `lib/features/chat/data/repositories/fleet_chat_repository.dart`
- **`events`** (1 archivos): `lib/features/admin/domain/services/gps_harvest_service.dart`
- **`gastos`** (3 archivos): `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/driver/presentation/screens/driver_dashboard_screen.dart`, `lib/features/trips/data/repositories/trip_repository.dart`
- **`gps_monitor`** (1 archivos): `functions/index.js`
- **`incidencias`** (2 archivos): `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/trips/data/repositories/trip_repository.dart`
- **`invitaciones`** (1 archivos): `lib/features/auth/data/repositories/auth_repository.dart`
- **`jornadas`** (2 archivos): `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/trips/data/repositories/trip_repository.dart`
- **`liquidaciones`** (1 archivos): `lib/features/admin/data/repositories/admin_repository.dart`
- **`mensajes`** (1 archivos): `lib/features/chat/data/repositories/fleet_chat_repository.dart`
- **`puntos`** (1 archivos): `lib/core/services/location_service.dart`
- **`raw_positions`** (1 archivos): `lib/features/admin/domain/services/gps_harvest_service.dart`
- **`secrets`** (2 archivos): `lib/features/admin/domain/services/ai_analytic_service.dart`, `lib/features/admin/domain/services/modogps_service.dart`
- **`service_requests`** (3 archivos): `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/admin/presentation/widgets/service_requests_inbox_view.dart`, `lib/features/trips/data/repositories/trip_repository.dart`
- **`telemetry`** (1 archivos): `lib/features/admin/domain/services/gps_harvest_service.dart`
- **`trip_summaries`** (1 archivos): `lib/features/admin/domain/services/gps_harvest_service.dart`
- **`usuarios`** (5 archivos): `functions/index.js`, `lib/core/services/push_notification_service.dart`, `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/auth/data/repositories/auth_repository.dart`, `lib/features/auth/presentation/providers/auth_provider.dart`
- **`vehiculos`** (3 archivos): `functions/index.js`, `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/trips/data/repositories/trip_repository.dart`
- **`viajes`** (4 archivos): `lib/core/services/location_service.dart`, `lib/core/services/silent_navigator_service.dart`, `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/trips/data/repositories/trip_repository.dart`
- **`viaticos`** (2 archivos): `lib/features/admin/data/repositories/admin_repository.dart`, `lib/features/trips/data/repositories/trip_repository.dart`

---
## 3. Inventario Completo por Archivo (Clases, Providers y Líneas)

### `lib/features/driver/presentation/screens/driver_dashboard_screen.dart` (4391 L | usado por 1 archivos)
- **Clases:** DriverDashboardScreen:L35, _DetectedTollPass:L2955, _EndTripDialog:L2985, _EndTripDialogState:L2998, _EndShiftDialog:L3980, _EndShiftDialogState:L3993
- **Firestore:** gastos
### `lib/features/admin/presentation/widgets/control_tower_view.dart` (3448 L | usado por 1 archivos)
- **Clases:** RefreshTriggerNotifier:L20, _UnitMotionState:L48, ControlTowerView:L62, _ControlTowerViewState:L69
- **Providers/Exports:** gpsHarvestServiceProvider:L18, refreshTriggerProvider:L27, fleetStreamProvider:L29
### `lib/features/admin/presentation/widgets/kpi_dashboard_view.dart` (1842 L | usado por 1 archivos)
- **Clases:** KpiDashboardView:L16
### `lib/features/admin/domain/services/modogps_service.dart` (1233 L | usado por 7 archivos)
- **Clases:** GpsGeofence:L34, GpsUnit:L94, GpsGeofenceStay:L136, GpsHistoricalPoint:L151, GpsStop:L167, GpsJourneyStart:L185, GpsJourneyEnd:L217, GpsTripLeg:L249, GpsHistoricalTrip:L273, ModoGpsService:L311
- **Providers/Exports:** modoGpsServiceProvider:L10, singleVehicleGpsProvider:L13
- **Firestore:** config_empresas, secrets
### `lib/features/trips/presentation/screens/trip_form_screen.dart` (1173 L | usado por 1 archivos)
- **Clases:** TripFormScreen:L31, _TripFormScreenState:L44, _ThousandsSeparatorFormatter:L1139, _UpperCaseFormatter:L1168
### `lib/features/admin/presentation/widgets/config_admin_view.dart` (1100 L | usado por 1 archivos)
- **Clases:** ConfigAdminView:L15, _ConfigAdminViewState:L22
### `lib/features/admin/presentation/screens/cotizador_screen.dart` (1074 L | usado por 1 archivos)
- **Clases:** CotizadorScreen:L14, _CotizadorScreenState:L21
### `lib/features/admin/presentation/widgets/fuel_performance_view.dart` (1031 L | usado por 1 archivos)
- **Clases:** FuelPerformanceView:L10, _FuelPerformanceViewState:L17
### `lib/features/driver/presentation/screens/monthly_summary_screen.dart` (982 L | usado por 1 archivos)
- **Clases:** MonthlySummaryScreen:L14, _MonthlySummaryScreenState:L23
### `lib/features/admin/presentation/widgets/monthly_reports_view.dart` (840 L | usado por 1 archivos)
- **Clases:** MonthlyReportsView:L17, _MonthlyReportsViewState:L24
### `lib/features/admin/presentation/widgets/mantenimiento_admin_view.dart` (773 L | usado por 1 archivos)
- **Clases:** MantenimientoAdminView:L9, _FleetStatusTab:L94, _IncidenciasTab:L599
### `lib/features/admin/presentation/widgets/csv_importer_dialog.dart` (756 L | usado por 1 archivos)
- **Clases:** CsvImporterDialog:L14, _CsvImporterDialogState:L21
### `lib/core/utils/chilean_financial_calculator.dart` (741 L | usado por 4 archivos)
- **Clases:** ChileanFinancialCalculator:L9
### `lib/features/admin/presentation/widgets/conductores_view.dart` (732 L | usado por 1 archivos)
- **Clases:** ConductoresView:L10, _ConductoresViewState:L17, _DriverEditForm:L415, _DriverEditFormState:L426
### `lib/features/trips/presentation/screens/expense_form_screen.dart` (723 L | usado por 1 archivos)
- **Clases:** ExpenseFormScreen:L11, _ExpenseFormScreenState:L19
### `lib/features/trips/domain/services/route_mission_service.dart` (646 L | usado por 6 archivos)
- **Clases:** DeliveryDestination:L7, ElevationProfilePoint:L26, CriticalGradientSegment:L41, RouteTopographyAnalysis:L62, RouteMissionService:L110
### `lib/features/admin/data/repositories/admin_repository.dart` (633 L | usado por 1 archivos)
- **Clases:** AdminRepository:L16
- **Firestore:** configuraciones_empresa, contadores, cotizaciones, gastos, incidencias, jornadas, liquidaciones, service_requests, usuarios, vehiculos, viajes, viaticos
### `lib/features/chat/presentation/screens/fleet_chat_screen.dart` (630 L | usado por 1 archivos)
- **Clases:** FleetChatScreen:L13, _FleetChatScreenState:L20, BoxInsets:L625
### `lib/features/trips/presentation/screens/retro_trip_form_screen.dart` (595 L | usado por 1 archivos)
- **Clases:** RetroTripFormScreen:L15, _RetroTripFormScreenState:L22, _ThousandsSeparatorFormatter:L568, _UpperCaseFormatter:L590
### `lib/features/driver/presentation/screens/driver_profile_screen.dart` (588 L | usado por 1 archivos)
- **Clases:** DriverProfileScreen:L12, _DriverProfileScreenState:L19, _DocStatus:L575
### `lib/features/admin/presentation/widgets/analytics_view.dart` (576 L | usado por 1 archivos)
- **Clases:** AnalyticsView:L8
### `lib/features/auth/presentation/screens/register_profile_screen.dart` (551 L | usado por 1 archivos)
- **Clases:** RegisterProfileScreen:L13, _RegisterProfileScreenState:L24
### `lib/features/admin/domain/services/ziyu_service.dart` (525 L | usado por 1 archivos)
- **Clases:** ZiyuService:L11
### `lib/features/admin/presentation/widgets/driver_efficiency_matrix_view.dart` (521 L | usado por 1 archivos)
- **Clases:** DriverEfficiencyMatrixView:L9, _DriverEfficiencyMatrixViewState:L17
### `lib/features/admin/presentation/widgets/viaticos_admin_view.dart` (516 L | usado por 1 archivos)
- **Clases:** ViaticosAdminView:L12
### `lib/features/admin/presentation/widgets/flota_admin_view.dart` (489 L | usado por 1 archivos)
- **Clases:** FlotaAdminView:L10
### `lib/features/admin/presentation/providers/admin_provider.dart` (482 L | usado por 24 archivos)
- **Clases:** AIAnalysisNotifier:L29, ChatMessage:L50, OperationalChatNotifier:L58, SelectedMonthNotifier:L114, SelectedVehicleNotifier:L127, KpiData:L212, ZiyuConciliationState:L454, ZiyuConciliationNotifier:L472
- **Providers/Exports:** adminRepositoryProvider:L21, aiAnalyticServiceProvider:L25, aiAnalysisResultProvider:L46, operationalChatProvider:L88, taxIndicatorServiceProvider:L90, utmSyncProvider:L94, selectedMonthProvider:L123, selectedVehicleProvider:L133, monthlyTripsProvider:L137, monthlyExpensesProvider:L144, allTripsProvider:L151, routeTariffBaselineProvider:L158, allExpensesProvider:L163, choferesProvider:L169, adminVehiclesProvider:L175, adminViaticosProvider:L181, adminIncidenciasProvider:L187, companyConfigProvider:L195, gastosFijosAplicadosProvider:L202, financialSummaryProvider:L246, kpiProvider:L344, expenseBreakdownProvider:L356, topClientsProvider:L372, topRoutesProvider:L380, routeProfitabilityProvider:L388, trendProvider:L405, liquidacionesProvider:L444, ziyuConciliationProvider:L482
### `lib/features/admin/presentation/widgets/ziyu_conciliation_view.dart` (478 L | usado por 1 archivos)
- **Clases:** ZiyuConciliationView:L11, _ZiyuConciliationViewState:L18
### `lib/features/trips/data/repositories/trip_repository.dart` (478 L | usado por 1 archivos)
- **Clases:** TripRepository:L16
- **Firestore:** auditoria, gastos, incidencias, jornadas, service_requests, vehiculos, viajes, viaticos
### `lib/features/admin/presentation/widgets/liquidaciones_admin_view.dart` (477 L | usado por 1 archivos)
- **Clases:** LiquidacionesAdminView:L7, _LiquidacionesAdminViewState:L14
### `lib/features/driver/presentation/screens/viaticos_request_screen.dart` (465 L | usado por 1 archivos)
- **Clases:** ViaticosRequestScreen:L12, _ViaticosRequestScreenState:L20
### `lib/features/driver/presentation/widgets/viaticos_calendar_picker_modal.dart` (461 L | usado por 1 archivos)
- **Clases:** ViaticosCalendarPickerModal:L11, _ViaticosCalendarPickerModalState:L41, _WeekDayLabel:L416, _LegendIndicator:L433
### `lib/features/admin/presentation/widgets/route_elevation_profile_widget.dart` (441 L | usado por 2 archivos)
- **Clases:** RouteElevationProfileWidget:L7, _RouteElevationProfileWidgetState:L25, _ElevationCurvePainter:L325
### `lib/features/admin/domain/services/gps_harvest_service.dart` (414 L | usado por 1 archivos)
- **Clases:** GpsEvent:L10, TripSummary:L44, _UnitState:L109, GpsHarvestService:L166
- **Firestore:** events, raw_positions, telemetry, trip_summaries
### `lib/features/admin/presentation/widgets/monthly_report_exporter.dart` (401 L | usado por 1 archivos)
- **Clases:** MonthlyReportExporter:L16
### `lib/core/utils/pdf_generator.dart` (385 L | usado por 2 archivos)
- **Clases:** PdfGenerator:L8
### `functions/index.js` (377 L | usado por 0 archivos)
- **Providers/Exports:** exports.analyzeProfitability:L10, exports.syncLiotGps:L58, exports.onTripFinished:L185, exports.onIncidenceCreated:L230, exports.dailyDocumentCheck:L250, exports.onServiceRequestUpdated:L299, exports.onViaticoUpdated:L322, exports.publishAppUpdate:L352
- **Firestore:** app_version, gps_monitor, usuarios, vehiculos
### `lib/features/trips/domain/services/route_tariff_baseline_service.dart` (372 L | usado por 3 archivos)
- **Clases:** RouteTariffStats:L7, RouteTariffAnomaly:L32, RouteTariffBaselineService:L99
### `lib/core/services/push_notification_service.dart` (367 L | usado por 6 archivos)
- **Clases:** PushTestResult:L36, PushNotificationService:L50
- **Firestore:** usuarios
### `lib/features/admin/presentation/widgets/service_requests_inbox_view.dart` (355 L | usado por 1 archivos)
- **Clases:** ServiceRequestsInboxView:L22
- **Providers/Exports:** serviceRequestsProvider:L11
- **Firestore:** service_requests
### `lib/features/admin/presentation/widgets/create_incidencia_dialog.dart` (349 L | usado por 2 archivos)
### `lib/core/services/location_service.dart` (344 L | usado por 3 archivos)
- **Clases:** LocationService:L21
- **Firestore:** puntos, viajes
### `lib/features/admin/presentation/widgets/route_comparator_widget.dart` (332 L | usado por 1 archivos)
- **Clases:** ComparedRouteData:L6, RouteComparatorWidget:L34
### `lib/features/trips/presentation/screens/shift_start_screen.dart` (321 L | usado por 1 archivos)
- **Clases:** ShiftStartScreen:L10, _ShiftStartScreenState:L17
### `lib/features/admin/presentation/widgets/fleet_announcements_admin_view.dart` (307 L | usado por 1 archivos)
- **Clases:** FleetAnnouncementsAdminView:L9, _FleetAnnouncementsAdminViewState:L16
### `lib/features/admin/domain/services/fuel_performance_service.dart` (306 L | usado por 1 archivos)
- **Clases:** TankState:L5, FleetFuelSummary:L74, FuelPerformanceService:L98
### `lib/features/admin/presentation/screens/admin_dashboard_screen.dart` (297 L | usado por 1 archivos)
- **Clases:** AdminDashboardScreen:L24, _AdminDashboardScreenState:L31, _FleetDocumentAlertBanner:L231
### `lib/features/admin/domain/models/cotizacion_model.dart` (280 L | usado por 4 archivos)
- **Clases:** CotizacionModel:L3
### `lib/features/trips/domain/models/trip_model.dart` (276 L | usado por 19 archivos)
- **Clases:** TripModel:L1
### `lib/core/widgets/app_update_dialog.dart` (275 L | usado por 1 archivos)
- **Clases:** AppUpdateDialog:L7, _AppUpdateDialogState:L27
### `lib/features/admin/domain/models/infraestructura_vial_model.dart` (265 L | usado por 5 archivos)
- **Clases:** PuntoInfraestructuraModel:L58
### `lib/features/trips/domain/models/vehicle_model.dart` (261 L | usado por 20 archivos)
- **Clases:** VehicleModel:L1
### `lib/features/admin/domain/models/company_config_model.dart` (240 L | usado por 13 archivos)
- **Clases:** CompanyConfigModel:L3
### `lib/features/admin/presentation/widgets/remuneraciones_view.dart` (235 L | usado por 1 archivos)
- **Clases:** RemuneracionesView:L10, _RemuneracionesViewState:L17
### `lib/core/services/silent_navigator_service.dart` (234 L | usado por 1 archivos)
- **Clases:** PendingArrivalEvent:L13, PendingArrivalNotifier:L32, SilentNavigatorService:L50
- **Providers/Exports:** pendingArrivalProvider:L45, silentNavigatorServiceProvider:L212, silentNavigatorObserverProvider:L217
- **Firestore:** viajes
### `lib/core/utils/route_live_monitor.dart` (230 L | usado por 1 archivos)
- **Clases:** RouteAlert:L11, RouteMonitorState:L32
- **Providers/Exports:** routeMonitorStreamProvider:L61
### `lib/features/trips/domain/services/pdf_service.dart` (213 L | usado por 2 archivos)
- **Clases:** PdfService:L9
### `lib/core/utils/road_infrastructure_detector.dart` (208 L | usado por 2 archivos)
- **Clases:** RoadInfrastructureDetector:L9
### `lib/features/admin/domain/services/cotizacion_pdf_service.dart` (206 L | usado por 1 archivos)
- **Clases:** CotizacionPdfService:L11
### `lib/features/admin/presentation/providers/cotizador_provider.dart` (203 L | usado por 1 archivos)
- **Clases:** CotizadorFormState:L17, CotizadorFormNotifier:L98
- **Providers/Exports:** cotizacionesProvider:L10, cotizadorFormProvider:L171, cotizadorResultProvider:L176
### `lib/features/admin/domain/services/ai_analytic_service.dart` (187 L | usado por 1 archivos)
- **Clases:** _AiConfig:L6, AIAnalyticService:L13
- **Firestore:** secrets
### `lib/core/utils/tms_backbone.dart` (180 L | usado por 4 archivos)
- **Clases:** TmsBackbone:L11
### `lib/features/auth/data/repositories/auth_repository.dart` (173 L | usado por 1 archivos)
- **Clases:** AuthRepository:L8
- **Firestore:** empresas, invitaciones, usuarios
### `lib/core/widgets/glass_container.dart` (157 L | usado por 3 archivos)
- **Clases:** GlassContainer:L8, _GlassBorderPainter:L127
### `lib/features/admin/presentation/widgets/operational_chat_widget.dart` (155 L | usado por 0 archivos)
- **Clases:** OperationalChatWidget:L5, _OperationalChatWidgetState:L12
### `lib/core/router/app_router.dart` (143 L | usado por 1 archivos)
- **Providers/Exports:** appRouterProvider:L19
### `lib/core/services/app_update_service.dart` (143 L | usado por 3 archivos)
- **Clases:** AppUpdateInfo:L9, UpdateProgress:L26, AppUpdateService:L39
### `lib/features/chat/domain/services/audio_voice_service.dart` (132 L | usado por 1 archivos)
- **Clases:** AudioVoiceService:L13
- **Providers/Exports:** audioVoiceServiceProvider:L9
### `lib/features/auth/domain/models/user_model.dart` (127 L | usado por 18 archivos)
- **Clases:** UserModel:L3
### `lib/features/auth/presentation/screens/login_screen.dart` (122 L | usado por 1 archivos)
- **Clases:** LoginScreen:L5, _LoginScreenState:L12
### `lib/features/chat/data/repositories/fleet_chat_repository.dart` (121 L | usado por 2 archivos)
- **Clases:** FleetChatRepository:L19
- **Providers/Exports:** fleetChatRepositoryProvider:L7, fleetMessagesStreamProvider:L14
- **Firestore:** empresas, mensajes
### `lib/features/admin/domain/models/incidencia_model.dart` (110 L | usado por 8 archivos)
- **Clases:** IncidenciaModel:L1
### `lib/features/trips/domain/models/expense_model.dart` (110 L | usado por 15 archivos)
- **Clases:** ExpenseModel:L1
### `lib/core/theme/app_theme.dart` (108 L | usado por 15 archivos)
- **Clases:** AppColors:L4, AppTheme:L30
### `lib/features/admin/domain/models/ziyu_models.dart` (104 L | usado por 3 archivos)
- **Clases:** ZiyuRecord:L3, ReconciliationResult:L76
### `lib/core/utils/chilean_holidays.dart` (103 L | usado por 3 archivos)
- **Clases:** ChileanHolidays:L3
### `lib/features/trips/domain/services/container_validator.dart` (96 L | usado por 2 archivos)
- **Clases:** ContainerValidator:L6
### `lib/features/trips/presentation/providers/trip_provider.dart` (96 L | usado por 10 archivos)
- **Providers/Exports:** tripRepositoryProvider:L12, activeShiftProvider:L18, activeTripsProvider:L24, currentShiftTripsProvider:L30, expensesProvider:L40, totalExpensesProvider:L46, vehiclesProvider:L61, viaticosProvider:L67, assignedRequestsProvider:L72, currentVehicleProvider:L78, frequentDestinationsProvider:L93
### `lib/features/chat/domain/models/fleet_message_model.dart` (95 L | usado por 3 archivos)
- **Clases:** FleetMessageModel:L10
### `lib/features/trips/domain/services/distance_service.dart` (92 L | usado por 2 archivos)
- **Clases:** DistanceService:L10
- **Providers/Exports:** distanceServiceProvider:L92
### `lib/features/trips/presentation/providers/trip_draft_provider.dart` (89 L | usado por 1 archivos)
- **Clases:** TripDraft:L6, TripDraftNotifier:L59
- **Providers/Exports:** tripDraftProvider:L89
### `lib/features/admin/data/repositories/infraestructura_repository.dart` (87 L | usado por 4 archivos)
- **Clases:** InfraestructuraRepository:L5
- **Providers/Exports:** infraestructuraRepositoryProvider:L65, puntosInfraestructuraProvider:L69, peajesProvider:L74, romanasProvider:L79, restriccionesProvider:L84
### `lib/features/trips/domain/services/fuzzy_search_service.dart` (83 L | usado por 4 archivos)
- **Clases:** FuzzySearchService:L8
- **Providers/Exports:** fuzzySearchProvider:L4
### `lib/features/admin/domain/models/service_request_model.dart` (78 L | usado por 6 archivos)
- **Clases:** ServiceRequest:L5
### `lib/firebase_options.dart` (75 L | usado por 3 archivos)
- **Clases:** DefaultFirebaseOptions:L17
### `lib/features/trips/domain/models/shift_model.dart` (74 L | usado por 4 archivos)
- **Clases:** ShiftModel:L1
### `lib/features/admin/domain/models/liquidacion_model.dart` (70 L | usado por 4 archivos)
- **Clases:** LiquidacionModel:L3
### `lib/features/auth/presentation/providers/auth_provider.dart` (67 L | usado por 27 archivos)
- **Clases:** AuthService:L43
- **Providers/Exports:** authStateProvider:L12, currentUserProfileProvider:L18, authServiceProvider:L39, authRepositoryProvider:L65
- **Firestore:** usuarios
### `lib/main.dart` (67 L | usado por 1 archivos)
- **Clases:** BitacoraApp:L53
### `lib/features/admin/domain/models/recurring_expense_model.dart` (60 L | usado por 4 archivos)
- **Clases:** RecurringExpenseModel:L3
### `lib/features/admin/domain/models/analytics_models.dart` (57 L | usado por 3 archivos)
- **Clases:** RouteProfitability:L1, TrendData:L45
### `lib/features/trips/domain/models/viatico_model.dart` (55 L | usado por 7 archivos)
- **Clases:** ViaticoModel:L3
### `lib/core/utils/number_utils.dart` (49 L | usado por 5 archivos)
- **Clases:** NumberUtils:L3, DecimalTextInputFormatter:L36
### `lib/core/models/audit_log_model.dart` (39 L | usado por 1 archivos)
- **Clases:** AuditLogModel:L3
### `lib/features/auth/domain/models/invitation_model.dart` (38 L | usado por 1 archivos)
- **Clases:** InvitationModel:L1
### `lib/features/admin/domain/services/tax_indicator_service.dart` (34 L | usado por 1 archivos)
- **Clases:** TaxIndicatorService:L4
### `lib/features/auth/domain/models/company_model.dart` (30 L | usado por 1 archivos)
- **Clases:** CompanyModel:L1
### `lib/core/utils/file_downloader.dart` (20 L | usado por 1 archivos)
### `lib/features/admin/domain/services/wialon_caller_web.dart` (15 L | usado por 1 archivos)
### `lib/core/utils/security_utils.dart` (14 L | usado por 1 archivos)
- **Clases:** SecurityUtils:L1
### `lib/features/admin/domain/services/wialon_caller_stub.dart` (13 L | usado por 1 archivos)
### `lib/features/admin/domain/services/wialon_caller.dart` (2 L | usado por 1 archivos)