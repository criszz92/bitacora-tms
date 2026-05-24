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
        model: "llama-3.3-70b-versatile",
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
