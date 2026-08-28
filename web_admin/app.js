// Firebase Configuration for La Diabla App
const firebaseConfig = {
  apiKey: "AIzaSyALoHHu4zV9IpwAljGHWjHskoqEvHSKMFQ",
  authDomain: "ladiabla-11718.firebaseapp.com",
  projectId: "ladiabla-11718",
  storageBucket: "ladiabla-11718.firebasestorage.app",
  messagingSenderId: "724540997267",
  appId: "1:724540997267:web:c7932bc391104f4886612d"
};

// Initialize Firebase
let db = null;
try {
  firebase.initializeApp(firebaseConfig);
  db = firebase.firestore();
  console.log("🔥 Firebase initialized successfully!");
} catch (e) {
  console.error("Firebase init error:", e);
}

// State
let allOrders = [];
let allRefunds = [];
let allCoupons = [];
let currentFilter = 'all';
let previousOrderCount = 0;
let isAudioUnlocked = false;

// Audio Chime Generator using Web Audio API
function playOrderChime() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = 'triangle';
    osc.frequency.setValueAtTime(587.33, ctx.currentTime); // D5
    osc.frequency.setValueAtTime(880.00, ctx.currentTime + 0.15); // A5
    osc.frequency.setValueAtTime(1174.66, ctx.currentTime + 0.3); // D6

    gain.gain.setValueAtTime(0.3, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.8);

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.start();
    osc.stop(ctx.currentTime + 0.8);
  } catch (e) {
    console.log("Audio play error:", e);
  }
}

// Format COP currency
function formatCOP(num) {
  if (!num) return '$0';
  return '$' + Math.round(num).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
}

// Format Date / Time
function formatTime(timestamp) {
  if (!timestamp) return 'Hace un momento';
  const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
  return date.toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit', hour12: true });
}

// Progression Mapping
const statusFlow = {
  'pending': { next: 'confirmed', label: '✅ Confirmar Pedido', btnClass: 'btn-confirm' },
  'confirmed': { next: 'preparing', label: '🍳 Mandar a Cocina', btnClass: 'btn-cook' },
  'preparing': { next: 'ready', label: '📦 Marcar Listo / Despachar', btnClass: 'btn-ready' }
};

const statusBadges = {
  'pending': { label: '⏳ PENDIENTE', color: '#F59E0B', bg: 'rgba(245, 158, 11, 0.15)' },
  'confirmed': { label: '✅ CONFIRMADO', color: '#3B82F6', bg: 'rgba(59, 130, 246, 0.15)' },
  'preparing': { label: '🍳 PREPARANDO', color: '#8B5CF6', bg: 'rgba(139, 92, 246, 0.15)' },
  'ready': { label: '📦 LISTO PARA DESPACHO', color: '#06B6D4', bg: 'rgba(6, 182, 212, 0.15)' },
  'assigned': { label: '🛵 REPARTIDOR ASIGNADO', color: '#0284C7', bg: 'rgba(2, 132, 199, 0.15)' },
  'onTheWay': { label: '🛵 EN RUTA', color: '#10B981', bg: 'rgba(16, 185, 129, 0.15)' },
  'on_the_way': { label: '🛵 EN RUTA', color: '#10B981', bg: 'rgba(16, 185, 129, 0.15)' },
  'delivered': { label: '🎉 ENTREGADO', color: '#16A34A', bg: 'rgba(22, 163, 74, 0.15)' },
  'cancelled': { label: '❌ CANCELADO', color: '#EF4444', bg: 'rgba(239, 68, 68, 0.15)' }
};

// Ensure Firebase Auth session is active
async function ensureAdminAuth() {
  if (typeof firebase !== 'undefined' && firebase.auth) {
    try {
      if (!firebase.auth().currentUser) {
        await firebase.auth().signInWithEmailAndPassword('appladiabla@gmail.com', 'diablaadmin1')
          .catch(() => firebase.auth().signInAnonymously());
      }
    } catch (_) {}
  }
}

