// =========================================================
// PASO 6.3 — Agregaciones MongoDB (resultado EN LA MISMA coleccion)
// Ejecutar despues de: 1. casos_20_migracion.js (50 docs/coleccion)
//
// Cada pipeline termina con $merge hacia la coleccion de origen.
// Los resultados se distinguen con:
//   _tipo: "AGREGACION"
//   _agregacion: "A1_ventas_comercio"  (nombre del reporte)
//
// Asi no se crean colecciones nuevas (agg_*).
//
// Consultar solo resúmenes:
//   db.pedidos_docs.find({ _tipo: "AGREGACION" })
// Consultar solo datos operativos:
//   db.pedidos_docs.find({ _tipo: { $ne: "AGREGACION" } })
//
//   mongosh delivery_nosql_jmg < "6. nosql-mongodb/3. agregaciones.js"
// =========================================================

const dbx = db.getSiblingDB("delivery_nosql_jmg");

print("=== Agregaciones con $merge (misma coleccion de origen) ===\n");
print("Los documentos de resultado llevan _tipo: 'AGREGACION'\n");

// Limpia resúmenes previos de una agregacion concreta (evita basura entre corridas)
function limpiarAgregacion(coleccion, nombreAgg) {
  dbx[coleccion].deleteMany({ _tipo: "AGREGACION", _agregacion: nombreAgg });
}

// Corre pipeline + merge en la misma coleccion
function agregarEnMismaColeccion(coleccion, etapas, nombreAgg, etiqueta) {
  print(`=== ${etiqueta} → ${coleccion} (_agregacion=${nombreAgg}) ===\n`);

  limpiarAgregacion(coleccion, nombreAgg);

  dbx[coleccion].aggregate([
    ...etapas,
    {
      $set: {
        _tipo: "AGREGACION",
        _agregacion: nombreAgg,
        generado_en: "$$NOW"
      }
    },
    {
      // Escribe en la MISMA coleccion
      $merge: {
        into: coleccion,
        on: "_id",
        whenMatched: "replace",
        whenNotMatched: "insert"
      }
    }
  ]);

  const n = dbx[coleccion].countDocuments({ _tipo: "AGREGACION", _agregacion: nombreAgg });
  const total = dbx[coleccion].countDocuments();
  print(`  Guardados: ${n} resúmenes en '${coleccion}'`);
  print(`  Total actual de la coleccion: ${total} docs`);
  print("  Preview:");
  printjson(
    dbx[coleccion].find({ _tipo: "AGREGACION", _agregacion: nombreAgg }).limit(5).toArray()
  );
  print("");
  return n;
}

// ------------------------------------------------------------
// A1 — Ventas por comercio  → pedidos_docs
// ------------------------------------------------------------
agregarEnMismaColeccion("pedidos_docs", [
  { $match: { _tipo: { $ne: "AGREGACION" }, estado: "ENTREGADO" } },
  { $group: {
      _id: { region: "$region_codigo", comercio: "$nombre_comercio" },
      total_pedidos: { $sum: 1 },
      monto_total: { $sum: "$total" },
      ticket_promedio: { $avg: "$total" }
  }},
  { $project: {
      _id: { $concat: ["agg:A1:", "$_id.region", ":", "$_id.comercio"] },
      region: "$_id.region",
      comercio: "$_id.comercio",
      total_pedidos: 1,
      monto_total: { $round: ["$monto_total", 2] },
      ticket_promedio: { $round: ["$ticket_promedio", 2] }
  }}
], "A1_ventas_comercio", "A1 — Ventas por comercio");

// ------------------------------------------------------------
// A2 — Productos mas vendidos → pedidos_docs
// ------------------------------------------------------------
agregarEnMismaColeccion("pedidos_docs", [
  { $match: { _tipo: { $ne: "AGREGACION" }, estado: { $in: ["ENTREGADO", "EN_CAMINO"] } } },
  { $unwind: "$detalle" },
  { $group: {
      _id: { region: "$region_codigo", producto: "$detalle.nombre" },
      unidades: { $sum: "$detalle.cantidad" },
      ingresos: { $sum: "$detalle.importe" }
  }},
  { $project: {
      _id: { $concat: ["agg:A2:", "$_id.region", ":", "$_id.producto"] },
      region: "$_id.region",
      producto: "$_id.producto",
      unidades: 1,
      ingresos: { $round: ["$ingresos", 2] }
  }}
], "A2_productos_vendidos", "A2 — Productos mas vendidos");

