// functions/index.js
// Cloud Functions para La Diabla — Firebase Functions v2
const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
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
