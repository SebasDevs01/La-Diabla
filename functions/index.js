// functions/index.js
// Cloud Functions para La Diabla — Firebase Functions v2
const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// ─── Mensajes de estado de orden ────────────────────────────────────────────
const STATUS_MESSAGES = {
  pending:     { title: "⏳ Pedido recibido",          body: "Tu pedido en La Diabla fue recibido y está esperando confirmación 🌶️" },
  confirmed:   { title: "✅ Pedido confirmado",         body: "Tu pedido fue confirmado. ¡Empezamos a prepararlo! 👨‍🍳" },
  preparing:   { title: "🍳 En preparación",            body: "Tu comida de La Diabla está en el fuego. ¡Pronto lista! 🔥" },
  ready:       { title: "📦 Listo para despacho",      body: "Tu pedido está listo y esperando al repartidor 🛵" },
  assigned:    { title: "🛵 Repartidor asignado",      body: "Un repartidor fue asignado a tu pedido. ¡Pronto irá en camino! 🌶️" },
  on_the_way:  { title: "🛵 ¡Va en camino!",           body: "El repartidor ya salió con tu comida. ¡Ya casi llega! 🌶️" },
  onTheWay:    { title: "🛵 ¡Va en camino!",           body: "El repartidor ya salió con tu comida. ¡Ya casi llega! 🌶️" },
  delivered:   { title: "✅ ¡Pedido entregado!",        body: "¡Buen provecho! Califica tu experiencia en La Diabla 🌮⭐" },
  cancelled:   { title: "❌ Pedido cancelado",          body: "Tu pedido fue cancelado. Contáctanos si tienes dudas 📞" },
};

// ─── 1. Push al cliente cuando cambia el estado de su pedido ────────────────
exports.onOrderStatusChanged = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  // Solo actuar si el status cambió
  if (before.status === after.status) return null;

  const userId = after.userId;
  if (!userId) return null;

  // Obtener FCM token del cliente
  const userDoc = await db.collection("users").doc(userId).get();
  const fcmToken = userDoc.data()?.fcmToken;

  if (!fcmToken) {
    console.log(`[onOrderStatusChanged] Sin FCM token para usuario ${userId}`);
    return null;
  }

  const msg = STATUS_MESSAGES[after.status];
  if (!msg) return null;

  const message = {
    token: fcmToken,
    notification: { title: msg.title, body: msg.body },
    android: {
      priority: "high",
      notification: {
        channelId: "la_diabla_orders",
        priority: "max",
        visibility: "public",
        defaultSound: true,
        defaultVibrateTimings: true,
        sound: "default",
      },
    },
    apns: {
      payload: {
        aps: { alert: { title: msg.title, body: msg.body }, sound: "default", badge: 1 },
      },
    },
    data: {
      orderId: event.params.orderId,
      status: after.status,
      type: "order_status",
      title: msg.title,
      body: msg.body,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
  };

  try {
    await messaging.send(message);
    console.log(`[onOrderStatusChanged] Push enviado a ${userId}: ${after.status}`);

    // Guardar en el historial de notificaciones del usuario de manera idempotente (evita duplicados)
    await db.collection("users").doc(userId).collection("notifications").doc(`${event.params.orderId}_${after.status}`).set({
      title: msg.title,
      body: msg.body,
      orderId: event.params.orderId,
      status: after.status,
      type: "order_status",
      createdAt: FieldValue.serverTimestamp(),
      isRead: false,
    }, { merge: true });
  } catch (err) {
    console.error(`[onOrderStatusChanged] Error enviando push: ${err}`);
  }

  return null;
});

