/**
 * RappiSim — Simulación frontend tipo Rappi
 * Basado en el esquema PostgreSQL delivery_db
 */

// --- Catálogo maestro ---
const CATALOGO = {
  TIPO_VEHICULO: [
    { id: 1, codigo: 'BICI', nombre: 'Bicicleta', icon: '🚲' },
    { id: 2, codigo: 'MOTO', nombre: 'Motocicleta', icon: '🏍️' },
    { id: 3, codigo: 'AUTO', nombre: 'Automóvil', icon: '🚗' },
    { id: 4, codigo: 'OTRO', nombre: 'Otro', icon: '🛵' },
  ],
  ESTADO_PEDIDO: [
    { id: 5, codigo: 'CREADO', nombre: 'Creado', orden: 1 },
    { id: 6, codigo: 'CONFIRMADO', nombre: 'Confirmado', orden: 2 },
    { id: 7, codigo: 'EN_CAMINO', nombre: 'En camino', orden: 3 },
    { id: 8, codigo: 'ENTREGADO', nombre: 'Entregado', orden: 4 },
    { id: 9, codigo: 'CANCELADO', nombre: 'Cancelado', orden: 5 },
  ],
  METODO_PAGO: [
    { id: 10, codigo: 'EFECTIVO', nombre: 'Efectivo', icon: '💵' },
    { id: 11, codigo: 'TARJETA', nombre: 'Tarjeta', icon: '💳' },
    { id: 12, codigo: 'YAPE', nombre: 'Yape', icon: '📱' },
    { id: 13, codigo: 'PLIN', nombre: 'Plin', icon: '📲' },
    { id: 14, codigo: 'TRANSFERENCIA', nombre: 'Transferencia', icon: '🏦' },
  ],
};

// --- Verticales estilo super-app Rappi ---
const VERTICALES = [
  { id: 'todos', nombre: 'Todo', icon: '✨', color: '#ff441f' },
  { id: 'restaurantes', nombre: 'Restaurantes', icon: '🍔', color: '#ff6b35' },
  { id: 'mercados', nombre: 'Mercados', icon: '🛒', color: '#43a047' },
  { id: 'farmacias', nombre: 'Farmacias', icon: '💊', color: '#1e88e5' },
  { id: 'cafes', nombre: 'Cafés', icon: '☕', color: '#8d6e63' },
  { id: 'saludable', nombre: 'Saludable', icon: '🥗', color: '#66bb6a' },
];

const PROMOS = [
  { titulo: 'Envío gratis en tu 1er pedido', desc: 'Código BIENVENIDO al pagar', gradient: 'linear-gradient(135deg,#ff441f,#ff7a59)' },
  { titulo: '30% OFF en Sabor Peruano', desc: 'Platos seleccionados esta semana', gradient: 'linear-gradient(135deg,#e65100,#ff9800)' },
  { titulo: '10% con RAPPI10', desc: 'Descuento en tu subtotal', gradient: 'linear-gradient(135deg,#6a1b9a,#ab47bc)' },
];

const CUPONES = {
  BIENVENIDO: { tipo: 'envio', desc: 'Envío gratis aplicado' },
  RAPPI10: { tipo: 'porcentaje', valor: 10, desc: '10% de descuento en subtotal' },
};

const POPULARES = [
  { id_producto: 1, id_comercio: 1, nombre: 'Lomo saltado', precio: 28, emoji: '🥩', ventas: 1240 },
  { id_producto: 7, id_comercio: 2, nombre: 'Pizza Margarita', precio: 35, emoji: '🍕', ventas: 980 },
  { id_producto: 3, id_comercio: 1, nombre: 'Ceviche mixto', precio: 32, emoji: '🐟', ventas: 870 },
  { id_producto: 13, id_comercio: 3, nombre: 'Bowl Proteína', precio: 29, emoji: '💪', ventas: 650 },
  { id_producto: 18, id_comercio: 4, nombre: 'Cappuccino', precio: 12, emoji: '🤎', ventas: 2100 },
  { id_producto: 26, id_comercio: 6, nombre: 'Paracetamol x20', precio: 8, emoji: '💊', ventas: 430 },
];

// --- Cliente (persona → usuario → cliente) ---
const CLIENTE = {
  id_cliente: 1,
  persona: {
    nombres: 'María',
    apellidos: 'García López',
    correo: 'maria.garcia@email.com',
    direccion: 'Av. Javier Prado 1234, San Borja',
    referencia: 'Edificio Torre Azul, piso 8',
    telefono: '987654321',
  },
};

const DIRECCIONES_GUARDADAS = [
  { id: 1, direccion: 'Av. Javier Prado 1234, San Borja', referencia: 'Torre Azul, piso 8', principal: true },
  { id: 2, direccion: 'Calle Las Flores 567, Miraflores', referencia: 'Casa blanca con portón negro', principal: false },
];

