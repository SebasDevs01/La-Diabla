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
let currentUploadTask = null; // Firebase Storage UploadTask en curso (para cancelar al cerrar modal)

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

    // La notificación push y el registro en el historial son gestionados automáticamente
    // por la Cloud Function onOrderStatusChanged para garantizar exactamente 1 notificación única.

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
  const current = document.documentElement.getAttribute('data-theme') || 'light';
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
        <div class="product-card-img-wrap" onclick="openProductDetailModal('${p.id}')" title="Click para ver ficha completa del platillo" style="cursor:pointer;">
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
            <div class="product-card-title diabla-font" onclick="openProductDetailModal('${p.id}')" title="Click para ver detalles" style="cursor:pointer;">${escapeHtml(p.name)}</div>
            <div class="product-card-price diabla-font">${formatCOP(p.price)}</div>
          </div>

          <div class="product-card-desc" onclick="openProductDetailModal('${p.id}')" style="cursor:pointer;" title="Click para ver detalles">${escapeHtml(p.description || 'Sin descripción detallada.')}</div>

          <div class="product-ingredients-wrap" onclick="openProductDetailModal('${p.id}')" style="cursor:pointer;" title="Click para ver detalles">
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
              <button class="btn-card-action" title="Ver ficha del platillo" onclick="openProductDetailModal('${p.id}')">
                <span class="material-symbols-rounded md-18">visibility</span>
              </button>
              <button class="btn-card-action" title="Editar platillo" onclick="openProductModal('${p.id}')">
                <span class="material-symbols-rounded md-18">edit</span>
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
  const originInput = document.getElementById('pmOrigin');
  const ingInput = document.getElementById('pmIngredientInput');
  const urlInput = document.getElementById('pmImageUrl');
  const filesInput = document.getElementById('pmImageFiles');
  const availInput = document.getElementById('pmAvailable');

  currentModalIngredients = [];
  currentModalImages = [];
  selectedImageFile = null;
  if (filesInput) filesInput.value = '';
  if (urlInput) urlInput.value = '';

  if (isEditing) {
    const prod = allProducts.find(p => String(p.id).trim() === String(productId).trim());
    if (prod) {
      if (title) title.textContent = 'Editar Platillo';
      if (idInput) idInput.value = prod.id;
      if (nameInput) nameInput.value = prod.name || '';
      if (priceInput) priceInput.value = prod.price || '';
      if (catInput) catInput.value = prod.categoryId || 'tacos';
      if (descInput) descInput.value = prod.description || '';
      if (originInput) originInput.value = prod.origin || prod.origen || '';
      if (availInput) availInput.checked = prod.available !== false;
      selectSpicyLevel(prod.spicyLevel || 0);

      currentModalIngredients = Array.isArray(prod.ingredients) ? [...prod.ingredients] : [];

      // Cargar TODAS las imágenes existentes de manera exhaustiva (soporta images, imageUrl, image)
      const rawUrls = [];
      if (Array.isArray(prod.images)) {
        prod.images.forEach(u => {
          if (u && typeof u === 'string' && u.trim().length > 0 && !rawUrls.includes(u.trim())) {
            rawUrls.push(u.trim());
          }
        });
      }
      if (prod.imageUrl && typeof prod.imageUrl === 'string' && prod.imageUrl.trim().length > 0) {
        const u = prod.imageUrl.trim();
        if (!rawUrls.includes(u)) {
          rawUrls.unshift(u);
        }
      }
      if (prod.image && typeof prod.image === 'string' && prod.image.trim().length > 0) {
        const u = prod.image.trim();
        if (!rawUrls.includes(u)) {
          rawUrls.unshift(u);
        }
      }

      currentModalImages = rawUrls.map((u, idx) => ({
        id: 'ex_' + idx + '_' + Math.random().toString(36).substr(2, 6),
        url: u,
        file: null,
        isPending: false
      }));
    }
  } else {
    // Creación de Nuevo Platillo
    if (title) title.textContent = 'Nuevo Platillo';
    if (idInput) idInput.value = '';
    if (nameInput) nameInput.value = '';
    if (priceInput) priceInput.value = '';
    if (catInput) catInput.value = 'tacos';
    if (descInput) descInput.value = '';
    if (originInput) originInput.value = '';
    if (availInput) availInput.checked = true;
    selectSpicyLevel(0);
    currentModalImages = [];
  }

  if (ingInput) ingInput.value = '';
  renderModalIngredientChips();
  renderModalImagesGallery();

  if (modal) {
    modal.style.display = 'flex';
  }
}

