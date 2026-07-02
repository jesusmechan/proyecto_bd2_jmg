// =========================================================
// PASO 6.1 — 20 casos practicos: modelo RELACIONAL → MongoDB
// delivery_db_distribuida  →  BD: delivery_nosql
//
// Ejecutar (mongosh):
//   mongosh < "6. nosql-mongodb/1. casos_20_migracion.js"
// =========================================================

const dbName = "delivery_nosql";
const dbx = db.getSiblingDB(dbName);

const REGIONES = [
  { codigo: "LIM-N", idx: 1, nombre: "Lima Norte" },
  { codigo: "LIM-S", idx: 2, nombre: "Lima Sur" },
  { codigo: "AQP",   idx: 3, nombre: "Arequipa" }
];

const ESTADOS_PEDIDO = ["CREADO", "CONFIRMADO", "EN_CAMINO", "ENTREGADO", "CANCELADO"];
const METODOS_PAGO   = ["EFECTIVO", "TARJETA", "YAPE", "PLIN", "TRANSFERENCIA"];
const ESTADOS_PAGO   = ["PENDIENTE", "PAGADO", "RECHAZADO"];
const VEHICULOS      = ["MOTO", "BICI", "AUTO"];
const NOMBRES        = ["Maria", "Juan", "Carlos", "Ana", "Luis", "Rosa", "Pedro", "Lucia", "Miguel", "Elena"];
const APELLIDOS      = ["Garcia", "Rodriguez", "Lopez", "Martinez", "Gonzalez", "Perez", "Sanchez", "Ramirez"];
const COMERCIOS_TIPO = ["Polleria", "Cevicheria", "Pizzeria", "Cafeteria", "Chifa", "Sushi Bar", "Pasteleria", "Delivery Saludable"];
const PRODUCTOS      = ["Lomo saltado", "Ceviche mixto", "Pizza margarita", "Arroz chaufa", "Pollo a la brasa",
                        "Causa limeña", "Tallarin saltado", "Hamburguesa clásica", "Ensalada César", "Sushi roll 12p"];

// UUID determinístico (igual que seed_uuid en PostgreSQL)
function seedUuid(tipo, regionIdx, n) {
  const t = tipo.toString(16).padStart(8, "0");
  const r = regionIdx.toString(16).padStart(4, "0");
  const num = n.toString(16).padStart(12, "0");
  return `${t}-${r}-4001-8001-${num}`;
}

function pick(arr, i) { return arr[i % arr.length]; }
function fecha(diasAtras) {
  const d = new Date();
  d.setDate(d.getDate() - diasAtras);
  d.setHours(10 + (diasAtras % 10), (diasAtras * 7) % 60, 0, 0);
  return d;
}

[
  "perfiles_cliente", "catalogo", "comercios", "productos_ricos", "pedidos_docs",
  "repartidores_tracking", "rutas", "bitacora_eventos", "saga_eventos",
  "metadata_nodos", "proveedores", "config_fragmentacion", "tracking_pedidos",
  "resenas_producto", "repartidores_estado", "promociones", "notificaciones",
  "inventario_cache", "metricas_comercio", "sesiones_app"
].forEach(c => dbx[c].drop());

print("=== 20 CASOS RELACIONAL → NoSQL + DATOS MASIVOS ===\n");

// =================================================================
// CASOS 1–20 (ejemplo representativo de cada migración)
// =================================================================

// CASO 1 — persona + usuario + cliente → perfiles_cliente
dbx.perfiles_cliente.insertOne({
  _id: `LIM-N:${seedUuid(3, 1, 1)}`,
  region_codigo: "LIM-N",
  id_cliente: seedUuid(3, 1, 1),
  id_persona: seedUuid(1, 1, 1),
  id_usuario: seedUuid(2, 1, 1),
  nombres: "Ana", apellidos: "Garcia Lopez",
  correo: "ana.garcia@lim-n.pe", telefono: "999111222",
  rol: "CLIENTE",
  preferencias: { idioma: "es", notificaciones: "TODAS", acepta_publicidad: true },
  direcciones: [{ id: 1, direccion: "Av. Alfredo Mendiola 456", referencia: "Piso 3", principal: true }],
  favoritos: [{ id_comercio: seedUuid(5, 1, 1), id_producto: seedUuid(8, 1, 1), fecha: fecha(5) }],
  fecha_registro: fecha(120)
});
print("Caso 1: persona+usuario+cliente → perfiles_cliente");

