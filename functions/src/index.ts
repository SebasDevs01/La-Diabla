/**
 * La Diabla — Cloud Functions para FCM
 * Dispara notificaciones push al cliente cuando el estado del pedido cambia.
 *
 * Trigger: onDocumentUpdated("orders/{orderId}")
 * Runtime: Node 18 / Firebase Functions v2
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

// Inicializar Firebase Admin SDK (una sola vez)
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ─── Tipos ────────────────────────────────────────────────────────────────────

interface NotificationPayload {
  title: string;
  body: string;
  emoji: string;
  data?: Record<string, string>;
}

// ─── Mapa de estados → payload de notificación ────────────────────────────────

const STATUS_NOTIFICATIONS: Record<string, NotificationPayload> = {
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

export const onOrderStatusChanged = onDocumentUpdated(
  {
    document: "orders/{orderId}",
    region: "us-central1",
  },
  async (event) => {
    const orderId = event.params.orderId;

    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!beforeData || !afterData) {
      logger.warn(`[FCM] Datos inválidos para orderId=${orderId}`);
      return;
    }

    const prevStatus: string = beforeData.status ?? "";
    const newStatus: string = afterData.status ?? "";

    // Ignorar si el estado no cambió
    if (prevStatus === newStatus) {
      logger.info(`[FCM] Sin cambio de estado para orderId=${orderId}`);
      return;
    }

    logger.info(
      `[FCM] Orden ${orderId}: "${prevStatus}" → "${newStatus}"`
    );

    // Obtener el payload correspondiente al nuevo estado
    const payload = STATUS_NOTIFICATIONS[newStatus];
    if (!payload) {
      logger.info(`[FCM] Estado "${newStatus}" no requiere notificación.`);
      return;
    }

    // Obtener userId de la orden
    const userId: string = afterData.userId ?? "";
    if (!userId) {
      logger.warn(`[FCM] Orden ${orderId} sin userId. No se puede notificar.`);
      return;
    }

    // Leer el token FCM del usuario desde Firestore
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      logger.warn(`[FCM] Usuario ${userId} no encontrado en Firestore.`);
      return;
    }

    const fcmToken: string | undefined = userDoc.data()?.fcmToken;
    if (!fcmToken) {
      logger.warn(
        `[FCM] Usuario ${userId} no tiene fcmToken registrado.`
      );
      return;
    }

    // Construir el mensaje FCM
    const shortOrderId = orderId.length > 6
      ? orderId.slice(-6).toUpperCase()
      : orderId.toUpperCase();

    const message: admin.messaging.Message = {
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
      data: {
        type: "order_status",
        orderId: orderId,
        status: newStatus,
        shortOrderId,
        ...(payload.data ?? {}),
      },
    };

    try {
      const response = await messaging.send(message);
      logger.info(
        `[FCM] ✅ Push enviado a usuario ${userId} (orderId=${orderId}, status=${newStatus}). messageId=${response}`
      );

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

      logger.info(
        `[FCM] 📝 Notificación guardada en historial del usuario ${userId}`
      );
    } catch (err) {
      logger.error(`[FCM] ❌ Error enviando push a ${userId}:`, err);

      // Si el token es inválido (registration-token-not-registered), limpiar de Firestore
      const errorCode = (err as admin.FirebaseError).code;
      if (
        errorCode === "messaging/registration-token-not-registered" ||
        errorCode === "messaging/invalid-registration-token"
      ) {
        logger.warn(
          `[FCM] Token inválido para userId=${userId}. Eliminando de Firestore...`
        );
        await db.collection("users").doc(userId).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
      }
    }
  }
);

// ─── Función de limpieza de tokens ────────────────────────────────────────────
// Limpia automáticamente los tokens FCM expirados cuando detecta errores

export const cleanupExpiredTokens = onDocumentUpdated(
  {
    document: "users/{userId}",
    region: "us-central1",
  },
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    // Solo interesa si el fcmToken fue eliminado (limpieza)
    if (beforeData?.fcmToken && !afterData?.fcmToken) {
      const userId = event.params.userId;
      logger.info(
        `[FCM] Token limpiado para userId=${userId}`
      );
    }
  }
);