// --- Comercios ---
const COMERCIOS = [
  {
    id_comercio: 1,
    nombre: 'Sabor Peruano',
    vertical: 'restaurantes',
    direccion: 'Jr. de la Unión 456, Lima Centro',
    telefono: '014567890',
    activo: true,
    emoji: '🍲',
    gradient: 'linear-gradient(135deg,#c2410c,#ea580c)',
    rating: 4.8,
    tiempo_min: 25,
    tiempo_max: 35,
    costo_envio: 4.90,
    envio_gratis_desde: 50,
    promo: '30% OFF',
    categorias: [
      { id_categoria: 1, nombre: 'Platos principales' },
      { id_categoria: 2, nombre: 'Bebidas' },
      { id_categoria: 3, nombre: 'Postres' },
    ],
    productos: [
      { id_producto: 1, id_categoria: 1, nombre: 'Lomo saltado', descripcion: 'Clásico peruano con papas fritas y arroz.', precio: 28.0, emoji: '🥩' },
      { id_producto: 2, id_categoria: 1, nombre: 'Ají de gallina', descripcion: 'Pollo deshilachado en crema de ají amarillo.', precio: 24.0, emoji: '🍗' },
      { id_producto: 3, id_categoria: 1, nombre: 'Ceviche mixto', descripcion: 'Pescado, calamares y langostinos frescos.', precio: 32.0, emoji: '🐟' },
      { id_producto: 4, id_categoria: 2, nombre: 'Chicha morada', descripcion: 'Refresco tradicional de maíz morado.', precio: 8.0, emoji: '🥤' },
      { id_producto: 5, id_categoria: 2, nombre: 'Inca Kola 500ml', descripcion: 'Gaseosa peruana.', precio: 5.0, emoji: '🍾' },
      { id_producto: 6, id_categoria: 3, nombre: 'Suspiro limeño', descripcion: 'Postre de manjar blanco y merengue.', precio: 12.0, emoji: '🍮' },
    ],
  },
  {
    id_comercio: 2,
    nombre: 'Pizza Napoli',
    vertical: 'restaurantes',
    direccion: 'Av. Benavides 789, Miraflores',
    telefono: '015678901',
    activo: true,
    emoji: '🍕',
    gradient: 'linear-gradient(135deg,#b91c1c,#dc2626)',
    rating: 4.6,
    tiempo_min: 30,
    tiempo_max: 45,
    costo_envio: 5.50,
    envio_gratis_desde: null,
    promo: null,
    categorias: [
      { id_categoria: 4, nombre: 'Pizzas' },
      { id_categoria: 5, nombre: 'Complementos' },
    ],
    productos: [
      { id_producto: 7, id_categoria: 4, nombre: 'Pizza Margarita', descripcion: 'Tomate, mozzarella y albahaca fresca.', precio: 35.0, emoji: '🍕' },
      { id_producto: 8, id_categoria: 4, nombre: 'Pizza Hawaiana', descripcion: 'Jamón, piña y queso mozzarella.', precio: 38.0, emoji: '🍍' },
      { id_producto: 9, id_categoria: 4, nombre: 'Pizza Pepperoni', descripcion: 'Pepperoni premium y extra queso.', precio: 40.0, emoji: '🌶️' },
      { id_producto: 10, id_categoria: 5, nombre: 'Palitos de ajo', descripcion: '6 unidades con salsa marinara.', precio: 14.0, emoji: '🥖' },
      { id_producto: 11, id_categoria: 5, nombre: 'Ensalada César', descripcion: 'Lechuga, crutones, parmesano y aderezo.', precio: 18.0, emoji: '🥗' },
    ],
  },
  {
    id_comercio: 3,
    nombre: 'Green Bowl',
    vertical: 'saludable',
    direccion: 'Calle Las Begonias 321, San Isidro',
    telefono: '016789012',
    activo: true,
    emoji: '🥗',
    gradient: 'linear-gradient(135deg,#15803d,#22c55e)',
    rating: 4.9,
    tiempo_min: 20,
    tiempo_max: 30,
    costo_envio: 3.90,
    envio_gratis_desde: 40,
    promo: 'Envío gratis',
    categorias: [
      { id_categoria: 6, nombre: 'Bowls' },
      { id_categoria: 7, nombre: 'Smoothies' },
    ],
    productos: [
      { id_producto: 12, id_categoria: 6, nombre: 'Bowl Mediterráneo', descripcion: 'Quinoa, hummus, pepino, tomate y aceitunas.', precio: 26.0, emoji: '🥙' },
      { id_producto: 13, id_categoria: 6, nombre: 'Bowl Proteína', descripcion: 'Pollo grillado, arroz integral y vegetales.', precio: 29.0, emoji: '💪' },
      { id_producto: 14, id_categoria: 6, nombre: 'Bowl Vegano', descripcion: 'Tofu, aguacate, edamame y semillas.', precio: 27.0, emoji: '🌱' },
      { id_producto: 15, id_categoria: 7, nombre: 'Smoothie Verde', descripcion: 'Espinaca, plátano, manzana y jengibre.', precio: 15.0, emoji: '🍏' },
      { id_producto: 16, id_categoria: 7, nombre: 'Smoothie Tropical', descripcion: 'Mango, piña y coco.', precio: 16.0, emoji: '🥭' },
    ],
  },
  {
    id_comercio: 4,
    nombre: 'Café Aroma',
    vertical: 'cafes',
    direccion: 'Av. Larco 567, Miraflores',
    telefono: '017890123',
    activo: true,
    emoji: '☕',
    gradient: 'linear-gradient(135deg,#78350f,#a16207)',
    rating: 4.7,
    tiempo_min: 15,
    tiempo_max: 25,
    costo_envio: 3.50,
    envio_gratis_desde: null,
    promo: '2x1 en cafés',
    categorias: [
      { id_categoria: 8, nombre: 'Cafés' },
      { id_categoria: 9, nombre: 'Pastelería' },
    ],
    productos: [
      { id_producto: 17, id_categoria: 8, nombre: 'Espresso', descripcion: 'Café de origen peruano, tueste medio.', precio: 9.0, emoji: '☕' },
      { id_producto: 18, id_categoria: 8, nombre: 'Cappuccino', descripcion: 'Espresso con leche espumada.', precio: 12.0, emoji: '🤎' },
      { id_producto: 19, id_categoria: 8, nombre: 'Latte de vainilla', descripcion: 'Espresso, leche y vainilla natural.', precio: 14.0, emoji: '🥛' },
      { id_producto: 20, id_categoria: 9, nombre: 'Croissant', descripcion: 'Mantequilla francesa, horneado diario.', precio: 8.0, emoji: '🥐' },
      { id_producto: 21, id_categoria: 9, nombre: 'Cheesecake', descripcion: 'Con coulis de frutos rojos.', precio: 15.0, emoji: '🍰' },
    ],
  },
  {
    id_comercio: 5,
    nombre: 'Mercado Express',
    vertical: 'mercados',
    direccion: 'Av. Angamos 234, Surquillo',
    telefono: '018901234',
    activo: true,
    emoji: '🛒',
    gradient: 'linear-gradient(135deg,#2e7d32,#43a047)',
    rating: 4.5,
    tiempo_min: 35,
    tiempo_max: 50,
    costo_envio: 6.90,
    envio_gratis_desde: 80,
    promo: null,
    categorias: [
      { id_categoria: 10, nombre: 'Abarrotes' },
      { id_categoria: 11, nombre: 'Lácteos' },
    ],
    productos: [
      { id_producto: 22, id_categoria: 10, nombre: 'Arroz Costeño 1kg', descripcion: 'Arroz extra graneado.', precio: 5.5, emoji: '🍚' },
      { id_producto: 23, id_categoria: 10, nombre: 'Aceite Primor 1L', descripcion: 'Aceite vegetal.', precio: 12.0, emoji: '🫒' },
      { id_producto: 24, id_categoria: 11, nombre: 'Leche Gloria 1L', descripcion: 'Leche evaporada.', precio: 6.5, emoji: '🥛' },
      { id_producto: 25, id_categoria: 11, nombre: 'Yogurt Gloria pack x4', descripcion: 'Sabores surtidos.', precio: 9.0, emoji: '🧁' },
    ],
  },
  {
    id_comercio: 6,
    nombre: 'Farmacia Vital',
    vertical: 'farmacias',
    direccion: 'Av. Primavera 890, Santiago de Surco',
    telefono: '019012345',
    activo: true,
    emoji: '💊',
    gradient: 'linear-gradient(135deg,#1565c0,#42a5f5)',
    rating: 4.4,
    tiempo_min: 20,
    tiempo_max: 35,
    costo_envio: 4.50,
    envio_gratis_desde: 60,
    promo: '15% en vitaminas',
    categorias: [
      { id_categoria: 12, nombre: 'Medicamentos' },
      { id_categoria: 13, nombre: 'Cuidado personal' },
    ],
    productos: [
      { id_producto: 26, id_categoria: 12, nombre: 'Paracetamol 500mg x20', descripcion: 'Analgésico y antipirético.', precio: 8.0, emoji: '💊' },
      { id_producto: 27, id_categoria: 12, nombre: 'Vitamina C 1000mg', descripcion: 'Suplemento vitamínico x30.', precio: 22.0, emoji: '🍊' },
      { id_producto: 28, id_categoria: 13, nombre: 'Alcohol en gel 500ml', descripcion: 'Desinfectante de manos.', precio: 12.5, emoji: '🧴' },
      { id_producto: 29, id_categoria: 13, nombre: 'Protector solar FPS50', descripcion: 'Protección UVA/UVB.', precio: 35.0, emoji: '☀️' },
    ],
  },
];