// CASO 2 — catalogo_maestro → catalogo por tipo
dbx.catalogo.insertMany([
  {
    tipo_catalogo: "ESTADO_PEDIDO",
    valores: ESTADOS_PEDIDO.map((c, i) => ({ codigo: c, nombre: c.replace("_", " "), orden: i + 1 }))
  },
  {
    tipo_catalogo: "METODO_PAGO",
    valores: METODOS_PAGO.map((c, i) => ({ codigo: c, nombre: c, orden: i + 1 }))
  },
  {
    tipo_catalogo: "ESTADO_PAGO",
    valores: ESTADOS_PAGO.map((c, i) => ({ codigo: c, nombre: c, orden: i + 1 }))
  },
  {
    tipo_catalogo: "TIPO_VEHICULO",
    valores: VEHICULOS.map((c, i) => ({ codigo: c, nombre: c, orden: i + 1 }))
  }
]);
print("Caso 2: catalogo_maestro → catalogo (4 tipos)");

// CASO 3 — comercio + categorias + proveedores embebidos
dbx.comercios.insertOne({
  _id: `LIM-N:${seedUuid(5, 1, 1)}`,
  region_codigo: "LIM-N",
  id_comercio: seedUuid(5, 1, 1),
  nombre: "Polleria Norte",
  ruc: "20123456789",
  direccion: "Av. Tomas Valle 120",
  correo: "contacto@pollerianorte.pe",
  telefono: "014567890",
  activo: true,
  categorias: [
    { id_categoria: seedUuid(7, 1, 1), nombre: "Platos" },
    { id_categoria: seedUuid(7, 1, 2), nombre: "Bebidas" }
  ],
  proveedores_vinculados: [{ id_proveedor: seedUuid(6, 1, 1), notas: "Abastecimiento pollo" }]
});
print("Caso 3: comercio embebido");

// CASO 4 — producto → productos_ricos
dbx.productos_ricos.insertOne({
  _id: `LIM-N:${seedUuid(8, 1, 1)}`,
  region_codigo: "LIM-N",
  id_producto: seedUuid(8, 1, 1),
  id_comercio: seedUuid(5, 1, 1),
  nombre: "Lomo saltado",
  precio: 28.00,
  disponible: true,
  atributos: { picante: false, porcion: "regular", tiempo_prep_min: 25 },
  alergenos: ["gluten", "soja"],
  imagenes: ["lomo_1.jpg"],
  tags: ["popular", "criollo"]
});
print("Caso 4: productos_ricos");

// CASO 5 — pedido + detalle + pago embebidos
dbx.pedidos_docs.insertOne({
  _id: `LIM-N:${seedUuid(9, 1, 1)}`,
  region_codigo: "LIM-N",
  id_pedido: seedUuid(9, 1, 1),
  id_cliente: seedUuid(3, 1, 1),
  id_comercio: seedUuid(5, 1, 1),
  nombre_cliente: "Ana Garcia Lopez",
  nombre_comercio: "Polleria Norte",
  estado: "ENTREGADO",
  direccion_entrega: "Av. Alfredo Mendiola 456",
  subtotal: 45.00, costo_envio: 5.00, total: 50.00,
  detalle: [
    { id_producto: seedUuid(8, 1, 1), nombre: "Lomo saltado", cantidad: 1, precio_unitario: 28.00, importe: 28.00 },
    { id_producto: seedUuid(8, 1, 2), nombre: "Chicha morada", cantidad: 2, precio_unitario: 8.50, importe: 17.00 }
  ],
  pago: { metodo: "YAPE", estado: "PAGADO", monto: 50.00, fecha_pago: fecha(10) },
  fecha_creacion: fecha(10)
});
print("Caso 5: pedidos_docs");

// CASO 6 — pago embebido en pedidos_docs (ver caso 5)
print("Caso 6: pago → pedidos_docs.pago");

// CASO 7 — repartidor + tracking GPS
dbx.repartidores_tracking.insertOne({
  _id: `LIM-N:${seedUuid(4, 1, 1)}`,
  region_codigo: "LIM-N",
  id_repartidor: seedUuid(4, 1, 1),
  placa: "DEMO-01",
  disponible: false,
  tipo_vehiculo: "MOTO",
  ubicacion_actual: { lat: -12.005, lng: -77.048, ts: new Date() },
  historial: [
    { lat: -12.010, lng: -77.050, ts: fecha(1), evento: "salida_comercio" },
    { lat: -12.008, lng: -77.049, ts: fecha(0), evento: "en_ruta" }
  ]
});
print("Caso 7: repartidores_tracking");