// Llamado desde el botón X — siempre cierra sin condiciones y resetea TODO el estado
function closeProductModal(event) {
  const modal = document.getElementById('productModal');
  if (modal) modal.style.display = 'none';

  // Cancelar upload en curso si existe
  if (currentUploadTask) {
    try { currentUploadTask.cancel(); } catch (_) {}
    currentUploadTask = null;
  }

  // Cancelar y limpiar imágenes seleccionadas
  selectedImageFile = null;
  currentModalImages = [];
  const filesInput = document.getElementById('pmImageFiles');
  if (filesInput) filesInput.value = '';
  const urlInput = document.getElementById('pmImageUrl');
  if (urlInput) urlInput.value = '';
  renderModalImagesGallery();

  // Resetear completamente el botón Guardar
  const saveBtn = document.getElementById('btnSaveProduct');
  const saveText = document.getElementById('btnSaveProductText');
  const saveIcon = document.getElementById('btnSaveProductIcon');
  if (saveBtn) saveBtn.disabled = false;
  if (saveText) saveText.textContent = 'Guardar Platillo';
  if (saveIcon) saveIcon.textContent = 'check';
}

// Llamado desde el backdrop — solo cierra si el click fue en el propio backdrop (no en la card)
function closeProductModalBackdrop(event) {
  if (event && event.target && event.target.id === 'productModal') {
    closeProductModal();
  }
}

// ─── PRODUCT DETAIL POP-UP MODAL (FICHA TÉCNICA DEL PLATILLO) ───
let currentDetailProductId = null;

function openProductDetailModal(productId) {
  if (!productId) return;
  const p = allProducts.find(x => x.id === productId);
  if (!p) return;

  currentDetailProductId = p.id;
  const modal = document.getElementById('productDetailModal');
  if (!modal) return;

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

  const isAvail = p.available !== false;
  const catLabel = categoryNames[p.categoryId] || p.categoryId || 'General';
  const spicyText = spicyLabels[p.spicyLevel || 0] || 'Sin picante';

  // Fotos del platillo (soporta array de images o single imageUrl)
  currentDetailImages = [];
  if (Array.isArray(p.images) && p.images.length > 0) {
    currentDetailImages = p.images.filter(u => u && typeof u === 'string' && u.trim().length > 0);
  }
  if (currentDetailImages.length === 0 && p.imageUrl && typeof p.imageUrl === 'string' && p.imageUrl.trim().length > 0) {
    currentDetailImages = [p.imageUrl.trim()];
  }
  if (currentDetailImages.length === 0) {
    currentDetailImages = ['https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600'];
  }
  currentDetailImageIndex = 0;

  // Elementos del Modal
  const headerCat = document.getElementById('pdHeaderCategory');
  const statusBadge = document.getElementById('pdStatusBadge');
  const statusIcon = document.getElementById('pdStatusIcon');
  const statusText = document.getElementById('pdStatusText');
  const catBadge = document.getElementById('pdDetailCatBadge');
  const spicyBadge = document.getElementById('pdDetailSpicyBadge');
  const idCode = document.getElementById('pdDetailIdCode');
  const nameEl = document.getElementById('pdDetailName');
  const priceEl = document.getElementById('pdDetailPrice');
  const descEl = document.getElementById('pdDetailDesc');
  const ingsEl = document.getElementById('pdDetailIngredients');
  const spicyTextEl = document.getElementById('pdDetailSpicyText');
  const catTextEl = document.getElementById('pdDetailCategoryText');
  const availTextEl = document.getElementById('pdDetailAvailText');
  const toggleBtnText = document.getElementById('pdBtnToggleAvailText');

  if (headerCat) headerCat.textContent = catLabel;
  if (nameEl) nameEl.textContent = p.name || 'Sin Nombre';
  if (priceEl) priceEl.textContent = formatCOP(p.price);
  if (idCode) idCode.textContent = `#${p.id}`;
  if (descEl) descEl.textContent = p.description || 'Sin descripción detallada para este producto.';

  // Renderizar galería de fotos de la ficha técnica
  updateDetailGalleryView(p);

  // Badges sobre la foto
  if (catBadge) catBadge.textContent = catLabel;
  if (spicyBadge) {
    if ((p.spicyLevel || 0) > 0) {
      spicyBadge.textContent = spicyText;
      spicyBadge.style.display = 'inline-block';
    } else {
      spicyBadge.style.display = 'none';
    }
  }

  // Meta cajas
  if (spicyTextEl) spicyTextEl.textContent = spicyText;
  if (catTextEl) catTextEl.textContent = catLabel;
  if (availTextEl) {
    availTextEl.textContent = isAvail ? 'Activo en la App' : 'Agotado temporalmente';
    availTextEl.style.color = isAvail ? '#22C55E' : '#EF4444';
  }

  // Badge de estado en el header
  if (statusBadge && statusIcon && statusText) {
    statusBadge.className = `product-status-pill ${isAvail ? 'pill-available' : 'pill-unavailable'}`;
    statusIcon.textContent = isAvail ? 'check_circle' : 'cancel';
    statusText.textContent = isAvail ? 'DISPONIBLE' : 'AGOTADO';
  }

  // Botón para alternar disponibilidad
  if (toggleBtnText) {
    toggleBtnText.textContent = isAvail ? 'Marcar como Agotado' : 'Marcar como Disponible';
  }

  // Lista de ingredientes en chips
  if (ingsEl) {
    if (p.ingredients && p.ingredients.length > 0) {
      ingsEl.innerHTML = p.ingredients.map(ing => `<span class="product-ingredient-chip">${escapeHtml(ing)}</span>`).join('');
    } else {
      ingsEl.innerHTML = '<span style="font-size:0.8rem; color:var(--text-muted); font-style:italic;">Sin ingredientes específicos registrados</span>';
    }
  }

  modal.style.display = 'flex';
}