const REPARTIDORES = [
  { id_repartidor: 1, nombres: 'Carlos', apellidos: 'Mendoza', id_tipo_vehiculo: 2, placa: 'ABC-123', disponible: true },
  { id_repartidor: 2, nombres: 'Ana', apellidos: 'Torres', id_tipo_vehiculo: 1, placa: null, disponible: true },
  { id_repartidor: 3, nombres: 'Luis', apellidos: 'Ramírez', id_tipo_vehiculo: 3, placa: 'XYZ-789', disponible: false },
  { id_repartidor: 4, nombres: 'Sofía', apellidos: 'Vega', id_tipo_vehiculo: 2, placa: 'DEF-456', disponible: true },
];

// --- Estado ---
let cart = loadCart();
let pedidos = loadPedidos();
let comercioActual = null;
let categoriaActiva = null;
let verticalActiva = 'todos';
let filtroActivo = 'todos';
let busqueda = '';
let busquedaTienda = '';
let cuponActivo = null;
let favoritos = loadFavoritos();
let promoAutoTimer = null;
let nextPedidoId = pedidos.length ? Math.max(...pedidos.map((p) => p.id_pedido)) + 1 : 1001;

// --- Utilidades ---
function formatMoney(n) {
  return `S/ ${Number(n).toFixed(2)}`;
}

function catalogoById(tipo, id) {
  return CATALOGO[tipo].find((c) => c.id === id);
}

function getComercio(id) {
  return COMERCIOS.find((c) => c.id_comercio === id);
}

function calcularEnvio(comercio, subtotal, cupon = cuponActivo) {
  if (cupon?.tipo === 'envio') return 0;
  if (comercio.envio_gratis_desde && subtotal >= comercio.envio_gratis_desde) return 0;
  return comercio.costo_envio;
}

function calcularDescuento(subtotal, cupon = cuponActivo) {
  if (!cupon || cupon.tipo !== 'porcentaje') return 0;
  return subtotal * (cupon.valor / 100);
}

function calcularTotales(comercio, items, cupon = cuponActivo) {
  const subtotal = items.reduce((s, i) => s + i.precio * i.cantidad, 0);
  const descuento = calcularDescuento(subtotal, cupon);
  const subtotalConDto = subtotal - descuento;
  const costo_envio = calcularEnvio(comercio, subtotalConDto, cupon);
  return { subtotal, descuento, costo_envio, total: subtotalConDto + costo_envio };
}

function loadFavoritos() {
  try {
    const d = localStorage.getItem('rappisim_favoritos');
    return d ? JSON.parse(d) : [1, 3];
  } catch { return [1, 3]; }
}

function saveFavoritos() {
  localStorage.setItem('rappisim_favoritos', JSON.stringify(favoritos));
}

function toggleFavorito(id, e) {
  e?.stopPropagation();
  const idx = favoritos.indexOf(id);
  if (idx >= 0) favoritos.splice(idx, 1);
  else favoritos.push(id);
  saveFavoritos();
  renderComercios();
  updateProfileStats();
  showToast(idx >= 0 ? 'Eliminado de favoritos' : '¡Agregado a favoritos! ❤️');
}

function estadoPedidoClass(codigo) {
  return ({ CREADO: 'creado', CONFIRMADO: 'confirmado', EN_CAMINO: 'en-camino', ENTREGADO: 'entregado', CANCELADO: 'cancelado' })[codigo] || 'creado';
}

function riderPosition(codigo) {
  return ({ CREADO: '15%', CONFIRMADO: '35%', EN_CAMINO: '65%', ENTREGADO: '85%', CANCELADO: '15%' })[codigo] || '15%';
}

function showToast(msg, type = 'success') {
  const toast = document.getElementById('toast');
  toast.textContent = msg;
  toast.className = `toast show ${type}`;
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => toast.classList.remove('show'), 3000);
}

function loadCart() {
  try {
    const data = localStorage.getItem('deliverygo_cart');
    return data ? JSON.parse(data) : [];
  } catch { return []; }
}

function saveCart() { localStorage.setItem('deliverygo_cart', JSON.stringify(cart)); }

function loadPedidos() {
  try {
    const data = localStorage.getItem('deliverygo_pedidos');
    if (data) return JSON.parse(data);
  } catch { /* ignore */ }
  const comercio = COMERCIOS[0];
  return [{
    id_pedido: 1000,
    id_comercio: 1,
    comercio_nombre: 'Sabor Peruano',
    estado_codigo: 'EN_CAMINO',
    direccion_entrega: CLIENTE.persona.direccion,
    subtotal: 60.0,
    costo_envio: 4.90,
    total: 64.90,
    id_metodo_pago: 12,
    metodo_pago: 'Yape',
    fecha_creacion: new Date(Date.now() - 1800000).toISOString(),
    detalle: [
      { nombre: 'Lomo saltado', cantidad: 1, precio_unitario: 28.0 },
      { nombre: 'Ceviche mixto', cantidad: 1, precio_unitario: 32.0 },
    ],
    repartidor: 'Carlos Mendoza',
    eta_min: 12,
  }];
}

function savePedidos() { localStorage.setItem('deliverygo_pedidos', JSON.stringify(pedidos)); }

// --- Renderizado home ---
function renderVerticales() {
  const container = document.getElementById('verticales');
  container.innerHTML = VERTICALES.map((v) => `
    <button class="vertical-item ${verticalActiva === v.id ? 'active' : ''}" data-vertical="${v.id}" type="button">
      <span class="vertical-item__icon">${v.icon}</span>
      <span>${v.nombre}</span>
    </button>
  `).join('');

  container.querySelectorAll('.vertical-item').forEach((btn) => {
    btn.addEventListener('click', () => {
      verticalActiva = btn.dataset.vertical;
      renderVerticales();
      renderComercios();
      const titulo = verticalActiva === 'todos' ? 'Tiendas cerca de ti' : VERTICALES.find((v) => v.id === verticalActiva)?.nombre;
      document.getElementById('comerciosTitle').textContent = titulo || 'Tiendas cerca de ti';
      document.getElementById('comercios').scrollIntoView({ behavior: 'smooth' });
    });
  });
}

function renderPromos() {
  const track = document.getElementById('promosTrack');
  const dots = document.getElementById('promosDots');

  track.innerHTML = PROMOS.map((p) => `
    <div class="promo-card" style="background:${p.gradient}">
      <strong>${p.titulo}</strong>
      <span>${p.desc}</span>
    </div>
  `).join('');

  dots.innerHTML = PROMOS.map((_, i) => `<button type="button" data-idx="${i}" class="${i === 0 ? 'active' : ''}"></button>`).join('');

  let promoIdx = 0;
  const goToPromo = (idx) => {
    promoIdx = idx;
    const card = track.children[promoIdx];
    if (card) card.scrollIntoView({ behavior: 'smooth', inline: 'start', block: 'nearest' });
    dots.querySelectorAll('button').forEach((d, i) => d.classList.toggle('active', i === promoIdx));
  };

  dots.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => goToPromo(Number(btn.dataset.idx)));
  });

  clearInterval(promoAutoTimer);
  promoAutoTimer = setInterval(() => goToPromo((promoIdx + 1) % PROMOS.length), 5000);
}