// CASO 8 — ruta + paradas
dbx.rutas.insertOne({
  _id: `LIM-N:${seedUuid(12, 1, 1)}`,
  region_codigo: "LIM-N",
  id_ruta: seedUuid(12, 1, 1),
  id_repartidor: seedUuid(4, 1, 1),
  estado: "EN_PROGRESO",
  fecha_planificacion: fecha(3),
  paradas: [
    { orden: 1, id_pedido: seedUuid(9, 1, 1), hora_estimada: fecha(1) },
    { orden: 2, id_pedido: seedUuid(9, 1, 2), hora_estimada: fecha(0) }
  ]
});
print("Caso 8: rutas.paradas[]");

// CASO 9 — bitacora
dbx.bitacora_eventos.insertOne({
  id_evento: seedUuid(99, 1, 1),
  region_codigo: "LIM-N",
  fecha_hora: new Date(),
  tipo_evento: "PEDIDO_ENTREGADO",
  tabla_afectada: "pedido",
  id_registro: seedUuid(9, 1, 1),
  id_usuario: seedUuid(2, 1, 1),
  nodo_origen: "LIM-N",
  payload: { estado_anterior: "EN_CAMINO", estado_nuevo: "ENTREGADO", minutos_retraso: 3 }
});
print("Caso 9: bitacora_eventos");

// CASO 10 — saga embebida
dbx.saga_eventos.insertOne({
  id_saga: seedUuid(14, 1, 1),
  tipo_operacion: "CREAR_PEDIDO",
  region_codigo: "LIM-N",
  estado: "COMPLETADA",
  id_pedido: seedUuid(9, 1, 1),
  pasos: [
    { orden: 1, nombre: "validar_stock", estado: "OK", detalle: { ok: true } },
    { orden: 2, nombre: "crear_pedido", estado: "OK", detalle: { id_pedido: seedUuid(9, 1, 1) } },
    { orden: 3, nombre: "registrar_pago", estado: "OK", detalle: { metodo: "YAPE" } },
    { orden: 4, nombre: "confirmar_pedido", estado: "OK", detalle: {} }
  ],
  fecha_creacion: fecha(10)
});
print("Caso 10: saga_eventos");

// CASO 11 — nodos
dbx.metadata_nodos.insertMany([
  { region_codigo: "GLOBAL", nombre_nodo: "Nodo central de catalogos", es_nodo_global: true, activo: true },
  ...REGIONES.map(r => ({ region_codigo: r.codigo, nombre_nodo: r.nombre, es_nodo_global: false, activo: true }))
]);
print("Caso 11: metadata_nodos");

// CASO 12 — proveedor
dbx.proveedores.insertOne({
  _id: `LIM-N:${seedUuid(6, 1, 1)}`,
  region_codigo: "LIM-N",
  id_proveedor: seedUuid(6, 1, 1),
  activo: true,
  identidad: { tipo_persona: "JURIDICA", razon_social: "Distribuidora Norte SAC", ruc: "20987654321",
    correo: "ventas@distnorte.pe", telefono: "014441111" }
});
print("Caso 12: proveedores");

// CASO 13 — config fragmentacion
dbx.config_fragmentacion.insertOne({
  version: 1,
  reglas: [
    { tabla: "pedido", estrategia: "HORIZONTAL", clave: "region_codigo" },
    { tabla: "producto", estrategia: "HORIZONTAL+VERTICAL", clave: "region_codigo" },
    { tabla: "catalogo_maestro", estrategia: "REPLICA", clave: null }
  ]
});
print("Caso 13: config_fragmentacion");

// CASO 14 — tracking timeline
dbx.tracking_pedidos.insertOne({
  region_codigo: "LIM-N",
  id_pedido: seedUuid(9, 1, 1),
  eventos: ESTADOS_PEDIDO.slice(0, 4).map((est, i) => ({
    estado: est, ts: fecha(10 - i), actor: i === 0 ? "sistema" : i < 3 ? "comercio" : "repartidor"
  }))
});
print("Caso 14: tracking_pedidos");

// CASO 15 — resenas
dbx.resenas_producto.insertOne({
  region_codigo: "LIM-N",
  id_producto: seedUuid(8, 1, 1),
  id_cliente: seedUuid(3, 1, 1),
  estrellas: 5,
  comentario: "Muy buen lomo, llego caliente",
  fotos: ["resena_001.jpg"],
  fecha: fecha(8)
});
print("Caso 15: resenas_producto");