function closeProductDetailModal(event) {
  if (event && event.target && !event.target.classList.contains('product-modal-backdrop') && !event.target.classList.contains('proof-modal-close') && !event.target.classList.contains('pd-btn-secondary')) {
    return;
  }
  const modal = document.getElementById('productDetailModal');
  if (modal) {
    modal.style.display = 'none';
  }
}

function editFromDetailModal() {
  const pId = currentDetailProductId;
  const modal = document.getElementById('productDetailModal');
  if (modal) modal.style.display = 'none';
  if (pId) {
    openProductModal(pId);
  }
}

async function toggleCurrentDetailProductAvail() {
  if (!currentDetailProductId) return;
  const prod = allProducts.find(p => p.id === currentDetailProductId);
  if (!prod) return;
  const newAvail = prod.available === false ? true : false;
  await toggleProductAvailability(currentDetailProductId, newAvail);
  // Refrescar modal con el nuevo estado
  openProductDetailModal(currentDetailProductId);
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
// Comprime una imagen con Canvas a max 800px / calidad 0.82 JPEG antes de subir
function compressImageFile(file) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        const MAX = 800;
        let w = img.width, h = img.height;
        if (w > MAX || h > MAX) {
          if (w > h) { h = Math.round(h * MAX / w); w = MAX; }
          else { w = Math.round(w * MAX / h); h = MAX; }
        }
        const canvas = document.createElement('canvas');
        canvas.width = w; canvas.height = h;
        canvas.getContext('2d').drawImage(img, 0, 0, w, h);
        canvas.toBlob((blob) => {
          if (!blob) { resolve(file); return; }
          const compressed = new File([blob], file.name.replace(/\.[^.]+$/, '.jpg'), { type: 'image/jpeg' });
          resolve(compressed);
        }, 'image/jpeg', 0.82);
      };
      img.onerror = () => resolve(file);
      img.src = e.target.result;
    };
    reader.onerror = () => resolve(file);
    reader.readAsDataURL(file);
  });
}

// ─── MULTI-IMAGE GALLERY MANAGEMENT IN MODAL ───────────────────
let currentModalImages = [];
let currentDetailImages = [];
let currentDetailImageIndex = 0;