function renderPopulares() {
  const container = document.getElementById('popularScroll');
  container.innerHTML = POPULARES.map((p, i) => {
    const comercio = getComercio(p.id_comercio);
    return `
    <article class="popular-card" style="animation-delay:${i * 0.06}s" data-comercio="${p.id_comercio}" data-producto="${p.id_producto}">
      <span class="popular-card__emoji">${p.emoji}</span>
      <h4>${p.nombre}</h4>
      <p class="popular-card__store">${comercio?.nombre || ''}</p>
      <span class="popular-card__precio">${formatMoney(p.precio)}</span>
    </article>`;
  }).join('');

  container.querySelectorAll('.popular-card').forEach((card) => {
    card.addEventListener('click', () => {
      const idComercio = Number(card.dataset.comercio);
      const idProducto = Number(card.dataset.producto);
      abrirComercio(idComercio);
      setTimeout(() => agregarAlCarrito(idProducto), 150);
    });
  });
}

function renderActiveOrder() {
  const el = document.getElementById('activeOrder');
  const activo = pedidos.find((p) => ['CREADO', 'CONFIRMADO', 'EN_CAMINO'].includes(p.estado_codigo));

  if (!activo) { el.hidden = true; return; }

  const estado = CATALOGO.ESTADO_PEDIDO.find((e) => e.codigo === activo.estado_codigo);
  const eta = activo.eta_min || (activo.estado_codigo === 'EN_CAMINO' ? 12 : 25);

  el.hidden = false;
  el.innerHTML = `
    <span class="active-order__icon">${activo.estado_codigo === 'EN_CAMINO' ? '🛵' : '⏳'}</span>
    <div class="active-order__info">
      <strong>${activo.comercio_nombre} · ${estado?.nombre || ''}</strong>
      <small>Pedido #${activo.id_pedido} · ${activo.repartidor || 'Asignando RappiTendero...'}</small>
    </div>
    <span class="active-order__eta">${activo.estado_codigo === 'EN_CAMINO' ? `${eta} min` : 'En prep.'}</span>
  `;
  el.onclick = () => document.getElementById('pedidos').scrollIntoView({ behavior: 'smooth' });
}

function renderComercios() {
  const grid = document.getElementById('comerciosGrid');
  const q = busqueda.toLowerCase().trim();

  let list = COMERCIOS.filter((c) => {
    if (!c.activo) return false;
    if (verticalActiva !== 'todos' && c.vertical !== verticalActiva) return false;
    if (q && !c.nombre.toLowerCase().includes(q) && !c.productos.some((p) => p.nombre.toLowerCase().includes(q))) return false;
    if (filtroActivo === 'envio-gratis' && !c.envio_gratis_desde) return false;
    if (filtroActivo === 'rapido' && c.tiempo_min > 25) return false;
    if (filtroActivo === 'promo' && !c.promo) return false;
    return true;
  });

  if (filtroActivo === 'rapido') list.sort((a, b) => a.tiempo_min - b.tiempo_min);

  if (!list.length) {
    grid.innerHTML = '<p class="empty-state"><span>🔍</span>No encontramos tiendas con esos filtros</p>';
    return;
  }

  const verticalLabel = (v) => VERTICALES.find((x) => x.id === v)?.nombre || v;

  grid.innerHTML = list.map((c) => {
    const envioTxt = c.envio_gratis_desde
      ? `Envío ${formatMoney(c.costo_envio)} · Gratis desde ${formatMoney(c.envio_gratis_desde)}`
      : `Envío ${formatMoney(c.costo_envio)}`;

    const esFav = favoritos.includes(c.id_comercio);
    return `
    <article class="tienda-card" data-id="${c.id_comercio}">
      <button class="btn-fav ${esFav ? 'active' : ''}" data-fav="${c.id_comercio}" type="button" aria-label="Favorito">${esFav ? '❤️' : '🤍'}</button>
      <div class="tienda-card__img" style="background:${c.gradient}">${c.emoji}</div>
      <div class="tienda-card__body">
        <div class="tienda-card__top">
          <h3>${c.nombre}</h3>
          <span class="tienda-card__rating">⭐ <strong>${c.rating}</strong></span>
        </div>
        <p class="tienda-card__meta">
          ${c.tiempo_min}–${c.tiempo_max} min<span class="dot">·</span>${envioTxt}
        </p>
        <div class="tienda-card__tags">
          <span class="tag tag--vertical">${verticalLabel(c.vertical)}</span>
          ${c.promo ? `<span class="tag tag--promo">${c.promo}</span>` : ''}
          ${c.envio_gratis_desde ? `<span class="tag tag--free">Envío gratis +S/${c.envio_gratis_desde}</span>` : ''}
        </div>
      </div>
    </article>`;
  }).join('');

  grid.querySelectorAll('.tienda-card').forEach((el) => {
    el.addEventListener('click', () => abrirComercio(Number(el.dataset.id)));
  });
  grid.querySelectorAll('.btn-fav').forEach((btn) => {
    btn.addEventListener('click', (e) => toggleFavorito(Number(btn.dataset.fav), e));
  });
}

function abrirComercio(id) {
  comercioActual = getComercio(id);
  if (!comercioActual) return;

  categoriaActiva = null;
  busquedaTienda = '';
  const storeSearch = document.getElementById('searchStore');
  if (storeSearch) storeSearch.value = '';
  document.getElementById('comercios').hidden = true;
  document.getElementById('productos').hidden = false;

  document.getElementById('storeHero').style.background = comercioActual.gradient;
  document.getElementById('storeHero').innerHTML = `
    <div class="store-hero__content">
      <h2>${comercioActual.emoji} ${comercioActual.nombre}</h2>
      <p>⭐ ${comercioActual.rating} · ${comercioActual.tiempo_min}–${comercioActual.tiempo_max} min · Envío ${formatMoney(comercioActual.costo_envio)}</p>
    </div>`;

  renderCategorias();
  renderProductos();
  document.getElementById('productos').scrollIntoView({ behavior: 'smooth' });
}

function volverComercios() {
  comercioActual = null;
  document.getElementById('productos').hidden = true;
  document.getElementById('comercios').hidden = false;
  document.getElementById('comercios').scrollIntoView({ behavior: 'smooth' });
}

function renderCategorias() {
  const tabs = document.getElementById('categoriasTabs');
  tabs.innerHTML = `
    <button class="tab ${!categoriaActiva ? 'active' : ''}" data-cat="" type="button">Todo el menú</button>
    ${comercioActual.categorias.map((c) => `
      <button class="tab ${categoriaActiva === c.id_categoria ? 'active' : ''}" data-cat="${c.id_categoria}" type="button">${c.nombre}</button>
    `).join('')}
  `;
  tabs.querySelectorAll('.tab').forEach((btn) => {
    btn.addEventListener('click', () => {
      categoriaActiva = btn.dataset.cat ? Number(btn.dataset.cat) : null;
      renderCategorias();
      renderProductos();
    });
  });
}