// CASO 16 — repartidor estado
dbx.repartidores_estado.insertOne({
  region_codigo: "LIM-N",
  id_repartidor: seedUuid(4, 1, 1),
  cambios: [
    { disponible: true,  ts: fecha(2), motivo: "inicio_turno" },
    { disponible: false, ts: fecha(1), motivo: "asignado_pedido", id_pedido: seedUuid(9, 1, 1) },
    { disponible: true,  ts: fecha(0), motivo: "pedido_entregado" }
  ]
});
print("Caso 16: repartidores_estado");

// CASO 17 — promociones
dbx.promociones.insertOne({
  region_codigo: "LIM-N",
  id_comercio: seedUuid(5, 1, 1),
  codigo: "POLLO10", tipo: "porcentaje", valor: 10,
  vigencia: { desde: new Date("2026-01-01"), hasta: new Date("2026-06-30") },
  productos_aplica: [seedUuid(8, 1, 1)], activa: true
});
print("Caso 17: promociones");

// CASO 18 — notificaciones
dbx.notificaciones.insertMany([
  { region_codigo: "LIM-N", id_cliente: seedUuid(3, 1, 1), canal: "push",  titulo: "Pedido en camino", leida: false, ts: fecha(0) },
  { region_codigo: "LIM-N", id_cliente: seedUuid(3, 1, 1), canal: "email", titulo: "Gracias por tu compra", leida: true, ts: fecha(1) }
]);
print("Caso 18: notificaciones");

// CASO 19 — inventario cache
dbx.inventario_cache.insertOne({
  region_codigo: "LIM-N",
  id_comercio: seedUuid(5, 1, 1),
  actualizado: new Date(),
  items: [
    { id_producto: seedUuid(8, 1, 1), nombre: "Lomo saltado", stock: 15, disponible: true },
    { id_producto: seedUuid(8, 1, 2), nombre: "Chicha morada", stock: 0, disponible: false }
  ]
});
print("Caso 19: inventario_cache");

// CASO 20 — metricas
dbx.metricas_comercio.insertOne({
  region_codigo: "LIM-N",
  id_comercio: seedUuid(5, 1, 1),
  periodo: "2026-01",
  pedidos_total: 142,
  monto_total: 6850.50,
  ticket_promedio: 48.24,
  productos_top: [{ id_producto: seedUuid(8, 1, 1), nombre: "Lomo saltado", unidades: 89 }]
});
print("Caso 20: metricas_comercio");

// =================================================================
// GENERACION MASIVA (volumen similar al seed PostgreSQL)
// =================================================================
print("\n--- Generando datos masivos ---\n");

const bulkPerfiles = [];
const bulkComercios = [];
const bulkProductos = [];
const bulkPedidos = [];
const bulkRepartidores = [];
const bulkBitacora = [];
const bulkResenas = [];
const bulkNotificaciones = [];
const bulkProveedores = [];
const bulkSagas = [];
const bulkRutas = [];
const bulkTracking = [];
const bulkPromos = [];
const bulkMetricas = [];
const bulkInventario = [];
const bulkSesiones = [];