// Drag & Drop handlers sobre el dropzone de subida de archivos
function handleProductDragOver(event) {
  event.preventDefault();
  event.stopPropagation();
  const dropZone = document.getElementById('pmDropZone');
  if (dropZone) dropZone.classList.add('dragover');
}

function handleProductDragLeave(event) {
  event.preventDefault();
  event.stopPropagation();
  const dropZone = document.getElementById('pmDropZone');
  if (dropZone) dropZone.classList.remove('dragover');
}

function handleProductDrop(event) {
  event.preventDefault();
  event.stopPropagation();
  const dropZone = document.getElementById('pmDropZone');
  if (dropZone) dropZone.classList.remove('dragover');

  const files = event.dataTransfer?.files;
  if (!files || files.length === 0) return;
  processProductFiles(Array.from(files));
}

// Selección de archivos desde el explorador del dispositivo / PC
function handleProductFilesSelect(event) {
  const files = event.target.files;
  if (!files || files.length === 0) return;
  processProductFiles(Array.from(files));
  event.target.value = '';
}

function processProductFiles(fileList) {
  let addedCount = 0;
  fileList.forEach((file) => {
    if (!file.type || !file.type.startsWith('image/')) return;
    const objectUrl = URL.createObjectURL(file);
    const item = {
      id: 'file_' + Date.now() + '_' + Math.random().toString(36).substr(2, 5),
      url: objectUrl,
      file: file,
      isPending: true
    };
    currentModalImages.push(item);
    addedCount++;

    // Comprimir en segundo plano para optimizar peso al subir
    compressImageFile(file).then((compressed) => {
      item.file = compressed;
    }).catch(() => {
      // Conservar file original si falla compresión
    });
  });

  if (addedCount > 0) {
    renderModalImagesGallery();
    showToast(`Se añadieron ${addedCount} foto(s) a la vista previa`, 'info');
  }
}

// Manejador tecla Enter en el input de URL
function handleProductUrlKey(event) {
  if (event.key === 'Enter') {
    event.preventDefault();
    addModalImageFromUrl();
  }
}

// Añadir foto mediante botón "+" o tecla Enter
function addModalImageFromUrl() {
  const input = document.getElementById('pmImageUrl');
  if (!input) return;
  const val = (input.value || '').trim();
  if (!val) {
    showToast("Pega primero la URL de una foto en el campo de texto", "warning");
    input.focus();
    return;
  }

  // Soporta múltiples URLs pegadas separadas por comas o saltos de línea
  const rawUrls = val.split(/[\n,]+/).map(s => s.trim()).filter(Boolean);
  let added = 0;

  rawUrls.forEach(urlStr => {
    let cleanUrl = urlStr;
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      if (cleanUrl.startsWith('www.') || cleanUrl.includes('.')) {
        cleanUrl = 'https://' + cleanUrl;
      } else {
        return;
      }
    }
    // Evitar URLs duplicadas
    if (!currentModalImages.some(img => img.url === cleanUrl)) {
      currentModalImages.push({
        id: 'url_' + Date.now() + '_' + Math.random().toString(36).substr(2, 5),
        url: cleanUrl,
        file: null,
        isPending: false
      });
      added++;
    }
  });

  if (added > 0) {
    input.value = '';
    renderModalImagesGallery();
    showToast(`¡${added} foto(s) agregada(s) a la vista previa!`, "success");
  } else {
    showToast("Por favor ingresa una URL válida (ej: https://...)", "warning");
  }
}

function removeModalImage(index) {
  if (index < 0 || index >= currentModalImages.length) return;
  currentModalImages.splice(index, 1);
  renderModalImagesGallery();
}

function setModalImagePrimary(index) {
  if (index <= 0 || index >= currentModalImages.length) return;
  const [item] = currentModalImages.splice(index, 1);
  currentModalImages.unshift(item);
  renderModalImagesGallery();
  showToast("Foto establecida como portada principal", "info");
}

