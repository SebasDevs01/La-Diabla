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

  const evidenceCount = allOrders
    .filter(o => !!o.deliveryProofUrl).length;

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

  if (filtered.length === 0) {
    const isEvidenceFilter = currentFilter === 'evidence';
    grid.innerHTML = `
      <div class="empty-state">
        <span class="material-symbols-rounded md-48" style="color:var(--text-muted); opacity:0.6; margin-bottom:12px;">${isEvidenceFilter ? 'photo_camera' : 'ramen_dining'}</span>
        <h3 class="diabla-font">${isEvidenceFilter ? 'Sin evidencias registradas' : 'Sin órdenes en esta categoría'}</h3>
        <p>${isEvidenceFilter ? 'Cuando un repartidor tome la foto de entrega desde la app, aparecerá aquí con visor en alta resolución.' : 'Los nuevos pedidos aparecerán aquí en tiempo real'}</p>
      </div>
    `;
    return;
  }

  if (currentFilter === 'evidence') {
    grid.innerHTML = filtered.map(order => {
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
            <img src="${proofUrl}" alt="Evidencia Pedido #${shortId}" class="evidence-thumb-img" onerror="this.src='data:image/svg+xml;utf8,<svg xmlns=\\'http://www.w3.org/2000/svg\\' width=\\'200\\' height=\\'200\\'><rect width=\\'100%\\' height=\\'100%\\' fill=\\'%23333\\'/><text x=\\'50%\\' y=\\'50%\\' fill=\\'%23888\\' dominant-baseline=\\'middle\\' text-anchor=\\'middle\\'>Error Cargando Foto</text></svg>'">
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
  if (!url || !url.startsWith('http')) return;

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

// Init
window.addEventListener('DOMContentLoaded', () => {
  const currentTheme = document.documentElement.getAttribute('data-theme') || 'dark';
  updateThemeToggleBtnLabel(currentTheme);

  if (sessionStorage.getItem('diabla_admin_auth') !== 'true') {
    window.location.href = 'login.html';
    return;
  }
  document.body.addEventListener('click', () => isAudioUnlocked = true, { once: true });
  initRealtimeOrders();
});
