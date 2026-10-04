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
  "gemini-2.0-flash-lite",
  "gemini-2.0-flash",
  "gemini-1.5-flash-latest",
  "gemini-1.5-flash"
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
          temperature: 0.7,
          maxOutputTokens: 380,
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
      userId = null,
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
      for (const msg of history.slice(-6)) {
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

    // ─── CASO 1: ASISTENTE DE SOPORTE AL CLIENTE (Sofía) ────────────────────
    if (type === "support") {
      let orderContext = "No hay un pedido específico seleccionado por el usuario en esta consulta.";
      let orderData = null;

      if (orderId) {
        try {
          const snap = await db.collection("orders").doc(orderId).get();
          if (snap.exists) {
            orderData = { id: snap.id, ...snap.data() };
          }
        } catch (e) {
          console.error("[askDiablaAi] Error leyendo pedido de Firestore:", e.message);
        }
      }

      // Si no tenemos orderData pero tenemos userId, buscamos los pedidos del usuario
      if (!orderData && userId) {
        try {
          const ordersSnap = await db.collection("orders")
            .where("userId", "==", userId)
            .limit(10)
            .get();

          if (!ordersSnap.empty) {
            const list = ordersSnap.docs.map(d => ({ id: d.id, ...d.data() }));
            list.sort((a, b) => {
              const tA = a.createdAt?.toDate ? a.createdAt.toDate().getTime() : (a.createdAt || 0);
              const tB = b.createdAt?.toDate ? b.createdAt.toDate().getTime() : (b.createdAt || 0);
              return tB - tA;
            });
            orderData = list[0];
          }
        } catch (e) {
          console.error("[askDiablaAi] Error buscando pedidos de usuario:", e.message);
        }
      }

      if (orderData) {
        const shortId = (orderData.id || "").substring(0, 6).toUpperCase();
        const status = orderData.status || "desconocido";
        const itemsStr = Array.isArray(orderData.items)
          ? orderData.items.map(i => `${i.quantity || 1}x ${i.product?.name || i.name || "Platillo"}`).join(", ")
          : "Detalles no disponibles";
        const total = orderData.total ? `$${Number(orderData.total).toLocaleString("es-CO")} COP` : "No especificado";
        const address = orderData.address?.formattedAddress || orderData.formattedAddress || orderData.address || "Dirección registrada";
        const paymentMethod = orderData.paymentMethod || "No especificado";

        // Obtener nombre del repartidor si existe
        let driverName = orderData.driverName || null;
        if (!driverName && orderData.driverId) {
          try {
            const driverSnap = await db.collection("users").doc(orderData.driverId).get();
            if (driverSnap.exists) {
              const d = driverSnap.data();
              driverName = d.displayName || d.name || d.fullName || null;
            }
          } catch (e) {}
        }
        const driverInfo = driverName
          ? `Repartidor asignado: ${driverName}`
          : (orderData.driverId ? "Repartidor asignado a la orden" : "Esperando asignación de repartidor");

        let elapsedMin = "reciente";
        if (orderData.createdAt && orderData.createdAt.toDate) {
          const diffMs = Date.now() - orderData.createdAt.toDate().getTime();
          elapsedMin = `${Math.max(1, Math.floor(diffMs / 60000))} minutos`;
        }

        orderContext = `DATOS REALES DEL ÚLTIMO PEDIDO O PEDIDO CONSULTADO EN VIVO:
- ID del Pedido: #${shortId} (ID completo: ${orderData.id})
- Estado actual: ${status} (pending=esperando confirmación, preparing=en cocina, on_the_way=en moto con repartidor, delivered=entregado, cancelled=cancelado)
- Platillos: ${itemsStr}
- Total: ${total}
- Método de pago: ${paymentMethod}
- Dirección de entrega: ${address}
- Realizado hace: aprox. ${elapsedMin}
- ${driverInfo}`;
      }

      const supportSystemPrompt = `Eres Sofía, la coordinadora de soporte y atención al cliente de "La Diabla" (restaurante mexicano en Bucaramanga, Colombia).
El cliente se llama: ${customerName}.

${orderContext}

DIRECTRICES PARA RESPONDER COMO UNA PERSONA REAL:
1. LONGITUD: Sé MUY BREVE y concisa (1 o 2 párrafos cortos, máximo 3 a 4 líneas en total). A la gente no le gusta leer textos largos. Ve directo al grano con amabilidad y calidez.
2. TONO: Cercano, empático, resolutivo y muy humano. Cero respuestas robóticas o de call center.
3. PREGUNTAS CASUALES O SALUDOS (ej. "hola", "cómo vas", "cómo estás"): Responde con naturalidad y buena energía en una sola línea amable y pregúntale en qué le puedes colaborar hoy.
4. CONSULTA DE ÚLTIMO PEDIDO O REPARTIDOR (ej. "dame el resumen de mi último pedido y quién me lo entregó"):
   - Si tienes los DATOS REALES arriba, dale el resumen exacto: número de pedido (#ID), platillos pedidos, total en COP, estado y el NOMBRE DEL REPARTIDOR.
   - Si no hay datos de pedidos registrados para el usuario, dile con amabilidad que no ves pedidos activos o recientes asociados a su sesión en este momento, y que puede revisar en la sección "Mis Pedidos".
5. PREGUNTAS SOBRE EL DESARROLLADOR O LA APP: Si te preguntan quién es el desarrollador o creador de la app de La Diabla, responde con orgullo: fue desarrollada y diseñada por Sebastián (conocido como SebasDevs / @SebasDevs01), el talentoso desarrollador de software que creó toda la tecnología de La Diabla.
6. TIEMPOS Y ENTREGAS: Si está en preparación, dile que está recién hecho en cocina; si va en camino, confirma que el repartidor va en moto; si figura entregado pero no lo tiene, recomiéndale revisar amablemente en portería o recepción.
7. PAGOS Y COBROS (Nequi, Daviplata, Tarjetas): Explica brevemente que los bancos suelen hacer retención temporal que se libera en 24-48h hábiles y que nunca cobramos doble.
8. ESCALAR: Si requiere solución manual o reembolso, ofrécele amablemente comunicarse al WhatsApp (+57 320 221 2856 o +57 317 116 6497).`;

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

DIRECTRICES CLAVE:
1. LONGITUD DE RESPUESTA: Sé MUY BREVE Y DIRECTA (máximo 2 párrafos cortos, de 2 a 3 líneas cada uno). La gente no lee textos largos. Habla con sazón, chispa, calidez y ve al grano.
2. PERSONALIDAD Y CHARLA: Si te saludan o preguntan cosas como "cómo vas", "qué haces", "hola", responde con simpatía y chispa mexicana en 1 o 2 líneas (ej: "¡Hola, mi corazón! Aquí con los comales prendidos y el sazón a mil 🔥 ¿Qué antojito tienes hoy?").
3. PREGUNTAS POR PRODUCTOS NO DISPONIBLES (ej: Bebidas, postres que no estén en carta, etc.):
   - Si el cliente pregunta "¿qué bebidas tienes?" o por algún producto que no esté en el catálogo disponible, responde con sinceridad y buena onda: explícale que por ahora en la app nuestra cocina se enfoca al 100% en los tacos y platillos mexicanos calientes más sabrosos de Bucaramanga y que no hay bebidas en la carta en este momento. ¡Y anímalo a consentirse con unos buenos tacos!
   - NO inventes bebidas ni agregues IDs si no hay en el catálogo.
4. PREGUNTAS SOBRE EL CREADOR O LA APP: Si preguntan quién es el desarrollador o creador de la app de La Diabla, responde con orgullo: fue desarrollada por Sebastián (conocido como SebasDevs / @SebasDevs01), el talentoso desarrollador de software que creó toda la plataforma y app de La Diabla.
5. RECOMENDACIONES: Recomienda de 1 a 3 platillos que encajen con su antojo.
6. FORMATO DE IDs: Si recomiendas platillos existentes que estén en el catálogo arriba para que el cliente los agregue, incluye al puro final en una línea separada:
IDs:[id1, id2]
(Si la pregunta es casual, de bebidas no disponibles, o charla general, NO incluyas IDs:[]).`;

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

