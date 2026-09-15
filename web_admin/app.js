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
let storage = null;
try {
  firebase.initializeApp(firebaseConfig);
  db = firebase.firestore();
  storage = firebase.storage();
  console.log("🔥 Firebase initialized successfully!");
} catch (e) {
  console.error("Firebase init error:", e);
}

// State
let allOrders = [];
let allRefunds = [];
let allCoupons = [];
let allDriverUsers = [];
let currentFilter = 'all';
let evidenceSubFilter = 'proofs'; // 'proofs' | 'plates'
let previousOrderCount = 0;
let isAudioUnlocked = false;

// Products & Menu State
let allProducts = [];
let currentAdminView = 'orders'; // 'orders' | 'products'
let currentProductCategory = 'all';
let productSearchQuery = '';
let currentModalIngredients = [];
let selectedImageFile = null;

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
  'pending':   { next: 'confirmed', label: '<span class="material-symbols-rounded md-18">check_circle</span> Confirmar Pedido', btnClass: 'btn-confirm' },
  'confirmed': { next: 'preparing', label: '<span class="material-symbols-rounded md-18">skillet</span> Mandar a Cocina',   btnClass: 'btn-cook' },
  'preparing': { next: 'ready',     label: '<span class="material-symbols-rounded md-18">inventory_2</span> Marcar Listo',         btnClass: 'btn-ready' }
};

const statusBadges = {
  'pending':    { label: '<span class="material-symbols-rounded md-16">hourglass_top</span> PENDIENTE',          color: '#F59E0B', bg: 'rgba(245, 158, 11, 0.15)' },
  'confirmed':  { label: '<span class="material-symbols-rounded md-16">check_circle</span> CONFIRMADO',           color: '#3B82F6', bg: 'rgba(59, 130, 246, 0.15)' },
  'preparing':  { label: '<span class="material-symbols-rounded md-16">skillet</span> PREPARANDO',            color: '#8B5CF6', bg: 'rgba(139, 92, 246, 0.15)' },
  'ready':      { label: '<span class="material-symbols-rounded md-16">inventory_2</span> LISTO PARA DESPACHO',      color: '#06B6D4', bg: 'rgba(6, 182, 212, 0.15)' },
  'assigned':   { label: '<span class="material-symbols-rounded md-16">two_wheeler</span> REPARTIDOR ASIGNADO',    color: '#0284C7', bg: 'rgba(2, 132, 199, 0.15)' },
  'onTheWay':   { label: '<span class="material-symbols-rounded md-16">two_wheeler</span> EN RUTA',                color: '#10B981', bg: 'rgba(16, 185, 129, 0.15)' },
  'on_the_way': { label: '<span class="material-symbols-rounded md-16">two_wheeler</span> EN RUTA',                color: '#10B981', bg: 'rgba(16, 185, 129, 0.15)' },
  'delivered':  { label: '<span class="material-symbols-rounded md-16">task_alt</span> ENTREGADO',            color: '#16A34A', bg: 'rgba(22, 163, 74, 0.15)' },
  'cancelled':  { label: '<span class="material-symbols-rounded md-16">cancel</span> CANCELADO',                     color: '#EF4444', bg: 'rgba(239, 68, 68, 0.15)' }
};

// Ensure Firebase Auth session is active for admin writes
async function ensureAdminAuth() {
  if (typeof firebase !== 'undefined' && firebase.auth) {
    try {
      if (!firebase.auth().currentUser) {
        await firebase.auth().signInWithEmailAndPassword('appladiabla@gmail.com', 'diablaadmin1').catch(async () => {
          await firebase.auth().signInAnonymously().catch(() => {});
        });
      }
    } catch (e) {
      console.warn("Auth initialization note:", e);
    }
  }
}

// Listen to Firestore in Realtime
function initRealtimeOrders() {
  if (!db) {
    renderFallbackDemo();
    return;
  }

  // Escuchar colección de órdenes en tiempo real inmediatamente
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

  // Driver users listener (for plate photos)
  db.collection('users')
    .where('role', '==', 'driver')
    .onSnapshot((snapshot) => {
      const drivers = [];
      snapshot.forEach(doc => {
        const d = doc.data();
        if (d.vehiclePlatePhotoUrl) {
          drivers.push({ id: doc.id, ...d });
        }
      });
      allDriverUsers = drivers;
      if (currentFilter === 'evidence' && evidenceSubFilter === 'plates') {
        renderOrders();
      }
      const evidenceEl = document.getElementById('evidenceCount');
      if (evidenceEl) {
        const proofCount = allOrders.filter(o => !!o.deliveryProofUrl).length;
        evidenceEl.innerText = proofCount + allDriverUsers.length;
      }
    }, () => {});

  // Asegurar sesión administrativa en segundo plano
  ensureAdminAuth();
}

function updateStats() {
  const totalSales = allOrders
    .filter(o => o.status !== 'cancelled')
    .reduce((sum, o) => sum + (o.total || 0), 0);

  const activeCount = allOrders
    .filter(o => ['pending', 'confirmed', 'preparing', 'ready', 'onTheWay', 'on_the_way'].includes(o.status)).length;

  const deliveredCount = allOrders
    .filter(o => o.status === 'delivered').length;

  const evidenceCount = allOrders.filter(o => !!o.deliveryProofUrl).length + allDriverUsers.length;

  const totalSalesEl = document.getElementById('statTotalSales');
  const activeOrdersEl = document.getElementById('statActiveOrders');
  const deliveredEl = document.getElementById('statDelivered');
  const totalOrdersEl = document.getElementById('statTotalOrders');
  const evidenceEl = document.getElementById('evidenceCount');

  if (totalSalesEl) totalSalesEl.innerText = formatCOP(totalSales);
  if (activeOrdersEl) activeOrdersEl.innerText = activeCount;
  if (deliveredEl) deliveredEl.innerText = deliveredCount;
  if (totalOrdersEl) totalOrdersEl.innerText = allOrders.length;
  if (evidenceEl) evidenceEl.innerText = evidenceCount;
}

