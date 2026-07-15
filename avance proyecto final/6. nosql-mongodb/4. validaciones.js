// =========================================================
// PASO 6.4 — Validaciones JSON Schema (collMod)
// Ejecutar despues de: 1. casos_20_migracion.js (50 docs/coleccion)
//
//   mongosh delivery_nosql < "6. nosql-mongodb/4. validaciones.js"
// =========================================================

const dbx = db.getSiblingDB("delivery_nosql_jmg");

print("=== Aplicando validadores JSON Schema ===\n");

function aplicarValidador(coleccion, schema, nivel) {
  dbx.runCommand({
    collMod: coleccion,
    validator: { $jsonSchema: schema },
    validationLevel: nivel || "moderate",
    validationAction: "error"
  });
  print(`  Validacion aplicada: ${coleccion} (${nivel || "moderate"})`);
}

// ------------------------------------------------------------
// V1 — pedidos_docs
// ------------------------------------------------------------
aplicarValidador("pedidos_docs", {
  bsonType: "object",
  required: ["region_codigo", "id_pedido", "estado", "total", "detalle"],
  properties: {
    region_codigo: {
      bsonType: "string",
      enum: ["LIM-N", "LIM-S", "AQP"],
      description: "Clave de fragmentacion"
    },
    id_pedido: { bsonType: "string" },
    estado: {
      enum: ["CREADO", "CONFIRMADO", "EN_CAMINO", "ENTREGADO", "CANCELADO"]
    },
    total: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
    subtotal: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
    costo_envio: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
    detalle: {
      bsonType: "array",
      minItems: 1,
      items: {
        bsonType: "object",
        required: ["nombre", "cantidad", "importe"],
        properties: {
          nombre: { bsonType: "string" },
          cantidad: { bsonType: ["double", "int", "long", "decimal"], minimum: 1 },
          precio_unitario: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
          importe: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 }
        }
      }
    },
    pago: {
      bsonType: "object",
      properties: {
        metodo: { enum: ["EFECTIVO", "TARJETA", "YAPE", "PLIN", "TRANSFERENCIA"] },
        estado: { enum: ["PENDIENTE", "PAGADO", "RECHAZADO", "DEVUELTO"] },
        monto: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 }
      }
    }
  }
}, "moderate");

// ------------------------------------------------------------
// V2 — productos_ricos
// ------------------------------------------------------------
aplicarValidador("productos_ricos", {
  bsonType: "object",
  required: ["region_codigo", "id_producto", "nombre", "precio"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    id_producto: { bsonType: "string" },
    id_comercio: { bsonType: "string" },
    nombre: { bsonType: "string", minLength: 2 },
    precio: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
    disponible: { bsonType: "bool" },
    alergenos: { bsonType: "array", items: { bsonType: "string" } },
    tags: { bsonType: "array", items: { bsonType: "string" } }
  }
}, "strict");

// ------------------------------------------------------------
// V3 — perfiles_cliente
// ------------------------------------------------------------
aplicarValidador("perfiles_cliente", {
  bsonType: "object",
  required: ["region_codigo", "id_cliente", "correo"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    id_cliente: { bsonType: "string" },
    correo: { bsonType: "string", pattern: "^.+@.+$" },
    rol: { enum: ["CLIENTE", "REPARTIDOR", "ADMINISTRADOR"] },
    preferencias: {
      bsonType: "object",
      properties: {
        idioma: { bsonType: "string" },
        notificaciones: { enum: ["TODAS", "SOLO_PEDIDOS", "NINGUNA"] },
        acepta_publicidad: { bsonType: "bool" }
      }
    },
    direcciones: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["direccion"],
        properties: {
          direccion: { bsonType: "string" },
          principal: { bsonType: "bool" }
        }
      }
    }
  }
}, "moderate");

// ------------------------------------------------------------
// V4 — comercios
// ------------------------------------------------------------
aplicarValidador("comercios", {
  bsonType: "object",
  required: ["region_codigo", "id_comercio", "nombre"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    id_comercio: { bsonType: "string" },
    nombre: { bsonType: "string", minLength: 2 },
    ruc: { bsonType: "string" },
    activo: { bsonType: "bool" },
    categorias: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["nombre"],
        properties: {
          id_categoria: { bsonType: "string" },
          nombre: { bsonType: "string" }
        }
      }
    }
  }
}, "moderate");

// ------------------------------------------------------------
// V5 — repartidores_tracking
// ------------------------------------------------------------
aplicarValidador("repartidores_tracking", {
  bsonType: "object",
  required: ["region_codigo", "id_repartidor", "disponible", "tipo_vehiculo"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    id_repartidor: { bsonType: "string" },
    disponible: { bsonType: "bool" },
    tipo_vehiculo: { enum: ["MOTO", "BICI", "AUTO"] },
    placa: { bsonType: "string" },
    ubicacion_actual: {
      bsonType: "object",
      properties: {
        lat: { bsonType: ["double", "int", "long", "decimal"] },
        lng: { bsonType: ["double", "int", "long", "decimal"] }
      }
    }
  }
}, "moderate");

// ------------------------------------------------------------
// V6 — resenas_producto
// ------------------------------------------------------------
aplicarValidador("resenas_producto", {
  bsonType: "object",
  required: ["region_codigo", "id_producto", "id_cliente", "estrellas"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    id_producto: { bsonType: "string" },
    id_cliente: { bsonType: "string" },
    estrellas: { bsonType: ["double", "int", "long", "decimal"], minimum: 1, maximum: 5 },
    comentario: { bsonType: "string" },
    fotos: { bsonType: "array", items: { bsonType: "string" } }
  }
}, "strict");

