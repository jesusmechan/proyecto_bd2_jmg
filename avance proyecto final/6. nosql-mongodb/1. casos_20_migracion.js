// =========================================================
// PASO 6.1 — 20 casos practicos: modelo RELACIONAL → MongoDB
// delivery_db_distribuida  →  BD: delivery_nosql
//
// Volumen: 50 documentos por cada coleccion.
//
// Ejecutar (mongosh):
//   mongosh < "6. nosql-mongodb/1. casos_20_migracion.js"
// =========================================================

const dbName = "delivery_nosql_jmg";
const dbx = db.getSiblingDB(dbName);

const DOCS_POR_COLECCION = 50;

const REGIONES = [
  { codigo: "LIM-N", idx: 1, nombre: "Lima Norte" },
  { codigo: "LIM-S", idx: 2, nombre: "Lima Sur" },
  { codigo: "AQP",   idx: 3, nombre: "Arequipa" }
];

const ESTADOS_PEDIDO = ["CREADO", "CONFIRMADO", "EN_CAMINO", "ENTREGADO", "CANCELADO"];
const METODOS_PAGO   = ["EFECTIVO", "TARJETA", "YAPE", "PLIN", "TRANSFERENCIA"];
const ESTADOS_PAGO   = ["PENDIENTE", "PAGADO", "RECHAZADO", "DEVUELTO"];
const VEHICULOS      = ["MOTO", "BICI", "AUTO"];
const ROLES          = ["CLIENTE", "REPARTIDOR", "ADMINISTRADOR"];
const NOMBRES        = ["Maria", "Juan", "Carlos", "Ana", "Luis", "Rosa", "Pedro", "Lucia", "Miguel", "Elena"];
const APELLIDOS      = ["Garcia", "Rodriguez", "Lopez", "Martinez", "Gonzalez", "Perez", "Sanchez", "Ramirez"];
const COMERCIOS_TIPO = ["Polleria", "Cevicheria", "Pizzeria", "Cafeteria", "Chifa", "Sushi Bar", "Pasteleria", "Delivery Saludable"];
const PRODUCTOS      = ["Lomo saltado", "Ceviche mixto", "Pizza margarita", "Arroz chaufa", "Pollo a la brasa",
                        "Causa limena", "Tallarin saltado", "Hamburguesa clasica", "Ensalada Cesar", "Sushi roll 12p"];
const CANALES        = ["push", "email", "sms"];
const DISPOSITIVOS   = ["android", "ios", "web"];

const COLECCIONES = [
  "perfiles_cliente", "catalogo", "comercios", "productos_ricos", "pedidos_docs",
  "repartidores_tracking", "rutas", "bitacora_eventos", "saga_eventos",
  "metadata_nodos", "proveedores", "config_fragmentacion", "tracking_pedidos",
  "resenas_producto", "repartidores_estado", "promociones", "notificaciones",
  "inventario_cache", "metricas_comercio", "sesiones_app"
];

// UUID deterministico (igual que seed_uuid en PostgreSQL)
function seedUuid(tipo, regionIdx, n) {
  const t = tipo.toString(16).padStart(8, "0");
  const r = regionIdx.toString(16).padStart(4, "0");
  const num = n.toString(16).padStart(12, "0");
  return `${t}-${r}-4001-8001-${num}`;
}

function pick(arr, i) { return arr[i % arr.length]; }
function regDe(i) { return pick(REGIONES, i - 1); }
function fecha(diasAtras) {
  const d = new Date();
  d.setDate(d.getDate() - diasAtras);
  d.setHours(10 + (Math.abs(diasAtras) % 10), (Math.abs(diasAtras) * 7) % 60, 0, 0);
  return d;
}

function range(n) {
  return Array.from({ length: n }, (_, i) => i + 1);
}

COLECCIONES.forEach(c => dbx[c].drop());