function renderOrders() {
  const grid = document.getElementById('ordersGrid');
  const search = document.getElementById('searchOrderInput').value.toLowerCase().trim();

  let filtered = allOrders;
  if (currentFilter !== 'all') {
    filtered = filtered.filter(o => {
      if (currentFilter === 'evidence') {
        return !!o.deliveryProofUrl;
      }
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

  if (currentFilter === 'evidence') {
    renderEvidenceView(grid, filtered);
    return;
  }

  if (filtered.length === 0) {
    grid.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-rounded md-48" style="color:var(--text-muted); opacity:0.6; margin-bottom:12px;">ramen_dining</span>
        <h3 class="diabla-font">Sin órdenes en esta categoría</h3>
        <p>Los nuevos pedidos aparecerán aquí en tiempo real</p>
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
              <div class="order-time"><span class="material-symbols-rounded md-16" style="vertical-align:middle;">schedule</span> ${formatTime(order.createdAt)}</div>
            </div>
            <span class="status-badge" style="background: ${badge.bg}; color: ${badge.color};">
              ${badge.label}
            </span>
          </div>

          <div class="order-customer">
            <div class="customer-name"><span class="material-symbols-rounded md-18" style="vertical-align:middle; margin-right:4px;">person</span> ${customer}</div>
            <div class="customer-address"><span class="material-symbols-rounded md-18" style="vertical-align:middle; margin-right:4px;">location_on</span> ${addressStr}</div>
            ${order.customerPhone ? `<div style="font-size: 0.83rem; color: #60A5FA; margin-top: 4px; display:flex; align-items:center; gap:5px;"><span class="material-symbols-rounded md-16">call</span> ${order.customerPhone}</div>` : ''}
            ${order.driverName ? `<div style="font-size: 0.83rem; color: #10B981; margin-top: 4px; display:flex; align-items:center; gap:5px;"><span class="material-symbols-rounded md-16">two_wheeler</span> Repartidor: ${order.driverName}</div>` : ''}
            ${order.cancelReason ? `<div style="font-size: 0.83rem; color: #F87171; margin-top: 6px; font-weight: bold; background: rgba(220, 38, 38, 0.1); padding: 6px 10px; border-radius: 8px; border: 1px solid rgba(220, 38, 38, 0.2); display:flex; align-items:center; gap:5px;"><span class="material-symbols-rounded md-16">cancel</span> Motivo: ${order.cancelReason}</div>` : ''}
          </div>

          <div class="order-items-list">
            ${itemsHtml || '<div style="color: var(--text-muted);">Sin detalles de productos</div>'}
          </div>
        </div>

        <div>
          <div class="order-total-row">
            <div>
              <div style="font-size: 0.75rem; color: var(--text-muted); display:flex; align-items:center; gap:5px;"><span class="material-symbols-rounded md-16">payments</span> ${(order.paymentMethod || 'Efectivo').toUpperCase()}</div>
              ${order.couponCode ? `<div style="font-size: 0.75rem; color: #16A34A; display:flex; align-items:center; gap:5px; margin-top:3px;"><span class="material-symbols-rounded md-16">local_activity</span> Cupón: ${order.couponCode}</div>` : ''}
              ${order.deliveryProofUrl ? `
                <div style="margin-top: 8px;">
                  <button type="button" class="btn-proof-preview" onclick="openProofModal('${encodeURIComponent(order.deliveryProofUrl)}', '${order.id}', '${(order.driverName || 'Repartidor').replace(/'/g, "\\'")}')" title="Ver foto de entrega en alta resolución" style="display:inline-flex; align-items:center; gap:8px; padding:6px 12px; background:rgba(16,185,129,0.15); border:1px solid rgba(16,185,129,0.35); border-radius:10px; cursor:pointer; color:#10B981; font-weight:600; font-size:0.78rem;">
                    <img src="${order.deliveryProofUrl}" alt="Evidencia" style="width:24px; height:24px; object-fit:cover; border-radius:6px; border:1px solid rgba(16,185,129,0.5);">
                    <span>📸 Ver Evidencia de Entrega</span>
                  </button>
                </div>
              ` : (status === 'delivered' ? `
                <div style="margin-top: 6px; font-size: 0.72rem; color: var(--text-muted); display: flex; align-items: center; gap: 4px;">
                  <span class="material-symbols-rounded md-14">no_photography</span> Sin foto registrada
                </div>
              ` : '')}
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
                <span class="material-symbols-rounded md-18">close</span>
              </button>
            ` : ''}
          </div>
        </div>
      </div>
    `;
  }).join('');
}

// Status Advancement with Realtime Customer Notification
async function advanceStatus(orderId, nextStatus) {
  const order = allOrders.find(o => o.id === orderId);

  if (!db) {
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

    // Enviar notificación en Firestore al cliente (para usuarios Google, Correo o Invitados)
    if (order && order.userId && order.userId !== 'guest') {
      const statusNotificationMap = {
        'confirmed': {
          title: '✅ ¡Pedido Confirmado!',
          body: 'Tu pedido en La Diabla fue confirmado. ¡Empezamos a prepararlo! 👨‍🍳',
          emoji: '✅'
        },
        'preparing': {
          title: '🍳 ¡Tus platillos están en la plancha!',
          body: 'Nuestros taqueros están preparando tu comida con el mejor sazón 🌶️',
          emoji: '🍳'
        },
        'ready': {
          title: '📦 ¡Pedido empacado y listo para despacho!',
          body: 'Asignando el repartidor más cercano para llevarlo a tu puerta 🛵',
          emoji: '📦'
        },
        'onTheWay': {
          title: '🛵 ¡Tu pedido va en camino!',
          body: 'El repartidor ya salió con tu comida caliente. ¡Ya casi llega! 🌶️',
          emoji: '🛵'
        },
        'delivered': {
          title: '✅ ¡Pedido Entregado con Éxito!',
          body: '¡Buen provecho! Disfruta de la mejor comida mexicana de Bucaramanga 🌮⭐',
          emoji: '🎉'
        }
      };

      const notif = statusNotificationMap[nextStatus] || {
        title: '🔥 Estado de tu pedido actualizado',
        body: `Tu pedido #${orderId.substring(0, 6).toUpperCase()} pasó a ${statusBadges[nextStatus]?.label ?? nextStatus}`,
        emoji: '🌮'
      };

      const notifDocId = `${orderId}_${nextStatus}`;
      db.collection('users').doc(order.userId).collection('notifications').doc(notifDocId).set({
        title: notif.title,
        body: notif.body,
        orderId: orderId,
        status: nextStatus,
        type: 'order_status',
        emoji: notif.emoji,
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        isRead: false
      }, { merge: true }).catch(err => console.warn("Error enviando notif a Firestore:", err));
    }

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

  const order = allOrders.find(o => o.id === orderId);

  if (!db) {
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

    // Notificar al cliente de la cancelación
    if (order && order.userId && order.userId !== 'guest') {
      const notifDocId = `${orderId}_cancelled`;
      db.collection('users').doc(order.userId).collection('notifications').doc(notifDocId).set({
        title: '❌ Pedido Cancelado',
        body: `Tu pedido #${orderId.substring(0, 6).toUpperCase()} fue cancelado. Motivo: ${reason}`,
        orderId: orderId,
        status: 'cancelled',
        type: 'order_status',
        emoji: '❌',
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        isRead: false
      }, { merge: true }).catch(err => console.warn("Error enviando notif de cancelacion:", err));
    }

    showNotificationToast("❌ Pedido cancelado");
  } catch (e) {
    alert("Error al cancelar: " + e.message);
  }
}

// Toast notification helper
function showNotificationToast(msg, icon = 'notifications') {
  const container = document.getElementById('toastContainer') || document.body;
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.innerHTML = `<span class="material-symbols-rounded md-20">${icon}</span><span>${msg}</span>`;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.animation = 'toastOut 0.3s ease forwards';
    setTimeout(() => toast.remove(), 320);
  }, 3500);
}

// Filter buttons
function setFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.filter === filter);
  });

  const ordersGrid = document.getElementById('ordersGrid');
  const refundsGrid = document.getElementById('refundsGrid');
  const evidenceSubTabs = document.getElementById('evidenceSubTabs');

  if (filter === 'refunds') {
    if (ordersGrid) ordersGrid.style.display = 'none';
    if (refundsGrid) refundsGrid.style.display = 'grid';
    if (evidenceSubTabs) evidenceSubTabs.style.display = 'none';
    renderRefunds();
  } else if (filter === 'evidence') {
    if (ordersGrid) ordersGrid.style.display = 'grid';
    if (refundsGrid) refundsGrid.style.display = 'none';
    if (evidenceSubTabs) evidenceSubTabs.style.display = 'flex';
    renderOrders();
  } else {
    if (ordersGrid) ordersGrid.style.display = 'grid';
    if (refundsGrid) refundsGrid.style.display = 'none';
    if (evidenceSubTabs) evidenceSubTabs.style.display = 'none';
    renderOrders();
  }
}

// Evidence sub-tab selector
function setEvidenceSubFilter(subFilter) {
  evidenceSubFilter = subFilter;
  document.querySelectorAll('.evidence-sub-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.sub === subFilter);
  });
  renderOrders();
}