// ------------------------------------------------------------
// A3 — Embudo de estados → pedidos_docs
// ------------------------------------------------------------
agregarEnMismaColeccion("pedidos_docs", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $group: {
      _id: { region: "$region_codigo", estado: "$estado" },
      cantidad: { $sum: 1 }
  }},
  { $group: {
      _id: "$_id.region",
      estados: { $push: { estado: "$_id.estado", cantidad: "$cantidad" } },
      total_region: { $sum: "$cantidad" }
  }},
  { $unwind: "$estados" },
  { $project: {
      _id: { $concat: ["agg:A3:", "$_id", ":", "$estados.estado"] },
      region: "$_id",
      estado: "$estados.estado",
      cantidad: "$estados.cantidad",
      total_region: 1,
      porcentaje: {
        $round: [{ $multiply: [{ $divide: ["$estados.cantidad", "$total_region"] }, 100] }, 2]
      }
  }}
], "A3_embudo_estados", "A3 — Embudo de estados");

// ------------------------------------------------------------
// A4 — Bitacora por tipo → bitacora_eventos
// ------------------------------------------------------------
agregarEnMismaColeccion("bitacora_eventos", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $group: {
      _id: { region: "$region_codigo", tipo: "$tipo_evento" },
      total: { $sum: 1 }
  }},
  { $project: {
      _id: { $concat: ["agg:A4:", { $ifNull: ["$_id.region", "NULL"] }, ":", "$_id.tipo"] },
      region: "$_id.region",
      tipo_evento: "$_id.tipo",
      total: 1
  }}
], "A4_bitacora_tipos", "A4 — Bitacora por tipo");

// ------------------------------------------------------------
// A5 — Disponibilidad repartidores → repartidores_tracking
// ------------------------------------------------------------
agregarEnMismaColeccion("repartidores_tracking", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $group: {
      _id: "$region_codigo",
      libres: { $sum: { $cond: ["$disponible", 1, 0] } },
      ocupados: { $sum: { $cond: ["$disponible", 0, 1] } },
      total: { $sum: 1 }
  }},
  { $project: {
      _id: { $concat: ["agg:A5:", "$_id"] },
      region: "$_id",
      libres: 1,
      ocupados: 1,
      total: 1,
      pct_libres: {
        $round: [{ $multiply: [{ $divide: ["$libres", "$total"] }, 100] }, 2]
      }
  }}
], "A5_disponibilidad", "A5 — Repartidores libres vs ocupados");

// ------------------------------------------------------------
// A6 — Promedio estrellas → resenas_producto
// ------------------------------------------------------------
agregarEnMismaColeccion("resenas_producto", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $group: {
      _id: { region: "$region_codigo", id_producto: "$id_producto" },
      promedio_estrellas: { $avg: "$estrellas" },
      total_resenas: { $sum: 1 }
  }},
  { $project: {
      _id: { $concat: ["agg:A6:", "$_id.region", ":", "$_id.id_producto"] },
      region: "$_id.region",
      id_producto: "$_id.id_producto",
      promedio_estrellas: { $round: ["$promedio_estrellas", 2] },
      total_resenas: 1
  }}
], "A6_promedio_estrellas", "A6 — Promedio de estrellas");

// ------------------------------------------------------------
// A7 — Pagos digitales → pedidos_docs
// ------------------------------------------------------------
agregarEnMismaColeccion("pedidos_docs", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $group: {
      _id: "$region_codigo",
      total: { $sum: 1 },
      digitales: {
        $sum: {
          $cond: [
            { $and: [
              { $in: ["$pago.metodo", ["YAPE", "PLIN", "TARJETA", "TRANSFERENCIA"]] },
              { $eq: ["$pago.estado", "PAGADO"] }
            ]},
            1, 0
          ]
        }
      },
      efectivo: {
        $sum: { $cond: [{ $eq: ["$pago.metodo", "EFECTIVO"] }, 1, 0] }
      },
      monto_pagado: {
        $sum: {
          $cond: [{ $eq: ["$pago.estado", "PAGADO"] }, "$pago.monto", 0]
        }
      }
  }},
  { $project: {
      _id: { $concat: ["agg:A7:", "$_id"] },
      region: "$_id",
      total: 1,
      digitales: 1,
      efectivo: 1,
      pct_digital: {
        $round: [{ $multiply: [{ $divide: ["$digitales", "$total"] }, 100] }, 2]
      },
      monto_pagado: { $round: ["$monto_pagado", 2] }
  }}
], "A7_pagos_digitales", "A7 — Pagos digitales");

// ------------------------------------------------------------
// A8 — Estado sagas → saga_eventos
// ------------------------------------------------------------
agregarEnMismaColeccion("saga_eventos", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $group: {
      _id: { region: "$region_codigo", estado: "$estado" },
      cantidad: { $sum: 1 }
  }},
  { $project: {
      _id: { $concat: ["agg:A8:", "$_id.region", ":", "$_id.estado"] },
      region: "$_id.region",
      estado_saga: "$_id.estado",
      cantidad: 1
  }}
], "A8_sagas_estado", "A8 — Estado de sagas");