function renderProductos() {
  const grid = document.getElementById('productosGrid');
  let productos = comercioActual.productos;
  if (categoriaActiva) productos = productos.filter((p) => p.id_categoria === categoriaActiva);
  const q = busquedaTienda.toLowerCase().trim();
  if (q) productos = productos.filter((p) => p.nombre.toLowerCase().includes(q) || p.descripcion.toLowerCase().includes(q));

  if (!productos.length) {
    grid.innerHTML = '<p class="empty-state" style="padding:2rem"><span>🔍</span>Sin resultados en el menú</p>';
    return;
  }

  grid.innerHTML = productos.map((p) => `
    <article class="producto-row" data-open-producto="${p.id_producto}">
      <div class="producto-row__info">
        <h4>${p.nombre}</h4>
        <p>${p.descripcion}</p>
        <span class="producto-row__precio">${formatMoney(p.precio)}</span>
      </div>
      <div class="producto-row__img">
        ${p.emoji}
        <button class="btn--add-round" data-producto="${p.id_producto}" type="button" aria-label="Agregar">+</button>
      </div>
    </article>
  `).join('');

  grid.querySelectorAll('[data-producto]').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      agregarAlCarrito(Number(btn.dataset.producto), btn);
    });
  });
  grid.querySelectorAll('[data-open-producto]').forEach((row) => {
    row.addEventListener('click', () => abrirDetalleProducto(Number(row.dataset.openProducto)));
  });
}

function abrirDetalleProducto(idProducto) {
  const producto = comercioActual?.productos.find((p) => p.id_producto === idProducto);
  if (!producto) return;

  document.getElementById('productModalContent').innerHTML = `
    <div class="product-modal__emoji">${producto.emoji}</div>
    <h3>${producto.nombre}</h3>
    <p>${producto.descripcion}</p>
    <div class="product-modal__precio">${formatMoney(producto.precio)}</div>
    <div class="product-modal__actions">
      <button type="button" class="btn btn--ghost" id="btnCloseProduct">Cerrar</button>
      <button type="button" class="btn btn--primary" id="btnAddFromModal">Agregar al carrito</button>
    </div>
  `;
  const modal = document.getElementById('productModal');
  modal.showModal();
  document.getElementById('btnCloseProduct').onclick = () => modal.close();
  document.getElementById('btnAddFromModal').onclick = () => {
    agregarAlCarrito(idProducto);
    modal.close();
  };
}

function agregarAlCarrito(idProducto, btnEl) {
  const comercio = comercioActual || getComercio(cart[0]?.id_comercio);
  if (!comercio) return;
  if (!comercioActual) comercioActual = comercio;
  const producto = comercio.productos.find((p) => p.id_producto === idProducto);
  if (!producto) return;

  if (btnEl) {
    btnEl.classList.add('added');
    setTimeout(() => btnEl.classList.remove('added'), 400);
  }

  if (cart.length && cart[0].id_comercio !== comercioActual.id_comercio) {
    if (!confirm('Solo puedes pedir de una tienda a la vez (como en Rappi). ¿Vaciar carrito y continuar?')) return;
    cart = [];
  }

  const existente = cart.find((i) => i.id_producto === idProducto);
  if (existente) existente.cantidad += 1;
  else {
    cart.push({
      id_producto: producto.id_producto,
      id_comercio: comercioActual.id_comercio,
      comercio_nombre: comercioActual.nombre,
      nombre: producto.nombre,
      precio: producto.precio,
      emoji: producto.emoji,
      cantidad: 1,
      costo_envio: comercioActual.costo_envio,
      envio_gratis_desde: comercioActual.envio_gratis_desde,
    });
  }

  saveCart();
  updateCartUI();
  showToast(`+1 ${producto.nombre}`);
}

function updateFloatCart() {
  const floatCart = document.getElementById('floatCart');
  if (!cart.length) {
    floatCart.hidden = true;
    return;
  }
  const comercio = getComercio(cart[0].id_comercio);
  const { total } = calcularTotales(comercio, cart);
  const items = cart.reduce((s, i) => s + i.cantidad, 0);

  floatCart.hidden = false;
  document.getElementById('floatCartCount').textContent = items;
  document.getElementById('floatCartTotal').textContent = formatMoney(total);
}

function updateCartUI() {
  const totalItems = cart.reduce((s, i) => s + i.cantidad, 0);
  ['cartBadge', 'cartBadgeBottom'].forEach((id) => {
    const badge = document.getElementById(id);
    if (badge) {
      badge.textContent = totalItems;
      badge.dataset.count = totalItems;
    }
  });

  const body = document.getElementById('cartBody');
  const footer = document.getElementById('cartFooter');
  const storeName = document.getElementById('cartStoreName');

  if (!cart.length) {
    body.innerHTML = '<div class="cart-empty"><span>🛒</span>Tu carrito está vacío<br><small>Agrega productos de una tienda</small></div>';
    footer.hidden = true;
    storeName.hidden = true;
    updateFloatCart();
    return;
  }

  storeName.hidden = false;
  storeName.textContent = `🏪 ${cart[0].comercio_nombre}`;

  body.innerHTML = cart.map((item, idx) => `
    <div class="cart-item">
      <span class="cart-item__emoji">${item.emoji}</span>
      <div class="cart-item__info">
        <h4>${item.nombre}</h4>
        <span>${formatMoney(item.precio)}</span>
      </div>
      <div class="qty-control">
        <button type="button" data-action="minus" data-idx="${idx}">−</button>
        <span>${item.cantidad}</span>
        <button type="button" data-action="plus" data-idx="${idx}">+</button>
      </div>
    </div>
  `).join('');

  body.querySelectorAll('[data-action]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const idx = Number(btn.dataset.idx);
      if (btn.dataset.action === 'plus') cart[idx].cantidad += 1;
      else {
        cart[idx].cantidad -= 1;
        if (cart[idx].cantidad <= 0) cart.splice(idx, 1);
      }
      saveCart();
      updateCartUI();
    });
  });

  const comercio = getComercio(cart[0].id_comercio);
  const { subtotal, descuento, costo_envio, total } = calcularTotales(comercio, cart);

  document.getElementById('cartSubtotal').textContent = formatMoney(subtotal);
  document.getElementById('cartEnvio').textContent = costo_envio === 0 ? 'Gratis' : formatMoney(costo_envio);
  document.getElementById('cartTotal').textContent = formatMoney(total);
  footer.hidden = false;
  updateFloatCart();
}

function openCart() {
  document.getElementById('cartPanel').classList.add('open');
  document.getElementById('cartPanel').setAttribute('aria-hidden', 'false');
}

function closeCart() {
  document.getElementById('cartPanel').classList.remove('open');
  document.getElementById('cartPanel').setAttribute('aria-hidden', 'true');
}