// Render the evidence section (sub-tabs: proofs vs plates)
function renderEvidenceView(grid, filteredOrders) {
  if (evidenceSubFilter === 'plates') {
    renderPlateEvidence(grid);
    return;
  }

  // --- Comprobantes de Pedidos ---
  const proofOrders = filteredOrders.filter(o => !!o.deliveryProofUrl);
  if (proofOrders.length === 0) {
    grid.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-rounded md-48" style="color:var(--text-muted); opacity:0.6; margin-bottom:12px;">photo_camera</span>
        <h3 class="diabla-font">Sin comprobantes registrados</h3>
        <p>Cuando un repartidor tome la foto de entrega, aparecerá aquí con visor en alta resolución.</p>
      </div>
    `;
    return;
  }

  grid.innerHTML = proofOrders.map(order => {
    const shortId = order.id.length > 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase();
    const addressStr = order.formattedAddress || (order.address && order.address.formattedAddress) || (typeof order.address === 'string' ? order.address : 'Dirección de entrega');
    const customer = order.customerName || order.userName || order.userId || 'Cliente La Diabla';
    const driver = order.driverName || 'Repartidor La Diabla';
    const proofUrl = order.deliveryProofUrl;
    const cleanProofUrl = encodeURIComponent(proofUrl);
    const safeCustomer = customer.replace(/'/g, "\\'");
    const safeAddress = addressStr.replace(/'/g, "\\'");
    const safeDriver = driver.replace(/'/g, "\\'");

    return `
      <div class="evidence-card">
        <div class="evidence-thumb-wrapper" onclick="openProofModal('${cleanProofUrl}', '${order.id}', '${safeCustomer}', '${safeAddress}', '${safeDriver}')">
          <img src="${proofUrl}" alt="Evidencia Pedido #${shortId}" class="evidence-thumb-img" onerror="this.src='data:image/svg+xml;utf8,<svg xmlns=\'http://www.w3.org/2000/svg\' width=\'200\' height=\'200\'><rect width=\'100%\' height=\'100%\' fill=\'%23333\'/><text x=\'50%\' y=\'50%\' fill=\'%23888\' dominant-baseline=\'middle\' text-anchor=\'middle\'>Error Cargando Foto</text></svg>'">
          <div class="evidence-badge-verified">
            <span class="material-symbols-rounded" style="font-size:14px;">check_circle</span>
            <span>ENTREGA VERIFICADA</span>
          </div>
        </div>
        <div class="evidence-card-content">
          <div style="display:flex; justify-content:space-between; align-items:flex-start;">
            <span class="order-id diabla-font" style="color:#DC2626; font-size:1.05rem;">PEDIDO #${shortId}</span>
            <span style="font-size:0.75rem; color:var(--text-muted); display:flex; align-items:center; gap:4px;">
              <span class="material-symbols-rounded md-14">schedule</span> ${formatTime(order.deliveredAt || order.createdAt)}
            </span>
          </div>
          <div style="margin-top:2px;">
            <div style="font-weight:700; color:var(--text-main); font-size:0.92rem; display:flex; align-items:center; gap:5px;">
              <span class="material-symbols-rounded md-16" style="color:#DC2626;">person</span> ${customer}
            </div>
            <div style="font-size:0.83rem; color:var(--text-muted); margin-top:3px; display:flex; align-items:flex-start; gap:5px;">
              <span class="material-symbols-rounded md-16" style="color:#DC2626; flex-shrink:0;">location_on</span>
              <span>${addressStr}</span>
            </div>
            <div style="font-size:0.82rem; color:#10B981; margin-top:4px; display:flex; align-items:center; gap:5px; font-weight:600;">
              <span class="material-symbols-rounded md-16">two_wheeler</span> Repartidor: ${driver}
            </div>
          </div>
          <div style="margin-top:auto; padding-top:10px; display:flex; justify-content:space-between; align-items:center; border-top:1px solid var(--card-border);">
            <span class="diabla-font" style="font-size:1.1rem; color:var(--text-main);">${formatCOP(order.total || 0)}</span>
            <button type="button" class="btn-proof-preview" onclick="openProofModal('${cleanProofUrl}', '${order.id}', '${safeCustomer}', '${safeAddress}', '${safeDriver}')">
              <span class="material-symbols-rounded md-16">zoom_in</span> Ver Completa
            </button>
          </div>
        </div>
      </div>
    `;
  }).join('');
}

// Render plate evidence cards
function renderPlateEvidence(grid) {
  if (allDriverUsers.length === 0) {
    grid.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-rounded md-48" style="color:var(--text-muted); opacity:0.6; margin-bottom:12px;">directions_car</span>
        <h3 class="diabla-font">Sin placas registradas</h3>
        <p>Cuando un repartidor registre la foto de su placa desde la app, aparecerá aquí.</p>
      </div>
    `;
    return;
  }

  grid.innerHTML = allDriverUsers.map(driver => {
    const name = driver.name || driver.displayName || 'Repartidor';
    const plate = driver.vehiclePlate || 'Sin Placa';
    const model = driver.vehicleModel || 'Sin Modelo';
    const color = driver.vehicleColor || '';
    const platePhotoUrl = driver.vehiclePlatePhotoUrl || '';
    const soatStatus = driver.soatStatus || 'No verificado';
    const safeName = name.replace(/'/g, "\\'");
    const safePlate = plate.replace(/'/g, "\\'");
    const cleanPlateUrl = encodeURIComponent(platePhotoUrl);

    return `
      <div class="plate-card">
        <div class="plate-thumb-wrapper" onclick="openProofModal('${cleanPlateUrl}', '', '${safeName}', 'Placa: ${safePlate}', '${safeName}')">
          ${platePhotoUrl
            ? `<img src="${platePhotoUrl}" alt="Placa ${plate}" class="evidence-thumb-img" onerror="this.parentElement.innerHTML='<div class=plate-no-photo><span class=\'material-symbols-rounded md-36\'>directions_car</span></div>'">`
            : `<div class="plate-no-photo"><span class="material-symbols-rounded md-36">directions_car</span></div>`
          }
          <div class="evidence-badge-verified" style="background:rgba(59,130,246,0.85);">
            <span class="material-symbols-rounded" style="font-size:14px;">badge</span>
            <span>PLACA REGISTRADA</span>
          </div>
        </div>
        <div class="evidence-card-content">
          <div style="font-weight:800; font-size:1.25rem; letter-spacing:2px; color:#3B82F6; font-family:'Bangers',cursive; display:flex; align-items:center; gap:8px;">
            <span class="material-symbols-rounded md-20">pin</span>${plate}
          </div>
          <div style="font-weight:600; color:var(--text-main); font-size:0.92rem; display:flex; align-items:center; gap:5px; margin-top:2px;">
            <span class="material-symbols-rounded md-16" style="color:#10B981;">person</span> ${name}
          </div>
          <div style="font-size:0.83rem; color:var(--text-muted); margin-top:3px; display:flex; align-items:center; gap:5px;">
            <span class="material-symbols-rounded md-16">two_wheeler</span> ${model}${color ? ' • ' + color : ''}
          </div>
          <div style="margin-top:8px; display:flex; align-items:center; gap:6px; font-size:0.78rem; font-weight:600; padding:5px 10px; border-radius:8px; width:fit-content; ${
            soatStatus === 'vigente'
              ? 'background:rgba(22,163,74,0.15); color:#16A34A; border:1px solid rgba(22,163,74,0.3);'
              : 'background:rgba(245,158,11,0.15); color:#F59E0B; border:1px solid rgba(245,158,11,0.3);'
          }">
            <span class="material-symbols-rounded md-14">verified_user</span> SOAT: ${soatStatus}
          </div>
          <div style="margin-top:auto; padding-top:10px; border-top:1px solid var(--card-border);">
            <button type="button" class="btn-proof-preview" style="border-color:#3B82F6; color:#3B82F6;" onclick="openProofModal('${cleanPlateUrl}', '', '${safeName}', 'Placa: ${safePlate}', '${safeName}')">
              <span class="material-symbols-rounded md-16">zoom_in</span> Ver Placa
            </button>
          </div>
        </div>
      </div>
    `;
  }).join('');
}

// Render Refunds Section
function renderRefunds() {
  const container = document.getElementById('refundsGrid');
  if (!container) return;

  if (allRefunds.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-rounded md-48" style="color:var(--text-muted); opacity:0.6; margin-bottom:12px;">currency_exchange</span>
        <h3 class="diabla-font">Sin reembolsos pendientes</h3>
        <p>Todas las transacciones y pedidos se encuentran al día.</p>
      </div>
    `;
    return;
  }

  container.innerHTML = allRefunds.map(ref => {
    const isPending  = ref.status === 'pending';
    const isApproved = ref.status === 'processed';
    const statusColor = isPending ? '#F59E0B' : (isApproved ? '#16A34A' : '#EF4444');
    const statusIcon  = isPending ? 'hourglass_top' : (isApproved ? 'check_circle' : 'cancel');
    const statusLabel = isPending ? 'PENDIENTE' : (isApproved ? 'PROCESADO' : 'RECHAZADO');

    return `
      <div class="order-card" style="border-top: 4px solid ${statusColor};">

        <!-- Header -->
        <div class="order-top">
          <div>
            <span class="order-id diabla-font"><span class="material-symbols-rounded md-18" style="vertical-align:middle; margin-right:4px;">currency_exchange</span> REEMBOLSO #${(ref.id || '').substring(0, 6).toUpperCase()}</span>
            <div class="order-time">
              <span class="material-symbols-rounded md-16" style="vertical-align:middle;">receipt_long</span> Pedido #${(ref.orderId || '').substring(0, 6).toUpperCase()}
            </div>
          </div>
          <span class="status-badge" style="background: ${statusColor}22; color: ${statusColor};">
            <span class="material-symbols-rounded md-16">${statusIcon}</span> ${statusLabel}
          </span>
        </div>

        <!-- Amount -->  
        <div style="margin: 10px 0; padding: 10px 14px; background: rgba(22,163,74,0.08); border: 1px solid rgba(22,163,74,0.2); border-radius: 12px; display:flex; justify-content:space-between; align-items:center;">
          <span style="color: var(--text-muted); font-size: 0.83rem; display:flex; align-items:center; gap:6px;"><span class="material-symbols-rounded md-16" style="color:#16A34A;">paid</span> Monto a Reembolsar</span>
          <span class="diabla-font" style="font-size: 1.35rem; color: #16A34A;">${formatCOP(ref.amount)}</span>
        </div>

        <!-- Details -->
        <div class="order-customer" style="border:none; padding-bottom:0; margin-bottom:0;">
          <div style="font-size: 0.85rem; margin-bottom: 6px; display:flex; align-items:center; gap:6px;">
            <span class="material-symbols-rounded md-18" style="color:var(--text-muted);">person</span>
            <strong>${ref.userName || 'Cliente'}</strong>
            <span style="color:var(--text-muted);">&bull; ${ref.userPhone || 'Sin teléfono'}</span>
          </div>
          <div style="font-size: 0.85rem; margin-bottom: 6px; display:flex; align-items:center; gap:6px;">
            <span class="material-symbols-rounded md-18" style="color:#F59E0B;">credit_card</span>
            <span><strong>Destino:</strong> <span style="color:#F59E0B; font-weight:700;">${ref.paymentMethod || 'Cuenta original'}</span></span>
          </div>
          ${ref.accountDetails ? `<div style="font-size: 0.83rem; margin-bottom: 6px; display:flex; align-items:center; gap:6px; color:var(--text-muted);"><span class="material-symbols-rounded md-16">tag</span> ${ref.accountDetails}</div>` : ''}
          <div style="font-size: 0.83rem; color: var(--text-muted); display:flex; align-items:flex-start; gap:6px;">
            <span class="material-symbols-rounded md-16" style="margin-top:2px;">chat</span>
            <em>"${ref.reason || 'Cancelación de pedido'}"</em>
          </div>
        </div>

        <!-- Actions -->
        ${isPending ? `
          <div class="order-actions" style="margin-top:14px;">
            <button onclick="processRefund('${ref.id}', '${ref.orderId}', '${ref.userId}', ${ref.amount}, '${ref.userName || 'Cliente'}')" 
                    class="action-btn btn-deliver">
              <span class="material-symbols-rounded md-18">check_circle</span> Aprobar Reembolso
            </button>
            <button onclick="rejectRefund('${ref.id}', '${ref.orderId}')" 
                    class="action-btn btn-cancel">
              <span class="material-symbols-rounded md-18">close</span>
            </button>
          </div>
        ` : `
          <div style="margin-top: 12px; font-size: 0.8rem; color: var(--text-muted); text-align:center; display:flex; align-items:center; justify-content:center; gap:6px;">
            <span class="material-symbols-rounded md-18">verified_user</span> Solicitud gestionada por la administración
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
    showNotificationToast(`Reembolso #${refundId.substring(0, 6)} procesado exitosamente`, 'check_circle');
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
    showNotificationToast('Solicitud de reembolso rechazada', 'cancel');
  } catch (e) {
    alert("Error al rechazar reembolso: " + e.message);
  }
}

// Borrar todos los pedidos de prueba en Firestore
async function clearAllTestOrders() {
  if (!confirm("⚠️ ¿Estás seguro de que deseas eliminar TODOS los pedidos de prueba en Firestore? Esta acción dejará el tablero en 0 para recibir nuevos pedidos reales.")) {
    return;
  }
  try {
    if (db) {
      const snapshot = await db.collection('orders').get();
      const batch = db.batch();
      snapshot.forEach(doc => {
        batch.delete(doc.ref);
      });
      await batch.commit();

      const refundsSnapshot = await db.collection('refunds').get();
      const refBatch = db.batch();
      refundsSnapshot.forEach(doc => {
        refBatch.delete(doc.ref);
      });
      await refBatch.commit();
    }
    allOrders = [];
    allRefunds = [];
    updateStats();
    renderOrders();
    showNotificationToast('Tablero limpiado con éxito', 'cleaning_services');
  } catch (e) {
    alert("Error al limpiar pedidos: " + e.message);
  }
}

// Fallback cuando no hay pedidos o sin conexión
function renderFallbackDemo() {
  allOrders = [];
  updateStats();
  renderOrders();
}

// Logout Action
function logoutAdmin() {
  sessionStorage.removeItem('diabla_admin_auth');
  if (typeof firebase !== 'undefined' && firebase.auth) {
    firebase.auth().signOut().catch(() => {});
  }
  window.location.href = 'login.html';
}

// Theme Toggle Helper (Modo Claro ☀️ / Modo Oscuro 🌙)
function toggleWebTheme() {
  const current = document.documentElement.getAttribute('data-theme') || 'dark';
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('diabla_web_theme', next);
  updateThemeToggleBtnLabel(next);
}

function updateThemeToggleBtnLabel(theme) {
  const icon  = document.getElementById('themeIcon');
  const label = document.getElementById('themeLabel');
  if (icon)  icon.textContent = theme === 'dark' ? 'light_mode' : 'dark_mode';
  if (label) label.textContent = theme === 'dark' ? 'Claro' : 'Oscuro';
}

// Abrir Evidencia de Entrega en Alta Resolución dentro del modal interactivo
function openProofModal(encodedUrl, orderId, customerName, address, driverName) {
  const url = decodeURIComponent(encodedUrl || '');
  if (!url || (!url.startsWith('http') && !url.startsWith('data:image/'))) return;

  const modal = document.getElementById('proofPhotoModal');
  const img = document.getElementById('proofModalImg');
  const title = document.getElementById('proofModalTitle');
  const orderEl = document.getElementById('proofModalOrder');
  const custEl = document.getElementById('proofModalCustomer');
  const addrEl = document.getElementById('proofModalAddress');
  const driverEl = document.getElementById('proofModalDriver');
  const downloadLink = document.getElementById('proofModalDownload');

  if (img) img.src = url;
  if (downloadLink) downloadLink.href = url;

  const shortId = orderId ? (orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase()) : '';
  if (title) title.innerText = shortId ? `Evidencia de Entrega #${shortId}` : 'Evidencia de Entrega';
  if (orderEl) orderEl.innerText = shortId ? `PEDIDO #${shortId}` : '';
  if (custEl) custEl.innerHTML = customerName ? `<strong>Cliente:</strong> ${customerName}` : '';
  if (addrEl) addrEl.innerHTML = address ? `<strong>Dirección:</strong> ${address}` : '';
  if (driverEl) driverEl.innerHTML = driverName ? `<strong>Repartidor:</strong> ${driverName}` : '';

  if (modal) {
    modal.style.display = 'flex';
  }
}

function closeProofModal(event) {
  if (event && event.target && !event.target.classList.contains('proof-modal-backdrop') && !event.target.classList.contains('proof-modal-close')) {
    return;
  }
  const modal = document.getElementById('proofPhotoModal');
  if (modal) {
    modal.style.display = 'none';
  }
}

// ─── UTILITIES (HTML ESCAPE & TOAST NOTIFICATIONS) ──────────────
function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function showToast(message, type = 'info') {
  const container = document.getElementById('toastContainer');
  if (!container) return;
  const toast = document.createElement('div');
  const bg = type === 'success' ? '#16A34A' : (type === 'danger' || type === 'error') ? '#DC2626' : (type === 'warning') ? '#F59E0B' : '#1F2937';
  const icon = type === 'success' ? 'check_circle' : (type === 'danger' || type === 'error') ? 'error' : (type === 'warning') ? 'warning' : 'info';
  
  toast.style.cssText = `
    display: flex;
    align-items: center;
    gap: 10px;
    background: ${bg};
    color: #fff;
    padding: 12px 20px;
    border-radius: 12px;
    margin-top: 10px;
    box-shadow: 0 10px 25px rgba(0,0,0,0.35);
    font-size: 0.9rem;
    font-weight: 600;
    font-family: 'Outfit', sans-serif;
    animation: fadeInToast 0.3s ease;
    transition: opacity 0.3s ease, transform 0.3s ease;
    z-index: 10000;
  `;
  toast.innerHTML = `<span class="material-symbols-rounded md-20">${icon}</span><span>${escapeHtml(message)}</span>`;
  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(-10px)';
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

// ─── VIEW SWITCHER (PEDIDOS VS MENÚ) ───────────────────────────
function switchAdminView(view) {
  currentAdminView = view;
  const ordersBtn = document.getElementById('viewOrdersBtn');
  const productsBtn = document.getElementById('viewProductsBtn');
  const ordersSec = document.getElementById('ordersSection');
  const productsSec = document.getElementById('productsSection');

  if (view === 'orders') {
    if (ordersBtn) ordersBtn.classList.add('active');
    if (productsBtn) productsBtn.classList.remove('active');
    if (ordersSec) ordersSec.style.display = 'block';
    if (productsSec) productsSec.style.display = 'none';
  } else {
    if (ordersBtn) ordersBtn.classList.remove('active');
    if (productsBtn) productsBtn.classList.add('active');
    if (ordersSec) ordersSec.style.display = 'none';
    if (productsSec) productsSec.style.display = 'block';
    renderProducts();
  }
}

// ─── PRODUCTS FIRESTORE REALTIME SYNC ─────────────────────────
let hasAutoStocked = false;

function initRealtimeProducts() {
  if (!db) return;
  db.collection('products').onSnapshot(async (snapshot) => {
    allProducts = [];
    snapshot.forEach((doc) => {
      const data = doc.data();
      allProducts.push({
        id: doc.id,
        ...data,
      });
    });

    // Auto-abastecimiento silencioso si Firestore tiene menos productos que el catálogo completo de la App
    if (!hasAutoStocked && allProducts.length < 40 && typeof BASE_DIABLA_PRODUCTS !== 'undefined' && BASE_DIABLA_PRODUCTS.length > 0) {
      hasAutoStocked = true;
      console.log(`📦 Abastecimiento automático activado (${allProducts.length} detectados, sincronizando base completa de ${BASE_DIABLA_PRODUCTS.length})...`);
      autoStockMissingProducts();
    }

    // Ordenar: creados más recientes primero
    allProducts.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));

    // Actualizar badge de contador
    const badge = document.getElementById('productTotalBadge');
    if (badge) badge.textContent = allProducts.length;

    if (currentAdminView === 'products') {
      renderProducts();
    }
  }, (err) => {
    console.error("Error al escuchar productos en tiempo real:", err);
  });
}

// Auto-abastecer silenciosamente los productos faltantes sin interrumpir al usuario
async function autoStockMissingProducts() {
  try {
    await ensureAdminAuth();
    const existingIds = new Set(allProducts.map(p => p.id));
    const missing = BASE_DIABLA_PRODUCTS.filter(p => !existingIds.has(p.id));
    if (missing.length === 0) return;

    const batch = db.batch();
    const now = Date.now();
    missing.forEach(p => {
      const ref = db.collection('products').doc(p.id);
      batch.set(ref, {
        ...p,
        extras: [],
        createdAt: now,
        updatedAt: now
      }, { merge: true });
    });
    await batch.commit();
    console.log(`✅ ¡Auto-abastecidos ${missing.length} productos faltantes con éxito!`);
  } catch (err) {
    console.warn("Nota de auto-abastecimiento:", err);
  }
}

// ─── PRODUCT CATEGORY & SEARCH FILTERS ─────────────────────────
function setProductCategoryFilter(category) {
  currentProductCategory = category;
  document.querySelectorAll('.product-cat-btn').forEach(btn => {
    if (btn.getAttribute('data-cat') === category) {
      btn.classList.add('active');
    } else {
      btn.classList.remove('active');
    }
  });
  renderProducts();
}

function onProductSearchChange(val) {
  productSearchQuery = (val || '').toLowerCase().trim();
  renderProducts();
}

// ─── RENDER PRODUCTS GRID ──────────────────────────────────────
function renderProducts() {
  const container = document.getElementById('productsGrid');
  if (!container) return;

  let filtered = allProducts;

  if (currentProductCategory !== 'all') {
    filtered = filtered.filter(p => (p.categoryId || '').toLowerCase() === currentProductCategory.toLowerCase());
  }

  if (productSearchQuery) {
    filtered = filtered.filter(p => {
      const nameMatch = (p.name || '').toLowerCase().includes(productSearchQuery);
      const descMatch = (p.description || '').toLowerCase().includes(productSearchQuery);
      const ingsMatch = (p.ingredients || []).some(i => i.toLowerCase().includes(productSearchQuery));
      return nameMatch || descMatch || ingsMatch;
    });
  }

  if (filtered.length === 0) {
    container.innerHTML = `
      <div style="grid-column: 1 / -1; text-align: center; padding: 3.5rem 1.5rem; background: var(--card-bg); border-radius: 22px; border: 1px dashed var(--card-border);">
        <span class="material-symbols-rounded" style="font-size: 56px; color: var(--text-muted); margin-bottom: 12px; display:block;">restaurant</span>
        <h3 class="diabla-font" style="font-size: 1.5rem; color: var(--text-main); margin-bottom: 6px;">No se encontraron platillos</h3>
        <p style="color: var(--text-muted); font-size: 0.95rem; margin-bottom: 1.25rem;">
          ${allProducts.length === 0 ? 'Aún no hay platillos cargados en el menú de la base de datos.' : 'No hay platillos que coincidan con la búsqueda o categoría seleccionada.'}
        </p>
        ${allProducts.length === 0 ? `
          <div style="display:flex; gap:10px; justify-content:center; flex-wrap:wrap;">
            <button onclick="openProductModal()" class="action-btn" style="background:var(--primary); color:white; padding:10px 20px; border-radius:12px; border:none; cursor:pointer; font-weight:700; display:inline-flex; align-items:center; gap:6px;">
              <span class="material-symbols-rounded md-18">add_circle</span> Crear Primer Platillo
            </button>
            <button onclick="seedBaseProducts()" class="btn-clean" style="padding:10px 20px; border-radius:12px; border:1px solid rgba(255,255,255,0.2); cursor:pointer; font-weight:700; display:inline-flex; align-items:center; gap:6px;">
              <span class="material-symbols-rounded md-18" style="color:#F59E0B;">bolt</span> Cargar Menú Inicial Base
            </button>
          </div>
        ` : ''}
      </div>
    `;
    return;
  }

  const categoryNames = {
    'tacos': '🌮 Tacos',
    'burritos': '🌯 Burritos',
    'quesadillas': '🧀 Quesadillas',
    'mariscos': '🦐 Mariscos',
    'ensaladas': '🥗 Ensaladas',
    'bebidas': '🥤 Bebidas',
    'especiales': '⭐ Especiales'
  };

  const spicyLabels = [
    'Sin picante',
    'Suave 🌶️',
    'Medio 🌶️🌶️',
    'Diabla 🔥'
  ];

  container.innerHTML = filtered.map(p => {
    const isAvail = p.available !== false;
    const catLabel = categoryNames[p.categoryId] || p.categoryId || 'General';
    const spicyText = spicyLabels[p.spicyLevel || 0] || 'Sin picante';
    const imgUrl = p.imageUrl && p.imageUrl.startsWith('http') 
      ? p.imageUrl 
      : 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600';
    const safeImgUrl = encodeURIComponent(imgUrl);
    const safeName = (p.name || '').replace(/'/g, "\\'");
    const safeCat = catLabel.replace(/'/g, "\\'");

    const ingredientsChips = (p.ingredients && p.ingredients.length > 0)
      ? p.ingredients.map(ing => `<span class="product-ingredient-chip">${escapeHtml(ing)}</span>`).join('')
      : '<span style="font-size:0.75rem; color:var(--text-muted); font-style:italic;">Sin ingredientes detallados</span>';

    return `
      <div class="product-card ${!isAvail ? 'unavailable' : ''}" id="prodCard_${p.id}">
        <div class="product-card-img-wrap" onclick="openProofModal('${safeImgUrl}', '${p.id}', '${safeName}', 'Precio: ${formatCOP(p.price)}', '${safeCat}')" title="Click para ampliar fotografía">
          <img src="${imgUrl}" alt="${escapeHtml(p.name)}" class="product-card-img" onerror="this.src='https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600'">
          <span class="product-card-category-badge">${catLabel}</span>
          ${(p.spicyLevel || 0) > 0 ? `<span class="product-card-spicy-badge">${spicyText}</span>` : ''}
          <div class="product-status-pill ${isAvail ? 'pill-available' : 'pill-unavailable'}">
            <span class="material-symbols-rounded" style="font-size:13px;">${isAvail ? 'check_circle' : 'cancel'}</span>
            <span>${isAvail ? 'DISPONIBLE' : 'AGOTADO'}</span>
          </div>
        </div>

        <div class="product-card-body">
          <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:8px; margin-bottom:4px;">
            <div class="product-card-title diabla-font">${escapeHtml(p.name)}</div>
            <div class="product-card-price diabla-font">${formatCOP(p.price)}</div>
          </div>

          <div class="product-card-desc">${escapeHtml(p.description || 'Sin descripción detallada.')}</div>

          <div class="product-ingredients-wrap">
            ${ingredientsChips}
          </div>

          <div class="product-card-footer">
            <div class="product-avail-toggle ${isAvail ? 'available' : 'unavailable'}">
              <label class="switch" title="${isAvail ? 'Disponible' : 'Agotado'}">
                <input type="checkbox" ${isAvail ? 'checked' : ''} onchange="toggleProductAvailability('${p.id}', this.checked)">
                <span class="slider"></span>
              </label>
              <span>${isAvail ? 'Disponible' : 'Agotado'}</span>
            </div>

            <div class="product-card-actions">
              <button class="btn-card-action" title="Editar platillo" onclick="openProductModal('${p.id}')">
                <span class="material-symbols-rounded md-18">edit</span>
                <span>Editar</span>
              </button>
              <button class="btn-card-action btn-delete" title="Eliminar platillo" onclick="deleteProduct('${p.id}')">
                <span class="material-symbols-rounded md-18">delete</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
  }).join('');
}

// ─── PRODUCT MODAL (CREAR / EDITAR) ────────────────────────────
function openProductModal(productId = null) {
  // Asegurar que solo IDs en string sean considerados edición (evitar pasar eventos de click)
  const isEditing = typeof productId === 'string' && productId.trim().length > 0;
  const modal = document.getElementById('productModal');
  const title = document.getElementById('productModalTitle');
  const idInput = document.getElementById('pmId');
  const nameInput = document.getElementById('pmName');
  const priceInput = document.getElementById('pmPrice');
  const catInput = document.getElementById('pmCategory');
  const descInput = document.getElementById('pmDesc');
  const ingInput = document.getElementById('pmIngredientInput');
  const urlInput = document.getElementById('pmImageUrl');
  const fileInput = document.getElementById('pmImageFile');
  const availInput = document.getElementById('pmAvailable');
  const previewImg = document.getElementById('pmImagePreview');
  const previewHolder = document.getElementById('pmPreviewPlaceholder');

  currentModalIngredients = [];
  selectedImageFile = null;
  if (fileInput) fileInput.value = '';

  if (isEditing) {
    const prod = allProducts.find(p => p.id === productId.trim());
    if (prod) {
      if (title) title.textContent = 'Editar Platillo';
      if (idInput) idInput.value = prod.id;
      if (nameInput) nameInput.value = prod.name || '';
      if (priceInput) priceInput.value = prod.price || '';
      if (catInput) catInput.value = prod.categoryId || 'tacos';
      if (descInput) descInput.value = prod.description || '';
      if (urlInput) urlInput.value = prod.imageUrl || '';
      if (availInput) availInput.checked = prod.available !== false;
      selectSpicyLevel(prod.spicyLevel || 0);

      currentModalIngredients = Array.isArray(prod.ingredients) ? [...prod.ingredients] : [];

      if (prod.imageUrl) {
        if (previewImg) {
          previewImg.src = prod.imageUrl;
          previewImg.style.display = 'block';
        }
        if (previewHolder) previewHolder.style.display = 'none';
      } else {
        if (previewImg) previewImg.style.display = 'none';
        if (previewHolder) previewHolder.style.display = 'flex';
      }
    }
  } else {
    // Creación de Nuevo Platillo
    if (title) title.textContent = 'Nuevo Platillo';
    if (idInput) idInput.value = '';
    if (nameInput) nameInput.value = '';
    if (priceInput) priceInput.value = '';
    if (catInput) catInput.value = 'tacos';
    if (descInput) descInput.value = '';
    if (urlInput) urlInput.value = '';
    if (availInput) availInput.checked = true;
    selectSpicyLevel(0);

    if (previewImg) previewImg.style.display = 'none';
    if (previewHolder) previewHolder.style.display = 'flex';
  }

  if (ingInput) ingInput.value = '';
  renderModalIngredientChips();

  if (modal) {
    modal.style.display = 'flex';
  }
}

// Llamado desde el botón X — siempre cierra sin condiciones
function closeProductModal(event) {
  const modal = document.getElementById('productModal');
  if (modal) modal.style.display = 'none';
  selectedImageFile = null;
}

// Llamado desde el backdrop — solo cierra si el click fue en el propio backdrop (no en la card)
function closeProductModalBackdrop(event) {
  if (event && event.target && event.target.id === 'productModal') {
    closeProductModal();
  }
}

function selectSpicyLevel(level) {
  const hiddenInput = document.getElementById('pmSpicy');
  if (hiddenInput) hiddenInput.value = level;
  document.querySelectorAll('.spicy-option-btn').forEach(btn => {
    if (parseInt(btn.getAttribute('data-spicy'), 10) === level) {
      btn.classList.add('active');
    } else {
      btn.classList.remove('active');
    }
  });
}

// ─── INGREDIENTS MANAGER IN MODAL ──────────────────────────────
function handleIngredientKey(event) {
  if (event.key === 'Enter') {
    event.preventDefault();
    addIngredientFromInput();
  }
}

function addIngredientFromInput() {
  const input = document.getElementById('pmIngredientInput');
  if (!input) return;
  const val = input.value.trim();
  if (val && !currentModalIngredients.includes(val)) {
    currentModalIngredients.push(val);
    renderModalIngredientChips();
  }
  input.value = '';
  input.focus();
}

function removeIngredient(index) {
  currentModalIngredients.splice(index, 1);
  renderModalIngredientChips();
}

function renderModalIngredientChips() {
  const container = document.getElementById('pmIngredientsChips');
  if (!container) return;
  if (currentModalIngredients.length === 0) {
    container.innerHTML = '<span style="color:var(--text-muted); font-size:0.8rem; padding:4px;">No hay ingredientes añadidos aún.</span>';
    return;
  }
  container.innerHTML = currentModalIngredients.map((ing, idx) => `
    <span class="interactive-ingredient-chip">
      <span>${escapeHtml(ing)}</span>
      <span class="remove-ing" onclick="removeIngredient(${idx})" title="Eliminar">&times;</span>
    </span>
  `).join('');
}

// ─── IMAGE FILE & URL PREVIEW ──────────────────────────────────
function handleProductFileSelect(event) {
  const file = event.target.files && event.target.files[0];
  if (!file) return;
  selectedImageFile = file;
  const objectUrl = URL.createObjectURL(file);
  const previewImg = document.getElementById('pmImagePreview');
  const previewHolder = document.getElementById('pmPreviewPlaceholder');
  if (previewImg) {
    previewImg.src = objectUrl;
    previewImg.style.display = 'block';
  }
  if (previewHolder) previewHolder.style.display = 'none';
}

function handleProductUrlInput(val) {
  const url = (val || '').trim();
  const previewImg = document.getElementById('pmImagePreview');
  const previewHolder = document.getElementById('pmPreviewPlaceholder');
  if (url && (url.startsWith('http://') || url.startsWith('https://'))) {
    if (previewImg) {
      previewImg.src = url;
      previewImg.style.display = 'block';
    }
    if (previewHolder) previewHolder.style.display = 'none';
  } else if (!selectedImageFile) {
    if (previewImg) previewImg.style.display = 'none';
    if (previewHolder) previewHolder.style.display = 'flex';
  }
}

// ─── SAVE PRODUCT (FIRESTORE + STORAGE) ────────────────────────
async function saveProduct() {
  const idInput = document.getElementById('pmId');
  const nameInput = document.getElementById('pmName');
  const priceInput = document.getElementById('pmPrice');
  const catInput = document.getElementById('pmCategory');
  const spicyInput = document.getElementById('pmSpicy');
  const descInput = document.getElementById('pmDesc');
  const urlInput = document.getElementById('pmImageUrl');
  const availInput = document.getElementById('pmAvailable');
  const saveBtn = document.getElementById('btnSaveProduct');
  const saveText = document.getElementById('btnSaveProductText');
  const saveIcon = document.getElementById('btnSaveProductIcon');

  const name = (nameInput?.value || '').trim();
  const price = parseFloat(priceInput?.value || '0');
  const categoryId = catInput?.value || 'tacos';
  const spicyLevel = parseInt(spicyInput?.value || '0', 10);
  const description = (descInput?.value || '').trim();
  let imageUrl = (urlInput?.value || '').trim();
  const available = availInput ? availInput.checked : true;
  const existingId = idInput?.value || null;

  if (!name) {
    showToast("Por favor ingresa el nombre del platillo", "warning");
    if (nameInput) nameInput.focus();
    return;
  }
  if (isNaN(price) || price <= 0) {
    showToast("Por favor ingresa un precio válido", "warning");
    if (priceInput) priceInput.focus();
    return;
  }

  // Generar ID si es nuevo
  const docId = existingId || ('prod_' + Date.now());

  // Indicar carga
  if (saveBtn) saveBtn.disabled = true;
  if (saveText) saveText.textContent = 'Guardando...';
  if (saveIcon) saveIcon.textContent = 'sync';

  try {
    // Si se subió archivo de imagen local, subir a Firebase Storage
    if (selectedImageFile && storage) {
      try {
        if (saveText) saveText.textContent = 'Subiendo foto...';
        const fileExt = selectedImageFile.name.split('.').pop() || 'jpg';
        const storageRef = storage.ref(`products/${docId}/main_${Date.now()}.${fileExt}`);
        const uploadSnapshot = await storageRef.put(selectedImageFile);
        imageUrl = await uploadSnapshot.ref.getDownloadURL();
      } catch (uploadErr) {
        console.warn("No se pudo subir a Storage, guardando con URL o local:", uploadErr);
      }
    }

    if (!imageUrl) {
      // Imagen por defecto apetitosa si no se suministró foto
      imageUrl = 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600';
    }

    const now = Date.now();
    const productPayload = {
      id: docId,
      name: name,
      description: description,
      price: price,
      imageUrl: imageUrl,
      categoryId: categoryId,
      spicyLevel: spicyLevel,
      available: available,
      ingredients: currentModalIngredients,
      extras: [],
      updatedAt: now
    };

    if (!existingId) {
      productPayload.createdAt = now;
    }

    await db.collection('products').doc(docId).set(productPayload, { merge: true });

    showToast(existingId ? "¡Platillo actualizado exitosamente!" : "¡Platillo creado exitosamente!", "success");
    const modal = document.getElementById('productModal');
    if (modal) modal.style.display = 'none';
  } catch (err) {
    console.error("Error al guardar platillo:", err);
    showToast("Error al guardar: " + err.message, "danger");
  } finally {
    if (saveBtn) saveBtn.disabled = false;
    if (saveText) saveText.textContent = 'Guardar Platillo';
    if (saveIcon) saveIcon.textContent = 'check';
  }
}

// ─── TOGGLE AVAILABILITY ───────────────────────────────────────
async function toggleProductAvailability(id, newStatus) {
  try {
    await db.collection('products').doc(id).update({
      available: newStatus,
      updatedAt: Date.now()
    });
    showToast(`Platillo marcado como ${newStatus ? 'Disponible' : 'Agotado'}`, "success");
  } catch (err) {
    console.error("Error al actualizar disponibilidad:", err);
    showToast("Error al actualizar disponibilidad: " + err.message, "danger");
  }
}

// ─── DELETE PRODUCT ────────────────────────────────────────────
async function deleteProduct(id) {
  const prod = allProducts.find(p => p.id === id);
  const name = prod ? prod.name : 'este platillo';
  if (!confirm(`¿Estás seguro de eliminar permanentemente "${name}" del menú?`)) {
    return;
  }

  try {
    await db.collection('products').doc(id).delete();
    showToast(`"${name}" eliminado del menú`, "success");
  } catch (err) {
    console.error("Error al eliminar platillo:", err);
    showToast("Error al eliminar: " + err.message, "danger");
  }
}

// ─── SEED BASE MENU ────────────────────────────────────────────
// ─── CATÁLOGO COMPLETO DE PRODUCTOS (ABASTECIMIENTO GENERAL) ────
const BASE_DIABLA_PRODUCTS = [
  // Test Card (para pruebas de pago)
  {
    id: 'test_tarjeta_50',
    name: 'Taco de Prueba 🧪 (Test Tarjeta)',
    description: 'Producto especial para probar cobro y pasarela de tarjetas sin gastar dinero. Valor simbólico de $50 pesos COP.',
    price: 50,
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600',
    categoryId: 'tacos',
    spicyLevel: 1,
    available: true,
    ingredients: ['Prueba de tarjeta', 'Cobro $50 COP', 'Verificación pasarela']
  },

  // ─── TACOS ───────────────────────────────────────────────────
  {
    id: 'tacos_pastor',
    name: 'Tacos al Pastor Diabla',
    description: '3 tacos de carne marinada en achiote con piña asada, cebolla, cilantro y un toque especial de salsa habanera.',
    price: 17000,
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600',
    categoryId: 'tacos',
    spicyLevel: 2,
    available: true,
    ingredients: ['Carne al pastor', 'Piña asada', 'Cebolla', 'Cilantro', 'Tortilla de maíz']
  },
  {
    id: 'tacos_birria',
    name: 'Tacos de Birria con Consomé',
    description: '3 tacos dorados de res deshebrada con queso oaxaca derretido, servidos con su consomé caliente para sopear.',
    price: 22000,
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600',
    categoryId: 'tacos',
    spicyLevel: 1,
    available: true,
    ingredients: ['Birria de res', 'Queso Oaxaca', 'Consomé caliente', 'Cebolla picada', 'Cilantro']
  },
  {
    id: 'tacos_suadero',
    name: 'Tacos de Suadero Especial',
    description: '3 tacos de suadero confitado a fuego lento, jugoso y dorado por fuera con guacamole artesanal.',
    price: 18000,
    imageUrl: 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=600',
    categoryId: 'tacos',
    spicyLevel: 1,
    available: true,
    ingredients: ['Suadero de res', 'Cebolla', 'Cilantro', 'Salsa verde borracha']
  },

  // ─── BURRITOS ────────────────────────────────────────────────
  {
    id: 'burrito_diablo',
    name: 'Burrito El Diablo 🔥',
    description: 'Gigante burrito con carne asada, frijoles refritos, arroz, queso cheddar derretido y salsa habanera La Diabla.',
    price: 29000,
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=600',
    categoryId: 'burritos',
    spicyLevel: 3,
    available: true,
    ingredients: ['Carne asada', 'Frijoles refritos', 'Arroz mexicano', 'Queso cheddar', 'Salsa habanera']
  },
  {
    id: 'burrito_pollo_chipotle',
    name: 'Burrito Pollo al Chipotle',
    description: 'Pollo desmechado bañado en salsa cremosa de chipotle, arroz mexicano, lechuga y pico de gallo.',
    price: 26000,
    imageUrl: 'https://images.unsplash.com/photo-1584031036380-3fb6f2d51880?w=600',
    categoryId: 'burritos',
    spicyLevel: 2,
    available: true,
    ingredients: ['Pechuga de pollo', 'Salsa chipotle cremosa', 'Arroz mexicano', 'Pico de gallo', 'Lechuga fresca']
  },
  {
    id: 'burrito_supremo',
    name: 'Burrito Supremo Diabla',
    description: 'Enorme burrito relleno de carne asada, arroz rojo, frijoles refritos, queso fundido y salsa de la casa.',
    price: 24000,
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=600',
    categoryId: 'burritos',
    spicyLevel: 2,
    available: true,
    ingredients: ['Tortilla de harina 30cm', 'Carne asada', 'Arroz mexicano', 'Frijoles refritos', 'Queso gouda', 'Guacamole']
  },

  // ─── QUESADILLAS ─────────────────────────────────────────────
  {
    id: 'gringa_pastor',
    name: 'Gringa de Pastor',
    description: 'Doble tortilla de harina rellena de queso fundido, carne al pastor y trozos de piña asada.',
    price: 19500,
    imageUrl: 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=600',
    categoryId: 'quesadillas',
    spicyLevel: 1,
    available: true,
    ingredients: ['Carne al pastor', 'Queso fundido Oaxaca', 'Piña caramelizada', 'Tortilla de harina']
  },
  {
    id: 'quesadilla_queso_birria',
    name: 'Quesabirria Gigante',
    description: 'Tortilla de harina dorada a la plancha con costra de queso y abundante birria marinada.',
    price: 24000,
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600',
    categoryId: 'quesadillas',
    spicyLevel: 1,
    available: true,
    ingredients: ['Birria de res', 'Costra de queso', 'Cilantro fresco', 'Cebolla', 'Consomé']
  },
  {
    id: 'quesadilla_sincronizada',
    name: 'Quesadilla Especial Diabla',
    description: 'Tortilla de harina gigante rellena de mezcla de quesos derretidos, jamón artesanal y pico de gallo.',
    price: 16000,
    imageUrl: 'https://images.unsplash.com/photo-1618040996337-56904b7850b9?w=600',
    categoryId: 'quesadillas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Tortilla de harina artesanal', 'Queso Oaxaca', 'Queso Mozzarella', 'Pico de gallo', 'Crema ácida']
  },

  // ─── MARISCOS & COCINA DE MAR ────────────────────────────────
  {
    id: 'camarones_diabla',
    name: 'Camarones a la Diabla 🔥🌶️',
    description: 'Camarones gigantes salteados en salsa explosiva de 3 chiles (árbol, chipotle y guajillo), servidos con arroz blanco.',
    price: 34000,
    imageUrl: 'https://images.unsplash.com/photo-1559742811-82286364ceaf?w=600',
    categoryId: 'mariscos',
    spicyLevel: 3,
    available: true,
    ingredients: ['Camarones tigre', 'Salsa de 3 chiles', 'Ajo rostizado', 'Arroz blanco', 'Ensalada']
  },
  {
    id: 'camarones_al_ajo',
    name: 'Camarones al Ajo 🧄',
    description: 'Tiernos camarones bañados en mantequilla dorada, abundante ajo laminado frito, perejil fresco y vino blanco.',
    price: 32000,
    imageUrl: 'https://images.unsplash.com/photo-1565557623262-b51c2513a641?w=600',
    categoryId: 'mariscos',
    spicyLevel: 0,
    available: true,
    ingredients: ['Camarones frescos', 'Ajo crocante', 'Mantequilla artesanal', 'Perejil', 'Limón']
  },
  {
    id: 'camarones_cora',
    name: 'Camarones a la Cora (Estilo Nayarit)',
    description: 'Receta secreta nayarita: camarones con chile de árbol seco, mantequilla, jugo de naranja agria y especias.',
    price: 33500,
    imageUrl: 'https://images.unsplash.com/photo-1551248429-40975aa4de74?w=600',
    categoryId: 'mariscos',
    spicyLevel: 2,
    available: true,
    ingredients: ['Camarones', 'Chile de árbol seco', 'Jugo de cítricos', 'Mantequilla', 'Cebolla morada']
  },
  {
    id: 'camarones_empanizados',
    name: 'Camarones Empanizados Doraditos 🍤',
    description: 'Camarones apanados en panko crujiente al punto dorado, acompañados de salsa tártara de la casa y papas fritas.',
    price: 31000,
    imageUrl: 'https://images.unsplash.com/photo-1535400255456-984241443b29?w=600',
    categoryId: 'mariscos',
    spicyLevel: 0,
    available: true,
    ingredients: ['Camarones en panko', 'Salsa tártara', 'Papas a la francesa', 'Limón']
  },
  {
    id: 'ceviche_camaron',
    name: 'Ceviche de Camarón Mazatlán',
    description: 'Camarones marinados en limón recién exprimido, pepino en cubos, cebolla morada, tomate, cilantro y aguacate con totopos.',
    price: 28000,
    imageUrl: 'https://images.unsplash.com/photo-1535399831218-d5bd36d1a6b3?w=600',
    categoryId: 'mariscos',
    spicyLevel: 1,
    available: true,
    ingredients: ['Camarón marinado', 'Pepino fresco', 'Cebolla morada', 'Tomate', 'Cilantro', 'Aguacate']
  },
  {
    id: 'coctel_camaron',
    name: 'Cóctel de Camarón Acapulco 🍸',
    description: 'Camarones cocidos en salsa coctelera tradicional mexicana con clamato, naranja, cebolla, cilantro, salsa inglesa y aguacate.',
    price: 29000,
    imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=600',
    categoryId: 'mariscos',
    spicyLevel: 1,
    available: true,
    ingredients: ['Camarones', 'Salsa coctelera con Clamato', 'Cebolla morada', 'Cilantro', 'Aguacate']
  },
  {
    id: 'levanta_muertos',
    name: 'Caldo Levanta Muertos 🥣⚡',
    description: 'Poderoso caldo caliente afrodisíaco de camarón, pulpo y pescado con chile chipotle, epazote y verduras.',
    price: 36000,
    imageUrl: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=600',
    categoryId: 'mariscos',
    spicyLevel: 2,
    available: true,
    ingredients: ['Camarón', 'Pulpo', 'Pescado blanco', 'Caldo de mariscos con chipotle', 'Cilantro y limón']
  },
  {
    id: 'campechana',
    name: 'Campechana Mixta Especial',
    description: 'La reina de los cócteles: generosa combinación de camarón cocido, pulpo tierno, callo, salsa bruja y aguacate.',
    price: 38000,
    imageUrl: 'https://images.unsplash.com/photo-1535399831218-d5bd36d1a6b3?w=600',
    categoryId: 'mariscos',
    spicyLevel: 1,
    available: true,
    ingredients: ['Camarón', 'Pulpo tierno', 'Callo', 'Clamato preparado', 'Aguacate fresco', 'Cilantro']
  },
  {
    id: 'endiablados',
    name: 'Mariscos Endiablados 🔥🐙',
    description: 'Surtido ardiente de camarón y pulpo salteados con pimientos asados, cebollitas caramelizadas y salsa de habanero negro.',
    price: 37000,
    imageUrl: 'https://images.unsplash.com/photo-1559742811-82286364ceaf?w=600',
    categoryId: 'mariscos',
    spicyLevel: 3,
    available: true,
    ingredients: ['Camarón tigre', 'Pulpo marinado', 'Pimientos asados', 'Salsa habanero negro', 'Cebolla']
  },
  {
    id: 'aguachile',
    name: 'Aguachile Sinaloense (Verde / Rojo) 🥑',
    description: 'Camarones frescos abiertos en mariposa, curtidos en jugo de limón con salsa de chiles serranos/chiltepín, pepino y cebolla morada.',
    price: 32000,
    imageUrl: 'https://images.unsplash.com/photo-1535399831218-d5bd36d1a6b3?w=600',
    categoryId: 'mariscos',
    spicyLevel: 3,
    available: true,
    ingredients: ['Camarón crudo curtido', 'Jugo de limón', 'Salsa de chile serrano', 'Pepino', 'Cebolla morada']
  },
  {
    id: 'pulpadita',
    name: 'Pulpadita a las Brasas 🐙',
    description: 'Tentáculos de pulpo tierno marinados en paprika ahumada y ajo, sellados a la plancha sobre cama de puré rústico de papa.',
    price: 39000,
    imageUrl: 'https://images.unsplash.com/photo-1544025162-d76694265947?w=600',
    categoryId: 'mariscos',
    spicyLevel: 1,
    available: true,
    ingredients: ['Pulpo a la plancha', 'Paprika ahumada', 'Ajo confitado', 'Puré de papa', 'Aceite de oliva']
  },

  // ─── ENSALADAS ───────────────────────────────────────────────
  {
    id: 'ensalada_cesar',
    name: 'Ensalada César con Pollo Grill 🥗',
    description: 'Fresca lechuga romana crujiente, pechuga de pollo a la parrilla, croutons dorados, queso parmesano en lajas y aderezo César.',
    price: 22000,
    imageUrl: 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=600',
    categoryId: 'ensaladas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Pechuga de pollo', 'Lechuga romana', 'Croutons', 'Queso parmesano', 'Aderezo César']
  },
  {
    id: 'ensalada_mango',
    name: 'Ensalada Tropical Mango y Aguacate 🥭🥑',
    description: 'Mix de lechugas orgánicas, cubos de mango Tommy dulce, aguacate, nueces caramelizadas, queso feta y vinagreta de maracuyá.',
    price: 21000,
    imageUrl: 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=600',
    categoryId: 'ensaladas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Mango dulce', 'Aguacate', 'Mix de lechugas', 'Nueces caramelizadas', 'Queso feta', 'Vinagreta maracuyá']
  },
  {
    id: 'taco_salad',
    name: 'Taco Salad Especial Diabla 🌮🥗',
    description: 'Gran canasta de tortilla crujiente rellena de carne o pollo, frijoles, pico de gallo, maíz dulce, guacamole y crema agria.',
    price: 27000,
    imageUrl: 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=600',
    categoryId: 'ensaladas',
    spicyLevel: 1,
    available: true,
    ingredients: ['Canasta de tortilla', 'Frijoles negros', 'Pico de gallo', 'Maíz dulce', 'Guacamole', 'Crema agria', 'Lechuga']
  },

  // ─── BEBIDAS & COCTELERÍA ────────────────────────────────────
  {
    id: 'agua_jamaica',
    name: 'Agua de Jamaica Artesanal (500ml) 🌺',
    description: 'Infusión natural de flor de jamaica mexicana con toque cítrico y endulzada al punto perfecto. Muy refrescante.',
    price: 6500,
    imageUrl: 'https://images.unsplash.com/photo-1556881286-fc6915169721?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Flor de jamaica natural', 'Limón', 'Agua filtrada', 'Hielo']
  },
  {
    id: 'agua_horchata',
    name: 'Agua de Horchata Tradicional (500ml) 🥛',
    description: 'Bebida cremosa tradicional a base de arroz, leche, canela en rama y esencia de vainilla mexicana.',
    price: 7000,
    imageUrl: 'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Arroz', 'Leche condensada', 'Canela en polvo', 'Vainilla', 'Hielo']
  },
  {
    id: 'agua_tamarindo',
    name: 'Agua de Tamarindo (500ml) 🫘',
    description: 'Pulpa de tamarindo natural hervida y macerada con azúcar de caña. El balance agridulce perfecto.',
    price: 6500,
    imageUrl: 'https://images.unsplash.com/photo-1556881286-fc6915169721?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Pulpa de tamarindo 100% natural', 'Azúcar de caña', 'Hielo']
  },
  {
    id: 'pina_colada',
    name: 'Piña Colada La Diabla 🍍🥥',
    description: 'Cremosa mezcla de piña fresca triturada, crema de coco gourmet, leche condensada y hielo frappé. ¡Elige con o sin licor!',
    price: 15000,
    imageUrl: 'https://images.unsplash.com/photo-1546171753-97d7676e4602?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Piña natural', 'Crema de coco', 'Cereza marrasquino', 'Hielo frappé']
  },
  {
    id: 'malteada_fresa',
    name: 'Malteada de Fresa Cremosa 🍓🥤',
    description: 'Helado artesanal de fresa batido con leche entera, sirope de fresas naturales, crema chantilly y chispas.',
    price: 13500,
    imageUrl: 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Helado de fresa', 'Leche entera', 'Sirope de fresa', 'Crema chantilly']
  },

  // Gaseosas (Coca-Cola, Postobón, etc.)
  {
    id: 'coca_cola_personal',
    name: 'Coca-Cola Sabor Original (400ml) 🥤',
    description: 'Botella personal bien fría de Coca-Cola original.',
    price: 4500,
    imageUrl: 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Coca-Cola 400ml bien fría']
  },
  {
    id: 'coca_cola_zero',
    name: 'Coca-Cola Zero Azúcar (400ml) 🖤',
    description: 'Todo el sabor de Coca-Cola sin calorías ni azúcar.',
    price: 4500,
    imageUrl: 'https://images.unsplash.com/photo-1554866585-cd94860890b7?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Coca-Cola Zero 400ml']
  },
  {
    id: 'coca_cola_1_5l',
    name: 'Coca-Cola Sabor Original (1.5 Litros) 🍾',
    description: 'Presentación familiar de 1.5 Litros para compartir.',
    price: 8500,
    imageUrl: 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Coca-Cola Original 1.5L']
  },
  {
    id: 'coca_cola_3l',
    name: 'Coca-Cola Mega Fiesta (3 Litros) 🎉',
    description: 'Botella gigante de 3 Litros para toda la familia.',
    price: 13000,
    imageUrl: 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Coca-Cola Mega 3L']
  },
  {
    id: 'postobon_manzana',
    name: 'Postobón Manzana (400ml / 1.5L) 🍎',
    description: 'La clásica gaseosa colombiana sabor manzana, dulce y burbujeante.',
    price: 4000,
    imageUrl: 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Postobón Manzana fría']
  },
  {
    id: 'colombiana_la_nuestra',
    name: 'Colombiana La Nuestra (400ml / 1.5L) 🇨🇴',
    description: 'Gaseosa sabor cola champaña tradicional de Colombia.',
    price: 4000,
    imageUrl: 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Colombiana La Nuestra fría']
  },
  {
    id: 'postobon_uva',
    name: 'Postobón Uva (400ml) 🍇',
    description: 'Gaseosa sabor a uva refrescante y helada.',
    price: 4000,
    imageUrl: 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Postobón Uva fría']
  },
  {
    id: 'postobon_naranja',
    name: 'Postobón Naranja (400ml) 🍊',
    description: 'Intenso sabor a naranja burbujeante.',
    price: 4000,
    imageUrl: 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Postobón Naranja fría']
  },
  {
    id: 'sprite_limon',
    name: 'Sprite Lima-Limón (400ml) 🍋',
    description: 'Burbujas cristalinas sabor lima limón bien helada.',
    price: 4500,
    imageUrl: 'https://images.unsplash.com/photo-1625772299848-391b6a87d7b3?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Sprite Lima Limón']
  },
  {
    id: 'quatro_toronja',
    name: 'Quatro Toronja (Cuatro 400ml) 🍊',
    description: 'Sabor único cítrico y amargo de toronja natural.',
    price: 4500,
    imageUrl: 'https://images.unsplash.com/photo-1625772299848-391b6a87d7b3?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Quatro Toronja helada']
  },
  {
    id: 'premio_gaseosa',
    name: 'Gaseosa Premio Roja (400ml) 🍓',
    description: 'Clásico sabor rojo dulce tradicional.',
    price: 3500,
    imageUrl: 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Premio Roja helada']
  },
  {
    id: 'ginger_ale',
    name: 'Canada Dry Ginger Ale (300ml) 🫚',
    description: 'Agua carbonatada con extracto suave de jengibre.',
    price: 5000,
    imageUrl: 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Canada Dry Ginger Ale']
  },
  {
    id: 'agua_brisa_gas',
    name: 'Agua Brisa con Gas y Limón (600ml) 💧🍋',
    description: 'Agua mineral con burbujas finas y toque de limón natural.',
    price: 3500,
    imageUrl: 'https://images.unsplash.com/photo-1548839140-29a749e1bc4e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Agua mineral con gas', 'Limón']
  },
  {
    id: 'agua_cristal_sin_gas',
    name: 'Agua Cristal Pura sin Gas (600ml) 💧',
    description: 'Agua pura de manantial tratada, fresca y ligera.',
    price: 3000,
    imageUrl: 'https://images.unsplash.com/photo-1548839140-29a749e1bc4e?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Agua pura de manantial']
  },
  {
    id: 'jugo_del_valle',
    name: 'Jugo Del Valle Néctar (400ml) 🧃',
    description: 'Delicioso néctar de fruta listo para tomar: Mora, Mango, Naranja o Guayaba.',
    price: 4500,
    imageUrl: 'https://images.unsplash.com/photo-1613478223719-2ab802602423?w=600',
    categoryId: 'bebidas',
    spicyLevel: 0,
    available: true,
    ingredients: ['Pulpa de fruta pasteurizada', 'Vitamina C']
  },

  // ─── ESPECIALES ──────────────────────────────────────────────
  {
    id: 'especial_nachos_diabla',
    name: 'Nachos Supremos La Diabla',
    description: 'Totopos crocantes de maíz bañados en abundante queso cheddar fundido, frijoles negros, jalapeños y guacamole.',
    price: 21000,
    imageUrl: 'https://images.unsplash.com/photo-1513456852971-30c0b8199d4d?w=600',
    categoryId: 'especiales',
    spicyLevel: 2,
    available: true,
    ingredients: ['Totopos de maíz', 'Queso cheddar', 'Jalapeños encurtidos', 'Frijoles negros', 'Pico de gallo', 'Guacamole']
  }
];

// ─── ABASTECIMIENTO / SEED BASE MENU ───────────────────────────
async function seedBaseProducts(force = false) {
  if (!db) return;
  if (!force) {
    if (!confirm(`¿Deseas abastecer y sincronizar el catálogo completo de La Diabla (${BASE_DIABLA_PRODUCTS.length} platillos y bebidas, incluyendo Coca-Colas, burritos, mariscos y ensaladas) en la base de datos?`)) {
      return;
    }
  }

  try {
    await ensureAdminAuth();
    showToast("Sincronizando y abasteciendo menú completo...", "info");
    const batch = db.batch();
    const now = Date.now();
    BASE_DIABLA_PRODUCTS.forEach(p => {
      const ref = db.collection('products').doc(p.id);
      batch.set(ref, {
        ...p,
        extras: [],
        createdAt: now,
        updatedAt: now
      }, { merge: true });
    });
    await batch.commit();
    showToast(`¡Catálogo completo (${BASE_DIABLA_PRODUCTS.length} platillos y bebidas) abastecido en Firestore!`, "success");
  } catch (err) {
    console.error("Error al abastecer menú:", err);
    showToast("Error al abastecer menú: " + err.message, "danger");
  }
}

// ─── INITIALIZATION ────────────────────────────────────────────
window.addEventListener('DOMContentLoaded', async () => {
  const currentTheme = document.documentElement.getAttribute('data-theme') || 'dark';
  updateThemeToggleBtnLabel(currentTheme);

  if (sessionStorage.getItem('diabla_admin_auth') !== 'true') {
    window.location.href = 'login.html';
    return;
  }
  await ensureAdminAuth();
  document.body.addEventListener('click', () => isAudioUnlocked = true, { once: true });
  initRealtimeOrders();
  initRealtimeProducts();
});

