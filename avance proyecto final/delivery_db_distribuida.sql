-- =========================================================
-- Script PostgreSQL: delivery_db_distribuida
-- Ejecutar con: psql -f delivery_db_distribuida.sql
--
-- Modelo adaptado para BASE DE DATOS DISTRIBUIDA (fragmentación horizontal por región).
-- Estrategia: cada región (nodo) almacena sus propios datos operativos; los catálogos
-- globales se replican en todos los nodos.
--
-- Cambios respecto a delivery_db.sql:
--   • PK con UUID (identificadores globales entre nodos).
--   • Clave de fragmentación: region_codigo en tablas regionales.
--   • PK compuesta (region_codigo, id_*) para forzar co-ubicación de FK en el mismo nodo.
--   • Referencias a catálogo por id_catalogo → catalogo_maestro (réplica global).
--   • Desnormalización en pedido y detalle_pedido (evita joins entre nodos).
--   • Persona referencia id_tipo_persona → catalogo_maestro (TIPO_PERSONA); proveedor FK a persona.
--   • bitacora_evento sin FK física (referencia lógica a usuario).
--   • Tablas saga_transaccion / saga_paso para operaciones distribuidas.
--   • Unicidad de documento/correo por región (no global).
--
-- Nodos de ejemplo (tabla nodo_registro):
--   GLOBAL  → catálogos replicados (catalogo_maestro)
--   LIM-N   → Lima Norte
--   LIM-S   → Lima Sur
--   AQP     → Arequipa
-- =========================================================