function renderModalImagesGallery() {
  const grid = document.getElementById('pmImagesGrid');
  const placeholder = document.getElementById('pmImagesEmptyPlaceholder');
  const badge = document.getElementById('pmPhotoCountBadge');

  if (badge) {
    badge.textContent = `${currentModalImages.length} foto${currentModalImages.length === 1 ? '' : 's'}`;
  }

  if (!grid || !placeholder) return;

  if (currentModalImages.length === 0) {
    grid.innerHTML = '';
    grid.style.display = 'none';
    placeholder.style.display = 'flex';
    return;
  }

  placeholder.style.display = 'none';
  grid.style.display = 'grid';

  grid.innerHTML = currentModalImages.map((img, idx) => {
    const isPrimary = idx === 0;
    const isLocalFile = !!img.file;
    return `
      <div class="pm-image-card ${isPrimary ? 'is-primary' : ''}">
        <img src="${escapeHtml(img.url)}" alt="Foto ${idx + 1}" onerror="this.src='https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600'">
        ${isPrimary ? `<span class="pm-primary-badge"><span class="material-symbols-rounded" style="font-size:12px;">star</span> Principal</span>` : ''}
        ${isLocalFile && !isPrimary ? `<span class="pm-local-badge" title="Foto desde archivo local"><span class="material-symbols-rounded" style="font-size:11px;">cloud_upload</span> Archivo</span>` : ''}
        <div class="pm-image-actions">
          <button type="button" class="pm-btn-icon" onclick="removeModalImage(${idx})" title="Eliminar foto">&times;</button>
        </div>
        ${!isPrimary ? `<button type="button" class="pm-btn-set-primary" onclick="setModalImagePrimary(${idx})">⭐ Hacer Principal</button>` : ''}
      </div>
    `;
  }).join('');
}

// ─── DETAIL MODAL GALLERY CONTROLS ─────────────────────────────
function updateDetailGalleryView(p) {
  if (!currentDetailImages || currentDetailImages.length === 0) return;
  if (currentDetailImageIndex < 0) currentDetailImageIndex = 0;
  if (currentDetailImageIndex >= currentDetailImages.length) currentDetailImageIndex = currentDetailImages.length - 1;

  const currentUrl = currentDetailImages[currentDetailImageIndex];
  const imgEl = document.getElementById('pdDetailImg');
  const imgOpenLink = document.getElementById('pdDetailImgOpen');
  const prevBtn = document.getElementById('pdGalleryPrev');
  const nextBtn = document.getElementById('pdGalleryNext');
  const counterEl = document.getElementById('pdGalleryCounter');
  const stripEl = document.getElementById('pdDetailGalleryStrip');

  if (imgEl) {
    imgEl.src = currentUrl;
    imgEl.alt = (p && p.name) ? p.name : 'Platillo';
  }
  if (imgOpenLink) {
    imgOpenLink.href = currentUrl;
  }

  const hasMultiple = currentDetailImages.length > 1;
  if (prevBtn) prevBtn.style.display = hasMultiple ? 'flex' : 'none';
  if (nextBtn) nextBtn.style.display = hasMultiple ? 'flex' : 'none';
  if (counterEl) {
    counterEl.style.display = hasMultiple ? 'block' : 'none';
    counterEl.textContent = `${currentDetailImageIndex + 1} / ${currentDetailImages.length}`;
  }

  if (stripEl) {
    if (hasMultiple) {
      stripEl.style.display = 'flex';
      stripEl.innerHTML = currentDetailImages.map((img, idx) => `
        <img src="${escapeHtml(img)}" class="pd-gallery-thumb ${idx === currentDetailImageIndex ? 'active' : ''}" 
          onclick="setDetailImageIndex(${idx})" alt="Miniatura ${idx + 1}" title="Foto ${idx + 1}">
      `).join('');
    } else {
      stripEl.style.display = 'none';
      stripEl.innerHTML = '';
    }
  }
}

function prevDetailImage() {
  if (!currentDetailImages || currentDetailImages.length <= 1) return;
  currentDetailImageIndex = (currentDetailImageIndex - 1 + currentDetailImages.length) % currentDetailImages.length;
  updateDetailGalleryView();
}

function nextDetailImage() {
  if (!currentDetailImages || currentDetailImages.length <= 1) return;
  currentDetailImageIndex = (currentDetailImageIndex + 1) % currentDetailImages.length;
  updateDetailGalleryView();
}