// ------------------------------------------------------------
// V7 — promociones
// ------------------------------------------------------------
aplicarValidador("promociones", {
  bsonType: "object",
  required: ["region_codigo", "codigo", "tipo", "valor", "activa"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    codigo: { bsonType: "string", minLength: 3 },
    tipo: { enum: ["porcentaje", "monto_fijo"] },
    valor: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
    activa: { bsonType: "bool" }
  }
}, "moderate");

// ------------------------------------------------------------
// V8 — saga_eventos
// ------------------------------------------------------------
aplicarValidador("saga_eventos", {
  bsonType: "object",
  required: ["id_saga", "tipo_operacion", "region_codigo", "estado", "pasos"],
  properties: {
    id_saga: { bsonType: "string" },
    tipo_operacion: { bsonType: "string" },
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    estado: { enum: ["INICIADA", "COMPLETADA", "COMPENSANDO", "FALLIDA"] },
    pasos: {
      bsonType: "array",
      minItems: 1,
      items: {
        bsonType: "object",
        required: ["orden", "nombre", "estado"],
        properties: {
          orden: { bsonType: ["double", "int", "long", "decimal"], minimum: 1 },
          nombre: { bsonType: "string" },
          estado: { enum: ["PENDIENTE", "OK", "ERROR", "COMPENSADO"] }
        }
      }
    }
  }
}, "moderate");

// ------------------------------------------------------------
// V9 — notificaciones
// ------------------------------------------------------------
aplicarValidador("notificaciones", {
  bsonType: "object",
  required: ["region_codigo", "id_cliente", "canal", "titulo", "leida"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    id_cliente: { bsonType: "string" },
    canal: { enum: ["push", "email", "sms"] },
    titulo: { bsonType: "string", minLength: 2 },
    leida: { bsonType: "bool" }
  }
}, "moderate");

// ------------------------------------------------------------
// V10 — sesiones_app
// ------------------------------------------------------------
aplicarValidador("sesiones_app", {
  bsonType: "object",
  required: ["region_codigo", "id_usuario", "dispositivo", "activa"],
  properties: {
    region_codigo: { bsonType: "string", enum: ["LIM-N", "LIM-S", "AQP"] },
    id_usuario: { bsonType: "string" },
    dispositivo: { enum: ["android", "ios", "web"] },
    token_fcm: { bsonType: "string" },
    activa: { bsonType: "bool" }
  }
}, "moderate");

// ------------------------------------------------------------
// Pruebas de rechazo / aceptacion
// ------------------------------------------------------------
print("\n=== Prueba 1: pedido invalido (debe fallar) ===");
try {
  dbx.pedidos_docs.insertOne({
    region_codigo: "LIM-N",
    id_pedido: "invalido-test",
    estado: "ESTADO_INVENTADO",
    total: -10,
    detalle: []
  });
  print("ERROR: debio rechazar el documento");
} catch (e) {
  print("OK — validacion rechazo documento invalido");
  print("  " + String(e.message).split("\n")[0]);
}

print("\n=== Prueba 2: resena con estrellas fuera de rango (debe fallar) ===");
try {
  dbx.resenas_producto.insertOne({
    region_codigo: "LIM-N",
    id_producto: "prod-x",
    id_cliente: "cli-x",
    estrellas: 9,
    comentario: "invalido"
  });
  print("ERROR: debio rechazar estrellas > 5");
} catch (e) {
  print("OK — rechazo estrellas fuera de rango");
  print("  " + String(e.message).split("\n")[0]);
}

print("\n=== Prueba 3: pedido valido (debe insertar) ===");
const r = dbx.pedidos_docs.insertOne({
  region_codigo: "LIM-N",
  id_pedido: "valido-test-001",
  id_cliente: "00000003-0001-4001-8001-000000000001",
  id_comercio: "00000005-0001-4001-8001-000000000001",
  nombre_cliente: "Cliente Prueba",
  nombre_comercio: "Polleria Norte",
  estado: "CREADO",
  subtotal: 20.00,
  costo_envio: 5.00,
  total: 25.00,
  detalle: [{
    id_producto: "00000008-0001-4001-8001-000000000001",
    nombre: "Menu prueba",
    cantidad: 1,
    precio_unitario: 20.00,
    importe: 20.00
  }],
  pago: { metodo: "YAPE", estado: "PENDIENTE", monto: 25.00, fecha_pago: null },
  fecha_creacion: new Date()
});
print("Insertado _id: " + r.insertedId);

dbx.pedidos_docs.deleteOne({ id_pedido: "valido-test-001" });
print("Documento de prueba eliminado (coleccion vuelve a 50 docs).");

print("\n=== Conteo post-validacion (objetivo 50) ===");
[
  "pedidos_docs", "productos_ricos", "perfiles_cliente", "comercios",
  "repartidores_tracking", "resenas_producto", "promociones",
  "saga_eventos", "notificaciones", "sesiones_app"
].forEach(col => {
  const n = dbx[col].countDocuments();
  print(`  ${col}: ${n} docs ${n === 50 ? "[OK]" : "[REVISAR]"}`);
});

print("\n=== Validaciones completadas ===");