// Listen to Firestore in Realtime
function initRealtimeOrders() {
  if (!db) {
    renderFallbackDemo();
    return;
  }

  ensureAdminAuth().then(() => {
    // Escuchar colección de órdenes en tiempo real
    db.collection('orders')
      .onSnapshot((snapshot) => {
        const orders = [];
        snapshot.forEach(doc => {
          orders.push({ id: doc.id, ...doc.data() });
        });

        // Ordenar descendentemente por fecha
        orders.sort((a, b) => {
          const tA = a.createdAt?.toDate ? a.createdAt.toDate().getTime() : (a.createdAt ? new Date(a.createdAt).getTime() : 0);
          const tB = b.createdAt?.toDate ? b.createdAt.toDate().getTime() : (b.createdAt ? new Date(b.createdAt).getTime() : 0);
          return tB - tA;
        });

        if (previousOrderCount > 0 && orders.length > previousOrderCount) {
          playOrderChime();
          showNotificationToast("🔔 ¡Nuevo pedido recibido en La Diabla!");
        }
        previousOrderCount = orders.length;

        allOrders = orders;
        updateStats();
        renderOrders();
      }, (error) => {
        console.warn("Firestore listener error:", error);
        if (allOrders.length === 0) renderFallbackDemo();
      });

    // Refunds listener
    db.collection('refunds')
      .onSnapshot((snapshot) => {
        const refunds = [];
        snapshot.forEach(doc => {
          refunds.push({ id: doc.id, ...doc.data() });
        });
        refunds.sort((a, b) => {
          const tA = a.createdAt?.toDate ? a.createdAt.toDate().getTime() : 0;
          const tB = b.createdAt?.toDate ? b.createdAt.toDate().getTime() : 0;
          return tB - tA;
        });
        allRefunds = refunds;
        const countEl = document.getElementById('refundCount');
        if (countEl) {
          const pendingCount = refunds.filter(r => r.status === 'pending').length;
          countEl.innerText = pendingCount;
        }
        if (currentFilter === 'refunds') {
          renderRefunds();
        }
      }, (e) => console.warn("Refunds listener error:", e));

    // Coupons listener
    db.collection('coupons').onSnapshot((snapshot) => {
      const coupons = [];
      snapshot.forEach(doc => {
        coupons.push({ id: doc.id, ...doc.data() });
      });
      allCoupons = coupons;
      renderCoupons();
    }, () => {});
  });
}

function updateStats() {
  const totalSales = allOrders
    .filter(o => o.status !== 'cancelled')
    .reduce((sum, o) => sum + (o.total || 0), 0);

  const activeCount = allOrders
    .filter(o => ['pending', 'confirmed', 'preparing', 'ready', 'onTheWay', 'on_the_way'].includes(o.status)).length;

  const deliveredCount = allOrders
    .filter(o => o.status === 'delivered').length;

  const totalSalesEl = document.getElementById('statTotalSales');
  const activeOrdersEl = document.getElementById('statActiveOrders');
  const deliveredEl = document.getElementById('statDelivered');
  const totalOrdersEl = document.getElementById('statTotalOrders');

  if (totalSalesEl) totalSalesEl.innerText = formatCOP(totalSales);
  if (activeOrdersEl) activeOrdersEl.innerText = activeCount;
  if (deliveredEl) deliveredEl.innerText = deliveredCount;
  if (totalOrdersEl) totalOrdersEl.innerText = allOrders.length;
}