function setDetailImageIndex(idx) {
  if (!currentDetailImages || idx < 0 || idx >= currentDetailImages.length) return;
  currentDetailImageIndex = idx;
  updateDetailGalleryView();
}

// ─── SAVE PRODUCT (FIRESTORE + STORAGE MULTI-FOTO) ─────────────
async function saveProduct() {
  const idInput = document.getElementById('pmId');
  const nameInput = document.getElementById('pmName');
  const priceInput = document.getElementById('pmPrice');
  const catInput = document.getElementById('pmCategory');
  const spicyInput = document.getElementById('pmSpicy');
  const descInput = document.getElementById('pmDesc');
  const availInput = document.getElementById('pmAvailable');
  const saveBtn = document.getElementById('btnSaveProduct');
  const saveText = document.getElementById('btnSaveProductText');
  const saveIcon = document.getElementById('btnSaveProductIcon');

  const name = (nameInput?.value || '').trim();
  const price = parseFloat(priceInput?.value || '0');
  const categoryId = catInput?.value || 'tacos';
  const spicyLevel = parseInt(spicyInput?.value || '0', 10);
  const description = (descInput?.value || '').trim();
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
    // Si el usuario pegó o escribió una URL en el campo pero olvidó pulsar el botón +, capturarla automáticamente
    const leftoverUrlInput = document.getElementById('pmImageUrl');
    if (leftoverUrlInput && leftoverUrlInput.value) {
      let rawVal = leftoverUrlInput.value.trim();
      if (rawVal.startsWith('http://') || rawVal.startsWith('https://')) {
        if (!currentModalImages.some(img => img.url === rawVal)) {
          currentModalImages.push({
            id: 'url_leftover_' + Date.now(),
            url: rawVal,
            file: null,
            isPending: false
          });
          leftoverUrlInput.value = '';
        }
      }
    }

    const finalImagesUrls = [];

    // Subir cada foto pendiente a Firebase Storage
    for (let i = 0; i < currentModalImages.length; i++) {
      const item = currentModalImages[i];
      if (item.file && storage) {
        try {
          if (saveText) saveText.textContent = `Subiendo foto ${i + 1}/${currentModalImages.length}...`;
          const storageRef = storage.ref(`products/${docId}/img_${Date.now()}_${i}.jpg`);
          currentUploadTask = storageRef.put(item.file);
          const uploadPromise = currentUploadTask.then(snap => snap.ref.getDownloadURL());
          const timeoutPromise = new Promise((_, reject) =>
            setTimeout(() => reject(new Error('Upload timeout (30s)')), 30000)
          );
          const downloadUrl = await Promise.race([uploadPromise, timeoutPromise]);
          currentUploadTask = null;
          finalImagesUrls.push(downloadUrl);
        } catch (uploadErr) {
          currentUploadTask = null;
          if (uploadErr.code === 'storage/cancelled') return;
          console.warn("Error subiendo foto a Storage:", uploadErr);
        }
      } else if (item.url && (item.url.startsWith('http://') || item.url.startsWith('https://'))) {
        finalImagesUrls.push(item.url);
      }
    }

    // Fallback si no quedó ninguna imagen
    if (finalImagesUrls.length === 0) {
      finalImagesUrls.push('https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600');
    }

    const primaryImageUrl = finalImagesUrls[0];
    const origin = (document.getElementById('pmOrigin')?.value || '').trim();
    const now = Date.now();

    const productPayload = {
      id: docId,
      name: name,
      description: description,
      origin: origin,
      price: price,
      imageUrl: primaryImageUrl,
      images: finalImagesUrls,
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

// ─── NORMALIZAR NOMBRES PARA COMPARACIÓN ─────────────────────
function normalizeMenuName(str) {
  return (str || '')
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/s\b/g, '') // convierte plurales a singulares: enchiladas -> enchilada
    .replace(/[^a-z0-9]/g, "");
}

// ─── CATÁLOGO OFICIAL DE 14 PLATILLOS DE LA DIABLA ─────────────
const OFFICIAL_DIABLA_PRODUCTS = [
  {
    id: 'aguachiles',
    name: 'Aguachiles',
    description: 'Camarón marinado/curtido en especias picantes, cebolla, jalapeño, pepino, jugo de limón fresco y aguacate.',
    price: 49900,
    imageUrl: 'https://images.unsplash.com/photo-1535400255456-984241443b29?w=600',
    categoryId: 'mariscos',
    spicyLevel: 3, // Diabla 🔥
    available: true,
    ingredients: ['Camarón', 'Especias picantes', 'Cebolla', 'Jalapeño', 'Pepino', 'Jugo de limón', 'Aguacate']
  },
  {
    id: 'aguachiles_mixtos',
    name: 'Aguachiles mixtos',
    description: 'Camarones y pulpo marinados en especias picantes, limón, jalapeño, cebolla, pepino y aguacate.',
    price: 69900,
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600',
    categoryId: 'mariscos',
    spicyLevel: 3, // Diabla 🔥
    available: true,
    ingredients: ['Pulpo', 'Camarón', 'Especias picantes', 'Cebolla', 'Jalapeño', 'Pepino', 'Jugo de limón', 'Aguacate']
  },
  {
    id: 'pulpaditas',
    name: 'Pulpaditas',
    description: 'Tres mini tostadas de pulpo acompañadas de cebolla, mango, pepino y aguacate.',
    price: 39900,
    imageUrl: 'https://images.unsplash.com/photo-1544025162-d76694265947?w=600',
    categoryId: 'mariscos',
    spicyLevel: 0, // Sin picante
    available: true,
    ingredients: ['Tres mini tostadas de pulpo con cebolla', 'mango', 'pepino', 'aguacate']
  },
  {
    id: 'enchiladas_pollo',
    name: 'Enchilada de pollo',
    description: 'Enchilada rellena de pollo deshebrado, cubierta con salsa de mole y queso, con salsa verde opcional.',
    price: 19900,
    imageUrl: 'https://images.unsplash.com/photo-1584031036380-3fb6f2d51880?w=600',
    categoryId: 'enchiladas',
    spicyLevel: 1, // Suave 🌶️
    available: true,
    ingredients: ['Pollo deshebrado', 'salsa de mole', 'queso jack', 'salsa verde (opcional)']
  },
  {
    id: 'enchiladas_queso',
    name: 'Enchilada de queso',
    description: 'Enchilada rellena de queso y cubierta con salsa de mole y queso, con salsa verde opcional.',
    price: 18900,
    imageUrl: 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=600',
    categoryId: 'enchiladas',
    spicyLevel: 1, // Suave 🌶️
    available: true,
    ingredients: ['Queso', 'Salsa de mole', 'Queso Jack', 'Salsa verde (opcional)']
  },
  {
    id: 'enchiladas_res',
    name: 'Enchilada de res',
    description: 'Enchilada rellena de carne de res deshebrada, cubierta con salsa de mole y queso, con salsa verde opcional.',
    price: 22000,
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600',
    categoryId: 'enchiladas',
    spicyLevel: 1, // Suave 🌶️
    available: true,
    ingredients: ['Carne de res deshebrada', 'Salsa de mole', 'Queso Jack', 'Salsa verde (opcional)']
  },
  {
    id: 'burrito_carne_asada',
    name: 'Burrito de carne asada',
    description: 'Burrito de tortilla de harina relleno de carne asada, arroz, frijoles y queso.',
    price: 39500,
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=600',
    categoryId: 'burritos',
    spicyLevel: 0, // Sin picante
    available: true,
    ingredients: ['Carne Black Angus', 'Arroz', 'Frijoles', 'Queso']
  },
  {
    id: 'burrito_pollo',
    name: 'Burrito de pollo',
    description: 'Burrito de tortilla de harina relleno de pollo deshebrado, frijoles, arroz y queso.',
    price: 29900,
    imageUrl: 'https://images.unsplash.com/photo-1584031036380-3fb6f2d51880?w=600',
    categoryId: 'burritos',
    spicyLevel: 0, // Sin picante
    available: true,
    ingredients: ['Pollo', 'Arroz', 'Frijoles', 'Queso Jack']
  },
  {
    id: 'burrito_res',
    name: 'Burrito de res',
    description: 'Burrito de tortilla de harina relleno de carne de res deshebrada, frijoles, arroz y queso.',
    price: 32900,
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=600',
    categoryId: 'burritos',
    spicyLevel: 0, // Sin picante
    available: true,
    ingredients: ['Carne de res deshebrada', 'Arroz', 'Frijoles', 'Queso Jack']
  },
  {
    id: 'pollo_asado',
    name: 'Burrito de pollo asado (A la mexicana)',
    description: 'Burrito de tortilla de harina relleno de pollo asado, arroz, frijoles, aguacate, vegetales y queso cheddar.',
    price: 39900,
    imageUrl: 'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?w=600',
    categoryId: 'burritos',
    spicyLevel: 0, // Sin picante
    available: true,
    ingredients: [
      'pollo asado en tiras',
      'tortilla de trigo',
      'frijoles',
      'aguacate',
      'lechuga romana',
      'tomate',
      'cebolla morada',
      'maíz dulce',
      'queso cheddar',
      'pico de gallo',
      'limón verde',
      'crema agria'
    ]
  },
  {
    id: 'fajitas_pollo',
    name: 'Fajitas de pollo',
    description: 'Fajitas de pollo preparadas al momento con pimientos, cebolla asada, tomate y salsa especial de la casa.',
    price: 42900,
    imageUrl: 'https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2, // Medio 🌶️🌶️
    available: true,
    ingredients: ['Pollo', 'Pimientos', 'Cebolla asada', 'Tomate', 'Salsa de fajitas', 'Arroz', 'Frijoles', 'Crema', 'Queso', 'Guacamole', 'Tortilla de maíz o harina']
  },
  {
    id: 'fajitas_camaron',
    name: 'Fajitas de camarón',
    description: 'Camarones salteados al estilo fajita con pimientos, cebolla asada, tomate y salsa especial de la casa.',
    price: 49900,
    imageUrl: 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2, // Medio 🌶️🌶️
    available: true,
    ingredients: ['Camarón', 'Pimientos', 'Cebolla asada', 'Tomate', 'Salsa de fajitas', 'Arroz', 'Frijoles', 'Crema', 'Queso', 'Guacamole', 'Tortilla de maíz o harina']
  },
  {
    id: 'fajitas_mixtas',
    name: 'Fajitas mixtas',
    description: 'Combinación de carne asada, camarón y pollo preparados con pimientos, cebolla, tomate y salsa especial de la casa.',
    price: 54900,
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2, // Medio 🌶️🌶️
    available: true,
    ingredients: ['Carne asada', 'Pollo', 'Camarón', 'Pimientos', 'Cebolla asada', 'Tomate', 'Salsa de fajitas', 'Arroz', 'Frijoles', 'Crema', 'Queso', 'Guacamole', 'Tortilla de maíz o harina']
  },
  {
    id: 'fajitas_asada',
    name: 'Fajitas de asada',
    description: 'Tiras tiernas de carne asada preparadas al momento con pimientos, cebolla asada, tomate y salsa especial de la casa.',
    price: 47900,
    imageUrl: 'https://images.unsplash.com/photo-1599974579688-8dbdd335c77f?w=600',
    categoryId: 'fajitas',
    spicyLevel: 2, // Medio 🌶️🌶️
    available: true,
    ingredients: ['Carne asada', 'Pimientos', 'Cebolla asada', 'Tomate', 'Salsa de fajitas', 'Arroz', 'Frijoles', 'Crema', 'Queso', 'Guacamole', 'Tortilla de maíz o harina']
  }
];

const BASE_DIABLA_PRODUCTS = OFFICIAL_DIABLA_PRODUCTS;




// ─── INITIALIZATION ────────────────────────────────────────────
window.addEventListener('DOMContentLoaded', async () => {
  const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
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

// ─── BLOQUEO DE ZOOM TÁCTIL / PELLIZCO EN MÓVILES Y TABLETS ──
document.addEventListener('touchstart', function (e) {
  if (e.touches && e.touches.length > 1) {
    e.preventDefault();
  }
}, { passive: false });

document.addEventListener('touchmove', function (e) {
  if (e.touches && e.touches.length > 1) {
    e.preventDefault();
  }
}, { passive: false });

document.addEventListener('gesturestart', function (e) {
  e.preventDefault();
});
document.addEventListener('gesturechange', function (e) {
  e.preventDefault();
});
document.addEventListener('gestureend', function (e) {
  e.preventDefault();
});

