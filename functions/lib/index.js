"use strict";
/**
 * La Diabla — Cloud Functions para FCM
 * Dispara notificaciones push al cliente cuando el estado del pedido cambia.
 *
 * Trigger: onDocumentUpdated("orders/{orderId}")
 * Runtime: Node 18 / Firebase Functions v2
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupExpiredTokens = exports.onOrderStatusChanged = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
// Inicializar Firebase Admin SDK (una sola vez)
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
// ─── Mapa de estados → payload de notificación ────────────────────────────────
const STATUS_NOTIFICATIONS = {
    confirmed: {
        title: "✅ ¡Pedido confirmado!",
        body: "Estamos procesando tu pedido en La Diabla 🌮",
        emoji: "✅",
    },
    preparing: {
        title: "👨‍🍳 ¡Tu pedido está en preparación!",
        body: "Nuestro chef está cocinando con todo el sazón mexicano 🌶️🔥",
        emoji: "👨‍🍳",
    },
    ready: {
        title: "🔔 ¡Pedido listo!",
        body: "Tu pedido está listo y será recogido por el repartidor ahora mismo",
        emoji: "🔔",
    },
    assigned: {
        title: "🛵 ¡Repartidor asignado!",
        body: "Un repartidor fue asignado a tu pedido de La Diabla",
        emoji: "🛵",
    },
    on_the_way: {
        title: "🛵 ¡El repartidor va en camino!",
        body: "Tu comida de La Diabla está en ruta hacia tu puerta 🔥",
        emoji: "🛵",
    },
    delivered: {
        title: "✅ ¡Pedido entregado! ¡Buen provecho!",
        body: "¿Qué tal estuvo tu experiencia? Califica al repartidor y la comida 🌮⭐",
        emoji: "✅",
    },
    cancelled: {
        title: "❌ Tu pedido fue cancelado",
        body: "Lamentamos el inconveniente. Contáctanos al +57 320 221 2856 🌶️",
        emoji: "❌",
    },
};
// ─── Función principal ────────────────────────────────────────────────────────
exports.onOrderStatusChanged = (0, firestore_1.onDocumentUpdated)({
    document: "orders/{orderId}",
    region: "us-central1",
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g;
    const orderId = event.params.orderId;
    const beforeData = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const afterData = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!beforeData || !afterData) {
        firebase_functions_1.logger.warn(`[FCM] Datos inválidos para orderId=${orderId}`);
        return;
    }
    const prevStatus = (_c = beforeData.status) !== null && _c !== void 0 ? _c : "";
    const newStatus = (_d = afterData.status) !== null && _d !== void 0 ? _d : "";
    // Ignorar si el estado no cambió
    if (prevStatus === newStatus) {
        firebase_functions_1.logger.info(`[FCM] Sin cambio de estado para orderId=${orderId}`);
        return;
    }
    firebase_functions_1.logger.info(`[FCM] Orden ${orderId}: "${prevStatus}" → "${newStatus}"`);
    // Obtener el payload correspondiente al nuevo estado
    const payload = STATUS_NOTIFICATIONS[newStatus];
    if (!payload) {
        firebase_functions_1.logger.info(`[FCM] Estado "${newStatus}" no requiere notificación.`);
        return;
    }
    // Obtener userId de la orden
    const userId = (_e = afterData.userId) !== null && _e !== void 0 ? _e : "";
    if (!userId) {
        firebase_functions_1.logger.warn(`[FCM] Orden ${orderId} sin userId. No se puede notificar.`);
        return;
    }
    // Leer el token FCM del usuario desde Firestore
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
        firebase_functions_1.logger.warn(`[FCM] Usuario ${userId} no encontrado en Firestore.`);
        return;
    }
    const fcmToken = (_f = userDoc.data()) === null || _f === void 0 ? void 0 : _f.fcmToken;
    if (!fcmToken) {
        firebase_functions_1.logger.warn(`[FCM] Usuario ${userId} no tiene fcmToken registrado.`);
        return;
    }
    // Construir el mensaje FCM
    const shortOrderId = orderId.length > 6
        ? orderId.slice(-6).toUpperCase()
        : orderId.toUpperCase();
    const message = {
        token: fcmToken,
        notification: {
            title: payload.title,
            body: payload.body,
        },
        android: {
            notification: {
                channelId: "la_diabla_orders",
                priority: "high",
                color: "#DC2626",
                clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
            priority: "high",
        },
        apns: {
            payload: {
                aps: {
                    badge: 1,
                    sound: "default",
                },
            },
        },
        data: Object.assign({ type: "order_status", orderId: orderId, status: newStatus, shortOrderId }, ((_g = payload.data) !== null && _g !== void 0 ? _g : {})),
    };
    try {
        const response = await messaging.send(message);
        firebase_functions_1.logger.info(`[FCM] ✅ Push enviado a usuario ${userId} (orderId=${orderId}, status=${newStatus}). messageId=${response}`);
        // Guardar la notificación en Firestore para el historial en la app
        await db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .add({
            type: "order_status",
            title: payload.title,
            body: payload.body,
            emoji: payload.emoji,
            orderId,
            status: newStatus,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        firebase_functions_1.logger.info(`[FCM] 📝 Notificación guardada en historial del usuario ${userId}`);
    }
    catch (err) {
        firebase_functions_1.logger.error(`[FCM] ❌ Error enviando push a ${userId}:`, err);
        // Si el token es inválido (registration-token-not-registered), limpiar de Firestore
        const errorCode = err.code;
        if (errorCode === "messaging/registration-token-not-registered" ||
            errorCode === "messaging/invalid-registration-token") {
            firebase_functions_1.logger.warn(`[FCM] Token inválido para userId=${userId}. Eliminando de Firestore...`);
            await db.collection("users").doc(userId).update({
                fcmToken: admin.firestore.FieldValue.delete(),
            });
        }
    }
});
// ─── Función de limpieza de tokens ────────────────────────────────────────────
// Limpia automáticamente los tokens FCM expirados cuando detecta errores
exports.cleanupExpiredTokens = (0, firestore_1.onDocumentUpdated)({
    document: "users/{userId}",
    region: "us-central1",
}, async (event) => {
    var _a, _b;
    const beforeData = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const afterData = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    // Solo interesa si el fcmToken fue eliminado (limpieza)
    if ((beforeData === null || beforeData === void 0 ? void 0 : beforeData.fcmToken) && !(afterData === null || afterData === void 0 ? void 0 : afterData.fcmToken)) {
        const userId = event.params.userId;
        firebase_functions_1.logger.info(`[FCM] Token limpiado para userId=${userId}`);
    }
});
//# sourceMappingURL=index.js.map