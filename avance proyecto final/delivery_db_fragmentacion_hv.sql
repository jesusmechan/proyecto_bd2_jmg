-- =========================================================
-- Fragmentación HORIZONTAL y VERTICAL — delivery_db
-- Script de ejemplo (independiente del DDL principal)
--
-- Relacionado con: delivery_db_distribuida.sql
--
-- Ejecución sugerida:
--   psql -U postgres -c "CREATE DATABASE delivery_db_fragmentacion_hv;"
--   psql -U postgres -d delivery_db_fragmentacion_hv -f delivery_db_fragmentacion_hv.sql
--
-- Este script NO modifica delivery_db_distribuida.sql.
-- Demuestra criterios, tablas candidatas y fragmentos con vistas de reconstrucción.
-- =========================================================

CREATE SCHEMA IF NOT EXISTS frag;
SET search_path TO frag, public;

-- =========================================================
-- 1. MATRIZ DE DECISIÓN — ¿Horizontal, vertical o réplica?
-- =========================================================
--
-- HORIZONTAL (por filas):
--   • Partir datos según una clave de distribución (region_codigo, fecha, etc.).
--   • Cada fragmento vive en un nodo distinto o en una partición local.
--
-- VERTICAL (por columnas):
--   • Partir una tabla ancha en fragmentos con distinto patrón de acceso.
--   • Misma PK en todos los fragmentos; se reconstruye con JOIN o vista.
--
-- RÉPLICA (sin fragmentar):
--   • Copia idéntica en todos los nodos; lectura frecuente, escritura rara.
--
-- Tablas del modelo delivery_db_distribuida:
--
-- | Tabla              | Horizontal (filas)              | Vertical (columnas)     | Notas                          |
-- |--------------------|---------------------------------|-------------------------|--------------------------------|
-- | catalogo_maestro   | NO — réplica global             | NO                      | Solo lectura; pocos KB         |
-- | nodo_registro      | NO — réplica / catálogo nodos   | NO                      | Metadatos de topología         |
-- | regla_fragmentacion| NO — réplica                    | NO                      | Documentación                  |
-- | persona            | SÍ — region_codigo              | SÍ — identidad/contacto | Muy consultada en login        |
-- | usuario            | SÍ — region_codigo              | SÍ — cuenta/seguridad     | Auth vs perfil                 |
-- | cliente            | SÍ — region_codigo              | OPCIONAL — prefs/notas  | Tabla ya estrecha              |
-- | repartidor         | SÍ — region_codigo              | NO (opcional vehículo)  | Co-ubicar con persona          |
-- | comercio           | SÍ — region_codigo              | SÍ — básico/contacto    | Menú vs datos fiscales         |
-- | proveedor          | SÍ — region_codigo              | NO                      | Depende de persona             |
-- | comercio_proveedor | SÍ — region_codigo              | NO                      | Puente; pocos atributos        |
-- | categoria_producto | SÍ — region_codigo              | NO                      | Sigue a comercio               |
-- | producto           | SÍ — region_codigo              | SÍ — catálogo/precio    | Menú (lectura) vs precio (hot) |
-- | pedido             | SÍ — region + sub-part. fecha   | SÍ — núcleo/entrega/$   | Tabla más caliente             |
-- | detalle_pedido     | SÍ — misma regla que pedido     | NO                      | Ya desnormalizada              |
-- | pago               | SÍ — region_codigo              | NO                      | 1:1 con pedido                 |
-- | ruta_reparto       | SÍ — region_codigo              | NO                      | Operación reparto              |
-- | parada_ruta        | SÍ — region_codigo              | NO                      | Sigue a ruta                   |
-- | bitacora_evento    | SÍ — fecha_hora (partición)     | SÍ — evento/payload     | Append-only masivo             |
-- | saga_transaccion   | SÍ — region_codigo              | NO                      | Pocos campos                   |
-- | saga_paso          | NO horizontal propia            | NO                      | Sigue a saga (FK id_saga)      |
--
-- =========================================================

CREATE TABLE matriz_fragmentacion (
  id              SERIAL PRIMARY KEY,
  tabla_logica    VARCHAR(64) NOT NULL UNIQUE,
  estrategia      VARCHAR(20) NOT NULL CHECK (estrategia IN ('REPLICA','HORIZONTAL','VERTICAL','HORIZONTAL+VERTICAL')),
  clave_horizontal VARCHAR(80),
  fragmentos_verticales TEXT,
  criterio        TEXT NOT NULL,
  nodo_ejemplo    VARCHAR(10)
);

