const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

/**
 * Función segura para analizar la rentabilidad usando Groq.
 */
exports.analyzeProfitability = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "El usuario debe estar autenticado.");
  }

  const apiKey = process.env.GROQ_API_KEY;
  const baseUrl = "https://api.groq.com/openai/v1";

  if (!apiKey) {
    throw new functions.https.HttpsError("failed-precondition", "La configuración de seguridad no está completa.");
  }

  const prompt = `
    Eres un experto en logística y finanzas de transporte (TMS).
    Analiza los siguientes datos de rentabilidad de rutas:
    ${JSON.stringify(data)}

    Responde en español, de forma profesional y concisa. Usa bullet points.
  `;

  try {
    const response = await axios.post(
      `${baseUrl}/chat/completions`,
      {
        model: "llama-3.1-8b-instant",
        messages: [
          { role: "system", content: "Eres un asistente experto en analítica de transporte." },
          { role: "user", content: prompt }
        ],
        temperature: 0.7,
      },
      {
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`,
        },
      }
    );

    return { result: response.data.choices[0].message.content };
  } catch (error) {
    throw new functions.https.HttpsError("internal", "Error al procesar con la IA.");
  }
});
/**
 * Función que sincroniza los datos de Liot GPS con Firestore.
 * Se ejecuta cada 2 minutos.
 */
exports.syncLiotGps = functions.pubsub.schedule("every 2 minutes").onRun(async (context) => {
  const user = process.env.LIOT_USER;
  const pass = process.env.LIOT_PASS;
  const baseUrl = "http://liot.cl:8082/api";

  if (!user || !pass) {
    console.error("Faltan las credenciales de Liot en las variables de entorno.");
    return null;
  }

  const auth = Buffer.from(`${user}:${pass}`).toString("base64");
  const headers = { "Authorization": `Basic ${auth}` };

  try {
    // 1. Obtener Dispositivos (para tener las patentes/nombres)
    const devicesRes = await axios.get(`${baseUrl}/devices`, { headers });
    const devices = devicesRes.data;

    // 2. Obtener Posiciones (coordenadas reales)
    const positionsRes = await axios.get(`${baseUrl}/positions`, { headers });
    const positions = positionsRes.data;

    // 3. Cruzar datos y guardar en Firestore
    const batch = admin.firestore().batch();
    
    devices.forEach((device) => {
      const pos = positions.find((p) => p.deviceId === device.id);
      if (pos) {
        const docRef = admin.firestore().collection("gps_monitor").doc(device.name);
        batch.set(docRef, {
          plate: device.name,
          deviceId: device.id,
          lat: pos.latitude,
          lng: pos.longitude,
          speed: pos.speed,
          status: device.status,
          lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
          attributes: device.attributes,
        }, { merge: true });
      }
    });

    await batch.commit();
    console.log(`Sincronización de Liot completada para ${devices.length} camiones.`);
    return null;
  } catch (error) {
    console.error("Error al sincronizar con Liot:", error.message);
    return null;
  }
});

// ─── HELPER FUNCTIONS PARA NOTIFICACIONES PUSH ──────────────────────────────────

async function notifyAdmins(idEmpresa, title, body, data = {}) {
  const usersSnapshot = await admin.firestore().collection("usuarios")
    .where("idEmpresa", "==", idEmpresa)
    .where("rol", "==", "ADMIN")
    .get();

  const tokens = [];
  usersSnapshot.forEach(doc => {
    const d = doc.data();
    if (d.fcmToken) tokens.push(d.fcmToken);
  });

  if (tokens.length > 0) {
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        title: String(title),
        body: String(body),
        ...data
      },
      android: {
        priority: "high",
        notification: {
          channelId: "bitacora_binaural_v4",
          sound: "bitacora_alert",
          defaultSound: false,
          priority: "max",
          visibility: "public"
        }
      }
    });
  }
}

async function notifyDriver(idChofer, title, body, data = {}) {
  const userDoc = await admin.firestore().collection("usuarios").doc(idChofer).get();
  if (userDoc.exists) {
    const token = userDoc.data().fcmToken;
    if (token) {
      try {
        await admin.messaging().send({
          token,
          notification: { title, body },
          data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            title: String(title),
            body: String(body),
            ...data
          },
          android: {
            priority: "high",
            notification: {
              channelId: "bitacora_binaural_v4",
              sound: "bitacora_alert",
              defaultSound: false,
              priority: "max",
              visibility: "public"
            }
          }
        });
        console.log(`Notificación FCM enviada a chofer ${idChofer}: ${title}`);
      } catch (err) {
        console.error(`Error enviando FCM a chofer ${idChofer}:`, err.message);
      }
    } else {
      console.warn(`Chofer ${idChofer} no tiene fcmToken en Firestore.`);
    }
  }
}

// ─── MANTENIMIENTO PREDICTIVO Y ODÓMETRO (ON TRIP FINISHED) ───────────────────

exports.onTripFinished = functions.firestore
  .document("viajes/{tripId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Solo actuar cuando el estado cambia a "Finalizado" y hay kilómetros totales.
    if (before.status === after.status || after.status !== "Finalizado" || !after.totalKm) {
      return null;
    }

    const totalKm = after.totalKm;
    const vehicleRefId = after.patenteCamion || after.vehicleId;
    if (!vehicleRefId) return null;

    // Buscar el vehiculo por ID directo o por patente
    const vehiculosRef = admin.firestore().collection("vehiculos");
    let vehicleDoc = await vehiculosRef.doc(vehicleRefId).get();
    if (!vehicleDoc.exists) {
      const snapshot = await vehiculosRef.where("patente", "==", vehicleRefId).limit(1).get();
      if (snapshot.empty) return null;
      vehicleDoc = snapshot.docs[0];
    }

    const vehicleData = vehicleDoc.data();
    const currentOdometer = vehicleData.currentOdometer || 0;
    const newOdometer = currentOdometer + totalKm;

    // Actualizar el odómetro
    await vehicleDoc.ref.update({ currentOdometer: newOdometer });

    // Chequear mantenimiento preventivo (Aviso a los 500 km)
    const nextOilChangeKm = vehicleData.nextOilChangeKm;
    if (nextOilChangeKm && (nextOilChangeKm - newOdometer) <= 500) {
      const plateLabel = vehicleData.patente || vehicleRefId;
      const msgTitle = "Alerta de Mantenimiento Preventivo 🛠️";
      const msgBody = `El camión ${plateLabel} está a ${(nextOilChangeKm - newOdometer).toFixed(0)} km de su cambio de aceite.`;

      await notifyAdmins(vehicleData.idEmpresa, msgTitle, msgBody);
      await notifyDriver(after.idChofer, msgTitle, msgBody);
    }
    return null;
  });

// ─── NOTIFICACIÓN DE INCIDENCIAS OPERATIVAS ───────────────────────────────────

exports.onIncidenceCreated = functions.firestore
  .document("incidencias/{incidenceId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const vehiculo = data.vehiculoId || "Vehículo Desconocido";
    const descripcion = data.descripcion || "Sin descripción";

    // Buscar el nombre del chofer
    const userDoc = await admin.firestore().collection("usuarios").doc(data.idChofer).get();
    const driverName = userDoc.exists ? userDoc.data().nombre : "Un conductor";

    const title = "Nuevo Reporte Operativo ⚠️";
    const body = `${driverName} reportó incidencia en ${vehiculo}: ${descripcion}`;

    await notifyAdmins(data.idEmpresa, title, body);
    return null;
  });

// ─── CHEQUEO DIARIO DE DOCUMENTACIÓN (CRON JOB) ───────────────────────────────

exports.dailyDocumentCheck = functions.pubsub.schedule("every day 08:00").onRun(async (context) => {
  const vehiculosRef = admin.firestore().collection("vehiculos");
  const snapshot = await vehiculosRef.get();

  const now = new Date();
  const alertThreshold = new Date();
  alertThreshold.setDate(now.getDate() + 7); // Notificar con 7 días de anticipación

  const notificationsByCompany = {};

  snapshot.forEach(doc => {
    const v = doc.data();
    if (!v.idEmpresa) return;

    const checkDate = (dateString, docName) => {
      if (!dateString) return;
      const expDate = new Date(dateString);
      if (expDate <= alertThreshold && expDate >= now) {
        if (!notificationsByCompany[v.idEmpresa]) {
          notificationsByCompany[v.idEmpresa] = [];
        }
        notificationsByCompany[v.idEmpresa].push(`El ${docName} de ${v.patente} vence en menos de 7 días.`);
      } else if (expDate < now) {
        if (!notificationsByCompany[v.idEmpresa]) {
          notificationsByCompany[v.idEmpresa] = [];
        }
        notificationsByCompany[v.idEmpresa].push(`URGENTE: El ${docName} de ${v.patente} está VENCIDO.`);
      }
    };

    checkDate(v.rtExpirationDate, "Revisión Técnica");
    checkDate(v.soapExpirationDate, "SOAP");
    checkDate(v.permisoExpirationDate, "Permiso de Circulación");
  });

  // Enviar un mensaje consolidado a los admins de cada empresa
  for (const [idEmpresa, messages] of Object.entries(notificationsByCompany)) {
    if (messages.length > 0) {
      const title = "Alertas de Documentación de Flota 🚨";
      const body = messages.join("\n");
      await notifyAdmins(idEmpresa, title, body);
    }
  }

  return null;
});

// ─── NOTIFICACIÓN DE SERVICIO ASIGNADO A CONDUCTOR ───────────────────────────

exports.onServiceRequestUpdated = functions.firestore
  .document("service_requests/{requestId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.data();

    if (after.status === "assigned" && after.assignedTo) {
      const wasAssignedBefore = before && before.status === "assigned" && before.assignedTo === after.assignedTo;
      if (!wasAssignedBefore) {
        const title = "📦 ¡Nuevo Servicio Asignado!";
        const body = `${after.clientName || "Cliente"}: ${after.origin || "Origen"} ➔ ${after.destination || "Destino"}`;
        await notifyDriver(after.assignedTo, title, body, {
          requestId: context.params.requestId,
          type: "service_assignment"
        });
      }
    }
    return null;
  });

// ─── NOTIFICACIÓN DE ESTADO DE VIÁTICOS ───────────────────────────────────────

exports.onViaticoUpdated = functions.firestore
  .document("viaticos/{viaticoId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before.estado !== after.estado && after.idChofer) {
      const monto = after.montoTotal ?? after.monto ?? 0;
      const estadoLower = String(after.estado || "").toLowerCase();
      let title = "💵 Actualización de Viático";
      let body = `Tu solicitud por $${monto} ha cambiado a: ${after.estado}`;
      if (estadoLower === "pagado" || estadoLower === "aprobado") {
        title = estadoLower === "pagado" ? "✅ Viático Pagado" : "✅ Viático Aprobado";
        body = `Tu rendición por $${monto} ha sido ${estadoLower}.`;
      } else if (estadoLower === "rechazado") {
        title = "❌ Viático Rechazado";
        body = `Tu rendición por $${monto} ha sido rechazada.`;
      }
      await notifyDriver(after.idChofer, title, body, {
        viaticoId: context.params.viaticoId,
        type: "viatico_status"
      });
    }
    return null;
  });

/**
 * Publica o fuerza la actualización remota de versión de la app de choferes en Firestore.
 * Puede ser invocada vía HTTPS GET/POST o webhook.
 */
exports.publishAppUpdate = functions.https.onRequest(async (req, res) => {
  try {
    const buildNumber = parseInt(req.query.build || req.body?.build || "11");
    const versionName = req.query.version || req.body?.version || "1.1.0";
    const apkUrl = req.query.url || req.body?.url || "https://firebasestorage.googleapis.com/v0/b/bitacora-tms.appspot.com/o/app_releases%2Fbitacora-tms-v1.1.0%2B11.apk?alt=media";
    const releaseNotes = req.query.notes || req.body?.notes || "Actualización v1.1.0: Endurecimiento de reglas de seguridad, radar de tarifas por ruta, deducción IEPD Ley 19.764 y optimizaciones de telemetría.";
    const mandatory = req.query.mandatory === "true" || req.body?.mandatory === true;

    await admin.firestore().collection("app_version").doc("android_driver").set({
      buildNumber,
      versionName,
      apkUrl,
      releaseNotes,
      mandatory,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return res.status(200).json({
      status: "success",
      message: "Versión de app actualizada correctamente en Firestore",
      published: { buildNumber, versionName, apkUrl, mandatory, releaseNotes }
    });
  } catch (error) {
    return res.status(500).json({ status: "error", message: error.message });
  }
});
