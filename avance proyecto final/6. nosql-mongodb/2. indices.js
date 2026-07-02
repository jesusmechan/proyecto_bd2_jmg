// =========================================================
// PASO 6.2 — Indices MongoDB
// Ejecutar despues de: 1. casos_20_migracion.js
//
//   mongosh delivery_nosql < "6. nosql-mongodb/2. indices.js"
// =========================================================

const dbx = db.getSiblingDB("delivery_nosql");

print("=== Creando indices ===\n");

// Busqueda de pedidos por region y fecha
dbx.pedidos_docs.createIndex(
  { region_codigo: 1, fecha_creacion: -1 },
  { name: "idx_pedidos_region_fecha" }
);
print("idx_pedidos_region_fecha");

// Pedidos por estado (dashboard)
dbx.pedidos_docs.createIndex(
  { region_codigo: 1, estado: 1 },
  { name: "idx_pedidos_region_estado" }
);
print("idx_pedidos_region_estado");

// Productos por comercio y disponibilidad
dbx.productos_ricos.createIndex(
  { region_codigo: 1, id_comercio: 1, disponible: 1 },
  { name: "idx_productos_comercio_disp" }
);
print("idx_productos_comercio_disp");

// Texto en nombre de producto (busqueda)
dbx.productos_ricos.createIndex(
  { nombre: "text", tags: "text" },
  { name: "idx_productos_texto" }
);
print("idx_productos_texto");

// Bitacora por region y fecha (append-only)
dbx.bitacora_eventos.createIndex(
  { region_codigo: 1, fecha_hora: -1 },
  { name: "idx_bitacora_region_fecha" }
);
print("idx_bitacora_region_fecha");

// Perfiles por correo (login)
dbx.perfiles_cliente.createIndex(
  { region_codigo: 1, correo: 1 },
  { unique: true, name: "idx_perfiles_region_correo" }
);
print("idx_perfiles_region_correo (unico)");

// Tracking repartidor disponible
dbx.repartidores_tracking.createIndex(
  { region_codigo: 1, disponible: 1 },
  { name: "idx_repartidor_disponible" }
);
print("idx_repartidor_disponible");

// Resenas por producto
dbx.resenas_producto.createIndex(
  { region_codigo: 1, id_producto: 1, fecha: -1 },
  { name: "idx_resenas_producto" }
);
print("idx_resenas_producto");

print("\n=== Listado de indices por coleccion ===");
[
  "pedidos_docs", "productos_ricos", "bitacora_eventos",
  "perfiles_cliente", "repartidores_tracking", "resenas_producto"
].forEach(col => {
  print("\n" + col + ":");
  printjson(dbx[col].getIndexes());
});