INSERT INTO matriz_fragmentacion (tabla_logica, estrategia, clave_horizontal, fragmentos_verticales, criterio, nodo_ejemplo) VALUES
  ('catalogo_maestro',   'REPLICA',              NULL, NULL,
   'Catálogo pequeño; réplica completa en GLOBAL y cada nodo regional.', 'GLOBAL'),
  ('nodo_registro',      'REPLICA',              NULL, NULL,
   'Topología del cluster; una copia accesible desde orquestador.', 'GLOBAL'),
  ('persona',            'HORIZONTAL+VERTICAL',  'region_codigo',
   'fv_persona_identidad | fv_persona_contacto',
   'Horizontal: residencia/operción por región. Vertical: login usa identidad; CRM usa contacto.', 'LIM-N'),
  ('usuario',            'HORIZONTAL+VERTICAL',  'region_codigo',
   'fv_usuario_cuenta | fv_usuario_seguridad',
   'Horizontal: co-ubicado con persona. Vertical: auth lee solo seguridad; listados leen cuenta.', 'LIM-N'),
  ('cliente',            'HORIZONTAL',           'region_codigo', NULL,
   'Perfil comprador en el mismo nodo que usuario.', 'LIM-N'),
  ('repartidor',         'HORIZONTAL',           'region_codigo', NULL,
   'Operación logística regional; asignación local de pedidos.', 'LIM-S'),
  ('comercio',           'HORIZONTAL+VERTICAL',  'region_codigo',
   'fv_comercio_basico | fv_comercio_contacto',
   'Menú y pedidos consultan básico; facturación consulta contacto/RUC.', 'LIM-N'),
  ('proveedor',          'HORIZONTAL',           'region_codigo', NULL,
   'Abastecimiento local; identidad en persona.', 'LIM-N'),
  ('comercio_proveedor', 'HORIZONTAL',           'region_codigo', NULL,
   'Puente N:M; siempre mismo region_codigo que comercio y proveedor.', 'LIM-N'),
  ('categoria_producto', 'HORIZONTAL',           'region_codigo', NULL,
   'Catálogo de menú co-ubicado con comercio.', 'LIM-N'),
  ('producto',           'HORIZONTAL+VERTICAL',  'region_codigo',
   'fv_producto_catalogo | fv_producto_operacion',
   'Vertical: separar precio/disponible (escrituras) de nombre/descripción (lecturas).', 'LIM-N'),
  ('pedido',             'HORIZONTAL+VERTICAL',  'region_codigo + RANGE(fecha_creacion)',
   'fv_pedido_nucleo | fv_pedido_entrega | fv_pedido_totales',
   'Horizontal primaria por región; sub-partición mensual por fecha. Vertical: tracking vs montos.', 'LIM-N'),
  ('detalle_pedido',     'HORIZONTAL',           'region_codigo (hereda pedido)', NULL,
   'Líneas co-ubicadas con pedido y producto.', 'LIM-N'),
  ('pago',               'HORIZONTAL',           'region_codigo', NULL,
   'Transacción financiera en el nodo del pedido.', 'LIM-N'),
  ('ruta_reparto',       'HORIZONTAL',           'region_codigo', NULL,
   'Planificación de reparto por región.', 'LIM-S'),
  ('parada_ruta',        'HORIZONTAL',           'region_codigo', NULL,
   'Paradas en el mismo nodo que ruta y pedido.', 'LIM-S'),
  ('bitacora_evento',    'HORIZONTAL+VERTICAL',  'RANGE(fecha_hora)',
   'fv_bitacora_evento | fv_bitacora_payload',
   'Horizontal por mes (volumen). Vertical: metadatos vs JSONB pesado.', 'GLOBAL'),
  ('saga_transaccion',   'HORIZONTAL',           'region_codigo', NULL,
   'Coordinación distribuida por región operativa.', 'LIM-N'),
  ('saga_paso',          'HORIZONTAL',           'vía id_saga → saga_transaccion', NULL,
   'No se fragmenta sola; sigue a la saga padre.', 'LIM-N');
