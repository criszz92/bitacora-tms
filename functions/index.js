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