print("=== 20 CASOS RELACIONAL → NoSQL ===");
print(`Volumen objetivo: ${DOCS_POR_COLECCION} documentos por coleccion\n`);

// =================================================================
// Documentacion de los 20 casos de migracion
// =================================================================
print("Caso  1: persona + usuario + cliente     → perfiles_cliente");
print("Caso  2: catalogo_maestro               → catalogo");
print("Caso  3: comercio + categorias          → comercios (embebido)");
print("Caso  4: producto                       → productos_ricos");
print("Caso  5: pedido + detalle + pago        → pedidos_docs (embebido)");
print("Caso  6: pago                           → pedidos_docs.pago");
print("Caso  7: repartidor + GPS               → repartidores_tracking");
print("Caso  8: ruta + paradas                 → rutas.paradas[]");
print("Caso  9: bitacora_evento                → bitacora_eventos");
print("Caso 10: saga_transaccion + pasos       → saga_eventos");
print("Caso 11: nodo_registro                  → metadata_nodos");
print("Caso 12: proveedor + persona            → proveedores.identidad");
print("Caso 13: regla_fragmentacion            → config_fragmentacion");
print("Caso 14: historial de estados pedido    → tracking_pedidos");
print("Caso 15: (nuevo NoSQL) resenas          → resenas_producto");
print("Caso 16: historial disponibilidad       → repartidores_estado");
print("Caso 17: (nuevo NoSQL) promociones      → promociones");
print("Caso 18: (nuevo NoSQL) notificaciones   → notificaciones");
print("Caso 19: (nuevo NoSQL) inventario       → inventario_cache");
print("Caso 20: (nuevo NoSQL) metricas         → metricas_comercio");
print("       + sesiones_app (sesiones movil/web)\n");

// =================================================================
// GENERACION: 50 documentos por coleccion
// =================================================================
print(`--- Generando ${DOCS_POR_COLECCION} documentos por coleccion ---\n`);

// CASO 1 — perfiles_cliente
const perfiles = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  return {
    _id: `${reg.codigo}:${seedUuid(3, reg.idx, i)}`,
    region_codigo: reg.codigo,
    id_cliente: seedUuid(3, reg.idx, i),
    id_persona: seedUuid(1, reg.idx, i),
    id_usuario: seedUuid(2, reg.idx, i),
    nombres: pick(NOMBRES, i),
    apellidos: `${pick(APELLIDOS, i)} ${pick(APELLIDOS, i + 3)}`,
    correo: `${pick(NOMBRES, i).toLowerCase()}.${i}@${reg.codigo.toLowerCase()}.pe`,
    telefono: `9${String(10000000 + i * 137).slice(0, 8)}`,
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
      id_comercio: seedUuid(5, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
      id_producto: seedUuid(8, reg.idx, i),
      fecha: fecha(i % 30)
    }] : [],
    fecha_registro: fecha(60 + i)
  };
});