-- =========================================================
-- 3. FRAGMENTACIÓN VERTICAL — PERSONA
--    fv_persona_identidad  → consultas auth / validación doc
--    fv_persona_contacto   → consultas CRM / notificaciones
-- =========================================================
CREATE TABLE fv_persona_identidad (
  region_codigo       VARCHAR(10) NOT NULL REFERENCES nodo_registro(region_codigo),
  id_persona          UUID NOT NULL,
  id_tipo_persona     UUID NOT NULL REFERENCES catalogo_maestro(id_catalogo),
  id_tipo_documento   UUID NOT NULL REFERENCES catalogo_maestro(id_catalogo),
  numero_documento    VARCHAR(20) NOT NULL,
  nombres             VARCHAR(120),
  apellidos           VARCHAR(120),
  razon_social        VARCHAR(200),
  activo              BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (region_codigo, id_persona),
  UNIQUE (region_codigo, id_tipo_documento, numero_documento)
);

CREATE TABLE fv_persona_contacto (
  region_codigo     VARCHAR(10) NOT NULL,
  id_persona        UUID NOT NULL,
  correo            TEXT,
  telefono          VARCHAR(30),
  direccion         TEXT,
  fecha_nacimiento  DATE,
  fecha_creacion    TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_modificacion TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (region_codigo, id_persona),
  FOREIGN KEY (region_codigo, id_persona)
    REFERENCES fv_persona_identidad(region_codigo, id_persona)
    ON DELETE CASCADE
);

CREATE VIEW v_persona AS
SELECT
  i.region_codigo, i.id_persona,
  i.id_tipo_persona, i.id_tipo_documento, i.numero_documento,
  i.nombres, i.apellidos, i.razon_social, i.activo,
  c.correo, c.telefono, c.direccion, c.fecha_nacimiento,
  c.fecha_creacion, c.fecha_modificacion
FROM fv_persona_identidad i
JOIN fv_persona_contacto c
  ON c.region_codigo = i.region_codigo AND c.id_persona = i.id_persona;

COMMENT ON VIEW v_persona IS 'Reconstrucción lógica de PERSONA desde fragmentos verticales.';

-- =========================================================
-- 4. FRAGMENTACIÓN VERTICAL — USUARIO
--    fv_usuario_cuenta     → rol, acceso, estado (consultas frecuentes)
--    fv_usuario_seguridad  → hash, bloqueos (nodo/servicio auth aislado)
-- =========================================================
CREATE TABLE fv_usuario_cuenta (
  region_codigo     VARCHAR(10) NOT NULL,
  id_usuario        UUID NOT NULL,
  id_persona        UUID NOT NULL,
  id_rol            UUID NOT NULL REFERENCES catalogo_maestro(id_catalogo),
  nombre_acceso     TEXT NOT NULL,
  cuenta_activa     BOOLEAN NOT NULL DEFAULT TRUE,
  correo_verificado BOOLEAN NOT NULL DEFAULT FALSE,
  fecha_registro    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (region_codigo, id_usuario),
  UNIQUE (region_codigo, id_persona),
  FOREIGN KEY (region_codigo, id_persona)
    REFERENCES fv_persona_identidad(region_codigo, id_persona)
);

CREATE TABLE fv_usuario_seguridad (
  region_codigo       VARCHAR(10) NOT NULL,
  id_usuario          UUID NOT NULL,
  contrasena_hash     TEXT NOT NULL,
  intentos_fallidos   SMALLINT NOT NULL DEFAULT 0,
  bloqueado_hasta     TIMESTAMPTZ,
  fecha_ultimo_acceso TIMESTAMPTZ,
  PRIMARY KEY (region_codigo, id_usuario),
  FOREIGN KEY (region_codigo, id_usuario)
    REFERENCES fv_usuario_cuenta(region_codigo, id_usuario)
    ON DELETE CASCADE
);

CREATE VIEW v_usuario AS
SELECT
  c.region_codigo, c.id_usuario, c.id_persona, c.id_rol,
  c.nombre_acceso, c.cuenta_activa, c.correo_verificado, c.fecha_registro,
  s.contrasena_hash, s.intentos_fallidos, s.bloqueado_hasta, s.fecha_ultimo_acceso
FROM fv_usuario_cuenta c
JOIN fv_usuario_seguridad s
  ON s.region_codigo = c.region_codigo AND s.id_usuario = c.id_usuario;