function renderOrders() {
  const grid = document.getElementById('ordersGrid');
  const search = document.getElementById('searchOrderInput').value.toLowerCase().trim();

  let filtered = allOrders;
  if (currentFilter !== 'all') {
    filtered = filtered.filter(o => {
      if (currentFilter === 'onTheWay' || currentFilter === 'on_the_way') {
        return o.status === 'onTheWay' || o.status === 'on_the_way' || o.status === 'assigned';
      }
      return o.status === currentFilter;
    });
  }
  if (search) {
    filtered = filtered.filter(o => {
      const addr = o.formattedAddress || (o.address && o.address.formattedAddress) || (typeof o.address === 'string' ? o.address : '');
      const cust = o.customerName || o.userName || o.userId || '';
      return o.id.toLowerCase().includes(search) ||
        addr.toLowerCase().includes(search) ||
        cust.toLowerCase().includes(search);
    });
  }

  if (filtered.length === 0) {
    grid.innerHTML = `
      <div style="grid-column: 1 / -1; text-align: center; padding: 4rem 1rem; color: var(--text-muted);">
        <span style="font-size: 3.5rem;">🌮</span>
        <h3 class="diabla-font" style="font-size: 1.6rem; color: white; margin-top: 1rem;">No hay órdenes en esta categoría</h3>
        <p>Los nuevos pedidos entrarán automáticamente aquí en tiempo real 🔥</p>
      </div>
    `;
    return;
  }

  grid.innerHTML = filtered.map(order => {
    const status = order.status || 'pending';
    const badge = statusBadges[status] || statusBadges['pending'];
    const flow = statusFlow[status];
    const shortId = order.id.length > 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase();
    const addressStr = order.formattedAddress || (order.address && order.address.formattedAddress) || (typeof order.address === 'string' ? order.address : 'Dirección de entrega');
    const customer = order.customerName || order.userName || order.userId || 'Cliente La Diabla';
    const items = order.items || [];

    const itemsHtml = items.map(item => {
      const name = item.productName || (item.product ? item.product.name : (item.name || 'Platillo'));
      const price = item.price || (item.product ? item.product.price : 0);
      const qty = item.quantity || 1;
      return `
        <div class="order-item-row">
          <span><strong>${qty}x</strong> ${name}</span>
          <span>${formatCOP(price * qty)}</span>
        </div>
      `;
    }).join('');

    return `
      <div class="order-card status-${status}">
        <div>
          <div class="order-top">
            <div>
              <span class="order-id diabla-font">PEDIDO #${shortId}</span>
              <div class="order-time">🕒 ${formatTime(order.createdAt)}</div>
            </div>
            <span class="status-badge" style="background: ${badge.bg}; color: ${badge.color};">
              ${badge.label}
            </span>
          </div>

          <div class="order-customer">
            <div class="customer-name">👤 ${customer}</div>
            <div class="customer-address">📍 ${addressStr}</div>
            ${order.customerPhone ? `<div style="font-size: 0.85rem; color: #60A5FA; margin-top: 2px;">📞 ${order.customerPhone}</div>` : ''}
            ${order.driverName ? `<div style="font-size: 0.85rem; color: #10B981; margin-top: 2px;">🛵 Repartidor: ${order.driverName}</div>` : ''}
            ${order.cancelReason ? `<div style="font-size: 0.85rem; color: #F87171; margin-top: 6px; font-weight: bold; background: rgba(220, 38, 38, 0.1); padding: 6px 10px; border-radius: 8px; border: 1px solid rgba(220, 38, 38, 0.2);">❌ Motivo: ${order.cancelReason}</div>` : ''}
          </div>

          <div class="order-items-list">
            ${itemsHtml || '<div style="color: var(--text-muted);">Sin detalles de productos</div>'}
          </div>
        </div>

        <div>
          <div class="order-total-row">
            <div>
              <div style="font-size: 0.75rem; color: var(--text-muted);">MÉTODO: ${(order.paymentMethod || 'Efectivo').toUpperCase()}</div>
              ${order.couponCode ? `<div style="font-size: 0.75rem; color: #16A34A;">🎟️ Cupón: ${order.couponCode}</div>` : ''}
              ${order.deliveryProofUrl ? `<div style="margin-top: 6px;"><a href="${order.deliveryProofUrl}" target="_blank" style="font-size: 0.75rem; color: #10B981; font-weight: bold; text-decoration: underline;">📸 Ver foto de entrega</a></div>` : ''}
            </div>
            <div class="order-total diabla-font">${formatCOP(order.total || 0)}</div>
          </div>

          <div class="order-actions">
            ${flow ? `
              <button class="action-btn ${flow.btnClass}" onclick="advanceStatus('${order.id}', '${flow.next}')">
                ${flow.label}
              </button>
            ` : ''}
            ${status !== 'cancelled' && status !== 'delivered' ? `
              <button class="action-btn btn-cancel" onclick="cancelOrder('${order.id}')" title="Cancelar Pedido">
                ❌
              </button>
            ` : ''}
          </div>
        </div>
      </div>
    `;
  }).join('');
}

