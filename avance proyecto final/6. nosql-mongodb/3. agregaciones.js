// =========================================================
// PASO 6.3 — Agregaciones MongoDB
// Ejecutar despues de: 1. casos_20_migracion.js
//
//   mongosh delivery_nosql < "6. nosql-mongodb/3. agregaciones.js"
// =========================================================

const dbx = db.getSiblingDB("delivery_nosql");

print("=== A1 — Ventas por comercio (region LIM-N) ===\n");
printjson(dbx.pedidos_docs.aggregate([
  { $match: { region_codigo: "LIM-N", estado: "ENTREGADO" } },
  { $group: {
      _id: "$nombre_comercio",
      total_pedidos: { $sum: 1 },
      monto_total: { $sum: "$total" },
      ticket_promedio: { $avg: "$total" }
  }},
  { $sort: { monto_total: -1 } }
]).toArray());

print("\n=== A2 — Productos mas vendidos (unwind detalle) ===\n");
printjson(dbx.pedidos_docs.aggregate([
  { $match: { region_codigo: "LIM-N" } },
  { $unwind: "$detalle" },
  { $group: {
      _id: "$detalle.nombre",
      unidades: { $sum: "$detalle.cantidad" },
      ingresos: { $sum: "$detalle.importe" }
  }},
  { $sort: { unidades: -1 } },
  { $limit: 5 }
]).toArray());

print("\n=== A3 — Eventos de bitacora por tipo ===\n");
printjson(dbx.bitacora_eventos.aggregate([
  { $group: { _id: "$tipo_evento", total: { $sum: 1 } } },
  { $sort: { total: -1 } }
]).toArray());

print("\n=== A4 — Repartidores: disponibles vs ocupados por region ===\n");
printjson(dbx.repartidores_tracking.aggregate([
  { $group: {
      _id: { region: "$region_codigo", disponible: "$disponible" },
      cantidad: { $sum: 1 }
  }},
  { $sort: { "_id.region": 1 } }
]).toArray());

print("\n=== A5 — Promedio de estrellas por producto ===\n");
printjson(dbx.resenas_producto.aggregate([
  { $group: {
      _id: "$id_producto",
      promedio_estrellas: { $avg: "$estrellas" },
      total_resenas: { $sum: 1 }
  }},
  { $sort: { promedio_estrellas: -1 } }
]).toArray());

print("\n=== Agregaciones completadas ===");