// Volumenes alineados con 2. datos-semilla/2. delivery_db_distribuida_seed.sql
const VOLUMEN_POR_REGION = {
  1: { clientes: 100, comercios: 25, repartidores: 20, pedidos: 150 }, // LIM-N
  2: { clientes: 80,  comercios: 20, repartidores: 15, pedidos: 120 }, // LIM-S
  3: { clientes: 65,  comercios: 15, repartidores: 12, pedidos: 90  }  // AQP
};
const PRODUCTOS_POR_COMERCIO = 24; // 4 categorias x 6 productos (como en PG)
REGIONES.forEach(reg => {
  const vol = VOLUMEN_POR_REGION[reg.idx];
  const clientesPorRegion = vol.clientes;
  const comerciosPorRegion = vol.comercios;
  const repartidoresPorRegion = vol.repartidores;
  const pedidosPorRegion = vol.pedidos;
  for (let i = 2; i <= clientesPorRegion; i++) {
    bulkPerfiles.push({
      _id: `${reg.codigo}:${seedUuid(3, reg.idx, i)}`,
      region_codigo: reg.codigo,
      id_cliente: seedUuid(3, reg.idx, i),
      id_persona: seedUuid(1, reg.idx, i),
      id_usuario: seedUuid(2, reg.idx, i),
      nombres: pick(NOMBRES, i),
      apellidos: `${pick(APELLIDOS, i)} ${pick(APELLIDOS, i + 3)}`,
      correo: `${pick(NOMBRES, i).toLowerCase()}.${i}@${reg.codigo.toLowerCase()}.pe`,
      telefono: `9${String(10000000 + i * 12345).slice(0, 8)}`,
      rol: "CLIENTE",
      preferencias: {
        idioma: "es",
        notificaciones: pick(["TODAS", "SOLO_PEDIDOS", "NINGUNA"], i),
        acepta_publicidad: i % 3 !== 0
      },
      direcciones: [{
        id: 1,
        direccion: `Calle ${100 + i}, ${reg.nombre}`,
        referencia: i % 2 === 0 ? `Piso ${i % 10}` : null,
        principal: true
      }],
      favoritos: i % 4 === 0 ? [{
        id_comercio: seedUuid(5, reg.idx, (i % comerciosPorRegion) + 1),
        id_producto: seedUuid(8, reg.idx, i),
        fecha: fecha(i % 30)
      }] : [],
      fecha_registro: fecha(60 + i)
    });
  }

  // Comercios (caso 3 masivo) — el comercio 1 de LIM-N ya existe en el ejemplo
  const comercioInicio = reg.idx === 1 ? 2 : 1;
  for (let j = comercioInicio; j <= comerciosPorRegion; j++) {
    const idCom = seedUuid(5, reg.idx, j);
    bulkComercios.push({
      _id: `${reg.codigo}:${idCom}`,
      region_codigo: reg.codigo,
      id_comercio: idCom,
      nombre: `${pick(COMERCIOS_TIPO, j)} ${reg.codigo} ${j}`,
      ruc: `20${String(100000000 + reg.idx * 1000 + j).slice(0, 9)}`,
      direccion: `Av. Principal ${j * 100}, ${reg.nombre}`,
      correo: `contacto${j}@${reg.codigo.toLowerCase()}.pe`,
      telefono: `01${4000000 + j}`,
      activo: j % 7 !== 0,
      categorias: [
        { id_categoria: seedUuid(7, reg.idx, j * 2 - 1), nombre: "Platos" },
        { id_categoria: seedUuid(7, reg.idx, j * 2), nombre: "Bebidas" }
      ],
      proveedores_vinculados: [{ id_proveedor: seedUuid(6, reg.idx, j), notas: `Proveedor ${j}` }]
    });
  }

  // Productos ricos (caso 4 masivo) — 24 por comercio (4 categorias x 6)
  for (let j = 1; j <= comerciosPorRegion; j++) {
    for (let k = 1; k <= PRODUCTOS_POR_COMERCIO; k++) {
      const n = (j - 1) * PRODUCTOS_POR_COMERCIO + k;
      if (reg.idx === 1 && n === 1) continue; // ya en caso 4
      const idProd = seedUuid(8, reg.idx, n);
      bulkProductos.push({
        _id: `${reg.codigo}:${idProd}`,
        region_codigo: reg.codigo,
        id_producto: idProd,
        id_comercio: seedUuid(5, reg.idx, j),
        nombre: `${pick(PRODUCTOS, n)} - ${j}.${k}`,
        precio: Math.round((12 + k * 2.5 + j) * 100) / 100,
        disponible: k % 8 !== 0,
        atributos: {
          picante: k % 3 === 0,
          porcion: pick(["regular", "familiar", "personal"], k),
          tiempo_prep_min: 15 + (k % 20)
        },
        alergenos: k % 2 === 0 ? ["gluten"] : ["lacteos"],
        imagenes: [`prod_${reg.idx}_${n}.jpg`],
        tags: [pick(["popular", "nuevo", "promo", "criollo"], k), "delivery"]
      });
    }
  }

  // Pedidos (caso 5 masivo) — LIM-N:150, LIM-S:120, AQP:90 (como PostgreSQL)
  const pedidoInicio = reg.idx === 1 ? 2 : 1;
  for (let p = pedidoInicio; p <= pedidosPorRegion; p++) {
    const idPed = seedUuid(9, reg.idx, p);
    const idCli = seedUuid(3, reg.idx, (p % clientesPorRegion) + 1);
    const idCom = seedUuid(5, reg.idx, (p % comerciosPorRegion) + 1);
    const estado = pick(ESTADOS_PEDIDO, p);
    const idProd1 = seedUuid(8, reg.idx, ((p - 1) % (comerciosPorRegion * PRODUCTOS_POR_COMERCIO)) + 1);
    const idProd2 = seedUuid(8, reg.idx, ((p + 9) % (comerciosPorRegion * PRODUCTOS_POR_COMERCIO)) + 1);
    const precio1 = 22 + (p % 15);
    const precio2 = 8 + (p % 10);
    const envio = 4 + (p % 6);
    const subtotal = precio1 + precio2 * 2;
    const total = subtotal + envio;

    bulkPedidos.push({
      _id: `${reg.codigo}:${idPed}`,
      region_codigo: reg.codigo,
      id_pedido: idPed,
      id_cliente: idCli,
      id_comercio: idCom,
      nombre_cliente: `${pick(NOMBRES, p)} ${pick(APELLIDOS, p)}`,
      nombre_comercio: `${pick(COMERCIOS_TIPO, p)} ${reg.codigo}`,
      estado: estado,
      direccion_entrega: `Jr. Entrega ${p}, ${reg.nombre}`,
      subtotal: subtotal,
      costo_envio: envio,
      total: total,
      detalle: [
        { id_producto: idProd1, nombre: pick(PRODUCTOS, p), cantidad: 1, precio_unitario: precio1, importe: precio1 },
        { id_producto: idProd2, nombre: pick(PRODUCTOS, p + 3), cantidad: 2, precio_unitario: precio2, importe: precio2 * 2 }
      ],
      pago: {
        metodo: pick(METODOS_PAGO, p),
        estado: estado === "CANCELADO" ? "RECHAZADO" : pick(ESTADOS_PAGO, p),
        monto: total,
        fecha_pago: estado === "ENTREGADO" ? fecha(p % 25) : null
      },
      fecha_creacion: fecha(p % 45)
    });

    // Tracking (caso 14 masivo)
    const eventos = [];
    const maxEst = ESTADOS_PEDIDO.indexOf(estado);
    for (let e = 0; e <= maxEst && maxEst >= 0; e++) {
      eventos.push({ estado: ESTADOS_PEDIDO[e], ts: fecha(p % 45 - e), actor: pick(["sistema", "comercio", "repartidor"], e) });
    }
    if (eventos.length > 0) {
      bulkTracking.push({ region_codigo: reg.codigo, id_pedido: idPed, eventos: eventos });
    }

    // Bitacora (caso 9 masivo)
    bulkBitacora.push({
      id_evento: seedUuid(99, reg.idx, p),
      region_codigo: reg.codigo,
      fecha_hora: fecha(p % 30),
      tipo_evento: `PEDIDO_${estado}`,
      tabla_afectada: "pedido",
      id_registro: idPed,
      id_usuario: seedUuid(2, reg.idx, (p % clientesPorRegion) + 1),
      nodo_origen: reg.codigo,
      payload: { total: total, estado: estado, comercio: idCom }
    });

    // Saga cada 5 pedidos (caso 10 masivo)
    if (p % 5 === 0) {
      bulkSagas.push({
        id_saga: seedUuid(14, reg.idx, p),
        tipo_operacion: "CREAR_PEDIDO",
        region_codigo: reg.codigo,
        estado: estado === "CANCELADO" ? "FALLIDA" : "COMPLETADA",
        id_pedido: idPed,
        pasos: [
          { orden: 1, nombre: "validar_stock", estado: estado === "CANCELADO" ? "ERROR" : "OK", detalle: {} },
          { orden: 2, nombre: "crear_pedido", estado: "OK", detalle: { id_pedido: idPed } },
          { orden: 3, nombre: "registrar_pago", estado: estado === "CANCELADO" ? "ERROR" : "OK", detalle: {} },
          { orden: 4, nombre: "confirmar_pedido", estado: estado === "CANCELADO" ? "COMPENSADO" : "OK", detalle: {} }
        ],
        fecha_creacion: fecha(p % 40)
      });
    }
  }

  // Repartidores (caso 7 masivo) — repartidor 1 LIM-N ya en ejemplo
  const repInicio = reg.idx === 1 ? 2 : 1;
  for (let r = repInicio; r <= repartidoresPorRegion; r++) {
    const idRep = seedUuid(4, reg.idx, r);
    const lat = -12.0 - reg.idx * 0.05 - r * 0.01;
    bulkRepartidores.push({
      _id: `${reg.codigo}:${idRep}`,
      region_codigo: reg.codigo,
      id_repartidor: idRep,
      placa: `${reg.codigo.replace("-", "")}-${String(r).padStart(3, "0")}`,
      disponible: r % 3 !== 0,
      tipo_vehiculo: pick(VEHICULOS, r),
      ubicacion_actual: { lat: lat, lng: -77.04 - r * 0.005, ts: new Date() },
      historial: [
        { lat: lat + 0.002, lng: -77.045, ts: fecha(1), evento: "inicio_turno" },
        { lat: lat, lng: -77.04, ts: fecha(0), evento: "en_ruta" }
      ]
    });
  }

  // Rutas (caso 8 masivo) — 3 rutas por repartidor (como en PG)
  for (let rt = 1; rt <= repartidoresPorRegion * 3; rt++) {
    bulkRutas.push({
      _id: `${reg.codigo}:${seedUuid(12, reg.idx, rt)}`,
      region_codigo: reg.codigo,
      id_ruta: seedUuid(12, reg.idx, rt),
      id_repartidor: seedUuid(4, reg.idx, rt),
      estado: pick(["PLANIFICADA", "EN_PROGRESO", "FINALIZADA"], rt),
      fecha_planificacion: fecha(rt * 2),
      paradas: [
        { orden: 1, id_pedido: seedUuid(9, reg.idx, rt), hora_estimada: fecha(rt) },
        { orden: 2, id_pedido: seedUuid(9, reg.idx, rt + 5), hora_estimada: fecha(rt - 1) }
      ]
    });
  }

  // Proveedores (caso 12 masivo) — proveedor 1 LIM-N ya en ejemplo
  const provInicio = reg.idx === 1 ? 2 : 1;
  for (let pr = provInicio; pr <= 5; pr++) {
    bulkProveedores.push({
      _id: `${reg.codigo}:${seedUuid(6, reg.idx, pr)}`,
      region_codigo: reg.codigo,
      id_proveedor: seedUuid(6, reg.idx, pr),
      activo: true,
      identidad: {
        tipo_persona: pr % 2 === 0 ? "JURIDICA" : "NATURAL",
        razon_social: pr % 2 === 0 ? `Proveedor ${reg.codigo} SAC ${pr}` : null,
        nombres: pr % 2 !== 0 ? pick(NOMBRES, pr) : null,
        apellidos: pr % 2 !== 0 ? pick(APELLIDOS, pr) : null,
        ruc: `20${String(200000000 + reg.idx * 100 + pr).slice(0, 9)}`,
        correo: `prov${pr}@${reg.codigo.toLowerCase()}.pe`,
        telefono: `01${5000000 + pr}`
      }
    });
  }

  // Promociones, metricas, inventario por comercio
  for (let j = 1; j <= comerciosPorRegion; j++) {
    bulkPromos.push({
      region_codigo: reg.codigo,
      id_comercio: seedUuid(5, reg.idx, j),
      codigo: `PROMO${reg.idx}${j}`,
      tipo: j % 2 === 0 ? "porcentaje" : "monto_fijo",
      valor: j % 2 === 0 ? 10 + j : 5,
      vigencia: { desde: new Date("2026-01-01"), hasta: new Date("2026-12-31") },
      activa: j % 5 !== 0
    });

    bulkMetricas.push({
      region_codigo: reg.codigo,
      id_comercio: seedUuid(5, reg.idx, j),
      periodo: "2026-01",
      pedidos_total: Math.round(pedidosPorRegion / comerciosPorRegion * (0.8 + (j % 5) * 0.1)),
      monto_total: Math.round(pedidosPorRegion / comerciosPorRegion * (38 + j * 2) * 100) / 100,
      ticket_promedio: 35 + j * 2,
      productos_top: [
        { id_producto: seedUuid(8, reg.idx, j), nombre: pick(PRODUCTOS, j), unidades: 20 + j * 5 }
      ]
    });

    const items = [];
    for (let k = 1; k <= 8; k++) {
      items.push({
        id_producto: seedUuid(8, reg.idx, (j - 1) * PRODUCTOS_POR_COMERCIO + k),
        nombre: pick(PRODUCTOS, k),
        stock: 5 + ((j + k) % 20),
        disponible: k % 8 !== 0
      });
    }
    bulkInventario.push({
      region_codigo: reg.codigo,
      id_comercio: seedUuid(5, reg.idx, j),
      actualizado: new Date(),
      items: items
    });
  }
});