-- =========================
-- Metadatos de nodos / fragmentos
-- =========================
CREATE TABLE nodo_registro (
  region_codigo   VARCHAR(10) PRIMARY KEY,
  nombre_nodo     VARCHAR(80) NOT NULL,
  host            VARCHAR(120),
  puerto          INTEGER,
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  es_nodo_global  BOOLEAN NOT NULL DEFAULT FALSE,
  fecha_alta      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE nodo_registro IS 'Catálogo de nodos/regiones del sistema distribuido.';

INSERT INTO nodo_registro (region_codigo, nombre_nodo, es_nodo_global) VALUES
  ('GLOBAL', 'Nodo central de catálogos', TRUE),
  ('LIM-N',  'Lima Norte', FALSE),
  ('LIM-S',  'Lima Sur', FALSE),
  ('AQP',    'Arequipa', FALSE);

-- =========================
-- Datos GLOBALES (réplica en cada nodo físico)
-- =========================
CREATE TABLE catalogo_maestro (
  id_catalogo        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo_catalogo      VARCHAR(40) NOT NULL,
  codigo             VARCHAR(40) NOT NULL,
  nombre             VARCHAR(120) NOT NULL,
  descripcion        TEXT,
  orden_presentacion SMALLINT,
  activo             BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT uq_catalogo_maestro_tipo_codigo UNIQUE (tipo_catalogo, codigo)
);

COMMENT ON TABLE catalogo_maestro IS 'Réplica global: catálogos de valores fijos discriminados por tipo_catalogo.';
COMMENT ON COLUMN catalogo_maestro.tipo_catalogo IS 'Ej.: TIPO_VEHICULO, TIPO_PERSONA, TIPO_DOCUMENTO, ESTADO_PEDIDO, etc.';

INSERT INTO catalogo_maestro (tipo_catalogo, codigo, nombre, descripcion, orden_presentacion) VALUES
  ('TIPO_VEHICULO', 'BICI', 'Bicicleta', 'Entrega en bicicleta.', 1),
  ('TIPO_VEHICULO', 'MOTO', 'Motocicleta', 'Entrega en moto.', 2),
  ('TIPO_VEHICULO', 'AUTO', 'Automóvil', 'Entrega en auto.', 3),
  ('TIPO_VEHICULO', 'OTRO', 'Otro', 'Otro medio de transporte.', 4),
  ('ESTADO_PEDIDO', 'CREADO', 'Creado', 'Pedido registrado, pendiente de confirmación.', 1),
  ('ESTADO_PEDIDO', 'CONFIRMADO', 'Confirmado', 'El comercio o sistema confirmó el pedido.', 2),
  ('ESTADO_PEDIDO', 'EN_CAMINO', 'En camino', 'El pedido va en reparto.', 3),
  ('ESTADO_PEDIDO', 'ENTREGADO', 'Entregado', 'Entregado al cliente.', 4),
  ('ESTADO_PEDIDO', 'CANCELADO', 'Cancelado', 'Pedido anulado.', 5),
  ('METODO_PAGO', 'EFECTIVO', 'Efectivo', 'Pago en efectivo contra entrega.', 1),
  ('METODO_PAGO', 'TARJETA', 'Tarjeta', 'Tarjeta débito o crédito.', 2),
  ('METODO_PAGO', 'YAPE', 'Yape', 'Billetera Yape.', 3),
  ('METODO_PAGO', 'PLIN', 'Plin', 'Billetera Plin.', 4),
  ('METODO_PAGO', 'TRANSFERENCIA', 'Transferencia', 'Transferencia bancaria.', 5),
  ('ESTADO_PAGO', 'PENDIENTE', 'Pendiente', 'Pago aún no completado.', 1),
  ('ESTADO_PAGO', 'PAGADO', 'Pagado', 'Pago confirmado.', 2),
  ('ESTADO_PAGO', 'RECHAZADO', 'Rechazado', 'Pago rechazado por el medio o banco.', 3),
  ('ESTADO_PAGO', 'DEVUELTO', 'Devuelto', 'Reembolso o devolución del monto.', 4),
  ('ESTADO_RUTA', 'PLANIFICADA', 'Planificada', 'Ruta definida, aún no iniciada.', 1),
  ('ESTADO_RUTA', 'EN_PROGRESO', 'En progreso', 'Repartidor en recorrido.', 2),
  ('ESTADO_RUTA', 'FINALIZADA', 'Finalizada', 'Ruta completada.', 3),
  ('ESTADO_RUTA', 'CANCELADA', 'Cancelada', 'Ruta anulada.', 4),
  ('TIPO_PERSONA', 'NATURAL', 'Persona natural', 'Individuo identificado con DNI u otro doc. personal.', 1),
  ('TIPO_PERSONA', 'JURIDICA', 'Persona jurídica', 'Empresa u organización identificada con RUC.', 2),
  ('TIPO_DOCUMENTO', 'DNI', 'Documento Nacional de Identidad', 'Documento de identidad para persona natural.', 1),
  ('TIPO_DOCUMENTO', 'RUC', 'Registro Único de Contribuyentes', 'Identificación tributaria; persona jurídica o negocio.', 2),
  ('ROL', 'CLIENTE', 'Cliente', 'Realiza pedidos desde la aplicación.', 1),
  ('ROL', 'REPARTIDOR', 'Repartidor', 'Entrega pedidos y usa la app de conductor.', 2),
  ('ROL', 'ADMINISTRADOR', 'Administrador', 'Gestión de plataforma, comercios o configuración.', 3),
  ('PREFERENCIA_NOTIFICACION', 'TODAS', 'Todas', 'Recibe todas las notificaciones.', 1),
  ('PREFERENCIA_NOTIFICACION', 'SOLO_PEDIDOS', 'Solo pedidos', 'Notificaciones relacionadas con pedidos.', 2),
  ('PREFERENCIA_NOTIFICACION', 'NINGUNA', 'Ninguna', 'No recibe notificaciones push.', 3);

CREATE OR REPLACE FUNCTION id_catalogo_por_tipo_codigo(p_tipo_catalogo VARCHAR, p_codigo VARCHAR)
RETURNS UUID AS $$
  SELECT id_catalogo FROM catalogo_maestro
  WHERE tipo_catalogo = p_tipo_catalogo AND codigo = p_codigo AND activo
  LIMIT 1;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION id_catalogo_por_tipo_codigo IS 'Obtiene id_catalogo por tipo y código (p. ej. TIPO_PERSONA, NATURAL).';

-- =========================
-- Reglas de fragmentación (documentación en BD)
-- =========================
CREATE TABLE regla_fragmentacion (
  id_regla        SERIAL PRIMARY KEY,
  tabla           VARCHAR(64) NOT NULL,
  clave_fragmento VARCHAR(40) NOT NULL DEFAULT 'region_codigo',
  criterio        TEXT NOT NULL,
  nodo_ejemplo    VARCHAR(10) REFERENCES nodo_registro(region_codigo)
);

INSERT INTO regla_fragmentacion (tabla, criterio, nodo_ejemplo) VALUES
  ('persona',            'Filas por región de residencia del usuario.', 'LIM-N'),
  ('usuario',            'Misma región que persona.', 'LIM-N'),
  ('cliente',            'Misma región que usuario.', 'LIM-N'),
  ('repartidor',         'Región de operación del repartidor.', 'LIM-S'),
  ('comercio',           'Región donde opera el establecimiento.', 'LIM-N'),
  ('proveedor',          'Región del proveedor; siempre vinculado a persona (identidad base).', 'LIM-N'),
  ('producto',           'Misma región que comercio (co-ubicado).', 'LIM-N'),
  ('pedido',             'Región del comercio que recibe el pedido.', 'LIM-N'),
  ('detalle_pedido',     'Misma región que pedido y producto.', 'LIM-N'),
  ('pago',               'Misma región que pedido.', 'LIM-N'),
  ('ruta_reparto',       'Región del repartidor.', 'LIM-S'),
  ('parada_ruta',        'Misma región que ruta y pedido.', 'LIM-S'),
  ('bitacora_evento',    'Nodo de auditoría; partición por fecha_hora.', 'GLOBAL'),
  ('catalogo_maestro',   'Réplica completa en todos los nodos.', 'GLOBAL');

-- =========================
-- Fragmento REGIONAL: identidad y acceso
-- PK compuesta (region_codigo, id_*) → FK solo dentro del mismo nodo
-- =========================
CREATE TABLE persona (
  region_codigo         VARCHAR(10) NOT NULL REFERENCES nodo_registro(region_codigo),
  id_persona            UUID NOT NULL DEFAULT gen_random_uuid(),
  id_tipo_persona       UUID NOT NULL
                        REFERENCES catalogo_maestro(id_catalogo)
                        ON UPDATE CASCADE ON DELETE RESTRICT
                        DEFAULT id_catalogo_por_tipo_codigo('TIPO_PERSONA', 'NATURAL'),
  id_tipo_documento     UUID NOT NULL
                        REFERENCES catalogo_maestro(id_catalogo)
                        ON UPDATE CASCADE ON DELETE RESTRICT
                        DEFAULT id_catalogo_por_tipo_codigo('TIPO_DOCUMENTO', 'DNI'),
  numero_documento      VARCHAR(20) NOT NULL,
  nombres               VARCHAR(120),
  apellidos             VARCHAR(120),
  razon_social          VARCHAR(200),
  correo                TEXT,
  telefono              VARCHAR(30),
  fecha_nacimiento      DATE,
  direccion             TEXT,
  activo                BOOLEAN NOT NULL DEFAULT TRUE,
  nodo_origen           VARCHAR(10) NOT NULL,
  fecha_creacion        TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_modificacion    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (region_codigo, id_persona),
  CONSTRAINT uq_persona_region_documento UNIQUE (region_codigo, id_tipo_documento, numero_documento),
  CONSTRAINT ck_persona_correo_formato CHECK (correo IS NULL OR position('@' in correo) > 1),
  CONSTRAINT ck_persona_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON TABLE persona IS 'Identidad base regional; tipo y documento vía FK a catalogo_maestro.';
COMMENT ON COLUMN persona.id_tipo_persona IS 'FK a catalogo_maestro; tipo_catalogo = TIPO_PERSONA.';
COMMENT ON COLUMN persona.id_tipo_documento IS 'FK a catalogo_maestro; tipo_catalogo = TIPO_DOCUMENTO (DNI, RUC).';
COMMENT ON COLUMN persona.nombres IS 'Obligatorio si NATURAL; NULL si JURIDICA (p. ej. proveedor).';
COMMENT ON COLUMN persona.apellidos IS 'Obligatorio si NATURAL; NULL si JURIDICA.';
COMMENT ON COLUMN persona.razon_social IS 'Obligatorio si JURIDICA; NULL si NATURAL.';

CREATE TABLE usuario (
  region_codigo          VARCHAR(10) NOT NULL,
  id_usuario             UUID NOT NULL DEFAULT gen_random_uuid(),
  id_persona             UUID NOT NULL,
  id_rol                 UUID NOT NULL
                         REFERENCES catalogo_maestro(id_catalogo)
                         ON UPDATE CASCADE ON DELETE RESTRICT
                         DEFAULT id_catalogo_por_tipo_codigo('ROL', 'CLIENTE'),
  nombre_acceso          TEXT NOT NULL,
  contrasena_hash        TEXT NOT NULL,
  cuenta_activa          BOOLEAN NOT NULL DEFAULT TRUE,
  correo_verificado      BOOLEAN NOT NULL DEFAULT FALSE,
  telefono_verificado    BOOLEAN NOT NULL DEFAULT FALSE,
  nodo_origen            VARCHAR(10) NOT NULL,
  fecha_registro         TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_ultimo_acceso    TIMESTAMPTZ,
  intentos_fallidos      SMALLINT NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),
  bloqueado_hasta        TIMESTAMPTZ,
  PRIMARY KEY (region_codigo, id_usuario),
  CONSTRAINT uq_usuario_region_persona UNIQUE (region_codigo, id_persona),
  CONSTRAINT fk_usuario_persona
    FOREIGN KEY (region_codigo, id_persona)
    REFERENCES persona(region_codigo, id_persona)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_usuario_nombre_acceso_no_vacio CHECK (length(btrim(nombre_acceso)) > 0),
  CONSTRAINT ck_usuario_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON COLUMN usuario.id_rol IS 'FK a catalogo_maestro; tipo_catalogo = ROL.';

CREATE TABLE cliente (
  region_codigo                VARCHAR(10) NOT NULL,
  id_cliente                   UUID NOT NULL DEFAULT gen_random_uuid(),
  id_usuario                   UUID NOT NULL,
  fecha_alta_cliente           TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_preferencia_notificacion  UUID NOT NULL
                               REFERENCES catalogo_maestro(id_catalogo)
                               ON UPDATE CASCADE ON DELETE RESTRICT
                               DEFAULT id_catalogo_por_tipo_codigo('PREFERENCIA_NOTIFICACION', 'TODAS'),
  acepta_publicidad            BOOLEAN NOT NULL DEFAULT FALSE,
  idioma_preferido             VARCHAR(10) NOT NULL DEFAULT 'es',
  moneda_preferida             VARCHAR(3) NOT NULL DEFAULT 'PEN',
  nodo_origen                  VARCHAR(10) NOT NULL,
  notas                        TEXT,
  PRIMARY KEY (region_codigo, id_cliente),
  CONSTRAINT uq_cliente_region_usuario UNIQUE (region_codigo, id_usuario),
  CONSTRAINT fk_cliente_usuario
    FOREIGN KEY (region_codigo, id_usuario)
    REFERENCES usuario(region_codigo, id_usuario)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_cliente_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON COLUMN cliente.id_preferencia_notificacion IS 'FK a catalogo_maestro; tipo_catalogo = PREFERENCIA_NOTIFICACION.';

-- =========================
-- Fragmento REGIONAL: reparto
-- =========================
CREATE TABLE repartidor (
  region_codigo       VARCHAR(10) NOT NULL,
  id_repartidor       UUID NOT NULL DEFAULT gen_random_uuid(),
  id_persona          UUID NOT NULL,
  id_usuario          UUID,
  id_tipo_vehiculo    UUID NOT NULL
                      REFERENCES catalogo_maestro(id_catalogo)
                      ON UPDATE CASCADE ON DELETE RESTRICT,
  placa               VARCHAR(15),
  disponible          BOOLEAN NOT NULL DEFAULT TRUE,
  nodo_origen         VARCHAR(10) NOT NULL,
  PRIMARY KEY (region_codigo, id_repartidor),
  CONSTRAINT uq_repartidor_region_persona UNIQUE (region_codigo, id_persona),
  CONSTRAINT uq_repartidor_region_usuario UNIQUE (region_codigo, id_usuario),
  CONSTRAINT fk_repartidor_persona
    FOREIGN KEY (region_codigo, id_persona)
    REFERENCES persona(region_codigo, id_persona)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_repartidor_usuario
    FOREIGN KEY (region_codigo, id_usuario)
    REFERENCES usuario(region_codigo, id_usuario)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT ck_repartidor_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON COLUMN repartidor.id_tipo_vehiculo IS 'FK a catalogo_maestro; tipo_catalogo = TIPO_VEHICULO.';

-- =========================
-- Fragmento REGIONAL: comercio y catálogo de productos
-- =========================
CREATE TABLE comercio (
  region_codigo  VARCHAR(10) NOT NULL,
  id_comercio    UUID NOT NULL DEFAULT gen_random_uuid(),
  nombre         VARCHAR(160) NOT NULL,
  ruc            VARCHAR(20),
  telefono       VARCHAR(30),
  correo         TEXT,
  direccion      TEXT NOT NULL,
  activo         BOOLEAN NOT NULL DEFAULT TRUE,
  nodo_origen    VARCHAR(10) NOT NULL,
  PRIMARY KEY (region_codigo, id_comercio),
  CONSTRAINT uq_comercio_region_ruc UNIQUE (region_codigo, ruc),
  CONSTRAINT ck_comercio_correo_formato CHECK (correo IS NULL OR position('@' in correo) > 1),
  CONSTRAINT ck_comercio_nodo_origen CHECK (nodo_origen = region_codigo)
);

CREATE TABLE proveedor (
  region_codigo   VARCHAR(10) NOT NULL,
  id_proveedor    UUID NOT NULL DEFAULT gen_random_uuid(),
  id_persona      UUID NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  notas           TEXT,
  nodo_origen     VARCHAR(10) NOT NULL,
  PRIMARY KEY (region_codigo, id_proveedor),
  CONSTRAINT uq_proveedor_region_persona UNIQUE (region_codigo, id_persona),
  CONSTRAINT fk_proveedor_persona
    FOREIGN KEY (region_codigo, id_persona)
    REFERENCES persona(region_codigo, id_persona)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_proveedor_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON TABLE proveedor IS 'Rol proveedor; datos básicos (nombre, documento, contacto) vía persona.';
COMMENT ON COLUMN proveedor.id_persona IS 'Siempre obligatorio; persona natural o jurídica de la misma región.';

CREATE TABLE comercio_proveedor (
  region_codigo  VARCHAR(10) NOT NULL,
  id_comercio    UUID NOT NULL,
  id_proveedor   UUID NOT NULL,
  notas          TEXT,
  fecha_alta     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (region_codigo, id_comercio, id_proveedor),
  CONSTRAINT fk_cp_comercio
    FOREIGN KEY (region_codigo, id_comercio)
    REFERENCES comercio(region_codigo, id_comercio)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_cp_proveedor
    FOREIGN KEY (region_codigo, id_proveedor)
    REFERENCES proveedor(region_codigo, id_proveedor)
    ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE categoria_producto (
  region_codigo  VARCHAR(10) NOT NULL,
  id_categoria   UUID NOT NULL DEFAULT gen_random_uuid(),
  id_comercio    UUID NOT NULL,
  nombre         VARCHAR(120) NOT NULL,
  nodo_origen    VARCHAR(10) NOT NULL,
  PRIMARY KEY (region_codigo, id_categoria),
  CONSTRAINT uq_categoria_region_comercio_nombre UNIQUE (region_codigo, id_comercio, nombre),
  CONSTRAINT fk_categoria_comercio
    FOREIGN KEY (region_codigo, id_comercio)
    REFERENCES comercio(region_codigo, id_comercio)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_categoria_nodo_origen CHECK (nodo_origen = region_codigo)
);

CREATE TABLE producto (
  region_codigo   VARCHAR(10) NOT NULL,
  id_producto     UUID NOT NULL DEFAULT gen_random_uuid(),
  id_comercio     UUID NOT NULL,
  id_categoria    UUID,
  nombre          VARCHAR(160) NOT NULL,
  descripcion     TEXT,
  precio          NUMERIC(12,2) NOT NULL CHECK (precio >= 0),
  disponible      BOOLEAN NOT NULL DEFAULT TRUE,
  nodo_origen     VARCHAR(10) NOT NULL,
  PRIMARY KEY (region_codigo, id_producto),
  CONSTRAINT fk_producto_comercio
    FOREIGN KEY (region_codigo, id_comercio)
    REFERENCES comercio(region_codigo, id_comercio)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_producto_categoria
    FOREIGN KEY (region_codigo, id_categoria)
    REFERENCES categoria_producto(region_codigo, id_categoria)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT ck_producto_nodo_origen CHECK (nodo_origen = region_codigo)
);

-- =========================
-- Fragmento REGIONAL: pedidos (con desnormalización)
-- =========================
CREATE TABLE pedido (
  region_codigo          VARCHAR(10) NOT NULL,
  id_pedido              UUID NOT NULL DEFAULT gen_random_uuid(),
  id_cliente             UUID NOT NULL,
  id_comercio            UUID NOT NULL,
  id_repartidor          UUID,
  id_estado_pedido       UUID NOT NULL
                         REFERENCES catalogo_maestro(id_catalogo)
                         ON UPDATE CASCADE ON DELETE RESTRICT
                         DEFAULT id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'CREADO'),
  -- Desnormalización: evita consultar otro nodo para mostrar el pedido
  nombre_cliente         VARCHAR(240) NOT NULL,
  nombre_comercio        VARCHAR(160) NOT NULL,
  direccion_entrega      TEXT NOT NULL,
  referencia_entrega     TEXT,
  subtotal               NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  costo_envio            NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (costo_envio >= 0),
  total                  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  nodo_origen            VARCHAR(10) NOT NULL,
  fecha_creacion         TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_confirmacion     TIMESTAMPTZ,
  fecha_entrega_real     TIMESTAMPTZ,
  PRIMARY KEY (region_codigo, id_pedido),
  CONSTRAINT fk_pedido_cliente
    FOREIGN KEY (region_codigo, id_cliente)
    REFERENCES cliente(region_codigo, id_cliente)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_pedido_comercio
    FOREIGN KEY (region_codigo, id_comercio)
    REFERENCES comercio(region_codigo, id_comercio)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_pedido_repartidor
    FOREIGN KEY (region_codigo, id_repartidor)
    REFERENCES repartidor(region_codigo, id_repartidor)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT ck_pedido_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON COLUMN pedido.id_estado_pedido IS 'FK a catalogo_maestro; tipo_catalogo = ESTADO_PEDIDO.';
COMMENT ON COLUMN pedido.nombre_cliente IS 'Copia al crear pedido; no requiere join remoto.';

CREATE TABLE detalle_pedido (
  region_codigo      VARCHAR(10) NOT NULL,
  id_detalle_pedido  UUID NOT NULL DEFAULT gen_random_uuid(),
  id_pedido          UUID NOT NULL,
  id_producto        UUID NOT NULL,
  nombre_producto    VARCHAR(160) NOT NULL,
  cantidad           INTEGER NOT NULL CHECK (cantidad > 0),
  precio_unitario    NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
  importe_linea      NUMERIC(12,2) NOT NULL CHECK (importe_linea >= 0),
  nodo_origen        VARCHAR(10) NOT NULL,
  PRIMARY KEY (region_codigo, id_detalle_pedido),
  CONSTRAINT uq_detalle_region_pedido_producto UNIQUE (region_codigo, id_pedido, id_producto),
  CONSTRAINT fk_detalle_pedido
    FOREIGN KEY (region_codigo, id_pedido)
    REFERENCES pedido(region_codigo, id_pedido)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_detalle_producto
    FOREIGN KEY (region_codigo, id_producto)
    REFERENCES producto(region_codigo, id_producto)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_detalle_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON COLUMN detalle_pedido.nombre_producto IS 'Snapshot del nombre al momento del pedido.';

CREATE TABLE pago (
  region_codigo        VARCHAR(10) NOT NULL,
  id_pago              UUID NOT NULL DEFAULT gen_random_uuid(),
  id_pedido            UUID NOT NULL,
  id_metodo_pago       UUID NOT NULL
                       REFERENCES catalogo_maestro(id_catalogo)
                       ON UPDATE CASCADE ON DELETE RESTRICT,
  id_estado_pago       UUID NOT NULL
                       REFERENCES catalogo_maestro(id_catalogo)
                       ON UPDATE CASCADE ON DELETE RESTRICT
                       DEFAULT id_catalogo_por_tipo_codigo('ESTADO_PAGO', 'PENDIENTE'),
  monto                NUMERIC(12,2) NOT NULL CHECK (monto >= 0),
  nodo_origen          VARCHAR(10) NOT NULL,
  fecha_pago           TIMESTAMPTZ,
  PRIMARY KEY (region_codigo, id_pago),
  CONSTRAINT uq_pago_region_pedido UNIQUE (region_codigo, id_pedido),
  CONSTRAINT fk_pago_pedido
    FOREIGN KEY (region_codigo, id_pedido)
    REFERENCES pedido(region_codigo, id_pedido)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_pago_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON COLUMN pago.id_metodo_pago IS 'FK a catalogo_maestro; tipo_catalogo = METODO_PAGO.';
COMMENT ON COLUMN pago.id_estado_pago IS 'FK a catalogo_maestro; tipo_catalogo = ESTADO_PAGO.';

-- =========================
-- Fragmento REGIONAL: rutas de reparto
-- =========================
CREATE TABLE ruta_reparto (
  region_codigo         VARCHAR(10) NOT NULL,
  id_ruta               UUID NOT NULL DEFAULT gen_random_uuid(),
  id_repartidor         UUID NOT NULL,
  fecha_planificacion   DATE NOT NULL,
  id_estado_ruta        UUID NOT NULL
                        REFERENCES catalogo_maestro(id_catalogo)
                        ON UPDATE CASCADE ON DELETE RESTRICT
                        DEFAULT id_catalogo_por_tipo_codigo('ESTADO_RUTA', 'PLANIFICADA'),
  hora_inicio_real      TIMESTAMPTZ,
  hora_fin_real         TIMESTAMPTZ,
  distancia_kilometros  NUMERIC(10,2) CHECK (distancia_kilometros IS NULL OR distancia_kilometros >= 0),
  observaciones         TEXT,
  nodo_origen           VARCHAR(10) NOT NULL,
  fecha_creacion        TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (region_codigo, id_ruta),
  CONSTRAINT fk_ruta_repartidor
    FOREIGN KEY (region_codigo, id_repartidor)
    REFERENCES repartidor(region_codigo, id_repartidor)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_ruta_nodo_origen CHECK (nodo_origen = region_codigo)
);

COMMENT ON COLUMN ruta_reparto.id_estado_ruta IS 'FK a catalogo_maestro; tipo_catalogo = ESTADO_RUTA.';

CREATE TABLE parada_ruta (
  region_codigo           VARCHAR(10) NOT NULL,
  id_parada               UUID NOT NULL DEFAULT gen_random_uuid(),
  id_ruta                 UUID NOT NULL,
  id_pedido               UUID NOT NULL,
  orden_visita            INTEGER NOT NULL CHECK (orden_visita > 0),
  hora_estimada_llegada   TIMESTAMPTZ,
  hora_llegada_real       TIMESTAMPTZ,
  hora_salida_real        TIMESTAMPTZ,
  nodo_origen             VARCHAR(10) NOT NULL,
  PRIMARY KEY (region_codigo, id_parada),
  CONSTRAINT uq_parada_region_ruta_pedido UNIQUE (region_codigo, id_ruta, id_pedido),
  CONSTRAINT uq_parada_region_ruta_orden UNIQUE (region_codigo, id_ruta, orden_visita),
  CONSTRAINT fk_parada_ruta
    FOREIGN KEY (region_codigo, id_ruta)
    REFERENCES ruta_reparto(region_codigo, id_ruta)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_parada_pedido
    FOREIGN KEY (region_codigo, id_pedido)
    REFERENCES pedido(region_codigo, id_pedido)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_parada_nodo_origen CHECK (nodo_origen = region_codigo)
);

-- =========================
-- Nodo de AUDITORÍA (sin FK físicas entre nodos)
-- =========================
CREATE TABLE bitacora_evento (
  id_evento          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  region_codigo      VARCHAR(10),
  fecha_hora         TIMESTAMPTZ NOT NULL DEFAULT now(),
  tipo_evento        VARCHAR(50) NOT NULL,
  tabla_afectada     VARCHAR(64),
  id_registro        UUID,
  descripcion        TEXT,
  datos_adicionales  JSONB,
  id_usuario         UUID,
  nodo_origen        VARCHAR(10)
);

COMMENT ON TABLE bitacora_evento IS 'Log append-only; id_usuario es referencia lógica (sin FK entre nodos).';

-- =========================
-- Transacciones distribuidas (patrón Saga)
-- =========================
CREATE TABLE saga_transaccion (
  id_saga            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo_operacion     VARCHAR(50) NOT NULL,
  region_codigo      VARCHAR(10) NOT NULL REFERENCES nodo_registro(region_codigo),
  estado             VARCHAR(20) NOT NULL DEFAULT 'INICIADA'
                     CHECK (estado IN ('INICIADA','COMPLETADA','COMPENSANDO','FALLIDA')),
  id_pedido          UUID,
  payload            JSONB,
  fecha_creacion     TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_finalizacion TIMESTAMPTZ
);

COMMENT ON TABLE saga_transaccion IS 'Coordina operaciones que cruzan servicios/nodos (ej. crear pedido + reservar stock + pago).';

CREATE TABLE saga_paso (
  id_paso            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_saga            UUID NOT NULL REFERENCES saga_transaccion(id_saga) ON DELETE CASCADE,
  orden_paso         SMALLINT NOT NULL CHECK (orden_paso > 0),
  nombre_paso        VARCHAR(80) NOT NULL,
  estado             VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE'
                     CHECK (estado IN ('PENDIENTE','OK','ERROR','COMPENSADO')),
  nodo_ejecutor      VARCHAR(10),
  detalle            JSONB,
  fecha_ejecucion    TIMESTAMPTZ,
  CONSTRAINT uq_saga_orden UNIQUE (id_saga, orden_paso)
);

COMMENT ON TABLE saga_paso IS 'Pasos de una saga: reservar_stock → crear_pedido → registrar_pago → confirmar.';

-- =========================
-- Índices
-- =========================
CREATE INDEX idx_catalogo_maestro_tipo ON catalogo_maestro (tipo_catalogo) WHERE activo = TRUE;
CREATE INDEX idx_persona_region ON persona (region_codigo);
CREATE INDEX idx_persona_region_tipo ON persona (region_codigo, id_tipo_persona);
CREATE INDEX idx_persona_region_documento ON persona (region_codigo, id_tipo_documento);
CREATE INDEX idx_usuario_region_rol ON usuario (region_codigo, id_rol) WHERE cuenta_activa = TRUE;
CREATE INDEX idx_comercio_region ON comercio (region_codigo) WHERE activo = TRUE;
CREATE INDEX idx_proveedor_persona ON proveedor (region_codigo, id_persona);
CREATE INDEX idx_producto_region_comercio ON producto (region_codigo, id_comercio);
CREATE INDEX idx_pedido_region_cliente ON pedido (region_codigo, id_cliente);
CREATE INDEX idx_pedido_region_estado ON pedido (region_codigo, id_estado_pedido);
CREATE INDEX idx_detalle_region_pedido ON detalle_pedido (region_codigo, id_pedido);
CREATE INDEX idx_pago_region_estado ON pago (region_codigo, id_estado_pago);
CREATE INDEX idx_ruta_region_repartidor ON ruta_reparto (region_codigo, id_repartidor, fecha_planificacion);
CREATE INDEX idx_parada_region_ruta ON parada_ruta (region_codigo, id_ruta);
CREATE INDEX idx_bitacora_fecha ON bitacora_evento (fecha_hora);
CREATE INDEX idx_bitacora_region ON bitacora_evento (region_codigo);
CREATE INDEX idx_saga_region_estado ON saga_transaccion (region_codigo, estado);

-- Unicidad por región (no global)
CREATE UNIQUE INDEX uq_persona_region_correo_lower
  ON persona (region_codigo, lower(correo))
  WHERE correo IS NOT NULL;

CREATE UNIQUE INDEX uq_usuario_region_nombre_acceso_lower
  ON usuario (region_codigo, lower(nombre_acceso));

CREATE UNIQUE INDEX uq_comercio_region_correo_lower
  ON comercio (region_codigo, lower(correo))
  WHERE correo IS NOT NULL;

-- =========================
-- Vista de resumen de fragmentación
-- =========================
CREATE OR REPLACE VIEW v_resumen_fragmentacion AS
SELECT
  r.tabla,
  r.clave_fragmento,
  r.criterio,
  n.nombre_nodo AS nodo_ejemplo
FROM regla_fragmentacion r
LEFT JOIN nodo_registro n ON n.region_codigo = r.nodo_ejemplo
ORDER BY r.id_regla;

COMMENT ON VIEW v_resumen_fragmentacion IS 'Resumen de cómo se distribuye cada tabla en el sistema.';