// CASO 2 — catalogo (50 documentos: tipos ampliados + valores individuales)
const TIPOS_CATALOGO = [
  "ESTADO_PEDIDO", "METODO_PAGO", "ESTADO_PAGO", "TIPO_VEHICULO", "ROL",
  "PREFERENCIA_NOTIFICACION", "TIPO_PERSONA", "TIPO_DOCUMENTO", "ESTADO_RUTA", "CANAL_NOTIFICACION"
];
const catalogoDocs = range(DOCS_POR_COLECCION).map(i => {
  const tipo = pick(TIPOS_CATALOGO, i - 1);
  let valores;
  if (tipo === "ESTADO_PEDIDO") {
    valores = ESTADOS_PEDIDO.map((c, idx) => ({ codigo: c, nombre: c.replace("_", " "), orden: idx + 1 }));
  } else if (tipo === "METODO_PAGO") {
    valores = METODOS_PAGO.map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else if (tipo === "ESTADO_PAGO") {
    valores = ESTADOS_PAGO.map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else if (tipo === "TIPO_VEHICULO") {
    valores = VEHICULOS.map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else if (tipo === "ROL") {
    valores = ROLES.map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else if (tipo === "PREFERENCIA_NOTIFICACION") {
    valores = ["TODAS", "SOLO_PEDIDOS", "NINGUNA"].map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else if (tipo === "TIPO_PERSONA") {
    valores = ["NATURAL", "JURIDICA"].map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else if (tipo === "TIPO_DOCUMENTO") {
    valores = ["DNI", "RUC"].map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else if (tipo === "ESTADO_RUTA") {
    valores = ["PLANIFICADA", "EN_PROGRESO", "FINALIZADA", "CANCELADA"].map((c, idx) => ({ codigo: c, nombre: c, orden: idx + 1 }));
  } else {
    valores = CANALES.map((c, idx) => ({ codigo: c.toUpperCase(), nombre: c, orden: idx + 1 }));
  }
  return {
    _id: `cat_${String(i).padStart(2, "0")}_${tipo.toLowerCase()}`,
    tipo_catalogo: tipo,
    version_replica: i,
    nodo_origen: pick(["GLOBAL", "LIM-N", "LIM-S", "AQP"], i),
    activo: i % 10 !== 0,
    valores: valores,
    fecha_sincronizacion: fecha(i % 15)
  };
});

// CASO 3 — comercios
const comercios = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const idCom = seedUuid(5, reg.idx, i);
  return {
    _id: `${reg.codigo}:${idCom}`,
    region_codigo: reg.codigo,
    id_comercio: idCom,
    nombre: `${pick(COMERCIOS_TIPO, i)} ${reg.codigo} ${i}`,
    ruc: `20${String(100000000 + reg.idx * 1000 + i).slice(0, 9)}`,
    direccion: `Av. Principal ${i * 10}, ${reg.nombre}`,
    correo: `contacto${i}@${reg.codigo.toLowerCase()}.pe`,
    telefono: `01${4000000 + i}`,
    activo: i % 7 !== 0,
    categorias: [
      { id_categoria: seedUuid(7, reg.idx, i * 2 - 1), nombre: "Platos" },
      { id_categoria: seedUuid(7, reg.idx, i * 2), nombre: "Bebidas" }
    ],
    proveedores_vinculados: [{
      id_proveedor: seedUuid(6, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
      notas: `Abastecimiento ${i}`
    }]
  };
});

// CASO 4 — productos_ricos
const productos = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const idProd = seedUuid(8, reg.idx, i);
  return {
    _id: `${reg.codigo}:${idProd}`,
    region_codigo: reg.codigo,
    id_producto: idProd,
    id_comercio: seedUuid(5, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    nombre: `${pick(PRODUCTOS, i)} #${i}`,
    precio: Math.round((12 + (i % 20) * 2.5) * 100) / 100,
    disponible: i % 8 !== 0,
    atributos: {
      picante: i % 3 === 0,
      porcion: pick(["regular", "familiar", "personal"], i),
      tiempo_prep_min: 15 + (i % 20)
    },
    alergenos: i % 2 === 0 ? ["gluten"] : ["lacteos"],
    imagenes: [`prod_${reg.idx}_${i}.jpg`],
    tags: [pick(["popular", "nuevo", "promo", "criollo"], i), "delivery"]
  };
});

// CASO 5/6 — pedidos_docs (detalle + pago embebidos)
const pedidos = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const idPed = seedUuid(9, reg.idx, i);
  const estado = pick(ESTADOS_PEDIDO, i);
  const precio1 = 22 + (i % 15);
  const precio2 = 8 + (i % 10);
  const envio = 4 + (i % 6);
  const subtotal = precio1 + precio2 * 2;
  const total = subtotal + envio;
  return {
    _id: `${reg.codigo}:${idPed}`,
    region_codigo: reg.codigo,
    id_pedido: idPed,
    id_cliente: seedUuid(3, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    id_comercio: seedUuid(5, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    id_repartidor: estado === "CREADO" || estado === "CANCELADO"
      ? null
      : seedUuid(4, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    nombre_cliente: `${pick(NOMBRES, i)} ${pick(APELLIDOS, i)}`,
    nombre_comercio: `${pick(COMERCIOS_TIPO, i)} ${reg.codigo}`,
    estado: estado,
    direccion_entrega: `Jr. Entrega ${i}, ${reg.nombre}`,
    subtotal: subtotal,
    costo_envio: envio,
    total: total,
    detalle: [
      {
        id_producto: seedUuid(8, reg.idx, i),
        nombre: pick(PRODUCTOS, i),
        cantidad: 1,
        precio_unitario: precio1,
        importe: precio1
      },
      {
        id_producto: seedUuid(8, reg.idx, ((i + 9) % DOCS_POR_COLECCION) + 1),
        nombre: pick(PRODUCTOS, i + 3),
        cantidad: 2,
        precio_unitario: precio2,
        importe: precio2 * 2
      }
    ],
    pago: {
      metodo: pick(METODOS_PAGO, i),
      estado: estado === "CANCELADO" ? "DEVUELTO" : pick(["PENDIENTE", "PAGADO", "RECHAZADO"], i),
      monto: total,
      fecha_pago: estado === "ENTREGADO" || estado === "EN_CAMINO" ? fecha(i % 25) : null
    },
    fecha_creacion: fecha(i % 45)
  };
});

// CASO 7 — repartidores_tracking
const repartidores = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const idRep = seedUuid(4, reg.idx, i);
  const lat = -12.0 - reg.idx * 0.05 - (i % 10) * 0.01;
  return {
    _id: `${reg.codigo}:${idRep}`,
    region_codigo: reg.codigo,
    id_repartidor: idRep,
    placa: `${reg.codigo.replace("-", "")}-${String(i).padStart(3, "0")}`,
    disponible: i % 3 !== 0,
    tipo_vehiculo: pick(VEHICULOS, i),
    ubicacion_actual: { lat: lat, lng: -77.04 - (i % 10) * 0.005, ts: new Date() },
    historial: [
      { lat: lat + 0.002, lng: -77.045, ts: fecha(1), evento: "inicio_turno" },
      { lat: lat, lng: -77.04, ts: fecha(0), evento: "en_ruta" }
    ]
  };
});

// CASO 8 — rutas
const rutas = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  return {
    _id: `${reg.codigo}:${seedUuid(12, reg.idx, i)}`,
    region_codigo: reg.codigo,
    id_ruta: seedUuid(12, reg.idx, i),
    id_repartidor: seedUuid(4, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    estado: pick(["PLANIFICADA", "EN_PROGRESO", "FINALIZADA", "CANCELADA"], i),
    fecha_planificacion: fecha(i % 20),
    distancia_kilometros: Math.round((3 + i * 0.35) * 100) / 100,
    paradas: [
      { orden: 1, id_pedido: seedUuid(9, reg.idx, i), hora_estimada: fecha(i % 10) },
      { orden: 2, id_pedido: seedUuid(9, reg.idx, ((i + 4) % DOCS_POR_COLECCION) + 1), hora_estimada: fecha((i % 10) - 1) }
    ]
  };
});

// CASO 9 — bitacora_eventos
const bitacora = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const estado = pick(ESTADOS_PEDIDO, i);
  return {
    id_evento: seedUuid(99, reg.idx, i),
    region_codigo: reg.codigo,
    fecha_hora: fecha(i % 30),
    tipo_evento: `PEDIDO_${estado}`,
    tabla_afectada: "pedido",
    id_registro: seedUuid(9, reg.idx, i),
    id_usuario: seedUuid(2, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    nodo_origen: reg.codigo,
    payload: { total: 30 + i, estado: estado, comercio: seedUuid(5, reg.idx, i) }
  };
});

// CASO 10 — saga_eventos
const sagas = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const estadoPed = pick(ESTADOS_PEDIDO, i);
  const fallida = estadoPed === "CANCELADO";
  return {
    id_saga: seedUuid(14, reg.idx, i),
    tipo_operacion: "CREAR_PEDIDO",
    region_codigo: reg.codigo,
    estado: fallida ? "FALLIDA" : (estadoPed === "CREADO" ? "INICIADA" : "COMPLETADA"),
    id_pedido: seedUuid(9, reg.idx, i),
    pasos: [
      { orden: 1, nombre: "validar_stock", estado: fallida ? "ERROR" : "OK", detalle: { ok: !fallida } },
      { orden: 2, nombre: "crear_pedido", estado: "OK", detalle: { id_pedido: seedUuid(9, reg.idx, i) } },
      { orden: 3, nombre: "registrar_pago", estado: fallida ? "ERROR" : (estadoPed === "CREADO" ? "PENDIENTE" : "OK"), detalle: {} },
      { orden: 4, nombre: "confirmar_pedido", estado: fallida ? "COMPENSADO" : (estadoPed === "CREADO" ? "PENDIENTE" : "OK"), detalle: {} }
    ],
    payload: { pedido: i, region: reg.codigo, total: 30 + i },
    fecha_creacion: fecha(i % 40)
  };
});