// Resenas (caso 15 masivo) — 150 resenas
for (let i = 1; i <= 150; i++) {
  const reg = pick(REGIONES, i);
  bulkResenas.push({
    region_codigo: reg.codigo,
    id_producto: seedUuid(8, reg.idx, (i % 200) + 1),
    id_cliente: seedUuid(3, reg.idx, (i % VOLUMEN_POR_REGION[reg.idx].clientes) + 1),
    estrellas: (i % 5) + 1,
    comentario: pick([
      "Muy rico, llego caliente",
      "Buen sabor, porcion justa",
      "Demoro un poco pero ok",
      "Excelente presentacion",
      "Repetire pronto"
    ], i),
    fotos: i % 3 === 0 ? [`resena_${i}.jpg`] : [],
    fecha: fecha(i % 60)
  });
}

// Notificaciones (caso 18 masivo) — 250
for (let i = 1; i <= 250; i++) {
  const reg = pick(REGIONES, i);
  bulkNotificaciones.push({
    region_codigo: reg.codigo,
    id_cliente: seedUuid(3, reg.idx, (i % VOLUMEN_POR_REGION[reg.idx].clientes) + 1),
    canal: pick(["push", "email", "sms"], i),
    titulo: pick(["Pedido confirmado", "Pedido en camino", "Pedido entregado", "Promo disponible"], i),
    leida: i % 3 === 0,
    ts: fecha(i % 20)
  });
}

