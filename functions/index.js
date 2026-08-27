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
  onTheWay:    { title: "🛵 ¡Va en camino!",           body: "El repartidor ya salió con tu comida. ¡Ya casi! 🌶️" },
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
      notification: {
        channelId: "la_diabla_orders",
        priority: "high",
        defaultSound: true,
        defaultVibrateTimings: true,
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
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
  };

  try {
    await messaging.send(message);
    console.log(`[onOrderStatusChanged] Push enviado a ${userId}: ${after.status}`);

    // Guardar en el historial de notificaciones del usuario
    await db.collection("users").doc(userId).collection("notifications").add({
      title: msg.title,
      body: msg.body,
      orderId: event.params.orderId,
      status: after.status,
      createdAt: FieldValue.serverTimestamp(),
      isRead: false,
    });
  } catch (err) {
    console.error(`[onOrderStatusChanged] Error enviando push: ${err}`);
  }

  return null;
});

// ─── 2. Push a TODOS los repartidores cuando entra un pedido nuevo ───────────
exports.onNewOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data.data();

  // Solo notificar si el pedido está pendiente y el pago fue exitoso
  if (order.status !== "pending") return null;
  if (order.paymentStatus !== "paid" && order.paymentMethod !== "cash" && order.paymentMethod !== "dataphone") return null;

  // Obtener todos los usuarios con rol repartidor
  const driversSnap = await db.collection("users")
    .where("role", "==", "driver")
    .where("fcmToken", "!=", null)
    .get();

  if (driversSnap.empty) {
    console.log("[onNewOrderCreated] No hay repartidores con FCM token");
    return null;
  }

  const tokens = driversSnap.docs
    .map(doc => doc.data().fcmToken)
    .filter(Boolean);

  const shortId = event.params.orderId.substring(0, 6).toUpperCase();
  const address = order.formattedAddress || "Dirección del cliente";
  const total   = `$${(order.total || 0).toLocaleString("es-CO")} COP`;

  const multicastMessage = {
    tokens,
    notification: {
      title: `🔔 Nuevo pedido #${shortId}`,
      body: `${total} — ${address}`,
    },
    android: {
      notification: {
        channelId: "la_diabla_orders",
        priority: "high",
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
    data: {
      orderId: event.params.orderId,
      type: "new_order",
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
  };

  try {
    const response = await messaging.sendEachForMulticast(multicastMessage);
    console.log(`[onNewOrderCreated] Push enviado a ${response.successCount}/${tokens.length} repartidores`);
  } catch (err) {
    console.error(`[onNewOrderCreated] Error enviando push masivo: ${err}`);
  }

  return null;
});

// ─── 3. Acumular ganancias del repartidor al entregar ───────────────────────
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