function renderPaymentOptions() {
  document.getElementById('paymentOptions').innerHTML = CATALOGO.METODO_PAGO.map((m, i) => `
    <div class="payment-option">
      <input type="radio" name="metodoPago" id="pago_${m.codigo}" value="${m.id}" ${i === 2 ? 'checked' : ''}>
      <label for="pago_${m.codigo}">
        <span class="payment-option__icon">${m.icon}</span>
        ${m.nombre}
      </label>
    </div>
  `).join('');
}

function buildCheckoutResumen() {
  const comercio = getComercio(cart[0].id_comercio);
  const { subtotal, descuento, costo_envio, total } = calcularTotales(comercio, cart);
  const dtoLine = descuento > 0 ? `<br><span class="descuento">Descuento: -${formatMoney(descuento)}</span>` : '';
  document.getElementById('checkoutResumen').innerHTML = `
    <strong>${cart[0].comercio_nombre}</strong><br>
    ${cart.map((i) => `${i.cantidad}× ${i.nombre}`).join(' · ')}<br>
    Subtotal ${formatMoney(subtotal)}${dtoLine}<br>
    Envío ${costo_envio === 0 ? 'GRATIS' : formatMoney(costo_envio)} =
    <strong>${formatMoney(total)}</strong>
  `;
}

function aplicarCupon() {
  const codigo = document.getElementById('cuponCodigo').value.trim().toUpperCase();
  const hint = document.getElementById('cuponHint');
  if (!codigo) {
    cuponActivo = null;
    hint.textContent = 'Ingresa un código promocional';
    hint.className = 'cupon-hint';
    if (cart.length) buildCheckoutResumen();
    updateCartUI();
    return;
  }
  const cupon = CUPONES[codigo];
  if (!cupon) {
    cuponActivo = null;
    hint.textContent = 'Código no válido';
    hint.className = 'cupon-hint error';
    showToast('Cupón inválido', 'error');
    return;
  }
  cuponActivo = { ...cupon, codigo };
  hint.textContent = `✓ ${cupon.desc}`;
  hint.className = 'cupon-hint success';
  showToast(`Cupón ${codigo} aplicado`);
  if (cart.length) buildCheckoutResumen();
  updateCartUI();
}

function openCheckout() {
  if (!cart.length) { showToast('Tu carrito está vacío', 'error'); return; }
  closeCart();

  document.getElementById('cuponCodigo').value = cuponActivo?.codigo || '';
  buildCheckoutResumen();

  document.getElementById('direccionEntrega').value = CLIENTE.persona.direccion;
  document.getElementById('referenciaEntrega').value = CLIENTE.persona.referencia || '';
  document.getElementById('checkoutModal').showModal();
}

function confirmarPedido(e) {
  e.preventDefault();

  const direccion = document.getElementById('direccionEntrega').value.trim();
  const referencia = document.getElementById('referenciaEntrega').value.trim();
  const metodoId = Number(document.querySelector('input[name="metodoPago"]:checked')?.value);

  if (!direccion) { showToast('Ingresa tu dirección de entrega', 'error'); return; }

  const comercio = getComercio(cart[0].id_comercio);
  const { subtotal, descuento, costo_envio, total } = calcularTotales(comercio, cart);
  const metodo = CATALOGO.METODO_PAGO.find((m) => m.id === metodoId);
  const repartidorDisp = REPARTIDORES.find((r) => r.disponible);

  const pedido = {
    id_pedido: nextPedidoId++,
    id_comercio: cart[0].id_comercio,
    comercio_nombre: cart[0].comercio_nombre,
    estado_codigo: 'CONFIRMADO',
    direccion_entrega: direccion,
    referencia_entrega: referencia,
    subtotal,
    descuento,
    cupon: cuponActivo?.codigo || null,
    costo_envio,
    total,
    id_metodo_pago: metodoId,
    metodo_pago: metodo?.nombre || '—',
    fecha_creacion: new Date().toISOString(),
    detalle: cart.map((i) => ({
      nombre: i.nombre,
      cantidad: i.cantidad,
      precio_unitario: i.precio,
      importe_linea: i.precio * i.cantidad,
    })),
    repartidor: repartidorDisp ? `${repartidorDisp.nombres} ${repartidorDisp.apellidos}` : 'Asignando...',
    eta_min: comercio ? comercio.tiempo_max : 30,
  };

  pedidos.unshift(pedido);
  savePedidos();
  cart = [];
  cuponActivo = null;
  saveCart();
  updateCartUI();
  updateProfileStats();

  document.getElementById('checkoutModal').close();
  showToast(`¡Listo! Tu RappiTendero va en camino · #${pedido.id_pedido}`);

  simularProgresoPedido(pedido.id_pedido);
  renderPedidos();
  renderActiveOrder();
  document.getElementById('pedidos').scrollIntoView({ behavior: 'smooth' });
}

function simularProgresoPedido(idPedido) {
  const estados = ['CONFIRMADO', 'EN_CAMINO', 'ENTREGADO'];
  let step = 0;

  const avanzar = () => {
    step += 1;
    if (step >= estados.length) return;
    const codigo = estados[step];
    const estado = CATALOGO.ESTADO_PEDIDO.find((e) => e.codigo === codigo);
    const pedido = pedidos.find((p) => p.id_pedido === idPedido);
    if (pedido && estado) {
      pedido.estado_codigo = codigo;
      if (codigo === 'EN_CAMINO') pedido.eta_min = 12;
      savePedidos();
      renderPedidos();
      renderActiveOrder();
      const msgs = { EN_CAMINO: '¡Tu pedido va en camino! 🛵', ENTREGADO: '¡Pedido entregado! Buen provecho 🎉' };
      if (msgs[codigo]) showToast(msgs[codigo]);
    }
    if (step < estados.length - 1) setTimeout(avanzar, 7000);
    else setTimeout(renderActiveOrder, 500);
  };

  setTimeout(avanzar, 5000);
}