// Sesiones app — 100
for (let i = 1; i <= 100; i++) {
  const reg = pick(REGIONES, i);
  bulkSesiones.push({
    region_codigo: reg.codigo,
    id_usuario: seedUuid(2, reg.idx, (i % VOLUMEN_POR_REGION[reg.idx].clientes) + 1),
    dispositivo: pick(["android", "ios", "web"], i),
    token_fcm: `fcm_token_${i}_${Date.now()}`,
    ultimo_acceso: fecha(i % 10),
    activa: i % 5 !== 0
  });
}

// Repartidores estado — todos los repartidores por region
const bulkRepartidoresEstado = [];
REGIONES.forEach(reg => {
  const vol = VOLUMEN_POR_REGION[reg.idx];
  const repInicioEst = reg.idx === 1 ? 2 : 1;
  for (let r = repInicioEst; r <= vol.repartidores; r++) {
    bulkRepartidoresEstado.push({
      region_codigo: reg.codigo,
      id_repartidor: seedUuid(4, reg.idx, r),
      cambios: [
        { disponible: true, ts: fecha(2), motivo: "inicio_turno" },
        { disponible: false, ts: fecha(1), motivo: "asignado_pedido", id_pedido: seedUuid(9, reg.idx, r) },
        { disponible: true, ts: fecha(0), motivo: "pedido_entregado" }
      ]
    });
  }
});