// CASO 11 — metadata_nodos (50 nodos/replicas/shards documentados)
const metadataNodos = range(DOCS_POR_COLECCION).map(i => {
  if (i === 1) {
    return {
      region_codigo: "GLOBAL",
      nombre_nodo: "Nodo central de catalogos",
      es_nodo_global: true,
      activo: true,
      rol: "catalogo_replica",
      host: "global-01.delivery.local",
      puerto: 5432,
      version_schema: 1
    };
  }
  const reg = REGIONES[(i - 2) % REGIONES.length];
  const shard = Math.floor((i - 2) / REGIONES.length) + 1;
  return {
    region_codigo: reg.codigo,
    nombre_nodo: `${reg.nombre} shard-${String(shard).padStart(2, "0")}`,
    es_nodo_global: false,
    activo: i % 9 !== 0,
    rol: pick(["primario", "replica", "lectura"], i),
    host: `${reg.codigo.toLowerCase()}-s${shard}.delivery.local`,
    puerto: 5432 + (i % 5),
    version_schema: 1 + (i % 3),
    capacidad_max_docs: 100000 + i * 1000
  };
});

// CASO 12 — proveedores
const proveedores = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const juridica = i % 2 === 0;
  return {
    _id: `${reg.codigo}:${seedUuid(6, reg.idx, i)}`,
    region_codigo: reg.codigo,
    id_proveedor: seedUuid(6, reg.idx, i),
    activo: i % 11 !== 0,
    identidad: {
      tipo_persona: juridica ? "JURIDICA" : "NATURAL",
      razon_social: juridica ? `Proveedor ${reg.codigo} SAC ${i}` : null,
      nombres: juridica ? null : pick(NOMBRES, i),
      apellidos: juridica ? null : pick(APELLIDOS, i),
      ruc: `20${String(200000000 + reg.idx * 100 + i).slice(0, 9)}`,
      correo: `prov${i}@${reg.codigo.toLowerCase()}.pe`,
      telefono: `01${5000000 + i}`
    }
  };
});

