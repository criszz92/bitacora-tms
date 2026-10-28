# PLAN MAESTRO & ESTADO DE SITUACIÓN: BITÁCORA TMS (HEIRLOG TMS)

> **Documento de respaldo permanente para reanudación de desarrollo.**
> **Fecha de consolidación:** 26 de Octubre de 2026  
> **Rama activa:** `main` | **Último commit:** `4bab11a` (feat: modulo rendimiento y estanque digital)  
> **Versión Web Producción:** [https://bitacora-tms.web.app](https://bitacora-tms.web.app)  
> **APK Android Compilado:** `build/app/outputs/flutter-apk/app-release.apk` (71.8 MB)

---

## 1. Lo que está 100% Implementado y en Producción 🚀

### A. Rendimiento, Estanque Digital & Equipos Auxiliares (Último Hito)
- **Estanque Digital por Unidad:** Nivel en litros, porcentaje y autonomía en KM en tiempo real.
- **Calibración Obligatoria Inicial (`Full Tank Lock`):** La unidad requiere un llenado a tope registrado para fijar el 100% del estanque virtual.
- **Equipos Auxiliares de Frío (Genset / Thermo King / Carrier):**
  - Registro de generadores y equipos under-slung vinculados a un camión.
  - Control de consumo por **Horómetro** y tasa de **Litros/Hora**.
  - Detección de mermas y bloqueo de trasvasije fraudulento de combustible entre unidades.
- **App Conductor (APK):**
  - Selector táctil de estanque destino: `Camión` vs `Equipo Auxiliar`.
  - Switch de `Estanque Lleno (Full Tank)` que calcula automáticamente el rendimiento real del tramo en km/L.
  - Captura obligatoria de odómetro o horómetro según corresponda.
- **Módulo Web Directivo ("Rendimiento & Diésel"):**
  - **Petróleo en Estanques:** Total de dinero a favor en la calle valorizado al precio diésel neto ($ CLP).
  - **Déficit para 100% de la Flota:** Litros y presupuesto necesario para tener todos los camiones llenos.
  - Medidor de tanque individual y tabla de cargas históricas.

### B. Gestión de Viajes, Jornadas y Flota
- **Viajes (Trips):** Creación, asignación de chofer/unidad, sugerencia de tarifas históricas y estados operativos.
- **Jornadas Inteligentes:** Inicio y término de turno con sincronización automática de odómetros.
- **Flota:** Gestión de camiones, configuración de capacidades de estanque y vinculación de equipos de frío.

### C. Finanzas, Tributaria F29 y Rentabilidad Chilena
- **Análisis F29:** Desglose de IVA Débito, IVA Crédito y beneficio específico Diésel (Ley 19.764).
- **Cotizador de Fletes:** Simulación de márgenes con provisiones de mantenimiento, peajes y combustible.
- **Viáticos y Liquidaciones:** Liquidaciones automáticas con exportación a PDF paginada.

### D. Telemetría y Torre de Control
- **Integración ModoGPS / Wialon:** Trazado de ruta en vivo, rotación según rumbo y estela de migas de pan.
- **Historial de Rutas:** Diferenciación visual entre viaje de **Ida** y **Retorno**, detección de paradas y filtro de permanencia en geocercas.

---

## 2. Lo que Queda en Carpeta (Hoja de Ruta para Reanudar) 📋

### Eje 1: Fuente de Verdad Absoluta Financiera (F29 & Cuenta Corriente Tributaria)
- **El Dolor:** Compras de activos fijos (camiones) generan facturas millonarias con IVA a favor que dura meses. Hoy el sistema no arrastra ese crédito fiscal.
- **Qué construir al volver:**
  1. **Remanente de Crédito Fiscal Arrastrable:** Llevar una cuenta corriente del IVA remanente mes a mes reajustado por UTM (Líneas 33 y 77 del F29).
  2. **PPM Obligatorio:** Incluir el porcentaje de Pago Provisional Mensual que la empresa paga al SII mes a mes.
  3. **Separación de Métricas:** Mostrar claramente el **EBITDA Operacional** (si el camión es rentable por sí solo) vs. **Flujo de Caja Real en Banco**.

### Eje 2: Fondos a Rendir & Billetera por Conductor
- **El Dolor:** Las empresas entregan anticipos semanales/mensuales en efectivo para peajes y gastos varios, y la cuadratura manual es lenta y propensa a desajustes.
- **Qué construir al volver:**
  1. Registro de entregas de dinero con **destino habilitado** (ej. solo peajes en efectivo, vulcanización o AdBlue; bloqueando combustible si usan tarjetas de servicentro).
  2. Billetera por chofer donde se descuentan los gastos rendidos con boleta.
  3. Botón de cuadratura: liquidación automática para devolver en caja o descontar en sueldo.

### Eje 3: Alertas Predictivas y Seguridad en Ruta
- **Alerta de Combustible en Ruta:** Aviso al chofer y a la Torre de Control si la autonomía estimada es menor a los kilómetros que faltan para terminar el viaje activo.
- **Mantenimiento Predictivo:** Disparo automático de alertas al acercarse al kilometraje de cambio de aceite y filtros.
- **Hardware & Sensores I/O (Largo Plazo):** Conexión vía API/Webhooks para cámaras de fatiga/somnolencia (DMS/ADAS) y corte remoto preventivo de motor.

---

## 3. Guía Rápida para Retomar 🛠️
1. **Verificar el estado del repo:** Todo quedó limpio y commiteado en `main`.
2. **Reanudación recomendada:** Comenzar por el **Eje 1 (Cuenta Corriente Tributaria F29)** pidiendo a la administración o contador el % de PPM actual y si existe un saldo inicial de remanente por cargar.
3. El código fuente está compilando sin advertencias ni métodos obsoletos en Flutter moderno.