// ─── 2. Push a TODOS los repartidores cuando entra un pedido nuevo ───────────
exports.onNewOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data.data();

  // Solo notificar si el pedido está pendiente y no ha fallado el pago
  if (order.status !== "pending") return null;
  if (order.paymentStatus === "failed") return null;

  const shortId = event.params.orderId.substring(0, 6).toUpperCase();
  const address = order.formattedAddress || "Dirección del cliente";
  const total   = `$${(order.total || 0).toLocaleString("es-CO")} COP`;
  const notifTitle = `🔔 Nuevo pedido disponible #${shortId}`;
  const notifBody = `${total} — ${address}`;

  // 1. Enviar push broadcast inmediato al topic 'drivers' (recibido por todos los repartidores suscritos)
  const topicMessage = {
    topic: "drivers",
    notification: {
      title: notifTitle,
      body: notifBody,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "la_diabla_orders",
        priority: "max",
        visibility: "public",
        defaultSound: true,
        defaultVibrateTimings: true,
        sound: "default",
      },
    },
    apns: {
      payload: {
        aps: { alert: { title: notifTitle, body: notifBody }, sound: "default", badge: 1 },
      },
    },
    data: {
      orderId: event.params.orderId,
      type: "new_order",
      title: notifTitle,
      body: notifBody,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
  };

  try {
    await messaging.send(topicMessage);
    console.log(`[onNewOrderCreated] Push broadcast a topic 'drivers' enviado para pedido #${shortId}`);
  } catch (err) {
    console.error(`[onNewOrderCreated] Error enviando push a topic drivers: ${err}`);
  }

  // 2. Además, enviar a tokens directos de repartidores disponibles (sin índice compuesto)
  try {
    const driversSnap = await db.collection("users")
      .where("role", "==", "driver")
      .get();

    if (!driversSnap.empty) {
      const tokens = driversSnap.docs
        .map(doc => doc.data())
        .filter(d => d.isAvailable !== false && d.fcmToken && typeof d.fcmToken === "string" && d.fcmToken.length > 10)
        .map(d => d.fcmToken);

      if (tokens.length > 0) {
        const uniqueTokens = [...new Set(tokens)];
        const multicastMessage = {
          tokens: uniqueTokens,
          notification: {
            title: notifTitle,
            body: notifBody,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "la_diabla_orders",
              priority: "max",
              visibility: "public",
              defaultSound: true,
              defaultVibrateTimings: true,
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: { alert: { title: notifTitle, body: notifBody }, sound: "default", badge: 1 },
            },
          },
          data: {
            orderId: event.params.orderId,
            type: "new_order",
            title: notifTitle,
            body: notifBody,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        };
        const response = await messaging.sendEachForMulticast(multicastMessage);
        console.log(`[onNewOrderCreated] Push directo enviado a ${response.successCount}/${uniqueTokens.length} repartidores`);
      }
    }
  } catch (err) {
    console.error(`[onNewOrderCreated] Error enviando push directo a repartidores: ${err}`);
  }

  return null;
});