// ------------------------------------------------------------
// A9 — Top comercios → metricas_comercio
// ------------------------------------------------------------
agregarEnMismaColeccion("metricas_comercio", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $group: {
      _id: { region: "$region_codigo", comercio: "$id_comercio" },
      pedidos: { $sum: "$pedidos_total" },
      monto: { $sum: "$monto_total" },
      ticket_prom: { $avg: "$ticket_promedio" }
  }},
  { $project: {
      _id: { $concat: ["agg:A9:", "$_id.region", ":", "$_id.comercio"] },
      region: "$_id.region",
      id_comercio: "$_id.comercio",
      pedidos: 1,
      monto: { $round: ["$monto", 2] },
      ticket_prom: { $round: ["$ticket_prom", 2] }
  }}
], "A9_top_comercios", "A9 — Top comercios");

// ------------------------------------------------------------
// A10 — Notif pendientes → notificaciones
// ------------------------------------------------------------
agregarEnMismaColeccion("notificaciones", [
  { $match: { _tipo: { $ne: "AGREGACION" }, leida: false } },
  { $group: {
      _id: { region: "$region_codigo", canal: "$canal" },
      pendientes: { $sum: 1 }
  }},
  { $project: {
      _id: { $concat: ["agg:A10:", "$_id.region", ":", "$_id.canal"] },
      region: "$_id.region",
      canal: "$_id.canal",
      pendientes: 1
  }}
], "A10_notif_pendientes", "A10 — Notificaciones no leidas");

// ------------------------------------------------------------
// A11 — Stock bajo → inventario_cache
// ------------------------------------------------------------
agregarEnMismaColeccion("inventario_cache", [
  { $match: { _tipo: { $ne: "AGREGACION" } } },
  { $unwind: "$items" },
  { $match: { "items.stock": { $lt: 10 } } },
  { $group: {
      _id: "$region_codigo",
      items_bajo_stock: { $sum: 1 },
      stock_promedio: { $avg: "$items.stock" }
  }},
  { $project: {
      _id: { $concat: ["agg:A11:", "$_id"] },
      region: "$_id",
      items_bajo_stock: 1,
      stock_promedio: { $round: ["$stock_promedio", 2] }
  }}
], "A11_stock_bajo", "A11 — Stock bajo");

// ------------------------------------------------------------
// A12 — Conteo operativo (sin resúmenes) → catalogo
// ------------------------------------------------------------
print("=== A12 — Conteo operativo por coleccion → catalogo ===\n");
limpiarAgregacion("catalogo", "A12_conteo_colecciones");

const colecciones = [
  "perfiles_cliente", "catalogo", "comercios", "productos_ricos", "pedidos_docs",
  "repartidores_tracking", "rutas", "bitacora_eventos", "saga_eventos",
  "metadata_nodos", "proveedores", "config_fragmentacion", "tracking_pedidos",
  "resenas_producto", "repartidores_estado", "promociones", "notificaciones",
  "inventario_cache", "metricas_comercio", "sesiones_app"
];

const conteos = colecciones.map(col => ({
  _id: `agg:A12:${col}`,
  _tipo: "AGREGACION",
  _agregacion: "A12_conteo_colecciones",
  coleccion: col,
  docs_operativos: dbx[col].countDocuments({ _tipo: { $ne: "AGREGACION" } }),
  docs_agregacion: dbx[col].countDocuments({ _tipo: "AGREGACION" }),
  docs_total: dbx[col].countDocuments(),
  generado_en: new Date()
}));
dbx.catalogo.insertMany(conteos);
printjson(dbx.catalogo.find({ _agregacion: "A12_conteo_colecciones" }).toArray());

// ------------------------------------------------------------
// Resumen
// ------------------------------------------------------------
print("\n=== RESUMEN: agregaciones dentro de colecciones origen ===");
[
  ["pedidos_docs", "A1_ventas_comercio"],
  ["pedidos_docs", "A2_productos_vendidos"],
  ["pedidos_docs", "A3_embudo_estados"],
  ["pedidos_docs", "A7_pagos_digitales"],
  ["bitacora_eventos", "A4_bitacora_tipos"],
  ["repartidores_tracking", "A5_disponibilidad"],
  ["resenas_producto", "A6_promedio_estrellas"],
  ["saga_eventos", "A8_sagas_estado"],
  ["metricas_comercio", "A9_top_comercios"],
  ["notificaciones", "A10_notif_pendientes"],
  ["inventario_cache", "A11_stock_bajo"],
  ["catalogo", "A12_conteo_colecciones"]
].forEach(([col, agg]) => {
  const n = dbx[col].countDocuments({ _tipo: "AGREGACION", _agregacion: agg });
  print(`  ${col} / ${agg}: ${n} docs`);
});

print("\nConsultas utiles:");
print('  db.pedidos_docs.find({ _tipo: "AGREGACION" })');
print('  db.pedidos_docs.find({ _tipo: { $ne: "AGREGACION" } })  // solo operativos');
print("\n=== Agregaciones completadas (misma coleccion) ===");
