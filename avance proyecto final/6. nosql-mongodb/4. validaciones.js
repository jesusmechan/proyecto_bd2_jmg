// =========================================================
// PASO 6.4 — Validaciones JSON Schema (collMod)
// Ejecutar despues de: 1. casos_20_migracion.js
//
//   mongosh delivery_nosql < "6. nosql-mongodb/4. validaciones.js"
// =========================================================

const dbx = db.getSiblingDB("delivery_nosql");

print("=== Aplicando validadores JSON Schema ===\n");

// V1 — pedidos_docs: campos obligatorios y tipos
dbx.runCommand({
  collMod: "pedidos_docs",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["region_codigo", "id_pedido", "estado", "total", "detalle"],
      properties: {
        region_codigo: { bsonType: "string", description: "Clave de fragmentacion" },
        id_pedido: { bsonType: "string" },
        estado: {
          enum: ["CREADO", "CONFIRMADO", "EN_CAMINO", "ENTREGADO", "CANCELADO"],
          description: "Estado del pedido"
        },
        total: { bsonType: ["double", "int", "decimal"], minimum: 0 },
        detalle: {
          bsonType: "array",
          minItems: 0,
          items: {
            bsonType: "object",
            required: ["nombre", "cantidad", "importe"],
            properties: {
              nombre: { bsonType: "string" },
              cantidad: { bsonType: "int", minimum: 1 },
              importe: { bsonType: ["double", "int", "decimal"], minimum: 0 }
            }
          }
        },
        pago: {
          bsonType: "object",
          properties: {
            metodo: { enum: ["EFECTIVO", "TARJETA", "YAPE", "PLIN", "TRANSFERENCIA"] },
            estado: { enum: ["PENDIENTE", "PAGADO", "RECHAZADO", "DEVUELTO"] }
          }
        }
      }
    }
  },
  validationLevel: "moderate",
  validationAction: "error"
});
print("Validacion aplicada: pedidos_docs");

// V2 — productos_ricos: precio positivo, nombre requerido
dbx.runCommand({
  collMod: "productos_ricos",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["region_codigo", "id_producto", "nombre", "precio"],
      properties: {
        region_codigo: { bsonType: "string" },
        id_producto: { bsonType: "string" },
        nombre: { bsonType: "string", minLength: 2 },
        precio: { bsonType: ["double", "int", "decimal"], minimum: 0 },
        disponible: { bsonType: "bool" },
        alergenos: { bsonType: "array", items: { bsonType: "string" } }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});
print("Validacion aplicada: productos_ricos");

// V3 — perfiles_cliente: correo y estructura de direcciones
dbx.runCommand({
  collMod: "perfiles_cliente",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["region_codigo", "id_cliente", "correo"],
      properties: {
        region_codigo: { bsonType: "string" },
        id_cliente: { bsonType: "string" },
        correo: { bsonType: "string", pattern: "^.+@.+\\..+$" },
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
    }
  },
  validationLevel: "moderate",
  validationAction: "error"
});
print("Validacion aplicada: perfiles_cliente");

print("\n=== Prueba: documento invalido (debe fallar) ===");
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
  print("OK — validacion rechazo documento invalido:");
  print(e.message);
}

print("\n=== Prueba: documento valido (debe insertar) ===");
const r = dbx.pedidos_docs.insertOne({
  region_codigo: "LIM-N",
  id_pedido: "valido-test-001",
  id_comercio: "00000005-0001-4001-8001-000000000001",
  nombre_comercio: "Polleria Norte",
  estado: "CREADO",
  total: 25.00,
  detalle: [{ nombre: "Menu prueba", cantidad: 1, importe: 25.00 }],
  fecha_creacion: new Date()
});
print("Insertado _id: " + r.insertedId);

// Limpiar documento de prueba
dbx.pedidos_docs.deleteOne({ id_pedido: "valido-test-001" });
print("Documento de prueba eliminado.");

print("\n=== Validaciones completadas ===");