-- =========================================================
-- 5. FRAGMENTACIÓN VERTICAL — PEDIDO
--    fv_pedido_nucleo   → FKs, estado, fechas (tracking)
--    fv_pedido_entrega  → dirección (reparto)
--    fv_pedido_totales  → montos (contabilidad; bloqueos cortos)
-- =========================================================
CREATE TABLE fv_pedido_nucleo (
  region_codigo      VARCHAR(10) NOT NULL REFERENCES nodo_registro(region_codigo),
  id_pedido          UUID NOT NULL,
  id_cliente         UUID NOT NULL,
  id_comercio        UUID NOT NULL,
  id_repartidor      UUID,
  id_estado_pedido   UUID NOT NULL REFERENCES catalogo_maestro(id_catalogo),
  nombre_cliente     VARCHAR(240) NOT NULL,
  nombre_comercio    VARCHAR(160) NOT NULL,
  fecha_creacion     TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_confirmacion TIMESTAMPTZ,
  fecha_entrega_real TIMESTAMPTZ,
  PRIMARY KEY (region_codigo, id_pedido)
);

CREATE TABLE fv_pedido_entrega (
  region_codigo      VARCHAR(10) NOT NULL,
  id_pedido          UUID NOT NULL,
  direccion_entrega  TEXT NOT NULL,
  referencia_entrega TEXT,
  PRIMARY KEY (region_codigo, id_pedido),
  FOREIGN KEY (region_codigo, id_pedido)
    REFERENCES fv_pedido_nucleo(region_codigo, id_pedido)
    ON DELETE CASCADE
);

CREATE TABLE fv_pedido_totales (
  region_codigo  VARCHAR(10) NOT NULL,
  id_pedido      UUID NOT NULL,
  subtotal       NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  costo_envio    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (costo_envio >= 0),
  total          NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  PRIMARY KEY (region_codigo, id_pedido),
  FOREIGN KEY (region_codigo, id_pedido)
    REFERENCES fv_pedido_nucleo(region_codigo, id_pedido)
    ON DELETE CASCADE
);

CREATE VIEW v_pedido AS
SELECT
  n.region_codigo, n.id_pedido, n.id_cliente, n.id_comercio, n.id_repartidor,
  n.id_estado_pedido, n.nombre_cliente, n.nombre_comercio,
  e.direccion_entrega, e.referencia_entrega,
  t.subtotal, t.costo_envio, t.total,
  n.fecha_creacion, n.fecha_confirmacion, n.fecha_entrega_real
FROM fv_pedido_nucleo n
JOIN fv_pedido_entrega e
  ON e.region_codigo = n.region_codigo AND e.id_pedido = n.id_pedido
JOIN fv_pedido_totales t
  ON t.region_codigo = n.region_codigo AND t.id_pedido = n.id_pedido;

-- =========================================================
-- 6. FRAGMENTACIÓN HORIZONTAL — PEDIDO (LIST region + RANGE fecha)
--    Nivel 1: por region_codigo (nodos LIM-N, LIM-S, AQP)
--    Nivel 2: sub-partición mensual por fecha_creacion (archivo/hot data)
-- =========================================================
CREATE TABLE fh_pedido (
  region_codigo      VARCHAR(10) NOT NULL,
  id_pedido          UUID NOT NULL,
  id_cliente         UUID NOT NULL,
  id_comercio        UUID NOT NULL,
  id_estado_pedido   UUID NOT NULL REFERENCES catalogo_maestro(id_catalogo),
  total              NUMERIC(12,2) NOT NULL DEFAULT 0,
  fecha_creacion     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (region_codigo, id_pedido, fecha_creacion)
) PARTITION BY LIST (region_codigo);

CREATE TABLE fh_pedido_lim_n PARTITION OF fh_pedido
  FOR VALUES IN ('LIM-N') PARTITION BY RANGE (fecha_creacion);

CREATE TABLE fh_pedido_lim_s PARTITION OF fh_pedido
  FOR VALUES IN ('LIM-S') PARTITION BY RANGE (fecha_creacion);

CREATE TABLE fh_pedido_aqp PARTITION OF fh_pedido
  FOR VALUES IN ('AQP') PARTITION BY RANGE (fecha_creacion);