// Status Advancement
async function advanceStatus(orderId, nextStatus) {
  if (!db) {
    const order = allOrders.find(o => o.id === orderId);
    if (order) {
      order.status = nextStatus;
      updateStats();
      renderOrders();
    }
    return;
  }

  try {
    await db.collection('orders').doc(orderId).set({
      status: nextStatus,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    showNotificationToast(`✅ Pedido actualizado a ${statusBadges[nextStatus]?.label ?? nextStatus}`);
  } catch (e) {
    alert("Error al actualizar estado: " + e.message);
  }
}

async function cancelOrder(orderId) {
  const reason = prompt("Por favor ingresa el motivo de la cancelación de este pedido:");
  if (reason === null) return; // Se canceló la ventana
  if (!reason.trim()) {
    alert("Debes ingresar un motivo de cancelación obligatorio.");
    return;
  }

  if (!db) {
    const order = allOrders.find(o => o.id === orderId);
    if (order) {
      order.status = 'cancelled';
      order.cancelReason = reason;
      updateStats();
      renderOrders();
    }
    return;
  }

  try {
    await db.collection('orders').doc(orderId).set({
      status: 'cancelled',
      cancelReason: reason,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    showNotificationToast("❌ Pedido cancelado");
  } catch (e) {
    alert("Error al cancelar: " + e.message);
  }
}

// Toast notification helper
function showNotificationToast(msg) {
  const toast = document.createElement('div');
  toast.style.position = 'fixed';
  toast.style.bottom = '24px';
  toast.style.right = '24px';
  toast.style.background = '#DC2626';
  toast.style.color = '#FFF';
  toast.style.padding = '14px 24px';
  toast.style.borderRadius = '14px';
  toast.style.fontWeight = 'bold';
  toast.style.boxShadow = '0 10px 30px rgba(0,0,0,0.5)';
  toast.style.zIndex = '9999';
  toast.innerText = msg;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 3500);
}

// Filter buttons
function setFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.filter === filter);
  });

  const ordersGrid = document.getElementById('ordersGrid');
  const refundsGrid = document.getElementById('refundsGrid');

  if (filter === 'refunds') {
    if (ordersGrid) ordersGrid.style.display = 'none';
    if (refundsGrid) refundsGrid.style.display = 'grid';
    renderRefunds();
  } else {
    if (ordersGrid) ordersGrid.style.display = 'grid';
    if (refundsGrid) refundsGrid.style.display = 'none';
    renderOrders();
  }
}

// Render Refunds Section
function renderRefunds() {
  const container = document.getElementById('refundsGrid');
  if (!container) return;

  if (allRefunds.length === 0) {
    container.innerHTML = `
      <div style="grid-column: 1 / -1; text-align: center; padding: 3rem; background: var(--bg-card); border-radius: 16px;">
        <div style="font-size: 3rem; margin-bottom: 0.5rem;">🎉</div>
        <h3 style="color: var(--text-main); margin-bottom: 0.5rem;">No hay solicitudes de reembolso pendientes</h3>
        <p style="color: var(--text-muted); font-size: 0.9rem;">Todas las transacciones y pedidos se encuentran al día.</p>
      </div>
    `;
    return;
  }

  container.innerHTML = allRefunds.map(ref => {
    const isPending = ref.status === 'pending';
    const statusColor = isPending ? '#F59E0B' : (ref.status === 'processed' ? '#16A34A' : '#EF4444');
    const statusLabel = isPending ? '⏳ PENDIENTE DE APROBACIÓN' : (ref.status === 'processed' ? '✅ PROCESADO' : '❌ RECHAZADO');

    return `
      <div class="order-card" style="border-top: 4px solid ${statusColor};">
        <div class="order-card-header">
          <div>
            <span class="order-id">REEMBOLSO #${(ref.id || '').substring(0, 6).toUpperCase()}</span>
            <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 2px;">
              Pedido original: <strong>#${(ref.orderId || '').substring(0, 6).toUpperCase()}</strong>
            </div>
          </div>
          <span style="font-size: 0.75rem; font-weight: bold; padding: 4px 8px; border-radius: 6px; background: ${statusColor}22; color: ${statusColor};">
            ${statusLabel}
          </span>
        </div>

        <div style="margin: 12px 0; padding: 10px; background: rgba(0,0,0,0.2); border-radius: 10px;">
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <span style="color: var(--text-muted); font-size: 0.85rem;">Monto a Reembolsar:</span>
            <span class="diabla-font" style="font-size: 1.3rem; color: #16A34A;">${formatCOP(ref.amount)}</span>
          </div>
        </div>

        <div class="order-details">
          <div style="font-size: 0.85rem; margin-bottom: 6px;">
            👤 <strong>Cliente:</strong> ${ref.userName || 'Cliente'} (${ref.userPhone || 'Sin teléfono'})
          </div>
          <div style="font-size: 0.85rem; margin-bottom: 6px;">
            💳 <strong>Método Destino:</strong> <span style="color: #F59E0B; font-weight: bold;">${ref.paymentMethod || 'Cuenta original'}</span>
          </div>
          <div style="font-size: 0.85rem; margin-bottom: 6px;">
            🔢 <strong>Detalles:</strong> ${ref.accountDetails || 'N/A'}
          </div>
          <div style="font-size: 0.85rem; color: var(--text-muted); margin-top: 8px;">
            📝 <strong>Motivo:</strong> "${ref.reason || 'Cancelación de pedido'}"
          </div>
        </div>

        ${isPending ? `
          <div style="display: flex; gap: 8px; margin-top: 14px;">
            <button onclick="processRefund('${ref.id}', '${ref.orderId}', '${ref.userId}', ${ref.amount}, '${ref.userName || 'Cliente'}')" 
                    class="btn-primary" style="flex: 1; padding: 10px; font-size: 0.85rem; background: #16A34A; border: none; border-radius: 10px; color: white; font-weight: bold; cursor: pointer;">
              ✅ Procesar Reembolso
            </button>
            <button onclick="rejectRefund('${ref.id}', '${ref.orderId}')" 
                    class="btn-secondary" style="padding: 10px 14px; font-size: 0.85rem; background: rgba(239, 68, 68, 0.2); color: #EF4444; border: 1px solid #EF4444; border-radius: 10px; cursor: pointer;">
              ❌ Rechazar
            </button>
          </div>
        ` : `
          <div style="margin-top: 12px; font-size: 0.8rem; color: var(--text-muted); text-align: center;">
            Solicitud gestionada por la administración
          </div>
        `}
      </div>
    `;
  }).join('');
}