// CASO 13 — config_fragmentacion (50 reglas)
const TABLAS_FRAG = [
  "persona", "usuario", "cliente", "repartidor", "comercio", "proveedor",
  "producto", "pedido", "detalle_pedido", "pago", "ruta_reparto", "parada_ruta",
  "bitacora_evento", "catalogo_maestro", "saga_transaccion", "categoria_producto",
  "comercio_proveedor", "nodo_registro", "regla_fragmentacion", "metricas"
];
const configFrag = range(DOCS_POR_COLECCION).map(i => ({
  version: i,
  tabla: pick(TABLAS_FRAG, i - 1),
  estrategia: pick(["HORIZONTAL", "HORIZONTAL+VERTICAL", "REPLICA", "SHARD"], i),
  clave: i % 4 === 2 ? null : "region_codigo",
  nodo_ejemplo: pick(["LIM-N", "LIM-S", "AQP", "GLOBAL"], i),
  criterio: `Fragmentacion de ${pick(TABLAS_FRAG, i - 1)} — regla ${i}`,
  activo: i % 10 !== 0,
  fecha_actualizacion: fecha(i % 20)
}));

// CASO 14 — tracking_pedidos
const tracking = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const estado = pick(ESTADOS_PEDIDO, i);
  const maxEst = ESTADOS_PEDIDO.indexOf(estado);
  const eventos = [];
  for (let e = 0; e <= maxEst && maxEst >= 0; e++) {
    eventos.push({
      estado: ESTADOS_PEDIDO[e],
      ts: fecha((i % 45) - e),
      actor: pick(["sistema", "comercio", "repartidor"], e)
    });
  }
  return {
    region_codigo: reg.codigo,
    id_pedido: seedUuid(9, reg.idx, i),
    eventos: eventos.length ? eventos : [{ estado: "CREADO", ts: fecha(i % 10), actor: "sistema" }]
  };
});