function renderPedidos() {
  const list = document.getElementById('pedidosList');
  const empty = document.getElementById('pedidosEmpty');

  if (!pedidos.length) {
    list.innerHTML = '';
    empty.hidden = false;
    return;
  }
  empty.hidden = true;

  const pasos = CATALOGO.ESTADO_PEDIDO.filter((e) => e.codigo !== 'CANCELADO');

  list.innerHTML = pedidos.map((p) => {
    const estado = CATALOGO.ESTADO_PEDIDO.find((e) => e.codigo === p.estado_codigo);
    const ordenActual = estado?.orden || 1;
    const showMap = ['CONFIRMADO', 'EN_CAMINO'].includes(p.estado_codigo);

    const timeline = pasos.map((s) => {
      const done = s.orden < ordenActual;
      const active = s.orden === ordenActual;
      return `<div class="timeline__step ${done ? 'done' : ''} ${active ? 'active' : ''}">
        <div class="timeline__dot"></div>
        <span class="timeline__label">${s.nombre}</span>
      </div>`;
    }).join('');

    const fecha = new Date(p.fecha_creacion).toLocaleString('es-PE', {
      day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
    });

    const riderClass = p.estado_codigo === 'EN_CAMINO' ? 'tracking-map__rider--moving' : '';
    const mapHtml = showMap ? `
      <div class="tracking-map">
        <div class="tracking-map__grid"></div>
        <div class="tracking-map__route"></div>
        <span class="tracking-map__rider ${riderClass}" style="left:${riderPosition(p.estado_codigo)}">🛵</span>
        <span class="tracking-map__dest">📍</span>
        <span class="tracking-map__label">${p.estado_codigo === 'EN_CAMINO' ? `${p.repartidor} · ~${p.eta_min || 12} min` : 'Preparando tu pedido...'}</span>
      </div>` : '';

    const activo = ['CREADO', 'CONFIRMADO', 'EN_CAMINO'].includes(p.estado_codigo);
    const acciones = activo
      ? `<div class="pedido-card__actions"><button class="btn--sm btn--sm--danger" data-cancelar="${p.id_pedido}" type="button">Cancelar pedido</button></div>`
      : p.estado_codigo === 'ENTREGADO'
        ? `<div class="pedido-card__actions">
            <button class="btn--sm btn--sm--primary" data-reordenar="${p.id_pedido}" type="button">Pedir de nuevo</button>
          </div>
          ${!p.calificacion ? `<div class="order-rating" data-rating="${p.id_pedido}">
            <p>¿Cómo estuvo tu pedido?</p>
            <div class="stars">${[1,2,3,4,5].map((n) => `<button type="button" data-star="${n}" data-pedido="${p.id_pedido}">⭐</button>`).join('')}</div>
          </div>` : `<div class="order-rating"><p>Calificaste: ${'⭐'.repeat(p.calificacion)}</p></div>`}`
        : '';

    const cuponLine = p.cupon ? `<div>🎟️ Cupón: ${p.cupon}</div>` : '';
    const dtoLine = p.descuento > 0 ? `<div class="descuento">Descuento: -${formatMoney(p.descuento)}</div>` : '';

    return `
    <article class="pedido-card">
      ${mapHtml}
      <div class="pedido-card__header">
        <div>
          <div class="pedido-card__id">Pedido #${p.id_pedido}</div>
          <div class="pedido-card__comercio">${p.comercio_nombre} · ${fecha}</div>
        </div>
        <span class="status-badge status-badge--${estadoPedidoClass(p.estado_codigo)}">${estado?.nombre || p.estado_codigo}</span>
      </div>
      <div class="timeline">${timeline}</div>
      <div class="pedido-card__detalle">
        <ul class="pedido-card__items">
          ${p.detalle.map((d) => `<li>${d.cantidad}× ${d.nombre} — ${formatMoney(d.precio_unitario * d.cantidad)}</li>`).join('')}
        </ul>
        <div>
          <div>📍 ${p.direccion_entrega}</div>
          <div>💳 ${p.metodo_pago} · <strong>${formatMoney(p.total)}</strong></div>
          ${cuponLine}${dtoLine}
          <div>🛵 ${p.repartidor || 'Sin asignar'}</div>
        </div>
      </div>
      ${acciones}
    </article>`;
  }).join('');

  list.querySelectorAll('[data-cancelar]').forEach((btn) => {
    btn.addEventListener('click', () => cancelarPedido(Number(btn.dataset.cancelar)));
  });
  list.querySelectorAll('[data-reordenar]').forEach((btn) => {
    btn.addEventListener('click', () => reordenarPedido(Number(btn.dataset.reordenar)));
  });
  list.querySelectorAll('[data-star]').forEach((btn) => {
    btn.addEventListener('click', () => calificarPedido(Number(btn.dataset.pedido), Number(btn.dataset.star)));
  });
}

function cancelarPedido(id) {
  const pedido = pedidos.find((p) => p.id_pedido === id);
  if (!pedido || !['CREADO', 'CONFIRMADO', 'EN_CAMINO'].includes(pedido.estado_codigo)) return;
  if (!confirm(`¿Cancelar el pedido #${id}?`)) return;
  pedido.estado_codigo = 'CANCELADO';
  savePedidos();
  renderPedidos();
  renderActiveOrder();
  showToast('Pedido cancelado');
}

function reordenarPedido(id) {
  const pedido = pedidos.find((p) => p.id_pedido === id);
  if (!pedido) return;
  const comercio = getComercio(pedido.id_comercio);
  if (!comercio) return;

  cart = [];
  pedido.detalle.forEach((d) => {
    const prod = comercio.productos.find((p) => p.nombre === d.nombre);
    if (prod) {
      cart.push({
        id_producto: prod.id_producto,
        id_comercio: comercio.id_comercio,
        comercio_nombre: comercio.nombre,
        nombre: prod.nombre,
        precio: prod.precio,
        emoji: prod.emoji,
        cantidad: d.cantidad,
        costo_envio: comercio.costo_envio,
        envio_gratis_desde: comercio.envio_gratis_desde,
      });
    }
  });
  saveCart();
  updateCartUI();
  openCart();
  showToast('Productos agregados al carrito');
}

function calificarPedido(id, estrellas) {
  const pedido = pedidos.find((p) => p.id_pedido === id);
  if (!pedido) return;
  pedido.calificacion = estrellas;
  savePedidos();
  renderPedidos();
  showToast(`¡Gracias! Calificaste con ${estrellas} estrellas`);
}

function renderRepartidores() {
  document.getElementById('repartidoresGrid').innerHTML = REPARTIDORES.map((r) => {
    const vehiculo = catalogoById('TIPO_VEHICULO', r.id_tipo_vehiculo);
    return `
    <article class="repartidor-card">
      <div class="repartidor-card__avatar">${vehiculo?.icon || '🛵'}</div>
      <div class="repartidor-card__info">
        <h4>${r.nombres} ${r.apellidos}</h4>
        <p>RappiTendero · ${vehiculo?.nombre || '—'}${r.placa ? ` · ${r.placa}` : ''}</p>
        <p><span class="disponible-dot disponible-dot--${r.disponible ? 'si' : 'no'}"></span>${r.disponible ? 'Disponible ahora' : 'En ruta'}</p>
      </div>
    </article>`;
  }).join('');
}

function handleSearch(value) {
  busqueda = value;
  renderComercios();
}

function openProfile() {
  updateProfileStats();
  document.getElementById('profilePanel').classList.add('open');
  document.getElementById('profilePanel').setAttribute('aria-hidden', 'false');
}

function closeProfile() {
  document.getElementById('profilePanel').classList.remove('open');
  document.getElementById('profilePanel').setAttribute('aria-hidden', 'true');
}

function updateProfileStats() {
  const entregados = pedidos.filter((p) => p.estado_codigo === 'ENTREGADO').length;
  const elPedidos = document.getElementById('profilePedidos');
  const elFav = document.getElementById('profileFavoritos');
  if (elPedidos) elPedidos.textContent = pedidos.length;
  if (elFav) elFav.textContent = favoritos.length;
}

function renderSavedAddresses() {
  const container = document.getElementById('savedAddresses');
  container.innerHTML = DIRECCIONES_GUARDADAS.map((a) => `
    <label class="address-option ${a.direccion === CLIENTE.persona.direccion ? 'selected' : ''}">
      <input type="radio" name="savedAddr" value="${a.id}" ${a.direccion === CLIENTE.persona.direccion ? 'checked' : ''}>
      <div>
        <strong>${a.direccion}</strong><br>
        <small>${a.referencia || 'Sin referencia'}</small>
      </div>
    </label>
  `).join('');
}