// Inserciones masivas (por lotes en colecciones grandes)
function insertarEnLotes(coleccion, docs, tamLote = 100) {
  if (docs.length === 0) return;
  for (let i = 0; i < docs.length; i += tamLote) {
    dbx[coleccion].insertMany(docs.slice(i, i + tamLote), { ordered: false });
  }
  print(`  ${coleccion}: +${docs.length} documentos`);
}

const inserts = [
  ["perfiles_cliente", bulkPerfiles],
  ["comercios", bulkComercios],
  ["productos_ricos", bulkProductos, 200],
  ["pedidos_docs", bulkPedidos, 100],
  ["repartidores_tracking", bulkRepartidores],
  ["rutas", bulkRutas, 100],
  ["bitacora_eventos", bulkBitacora, 100],
  ["saga_eventos", bulkSagas, 100],
  ["proveedores", bulkProveedores],
  ["tracking_pedidos", bulkTracking, 100],
  ["resenas_producto", bulkResenas, 100],
  ["repartidores_estado", bulkRepartidoresEstado],
  ["promociones", bulkPromos],
  ["notificaciones", bulkNotificaciones, 100],
  ["inventario_cache", bulkInventario],
  ["metricas_comercio", bulkMetricas],
  ["sesiones_app", bulkSesiones]
];

inserts.forEach(([col, docs, tamLote]) => {
  insertarEnLotes(col, docs, tamLote || 100);
});

// Resumen final por region (pedidos)
print("\n=== PEDIDOS POR REGION ===");
REGIONES.forEach(reg => {
  const n = dbx.pedidos_docs.countDocuments({ region_codigo: reg.codigo });
  print(`  ${reg.codigo}: ${n} pedidos`);
});

// Resumen final
print("\n=== RESUMEN COLECCIONES ===");
[
  "perfiles_cliente", "catalogo", "comercios", "productos_ricos", "pedidos_docs",
  "repartidores_tracking", "rutas", "bitacora_eventos", "saga_eventos",
  "proveedores", "resenas_producto", "notificaciones", "metricas_comercio"
].forEach(col => {
  print(`  ${col}: ${dbx[col].countDocuments()} docs`);
});

print(`\n=== Fin: BD '${dbName}' cargada (20 casos + datos masivos) ===`);