// CASO 15 — resenas_producto
const COMENTARIOS = [
  "Muy rico, llego caliente",
  "Buen sabor, porcion justa",
  "Demoro un poco pero ok",
  "Excelente presentacion",
  "Repetire pronto"
];
const resenas = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  return {
    region_codigo: reg.codigo,
    id_producto: seedUuid(8, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    id_cliente: seedUuid(3, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    estrellas: (i % 5) + 1,
    comentario: pick(COMENTARIOS, i),
    fotos: i % 3 === 0 ? [`resena_${i}.jpg`] : [],
    fecha: fecha(i % 60)
  };
});

// CASO 16 — repartidores_estado
const repartidoresEstado = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  return {
    region_codigo: reg.codigo,
    id_repartidor: seedUuid(4, reg.idx, i),
    cambios: [
      { disponible: true, ts: fecha(2), motivo: "inicio_turno" },
      { disponible: false, ts: fecha(1), motivo: "asignado_pedido", id_pedido: seedUuid(9, reg.idx, i) },
      { disponible: true, ts: fecha(0), motivo: "pedido_entregado" }
    ]
  };
});

// CASO 17 — promociones
const promociones = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  return {
    region_codigo: reg.codigo,
    id_comercio: seedUuid(5, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    codigo: `PROMO${reg.idx}${String(i).padStart(2, "0")}`,
    tipo: i % 2 === 0 ? "porcentaje" : "monto_fijo",
    valor: i % 2 === 0 ? 10 + (i % 15) : 3 + (i % 8),
    vigencia: { desde: new Date("2026-01-01"), hasta: new Date("2026-12-31") },
    productos_aplica: [seedUuid(8, reg.idx, i)],
    activa: i % 5 !== 0
  };
});

// CASO 18 — notificaciones
const notificaciones = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  return {
    region_codigo: reg.codigo,
    id_cliente: seedUuid(3, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    canal: pick(CANALES, i),
    titulo: pick(["Pedido confirmado", "Pedido en camino", "Pedido entregado", "Promo disponible"], i),
    leida: i % 3 === 0,
    ts: fecha(i % 20)
  };
});

// CASO 19 — inventario_cache
const inventario = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const items = range(4).map(k => ({
    id_producto: seedUuid(8, reg.idx, ((i + k - 1) % DOCS_POR_COLECCION) + 1),
    nombre: pick(PRODUCTOS, i + k),
    stock: 5 + ((i + k) % 20),
    disponible: (i + k) % 8 !== 0
  }));
  return {
    region_codigo: reg.codigo,
    id_comercio: seedUuid(5, reg.idx, i),
    actualizado: new Date(),
    items: items
  };
});