function openAddressModal() {
  renderSavedAddresses();
  document.getElementById('newAddress').value = '';
  document.getElementById('newReference').value = '';
  document.getElementById('addressModal').showModal();
  closeProfile();
}

function saveAddress() {
  const selected = document.querySelector('input[name="savedAddr"]:checked');
  const nueva = document.getElementById('newAddress').value.trim();

  if (nueva) {
    CLIENTE.persona.direccion = nueva;
    CLIENTE.persona.referencia = document.getElementById('newReference').value.trim();
    DIRECCIONES_GUARDADAS.push({
      id: DIRECCIONES_GUARDADAS.length + 1,
      direccion: nueva,
      referencia: CLIENTE.persona.referencia,
      principal: false,
    });
  } else if (selected) {
    const addr = DIRECCIONES_GUARDADAS.find((a) => a.id === Number(selected.value));
    if (addr) {
      CLIENTE.persona.direccion = addr.direccion;
      CLIENTE.persona.referencia = addr.referencia;
    }
  }

  document.getElementById('addressText').textContent = CLIENTE.persona.direccion;
  document.getElementById('addressModal').close();
  showToast('Dirección actualizada');
}

function initScrollTop() {
  const btn = document.getElementById('scrollTop');
  window.addEventListener('scroll', () => {
    btn.classList.toggle('visible', window.scrollY > 400);
  });
  btn.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
}

function initNav() {
  const bottomItems = document.querySelectorAll('.bottom-nav__item[data-section]');

  bottomItems.forEach((link) => {
    link.addEventListener('click', (e) => {
      if (comercioActual && link.dataset.section === 'comercios') {
        e.preventDefault();
        volverComercios();
      }
      bottomItems.forEach((l) => l.classList.remove('active'));
      link.classList.add('active');
    });
  });

  const sections = document.querySelectorAll('section[id]');
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        const id = entry.target.id;
        if (id === 'productos') return;
        bottomItems.forEach((l) => l.classList.toggle('active', l.dataset.section === id));
      }
    });
  }, { rootMargin: '-45% 0px -45% 0px' });
  sections.forEach((s) => observer.observe(s));
}

function init() {
  document.getElementById('userName').textContent = CLIENTE.persona.nombres;
  document.getElementById('addressText').textContent = CLIENTE.persona.direccion;
  document.getElementById('profileName').textContent = `${CLIENTE.persona.nombres} ${CLIENTE.persona.apellidos}`;
  document.getElementById('profileEmail').textContent = CLIENTE.persona.correo;
  document.getElementById('profilePhone').textContent = CLIENTE.persona.telefono;

  renderVerticales();
  renderPromos();
  renderPopulares();
  renderActiveOrder();
  renderComercios();
  renderRepartidores();
  renderPedidos();
  renderPaymentOptions();
  updateCartUI();
  updateProfileStats();
  initScrollTop();

  const onSearch = (e) => handleSearch(e.target.value);
  document.getElementById('searchGlobal')?.addEventListener('input', onSearch);
  document.getElementById('searchMobile')?.addEventListener('input', onSearch);
  document.getElementById('searchStore')?.addEventListener('input', (e) => {
    busquedaTienda = e.target.value;
    renderProductos();
  });

  document.querySelectorAll('.filter-chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.filter-chip').forEach((c) => c.classList.remove('active'));
      chip.classList.add('active');
      filtroActivo = chip.dataset.filter;
      renderComercios();
    });
  });

  document.getElementById('btnVolverComercios').addEventListener('click', volverComercios);
  document.getElementById('btnCart').addEventListener('click', openCart);
  document.getElementById('btnCartBottom').addEventListener('click', openCart);
  document.getElementById('floatCartBtn')?.addEventListener('click', openCart);
  document.getElementById('btnCloseCart').addEventListener('click', closeCart);
  document.getElementById('cartOverlay').addEventListener('click', closeCart);
  document.getElementById('btnCheckout').addEventListener('click', openCheckout);
  document.getElementById('btnCloseCheckout').addEventListener('click', () => document.getElementById('checkoutModal').close());
  document.getElementById('btnCancelCheckout').addEventListener('click', () => document.getElementById('checkoutModal').close());
  document.getElementById('checkoutForm').addEventListener('submit', confirmarPedido);
  document.getElementById('btnAplicarCupon')?.addEventListener('click', aplicarCupon);

  document.getElementById('btnLogin').addEventListener('click', openProfile);
  document.getElementById('btnAddress').addEventListener('click', openAddressModal);
  document.getElementById('btnCloseAddress')?.addEventListener('click', () => document.getElementById('addressModal').close());
  document.getElementById('btnSaveAddress')?.addEventListener('click', saveAddress);
  document.getElementById('btnCloseProfile')?.addEventListener('click', closeProfile);
  document.getElementById('profileOverlay')?.addEventListener('click', closeProfile);
  document.getElementById('btnProfileAddress')?.addEventListener('click', openAddressModal);
  document.getElementById('btnProfilePedidos')?.addEventListener('click', () => {
    closeProfile();
    document.getElementById('pedidos').scrollIntoView({ behavior: 'smooth' });
  });
  document.getElementById('btnProfileFavoritos')?.addEventListener('click', () => {
    closeProfile();
    verticalActiva = 'todos';
    filtroActivo = 'todos';
    renderVerticales();
    const favComercios = COMERCIOS.filter((c) => favoritos.includes(c.id_comercio));
    const grid = document.getElementById('comerciosGrid');
    if (!favComercios.length) {
      grid.innerHTML = '<p class="empty-state"><span>❤️</span>No tienes tiendas favoritas aún</p>';
    } else {
      busqueda = '';
      renderComercios();
      grid.innerHTML = favComercios.map((c) => {
        const envioTxt = c.envio_gratis_desde ? `Envío ${formatMoney(c.costo_envio)}` : `Envío ${formatMoney(c.costo_envio)}`;
        return `<article class="tienda-card" data-id="${c.id_comercio}">
          <button class="btn-fav active" data-fav="${c.id_comercio}" type="button">❤️</button>
          <div class="tienda-card__img" style="background:${c.gradient}">${c.emoji}</div>
          <div class="tienda-card__body">
            <div class="tienda-card__top"><h3>${c.nombre}</h3><span class="tienda-card__rating">⭐ <strong>${c.rating}</strong></span></div>
            <p class="tienda-card__meta">${c.tiempo_min}–${c.tiempo_max} min · ${envioTxt}</p>
          </div>
        </article>`;
      }).join('');
      grid.querySelectorAll('.tienda-card').forEach((el) => el.addEventListener('click', () => abrirComercio(Number(el.dataset.id))));
      grid.querySelectorAll('.btn-fav').forEach((btn) => btn.addEventListener('click', (e) => toggleFavorito(Number(btn.dataset.fav), e)));
    }
    document.getElementById('comercios').scrollIntoView({ behavior: 'smooth' });
  });

  initNav();
}

document.addEventListener('DOMContentLoaded', init);
