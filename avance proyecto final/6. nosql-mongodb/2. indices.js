// =========================================================
// PASO 6.2 — Indices MongoDB
// Ejecutar despues de: 1. casos_20_migracion.js (50 docs/coleccion)
//
//   mongosh delivery_nosql < "6. nosql-mongodb/2. indices.js"
// =========================================================

const dbx = db.getSiblingDB("delivery_nosql_jmg");

print("=== Creando indices (alineados a 50 docs/coleccion) ===\n");

function crearIndice(coleccion, keys, opts) {
  dbx[coleccion].createIndex(keys, opts);
  print(`  ${coleccion}.${opts.name}`);
}

// ------------------------------------------------------------
// pedidos_docs — consultas por region, estado y fecha
// ------------------------------------------------------------
crearIndice("pedidos_docs",
  { region_codigo: 1, fecha_creacion: -1 },
  { name: "idx_pedidos_region_fecha" });

crearIndice("pedidos_docs",
  { region_codigo: 1, estado: 1 },
  { name: "idx_pedidos_region_estado" });

crearIndice("pedidos_docs",
  { region_codigo: 1, id_cliente: 1, fecha_creacion: -1 },
  { name: "idx_pedidos_region_cliente" });

crearIndice("pedidos_docs",
  { region_codigo: 1, id_comercio: 1 },
  { name: "idx_pedidos_region_comercio" });

crearIndice("pedidos_docs",
  { "pago.metodo": 1, "pago.estado": 1 },
  { name: "idx_pedidos_pago_metodo_estado" });

// ------------------------------------------------------------
// productos_ricos — catalogo y busqueda textual
// ------------------------------------------------------------
crearIndice("productos_ricos",
  { region_codigo: 1, id_comercio: 1, disponible: 1 },
  { name: "idx_productos_comercio_disp" });

crearIndice("productos_ricos",
  { nombre: "text", tags: "text" },
  { name: "idx_productos_texto", default_language: "spanish" });

crearIndice("productos_ricos",
  { region_codigo: 1, precio: 1 },
  { name: "idx_productos_region_precio" });

// ------------------------------------------------------------
// perfiles_cliente — login y preferencias
// ------------------------------------------------------------
crearIndice("perfiles_cliente",
  { region_codigo: 1, correo: 1 },
  { unique: true, name: "idx_perfiles_region_correo" });

crearIndice("perfiles_cliente",
  { region_codigo: 1, "preferencias.notificaciones": 1 },
  { name: "idx_perfiles_notif" });

// ------------------------------------------------------------
// comercios / proveedores
// ------------------------------------------------------------
crearIndice("comercios",
  { region_codigo: 1, activo: 1, nombre: 1 },
  { name: "idx_comercios_region_activo" });

crearIndice("comercios",
  { region_codigo: 1, ruc: 1 },
  { unique: true, name: "idx_comercios_region_ruc" });

crearIndice("proveedores",
  { region_codigo: 1, activo: 1 },
  { name: "idx_proveedores_region_activo" });

crearIndice("proveedores",
  { "identidad.ruc": 1 },
  { name: "idx_proveedores_ruc" });

// ------------------------------------------------------------
// repartidores y rutas
// ------------------------------------------------------------
crearIndice("repartidores_tracking",
  { region_codigo: 1, disponible: 1 },
  { name: "idx_repartidor_disponible" });

crearIndice("repartidores_tracking",
  { region_codigo: 1, tipo_vehiculo: 1 },
  { name: "idx_repartidor_vehiculo" });

crearIndice("rutas",
  { region_codigo: 1, id_repartidor: 1, fecha_planificacion: -1 },
  { name: "idx_rutas_repartidor_fecha" });

crearIndice("rutas",
  { region_codigo: 1, estado: 1 },
  { name: "idx_rutas_estado" });

crearIndice("repartidores_estado",
  { region_codigo: 1, id_repartidor: 1 },
  { name: "idx_rep_estado_repartidor" });

// ------------------------------------------------------------
// auditoria, sagas, tracking
// ------------------------------------------------------------
crearIndice("bitacora_eventos",
  { region_codigo: 1, fecha_hora: -1 },
  { name: "idx_bitacora_region_fecha" });

crearIndice("bitacora_eventos",
  { tipo_evento: 1, fecha_hora: -1 },
  { name: "idx_bitacora_tipo" });

crearIndice("saga_eventos",
  { region_codigo: 1, estado: 1 },
  { name: "idx_saga_region_estado" });

crearIndice("saga_eventos",
  { id_pedido: 1 },
  { name: "idx_saga_pedido" });

crearIndice("tracking_pedidos",
  { region_codigo: 1, id_pedido: 1 },
  { unique: true, name: "idx_tracking_pedido" });

// ------------------------------------------------------------
// resenas, promociones, notificaciones
// ------------------------------------------------------------
crearIndice("resenas_producto",
  { region_codigo: 1, id_producto: 1, fecha: -1 },
  { name: "idx_resenas_producto" });

crearIndice("resenas_producto",
  { region_codigo: 1, estrellas: -1 },
  { name: "idx_resenas_estrellas" });

crearIndice("promociones",
  { region_codigo: 1, activa: 1, codigo: 1 },
  { name: "idx_promos_activas" });

crearIndice("notificaciones",
  { region_codigo: 1, id_cliente: 1, leida: 1, ts: -1 },
  { name: "idx_notif_cliente" });

// ------------------------------------------------------------
// inventario, metricas, sesiones, catalogo, nodos, config
// ------------------------------------------------------------
crearIndice("inventario_cache",
  { region_codigo: 1, id_comercio: 1 },
  { unique: true, name: "idx_inventario_comercio" });

crearIndice("metricas_comercio",
  { region_codigo: 1, id_comercio: 1, periodo: 1 },
  { name: "idx_metricas_comercio_periodo" });

crearIndice("sesiones_app",
  { region_codigo: 1, id_usuario: 1, activa: 1 },
  { name: "idx_sesiones_usuario" });

crearIndice("catalogo",
  { tipo_catalogo: 1, activo: 1 },
  { name: "idx_catalogo_tipo" });

crearIndice("metadata_nodos",
  { region_codigo: 1, activo: 1, rol: 1 },
  { name: "idx_nodos_region_rol" });

crearIndice("config_fragmentacion",
  { tabla: 1, activo: 1 },
  { name: "idx_config_tabla" });

// ------------------------------------------------------------
// Resumen
// ------------------------------------------------------------
print("\n=== Listado de indices por coleccion ===");
[
  "pedidos_docs", "productos_ricos", "perfiles_cliente", "comercios",
  "proveedores", "repartidores_tracking", "rutas", "bitacora_eventos",
  "saga_eventos", "tracking_pedidos", "resenas_producto", "promociones",
  "notificaciones", "inventario_cache", "metricas_comercio", "sesiones_app",
  "catalogo", "metadata_nodos", "config_fragmentacion", "repartidores_estado"
].forEach(col => {
  const idxs = dbx[col].getIndexes();
  print(`\n${col} (${idxs.length} indices):`);
  idxs.forEach(ix => print(`  - ${ix.name}`));
});

print("\n=== Indices creados correctamente ===");