// CASO 20 — metricas_comercio
const metricas = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  const pedidosTotal = 20 + (i % 40);
  return {
    region_codigo: reg.codigo,
    id_comercio: seedUuid(5, reg.idx, i),
    periodo: pick(["2026-01", "2026-02", "2026-03"], i),
    pedidos_total: pedidosTotal,
    monto_total: Math.round(pedidosTotal * (38 + i) * 100) / 100,
    ticket_promedio: Math.round((35 + (i % 20)) * 100) / 100,
    productos_top: [{
      id_producto: seedUuid(8, reg.idx, i),
      nombre: pick(PRODUCTOS, i),
      unidades: 10 + i
    }]
  };
});

// Extra coleccion: sesiones_app (tambien 50)
const sesiones = range(DOCS_POR_COLECCION).map(i => {
  const reg = regDe(i);
  return {
    region_codigo: reg.codigo,
    id_usuario: seedUuid(2, reg.idx, ((i - 1) % DOCS_POR_COLECCION) + 1),
    dispositivo: pick(DISPOSITIVOS, i),
    token_fcm: `fcm_token_${i}_${reg.codigo}`,
    ultimo_acceso: fecha(i % 10),
    activa: i % 5 !== 0
  };
});

// Inserciones
function insertarEnLotes(coleccion, docs, tamLote = 50) {
  if (!docs || docs.length === 0) {
    print(`  ${coleccion}: 0 documentos (omitido)`);
    return;
  }
  for (let i = 0; i < docs.length; i += tamLote) {
    dbx[coleccion].insertMany(docs.slice(i, i + tamLote), { ordered: false });
  }
  print(`  ${coleccion}: ${docs.length} documentos`);
}

const inserts = [
  ["perfiles_cliente", perfiles],
  ["catalogo", catalogoDocs],
  ["comercios", comercios],
  ["productos_ricos", productos],
  ["pedidos_docs", pedidos],
  ["repartidores_tracking", repartidores],
  ["rutas", rutas],
  ["bitacora_eventos", bitacora],
  ["saga_eventos", sagas],
  ["metadata_nodos", metadataNodos],
  ["proveedores", proveedores],
  ["config_fragmentacion", configFrag],
  ["tracking_pedidos", tracking],
  ["resenas_producto", resenas],
  ["repartidores_estado", repartidoresEstado],
  ["promociones", promociones],
  ["notificaciones", notificaciones],
  ["inventario_cache", inventario],
  ["metricas_comercio", metricas],
  ["sesiones_app", sesiones]
];

inserts.forEach(([col, docs]) => insertarEnLotes(col, docs));

// Resumen por region (pedidos)
print("\n=== PEDIDOS POR REGION ===");
REGIONES.forEach(reg => {
  const n = dbx.pedidos_docs.countDocuments({ region_codigo: reg.codigo });
  print(`  ${reg.codigo}: ${n} pedidos`);
});

// Resumen final — cada coleccion debe tener 50
print("\n=== RESUMEN COLECCIONES (objetivo: 50 c/u) ===");
let ok = true;
COLECCIONES.forEach(col => {
  const n = dbx[col].countDocuments();
  const marca = n === DOCS_POR_COLECCION ? "OK" : `ESPERADO ${DOCS_POR_COLECCION}`;
  if (n !== DOCS_POR_COLECCION) ok = false;
  print(`  ${col}: ${n} docs  [${marca}]`);
});

print(`\n=== Fin: BD '${dbName}' cargada (20 casos + ${DOCS_POR_COLECCION} docs/coleccion) ${ok ? "✓" : "⚠ revisar conteos"} ===`);