// ─── 3. Push al destinatario cuando llega un mensaje de chat ────────────────
// Se dispara al crear un doc en users/{userId}/notifications con type='chat_message'
exports.onChatMessageNotification = onDocumentCreated(
  "users/{userId}/notifications/{notifId}",
  async (event) => {
    const notif = event.data.data();
    if (!notif) return null;

    // Solo procesar mensajes de chat
    if (notif.type !== "chat_message") return null;

    const recipientId = event.params.userId;
    const orderId     = notif.orderId  || "";
    const title       = notif.title    || "💬 Nuevo mensaje";
    const body        = notif.body     || "";

    // Obtener el FCM token del destinatario
    const userDoc  = await db.collection("users").doc(recipientId).get();
    const fcmToken = userDoc.data()?.fcmToken;

    if (!fcmToken) {
      console.log(`[onChatMessageNotification] Sin FCM token para usuario ${recipientId}`);
      return null;
    }

    const message = {
      token: fcmToken,
      notification: { title, body },
      android: {
        notification: {
          channelId: "la_diabla_orders",
          priority: "high",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        payload: {
          aps: { alert: { title, body }, sound: "default", badge: 1 },
        },
      },
      data: {
        orderId,
        type: "chat_message",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    };

    try {
      await messaging.send(message);
      console.log(`[onChatMessageNotification] Push de chat enviado a ${recipientId} para orden ${orderId}`);
    } catch (err) {
      console.error(`[onChatMessageNotification] Error enviando push: ${err}`);
    }

    return null;
  }
);

// ─── 4. Acumular ganancias del repartidor al entregar ───────────────────────
exports.onOrderDelivered = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  // Solo cuando el pedido pasa a "delivered"
  if (before.status === after.status) return null;
  if (after.status !== "delivered") return null;

  const driverId = after.driverId;
  if (!driverId) return null;

  const deliveryFee = after.deliveryFee || 5000; // Valor del domicilio

  // Acumular en la colección de ganancias del repartidor
  const earningRef = db.collection("users").doc(driverId).collection("earnings").doc();
  await earningRef.set({
    orderId: event.params.orderId,
    amount: deliveryFee,
    date: FieldValue.serverTimestamp(),
    customerAddress: after.formattedAddress || "",
    orderTotal: after.total || 0,
  });

  // Actualizar resumen acumulado
  const summaryRef = db.collection("users").doc(driverId).collection("earnings").doc("__summary__");
  await summaryRef.set({
    totalEarned: FieldValue.increment(deliveryFee),
    totalDeliveries: FieldValue.increment(1),
    lastUpdated: FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log(`[onOrderDelivered] Ganancia +$${deliveryFee} acumulada para driver ${driverId}`);
  return null;
});

const GEMINI_API_KEY = process.env.GEMINI_API_KEY || "";
const GEMINI_MODELS = [
  "gemini-3.1-flash-lite",
  "gemini-3.5-flash-lite",
  "gemini-flash-latest",
  "gemini-3.8-flash-lite"
];

async function callGeminiApi(systemPrompt, contents) {
  let lastError = null;
  for (const model of GEMINI_MODELS) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`;
      const payload = {
        systemInstruction: {
          parts: [{ text: systemPrompt }]
        },
        contents: contents,
        generationConfig: {
          temperature: 0.75,
          maxOutputTokens: 800,
        }
      };

      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });

      const data = await response.json();
      if (data.candidates && data.candidates[0] && data.candidates[0].content) {
        return data.candidates[0].content.parts[0].text;
      }
      if (data.error) {
        lastError = new Error(`[${model}] ${data.error.code}: ${data.error.message}`);
        console.warn(`[callGeminiApi] Error con modelo ${model}:`, data.error.message);
      }
    } catch (err) {
      lastError = err;
      console.warn(`[callGeminiApi] Excepción con modelo ${model}:`, err.message);
    }
  }
  throw lastError || new Error("No se pudo obtener respuesta de ningún modelo de Gemini.");
}

exports.askDiablaAi = onRequest({ cors: true, maxInstances: 15 }, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    const {
      type = "chef", // "chef" | "support"
      query = "",
      userName = "",
      orderId = null,
      history = [],
      catalog = []
    } = req.body || {};

    if (!query || typeof query !== "string" || !query.trim()) {
      res.status(400).json({ success: false, error: "El campo 'query' es requerido." });
      return;
    }

    const cleanQuery = query.trim();
    const customerName = userName && userName.trim() ? userName.trim() : "Cliente";

    // ─── Construir historial conversacional multi-turn para Gemini ──────────
    const formattedContents = [];
    if (Array.isArray(history) && history.length > 0) {
      for (const msg of history.slice(-8)) { // Mantener hasta los últimos 8 turnos
        if (msg && msg.text && msg.role) {
          formattedContents.push({
            role: msg.role === "user" ? "user" : "model",
            parts: [{ text: String(msg.text) }]
          });
        }
      }
    }
    // Agregar el mensaje actual del usuario
    formattedContents.push({
      role: "user",
      parts: [{ text: cleanQuery }]
    });

    // ─── CASO 1: ASISTENTE DE SOPORTE AL CLIENTE ────────────────────────────
    if (type === "support") {
      let orderContext = "No hay un pedido específico seleccionado por el usuario en esta consulta.";
      let orderData = null;

      if (orderId) {
        try {
          const snap = await db.collection("orders").doc(orderId).get();
          if (snap.exists) {
            orderData = snap.data();
            const shortId = orderId.substring(0, 6).toUpperCase();
            const status = orderData.status || "desconocido";
            const itemsStr = Array.isArray(orderData.items)
              ? orderData.items.map(i => `${i.quantity || 1}x ${i.product?.name || i.name || "Platillo"}`).join(", ")
              : "Detalles no disponibles";
            const total = orderData.total ? `$${orderData.total.toLocaleString("es-CO")} COP` : "No especificado";
            const address = orderData.formattedAddress || orderData.address || "Dirección registrada";
            const paymentMethod = orderData.paymentMethod || "No especificado";
            
            // Minutos transcurridos
            let elapsedMin = "reciente";
            if (orderData.createdAt && orderData.createdAt.toDate) {
              const diffMs = Date.now() - orderData.createdAt.toDate().getTime();
              elapsedMin = `${Math.max(1, Math.floor(diffMs / 60000))} minutos`;
            }

            orderContext = `DATOS REALES DEL PEDIDO EN VIVO:
- ID del Pedido: #${shortId} (Referencia: ${orderId})
- Estado actual: ${status} (pending=esperando confirmación, preparing=en cocina, on_the_way=en moto con repartidor, delivered=entregado, cancelled=cancelado)
- Platillos ordenados: ${itemsStr}
- Total: ${total}
- Método de pago: ${paymentMethod}
- Dirección de entrega: ${address}
- Tiempo desde que se realizó: hace aprox. ${elapsedMin}
- Repartidor asignado: ${orderData.driverId ? "Sí, conductor asignado" : "Esperando asignación"}`;
          }
        } catch (e) {
          console.error("[askDiablaAi] Error leyendo pedido de Firestore:", e.message);
        }
      }

      const supportSystemPrompt = `Eres Sofía, la coordinadora de soporte y atención al cliente de "La Diabla" (restaurante mexicano en Bucaramanga, Colombia).
El cliente se llama: ${customerName}.

${orderContext}

DIRECTRICES CLAVE PARA RESPONDER COMO UNA PERSONA REAL:
1. TONO: Cálido, empático, profesional, comprensivo y resolutivo. Habla en español de Colombia de forma educada y cercana.
2. NUNCA des respuestas robóticas ni listas genéricas de "estoy capacitado para ayudarte con...". Responde DIRECTAMENTE a lo que el cliente te expresa.
3. SI EL CLIENTE ESTÁ MOLESTO O PREOCUPADO: Valida sus emociones ("Entiendo totalmente tu molestia", "Comprendo tu preocupación por la demora", "Lamento este inconveniente").
4. TIEMPOS Y ENTREGAS: Usa los datos del pedido en vivo si existen. 
   - Si está "preparing", aclárale que la cocina está preparando sus platillos frescos y dile un estimado realista.
   - Si está "on_the_way", confírmale que el domiciliario va en camino con maletín térmico.
   - Si figura como "delivered" pero el cliente no lo tiene, recomiéndale revisar amablemente en portería o recepción del edificio antes de gestionar el reclamo.
5. PAGOS Y COBROS (Nequi, Daviplata, Tarjetas, PSE): Explica con tranquilidad que los bancos a menudo hacen una retención temporal de fondos que se libera en 24-48h hábiles y que en La Diabla nunca se hacen cobros dobles reales.
6. COMIDA INCOMPLETA, FRÍA O EQUIVOCADA: Activa la "Garantía Total La Diabla" ofreciendo reenvío express inmediato o reembolso del producto afectado.
7. ESCALAR A ASESOR HUMANO / WHATSAPP: Si el caso requiere intervención manual inmediata, autorizar un reembolso o el cliente está muy disgustado, ofrécele amablemente comunicarse con el supervisor directo al WhatsApp (+57 320 221 2856 o +57 317 116 6497).`;

      const aiText = await callGeminiApi(supportSystemPrompt, formattedContents);
      const shouldEscalate = /whatsapp|supervisor|asesor humano|320 221 2856|317 116 6497|comprobante/i.test(aiText);

      res.status(200).json({
        success: true,
        message: aiText,
        shouldEscalate: shouldEscalate
      });
      return;
    }

    // ─── CASO 2: LA DIABLA IA — CHEF Y GUÍA GASTRONÓMICA ───────────────────
    let menuContext = "";
    if (Array.isArray(catalog) && catalog.length > 0) {
      menuContext = catalog.slice(0, 30).map(p => {
        const ings = p.ingredients ? ` (Ingredientes: ${Array.isArray(p.ingredients) ? p.ingredients.join(", ") : p.ingredients})` : "";
        const pic = p.spicyLevel !== undefined ? ` [Picor: ${p.spicyLevel}/3]` : "";
        return `- ID:${p.id} | ${p.name} | $${Number(p.price || 0).toLocaleString("es-CO")} COP | Cat:${p.categoryId || "general"}${pic}${ings}`;
      }).join("\n");
    }

    const chefSystemPrompt = `Eres "La Diabla IA", la chef mexicana apasionada, carismática y auténtica del restaurante "La Diabla" en Bucaramanga.
El cliente se llama: ${customerName}.

CATÁLOGO REAL Y DISPONIBLE EN EL RESTAURANTE:
${menuContext || "(Menú tradicional: Tacos de Birria con consomé, Tacos al Pastor con piña asada, Gringas con queso fundido, Burritos gigantes, Tacos de Suadero, Nachos con queso y guacamole, Churros con arequipe/chocolate)"}

DIRECTRICES PARA RESPONDER COMO UNA VERDADERA CHEF:
1. TONO: Apasionada por la gastronomía mexicana, alegre, acogedora, con sazón y carisma. Usa emojis oportunos (🌮, 🌶️, 🔥, 🥑, 🧀).
2. INTERPRETACIÓN HUMANA: Si el cliente pregunta qué comer, qué es un platillo, si pica mucho, qué marida bien o si tiene presupuesto limitado, responde como una chef aconsejando a su comensal favorito en la mesa.
3. CONOCIMIENTO TRADICIONAL: Sabes la historia de la Birria de Jalisco con su consomé para sopear, el pastor con su trompo y piña, el suadero confitado de CDMX y las gringas con costra de queso derretido.
4. RECOMENDACIÓN PRECISA: Recomienda entre 1 y 3 platillos que encajen exactamente con lo que el cliente te pide (presupuesto, antojo, nivel de picante, etc.).
5. FORMATO OBLIGATORIO DE IDs: Si recomiendas o mencionas platillos del menú que el cliente pueda comprar, SIEMPRE termina tu respuesta en una línea separada al final con el formato EXACTO:
IDs:[id1, id2]
(poniendo entre corchetes los IDs exactos de los platillos del catálogo listados arriba).`;

    const aiText = await callGeminiApi(chefSystemPrompt, formattedContents);

    // Extraer los IDs recomendados
    const idRegex = /IDs:\s*\[(.*?)\]/i;
    const match = idRegex.exec(aiText);
    let productIds = [];
    let cleanMessage = aiText;

    if (match) {
      const rawIds = match[1] || "";
      productIds = rawIds
        .split(",")
        .map(s => s.trim().replace(/['"]/g, ""))
        .filter(s => s.length > 0);
      cleanMessage = aiText.replace(match[0], "").trim();
    }

    res.status(200).json({
      success: true,
      message: cleanMessage,
      productIds: productIds
    });
  } catch (err) {
    console.error("[askDiablaAi] Error general:", err);
    res.status(500).json({
      success: false,
      error: "Error procesando con IA",
      details: err.message
    });
  }
});