// Action: Process Refund
async function processRefund(refundId, orderId, userId, amount, userName) {
  if (!confirm(`¿Confirmas procesar el reembolso de ${formatCOP(amount)} a ${userName}?`)) return;

  try {
    if (db) {
      await db.collection('refunds').doc(refundId).update({
        status: 'processed',
        processedAt: firebase.firestore.FieldValue.serverTimestamp()
      });

      if (orderId) {
        await db.collection('orders').doc(orderId).update({
          refundStatus: 'processed',
          status: 'cancelled',
          paymentStatus: 'refunded',
          updatedAt: firebase.firestore.FieldValue.serverTimestamp()
        });
      }

      // Notificación al usuario en Firestore
      if (userId) {
        await db.collection('notifications').add({
          userId: userId,
          orderId: orderId,
          title: '✅ Reembolso Procesado con Éxito',
          body: `Tu reembolso por ${formatCOP(amount)} ha sido procesado exitosamente por la administración.`,
          emoji: '💰',
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
          isRead: false
        });
      }
    }
    showNotificationToast(`✅ Reembolso #${refundId.substring(0, 6)} procesado`);
  } catch (e) {
    alert("Error al procesar reembolso: " + e.message);
  }
}

// Action: Reject Refund
async function rejectRefund(refundId, orderId) {
  const reason = prompt("Indica el motivo del rechazo del reembolso:");
  if (reason === null) return;

  try {
    if (db) {
      await db.collection('refunds').doc(refundId).update({
        status: 'rejected',
        rejectReason: reason,
        rejectedAt: firebase.firestore.FieldValue.serverTimestamp()
      });
      if (orderId) {
        await db.collection('orders').doc(orderId).update({
          refundStatus: 'rejected',
          updatedAt: firebase.firestore.FieldValue.serverTimestamp()
        });
      }
    }
    showNotificationToast(`Solicitud de reembolso rechazada`);
  } catch (e) {
    alert("Error al rechazar reembolso: " + e.message);
  }
}

// Fallback demo data if offline
function renderFallbackDemo() {
  allOrders = [
    {
      id: "ord_diabla_101",
      createdAt: new Date(),
      status: "pending",
      customerName: "Lucitor Gamer",
      customerPhone: "315 889 4521",
      address: { formattedAddress: "Cl. 59 # 39W-24, Estoraques 1, Bucaramanga" },
      paymentMethod: "Efectivo",
      couponCode: "ENVIOGRATIS",
      total: 32000,
      items: [
        { quantity: 2, product: { name: "Tacos al Pastor Diabólicos", price: 11000 } },
        { quantity: 1, product: { name: "Quesadilla Especial de Birria", price: 10000 } }
      ]
    },
    {
      id: "ord_diabla_102",
      createdAt: new Date(Date.now() - 15 * 60000),
      status: "preparing",
      customerName: "Carolina Mendoza",
      customerPhone: "318 420 7711",
      address: { formattedAddress: "Carrera 21 # 55-12, Mutis, Bucaramanga" },
      paymentMethod: "Mercado Pago",
      total: 45000,
      items: [
        { quantity: 1, product: { name: "Super Burrito Habanero", price: 25000 } },
        { quantity: 2, product: { name: "Margarita de Fresa & Jalapeño", price: 10000 } }
      ]
    }
  ];
  updateStats();
  renderOrders();
}

// Init
window.addEventListener('DOMContentLoaded', () => {
  if (sessionStorage.getItem('diabla_admin_auth') !== 'true') {
    window.location.href = 'login.html';
    return;
  }
  document.body.addEventListener('click', () => isAudioUnlocked = true, { once: true });
  initRealtimeOrders();
});