-- Sub-particiones mensuales (ejemplo 2026)
CREATE TABLE fh_pedido_lim_n_2026_01 PARTITION OF fh_pedido_lim_n
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE fh_pedido_lim_n_2026_02 PARTITION OF fh_pedido_lim_n
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE fh_pedido_lim_s_2026_01 PARTITION OF fh_pedido_lim_s
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE fh_pedido_lim_s_2026_02 PARTITION OF fh_pedido_lim_s
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE fh_pedido_aqp_2026_01 PARTITION OF fh_pedido_aqp
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE fh_pedido_aqp_2026_02 PARTITION OF fh_pedido_aqp
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

COMMENT ON TABLE fh_pedido IS
  'Fragmentación horizontal compuesta: LIST(region_codigo) + RANGE(fecha_creacion).';

-- =========================================================
-- 7. FRAGMENTACIÓN HORIZONTAL — BITÁCORA (solo por fecha)
--    Append-only; particionar por mes reduce índices calientes
-- =========================================================
CREATE TABLE fv_bitacora_evento (
  id_evento       UUID NOT NULL DEFAULT gen_random_uuid(),
  region_codigo   VARCHAR(10),
  fecha_hora      TIMESTAMPTZ NOT NULL DEFAULT now(),
  tipo_evento     VARCHAR(50) NOT NULL,
  tabla_afectada  VARCHAR(64),
  id_registro     UUID,
  id_usuario      UUID,
  PRIMARY KEY (id_evento, fecha_hora)
);

CREATE TABLE fv_bitacora_payload (
  id_evento          UUID NOT NULL,
  fecha_hora         TIMESTAMPTZ NOT NULL,
  descripcion        TEXT,
  datos_adicionales  JSONB,
  nodo_origen        VARCHAR(10),
  PRIMARY KEY (id_evento, fecha_hora),
  FOREIGN KEY (id_evento, fecha_hora)
    REFERENCES fv_bitacora_evento(id_evento, fecha_hora)
    ON DELETE CASCADE
);

CREATE TABLE fh_bitacora_evento (
  id_evento     UUID NOT NULL DEFAULT gen_random_uuid(),
  region_codigo VARCHAR(10),
  fecha_hora    TIMESTAMPTZ NOT NULL DEFAULT now(),
  tipo_evento   VARCHAR(50) NOT NULL,
  descripcion   TEXT,
  PRIMARY KEY (id_evento, fecha_hora)
) PARTITION BY RANGE (fecha_hora);

CREATE TABLE fh_bitacora_2026_01 PARTITION OF fh_bitacora_evento
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE fh_bitacora_2026_02 PARTITION OF fh_bitacora_evento
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

-- =========================================================
-- 8. DATOS DE EJEMPLO
-- =========================================================
DO $$
DECLARE
  v_id_natural UUID;
  v_id_dni UUID;
  v_id_rol UUID;
  v_id_estado UUID;
  v_id_persona UUID := 'aaaaaaaa-0001-4001-8001-000000000001';
  v_id_usuario UUID := 'aaaaaaaa-0002-4001-8001-000000000001';
  v_id_cliente UUID := 'aaaaaaaa-0003-4001-8001-000000000001';
  v_id_comercio UUID := 'aaaaaaaa-0005-4001-8001-000000000001';
  v_id_pedido UUID := 'aaaaaaaa-0009-4001-8001-000000000001';
BEGIN
  SELECT id_catalogo INTO v_id_natural FROM catalogo_maestro WHERE tipo_catalogo = 'TIPO_PERSONA' AND codigo = 'NATURAL';
  SELECT id_catalogo INTO v_id_dni FROM catalogo_maestro WHERE tipo_catalogo = 'TIPO_DOCUMENTO' AND codigo = 'DNI';
  SELECT id_catalogo INTO v_id_rol FROM catalogo_maestro WHERE tipo_catalogo = 'ROL' AND codigo = 'CLIENTE';
  SELECT id_catalogo INTO v_id_estado FROM catalogo_maestro WHERE tipo_catalogo = 'ESTADO_PEDIDO' AND codigo = 'CREADO';

  -- Vertical: persona
  INSERT INTO fv_persona_identidad (region_codigo, id_persona, id_tipo_persona, id_tipo_documento, numero_documento, nombres, apellidos)
  VALUES ('LIM-N', v_id_persona, v_id_natural, v_id_dni, '71234567', 'Ana', 'García');

  INSERT INTO fv_persona_contacto (region_codigo, id_persona, correo, telefono, direccion)
  VALUES ('LIM-N', v_id_persona, 'ana@mail.lim-n.pe', '999111222', 'Los Olivos 123');

  -- Vertical: usuario
  INSERT INTO fv_usuario_cuenta (region_codigo, id_usuario, id_persona, id_rol, nombre_acceso)
  VALUES ('LIM-N', v_id_usuario, v_id_persona, v_id_rol, 'ana.garcia@lim-n.pe');

  INSERT INTO fv_usuario_seguridad (region_codigo, id_usuario, contrasena_hash)
  VALUES ('LIM-N', v_id_usuario, '$2b$10$ejemplo_hash');

  -- Vertical: pedido
  INSERT INTO fv_pedido_nucleo (region_codigo, id_pedido, id_cliente, id_comercio, id_estado_pedido, nombre_cliente, nombre_comercio)
  VALUES ('LIM-N', v_id_pedido, v_id_cliente, v_id_comercio, v_id_estado, 'Ana García', 'Pollería Norte');

  INSERT INTO fv_pedido_entrega (region_codigo, id_pedido, direccion_entrega)
  VALUES ('LIM-N', v_id_pedido, 'Av. Alfredo Mendiola 456');

  INSERT INTO fv_pedido_totales (region_codigo, id_pedido, subtotal, costo_envio, total)
  VALUES ('LIM-N', v_id_pedido, 45.00, 5.00, 50.00);

  -- Horizontal: pedido particionado
  INSERT INTO fh_pedido (region_codigo, id_pedido, id_cliente, id_comercio, id_estado_pedido, total, fecha_creacion)
  VALUES
    ('LIM-N', v_id_pedido, v_id_cliente, v_id_comercio, v_id_estado, 50.00, '2026-01-15 12:00:00+00'),
    ('LIM-S', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), v_id_estado, 32.00, '2026-01-20 18:30:00+00'),
    ('AQP',   gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), v_id_estado, 28.50, '2026-02-05 13:15:00+00');

  -- Horizontal + vertical bitácora
  INSERT INTO fh_bitacora_evento (region_codigo, fecha_hora, tipo_evento, descripcion)
  VALUES ('LIM-N', '2026-01-15 12:01:00+00', 'PEDIDO_CREADO', 'Pedido demo fragmentación HV');
END $$;

-- =========================================================
-- 9. CONSULTAS DE VERIFICACIÓN
-- =========================================================
SELECT 'Matriz de fragmentación' AS seccion;
SELECT tabla_logica, estrategia, clave_horizontal, fragmentos_verticales
FROM matriz_fragmentacion
ORDER BY id;

SELECT 'Reconstrucción vertical — v_persona' AS seccion;
SELECT region_codigo, nombres, apellidos, correo FROM v_persona;

SELECT 'Reconstrucción vertical — v_pedido' AS seccion;
SELECT region_codigo, id_pedido, total, direccion_entrega FROM v_pedido;

SELECT 'Fragmentación horizontal — pedidos por región y mes' AS seccion;
SELECT
  tableoid::regclass AS particion_fisica,
  region_codigo,
  COUNT(*) AS cantidad,
  ROUND(SUM(total), 2) AS monto
FROM fh_pedido
GROUP BY tableoid::regclass, region_codigo
ORDER BY particion_fisica;

SELECT 'Fragmentación horizontal — bitácora por partición mensual' AS seccion;
SELECT tableoid::regclass AS particion, COUNT(*) AS eventos
FROM fh_bitacora_evento
GROUP BY tableoid::regclass;

-- =========================================================
-- 10. RESUMEN EJECUTIVO (comentario final)
-- =========================================================
--
-- COMBINAR AMBAS ESTRATEGIAS EN PRODUCCIÓN:
--
--   1. Horizontal primero (region_codigo) → ya lo tienes en delivery_db_distribuida.
--   2. Sub-partición horizontal por fecha en tablas masivas (pedido, bitacora).
--   3. Vertical en tablas anchas o con perfiles de acceso distintos:
--        persona, usuario, pedido, producto, bitacora (payload JSONB).
--   4. NO fragmentar: catalogo_maestro, nodo_registro, saga_paso (sigue a saga).
--   5. Reconstruir con VISTAS (v_persona, v_pedido) o capa de aplicación.
--
-- =========================================================
