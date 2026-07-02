-- =========================================================
-- Fragmentación horizontal + réplica — esquema PostgreSQL por nodo
-- Carpeta: 3. fragmentacion  |  Orden: PASO 3
--
-- SCRIPT ÚNICO (v3 consolidado — incluye checklist 40 ítems):
--   • Sin fragmentación vertical en persona (tabla unificada)
--   • Pedido y bitácora unificados con partición RANGE por fecha
--   • Réplica incremental fila a fila (cola + LWW + conflictos)
--   • Fragmentación derivada vía tabla padre (detalle, pago, parada, saga_paso)
--   • FK compuestas en tablas particionadas (fecha_creacion_pedido)
--   • Heartbeat timeout, DR, recuperación desde réplica, simulaciones
--   • Vistas admin/monitoreo, validación profunda, benchmark, métricas
--
-- DEPENDE DE:
--   1. esquema/1. delivery_db_distribuida.sql
--   2. datos-semilla/2. delivery_db_distribuida_seed.sql
--
-- Ejecución:
--   psql -d delivery_db_distribuida -f "3. fragmentacion/3. delivery_db_fragmentacion_hv.sql"
--
-- LIMITACIÓN: los nodos se simulan con esquemas en UNA instancia PostgreSQL.
-- En producción cada nodo sería un servidor independiente (ver documentación).
-- =========================================================

DROP TRIGGER IF EXISTS tg_replica_catalogo_maestro ON public.catalogo_maestro;
DROP TRIGGER IF EXISTS tg_replica_nodo_registro ON public.nodo_registro;
DROP TRIGGER IF EXISTS tg_replica_regla_fragmentacion ON public.regla_fragmentacion;
DO $$ DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['persona','usuario','cliente','comercio','pedido','detalle_pedido','pago','bitacora_evento','parada_ruta','saga_paso'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS tg_frag_%s ON public.%I', t, t);
  END LOOP;
END $$;
DROP SCHEMA IF EXISTS frag CASCADE;
DROP SCHEMA IF EXISTS nodo_global CASCADE;
DROP SCHEMA IF EXISTS nodo_lim_n CASCADE;
DROP SCHEMA IF EXISTS nodo_lim_s CASCADE;
DROP SCHEMA IF EXISTS nodo_aqp CASCADE;

CREATE SCHEMA frag;
CREATE SCHEMA nodo_global;
SET search_path TO frag, public;

-- =========================================================
-- 1. METADATOS: MATRIZ, MAPA, FRAGMENTACIÓN DERIVADA
-- =========================================================
CREATE TABLE matriz_fragmentacion (
  id                    SERIAL PRIMARY KEY,
  tabla_logica          VARCHAR(64) NOT NULL UNIQUE,
  replicar              BOOLEAN NOT NULL DEFAULT FALSE,
  frag_horizontal       BOOLEAN NOT NULL DEFAULT FALSE,
  frag_vertical         BOOLEAN NOT NULL DEFAULT FALSE,
  frag_derivada         BOOLEAN NOT NULL DEFAULT FALSE,
  estrategia            VARCHAR(40) NOT NULL,
  clave_horizontal      VARCHAR(80),
  criterio_decision     TEXT NOT NULL,
  motivo                TEXT NOT NULL,
  nodo_ejemplo          VARCHAR(10)
);

INSERT INTO matriz_fragmentacion
  (tabla_logica, replicar, frag_horizontal, frag_vertical, frag_derivada, estrategia,
   clave_horizontal, criterio_decision, motivo, nodo_ejemplo) VALUES
  ('catalogo_maestro', TRUE,  FALSE, FALSE, FALSE, 'REPLICA_COMPLETA',
   NULL, 'Lectura frecuente, baja escritura, datos de referencia globales.',
   'Catálogos de consulta frecuente y poco cambio; se replican en todos los nodos.', 'GLOBAL'),
  ('nodo_registro', TRUE,  FALSE, FALSE, FALSE, 'REPLICA_COMPLETA',
   NULL, 'Metadatos del clúster necesarios en cada nodo para enrutamiento.',
   'Metadatos pequeños utilizados por todos los nodos.', 'GLOBAL'),
  ('regla_fragmentacion', TRUE,  FALSE, FALSE, FALSE, 'REPLICA_COMPLETA',
   NULL, 'Documentación de reglas de fragmentación accesible localmente.',
   'Configuración/documentación global.', 'GLOBAL'),
  ('persona', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Co-ubicación por región de residencia; pocas columnas — sin split vertical.',
   'Cada persona pertenece a una región.', 'LIM-N'),
  ('usuario', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Acceso y autenticación local por región.',
   'Acceso local por región.', 'LIM-N'),
  ('cliente', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Datos de clientes vinculados a usuarios regionales.',
   'Información regional.', 'LIM-N'),
  ('repartidor', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Operación de reparto limitada a una región.',
   'Opera únicamente en una región.', 'LIM-S'),
  ('comercio', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Comercios físicamente ubicados en una región.',
   'Pertenece a una región específica.', 'LIM-N'),
  ('proveedor', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Proveedores asociados a comercios regionales.',
   'Relacionado con comercios regionales.', 'LIM-N'),
  ('comercio_proveedor', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Asociación local comercio-proveedor.',
   'Asociación local entre comercios y proveedores.', 'LIM-N'),
  ('categoria_producto', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Catálogo de menú por comercio regional.',
   'Asociada a un comercio regional.', 'LIM-N'),
  ('producto', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Consultas de menú junto al comercio local.',
   'Se consulta junto con el comercio local.', 'LIM-N'),
  ('pedido', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL+PARTICION',
   'esquema regional + RANGE(fecha_creacion)',
   'Tabla unificada particionada; consultas típicas requieren todas las columnas.',
   'Mayor crecimiento; partición por fecha sin duplicar fh_pedido.', 'LIM-N'),
  ('detalle_pedido', FALSE, TRUE,  FALSE, TRUE,  'HORIZONTAL_DERIVADA',
   'hereda fragmento de pedido',
   'Misma región y nodo que su pedido padre (sin clave propia de región en réplica).',
   'Debe permanecer junto al pedido.', 'LIM-N'),
  ('pago', FALSE, TRUE,  FALSE, TRUE,  'HORIZONTAL_DERIVADA',
   'hereda fragmento de pedido',
   'Co-ubicado con el pedido al que pertenece.',
   'Ligado directamente al pedido.', 'LIM-N'),
  ('ruta_reparto', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL',
   'region_codigo → esquema nodo_*',
   'Planificación de rutas por región.',
   'Operación regional de reparto.', 'LIM-S'),
  ('parada_ruta', FALSE, TRUE,  FALSE, TRUE,  'HORIZONTAL_DERIVADA',
   'hereda fragmento de ruta_reparto',
   'Sigue la ruta regional del repartidor.',
   'Depende de la ruta local.', 'LIM-S'),
  ('bitacora_evento', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL+PARTICION',
   'esquema regional + RANGE(fecha_hora)',
   'Alto volumen append-only; partición directa sobre tabla principal.',
   'Gran volumen; partición por fecha y región.', 'LIM-N'),
  ('saga_transaccion', FALSE, TRUE,  FALSE, FALSE, 'HORIZONTAL+REPLICA_PARCIAL',
   'region_codigo → esquema nodo_*',
   'Ejecución local; solo estado replicado a nodo_global para monitoreo.',
   'Ejecución local; réplica parcial de estado para monitoreo.', 'LIM-N'),
  ('saga_paso', FALSE, TRUE,  FALSE, TRUE,  'HORIZONTAL_DERIVADA',
   'vía id_saga en nodo regional',
   'Pasos co-ubicados con su saga padre.',
   'Sigue la distribución de la saga.', 'LIM-N');

COMMENT ON TABLE matriz_fragmentacion IS
  'Decisiones de diseño: réplica vs horizontal vs derivada. Ver 0. documentacion/6. mejoras_distribuida.txt';

CREATE TABLE fragmentacion_derivada (
  id                SERIAL PRIMARY KEY,
  tabla_hija        VARCHAR(64) NOT NULL UNIQUE,
  tabla_padre       VARCHAR(64) NOT NULL,
  clave_enlace      VARCHAR(80) NOT NULL,
  descripcion       TEXT NOT NULL
);

INSERT INTO fragmentacion_derivada (tabla_hija, tabla_padre, clave_enlace, descripcion) VALUES
  ('detalle_pedido', 'pedido',       'id_pedido',  'Líneas de pedido en el mismo nodo que el pedido.'),
  ('pago',           'pedido',       'id_pedido',  'Pago en el mismo nodo que el pedido.'),
  ('parada_ruta',    'ruta_reparto', 'id_ruta',    'Paradas en el mismo nodo que la ruta.'),
  ('saga_paso',      'saga_transaccion', 'id_saga','Pasos en el mismo nodo que la saga.');

CREATE TABLE mapa_nodos (
  region_codigo  VARCHAR(10) PRIMARY KEY,
  esquema_pg     VARCHAR(63) NOT NULL UNIQUE,
  nombre_nodo    VARCHAR(80) NOT NULL,
  es_primario    BOOLEAN NOT NULL DEFAULT FALSE,
  activo         BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO mapa_nodos (region_codigo, esquema_pg, nombre_nodo, es_primario) VALUES
  ('GLOBAL', 'nodo_global', 'Nodo central — primario catálogos', TRUE),
  ('LIM-N',  'nodo_lim_n',  'Lima Norte',  FALSE),
  ('LIM-S',  'nodo_lim_s',  'Lima Sur',    FALSE),
  ('AQP',    'nodo_aqp',    'Arequipa',    FALSE);

-- Heartbeat / monitoreo de nodos
CREATE TABLE nodo_heartbeat (
  region_codigo         VARCHAR(10) PRIMARY KEY REFERENCES mapa_nodos(region_codigo),
  esquema_pg            VARCHAR(63) NOT NULL,
  estado                VARCHAR(20) NOT NULL DEFAULT 'ONLINE'
                        CHECK (estado IN ('ONLINE','OFFLINE','DEGRADADO','MANTENIMIENTO')),
  disponible            BOOLEAN NOT NULL DEFAULT TRUE,
  ultima_conexion       TIMESTAMPTZ NOT NULL DEFAULT now(),
  tiempo_respuesta_ms   INTEGER,
  ultimo_error          TEXT,
  registrado_en         TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO nodo_heartbeat (region_codigo, esquema_pg, estado, disponible, tiempo_respuesta_ms)
SELECT region_codigo, esquema_pg, 'ONLINE', activo, 5 FROM mapa_nodos;

-- Control de réplica ampliado
CREATE TABLE replica_control (
  id_replica            SERIAL PRIMARY KEY,
  tabla_logica          VARCHAR(64) NOT NULL,
  esquema_destino       VARCHAR(63) NOT NULL REFERENCES mapa_nodos(esquema_pg),
  region_destino        VARCHAR(10) NOT NULL REFERENCES mapa_nodos(region_codigo),
  rol_replica           VARCHAR(20) NOT NULL CHECK (rol_replica IN ('PRIMARIO','SECUNDARIO')),
  tipo_replicacion      VARCHAR(20) NOT NULL DEFAULT 'ASINCRONA'
                        CHECK (tipo_replicacion IN ('SINCRONA','ASINCRONA','SEMISINCRONA')),
  ultima_sync           TIMESTAMPTZ,
  duracion_sync_ms      INTEGER,
  filas_sincronizadas   INTEGER NOT NULL DEFAULT 0,
  filas_insertadas      INTEGER NOT NULL DEFAULT 0,
  filas_actualizadas    INTEGER NOT NULL DEFAULT 0,
  filas_eliminadas      INTEGER NOT NULL DEFAULT 0,
  cantidad_errores      INTEGER NOT NULL DEFAULT 0,
  ultimo_mensaje_error  TEXT,
  en_sync               BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (tabla_logica, esquema_destino)
);

INSERT INTO replica_control (tabla_logica, esquema_destino, region_destino, rol_replica, tipo_replicacion) VALUES
  ('catalogo_maestro',    'nodo_global', 'GLOBAL', 'PRIMARIO',   'SINCRONA'),
  ('catalogo_maestro',    'nodo_lim_n',  'LIM-N',  'SECUNDARIO', 'ASINCRONA'),
  ('catalogo_maestro',    'nodo_lim_s',  'LIM-S',  'SECUNDARIO', 'ASINCRONA'),
  ('catalogo_maestro',    'nodo_aqp',    'AQP',    'SECUNDARIO', 'ASINCRONA'),
  ('nodo_registro',       'nodo_global', 'GLOBAL', 'PRIMARIO',   'SINCRONA'),
  ('nodo_registro',       'nodo_lim_n',  'LIM-N',  'SECUNDARIO', 'ASINCRONA'),
  ('nodo_registro',       'nodo_lim_s',  'LIM-S',  'SECUNDARIO', 'ASINCRONA'),
  ('nodo_registro',       'nodo_aqp',    'AQP',    'SECUNDARIO', 'ASINCRONA'),
  ('regla_fragmentacion', 'nodo_global', 'GLOBAL', 'PRIMARIO',   'SINCRONA'),
  ('regla_fragmentacion', 'nodo_lim_n',  'LIM-N',  'SECUNDARIO', 'ASINCRONA'),
  ('regla_fragmentacion', 'nodo_lim_s',  'LIM-S',  'SECUNDARIO', 'ASINCRONA'),
  ('regla_fragmentacion', 'nodo_aqp',    'AQP',    'SECUNDARIO', 'ASINCRONA');

-- Cola de cambios para réplica incremental
CREATE TABLE replica_cambios (
  id_cambio       BIGSERIAL PRIMARY KEY,
  tabla_logica    VARCHAR(64) NOT NULL,
  operacion       CHAR(1) NOT NULL CHECK (operacion IN ('I','U','D')),
  id_registro     TEXT NOT NULL,
  version_origen  TIMESTAMPTZ NOT NULL DEFAULT now(),
  payload         JSONB,
  fecha_cambio    TIMESTAMPTZ NOT NULL DEFAULT now(),
  procesado       BOOLEAN NOT NULL DEFAULT FALSE,
  procesado_en    TIMESTAMPTZ
);

CREATE INDEX idx_replica_cambios_pendiente ON replica_cambios (tabla_logica, procesado, fecha_cambio);

-- Auditoría del clúster
CREATE TABLE auditoria_cluster (
  id_evento       BIGSERIAL PRIMARY KEY,
  tipo_evento     VARCHAR(40) NOT NULL,
  region_codigo   VARCHAR(10),
  esquema_pg      VARCHAR(63),
  detalle         TEXT NOT NULL,
  duracion_ms     INTEGER,
  exito           BOOLEAN NOT NULL DEFAULT TRUE,
  usuario         TEXT DEFAULT current_user,
  sesion_pid      INT DEFAULT pg_backend_pid(),
  host            TEXT DEFAULT inet_client_addr()::TEXT,
  txid            BIGINT DEFAULT txid_current(),
  registrado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tablas de soporte (checklist + v3)
CREATE TABLE config_cluster (
  clave VARCHAR(64) PRIMARY KEY, valor TEXT NOT NULL, descripcion TEXT
);

INSERT INTO config_cluster (clave, valor, descripcion) VALUES
  ('retencion_particiones_meses', '12', 'Meses de retención antes de purgar particiones'),
  ('replica_cambios_retencion_dias', '30', 'Días antes de limpiar cola replica_cambios'),
  ('fragmento_cambios_retencion_dias', '30', 'Días antes de limpiar cola fragmento_cambios'),
  ('sync_lock_timeout_ms', '5000', 'Timeout advisory lock sincronización'),
  ('heartbeat_timeout_seg', '120', 'Segundos sin conexión para marcar nodo OFFLINE'),
  ('estrategia_conflicto', 'LWW', 'Last Write Wins por version_origen');

CREATE TABLE fragmento_cambios (
  id_cambio BIGSERIAL PRIMARY KEY,
  tabla_logica VARCHAR(64) NOT NULL,
  region_codigo VARCHAR(10) NOT NULL,
  operacion CHAR(1) NOT NULL CHECK (operacion IN ('I','U','D')),
  id_registro TEXT NOT NULL,
  version_origen TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_cambio TIMESTAMPTZ NOT NULL DEFAULT now(),
  procesado BOOLEAN NOT NULL DEFAULT FALSE,
  procesado_en TIMESTAMPTZ
);

CREATE INDEX idx_fragmento_cambios_pend ON fragmento_cambios (procesado, region_codigo, tabla_logica);

CREATE TABLE replica_conflictos (
  id_conflicto BIGSERIAL PRIMARY KEY,
  tabla_logica VARCHAR(64) NOT NULL,
  esquema_destino VARCHAR(63) NOT NULL,
  id_registro TEXT NOT NULL,
  valor_primario JSONB,
  valor_replica JSONB,
  resuelto BOOLEAN NOT NULL DEFAULT FALSE,
  detectado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  resuelto_en TIMESTAMPTZ
);

CREATE TABLE migracion_metricas (
  id_metrica BIGSERIAL PRIMARY KEY,
  region_codigo VARCHAR(10) NOT NULL,
  esquema_pg VARCHAR(63) NOT NULL,
  entidad VARCHAR(64) NOT NULL,
  filas_migradas BIGINT NOT NULL DEFAULT 0,
  errores INTEGER NOT NULL DEFAULT 0,
  duracion_ms INTEGER,
  registrado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE metricas_espacio_nodo (
  id_medicion BIGSERIAL PRIMARY KEY,
  esquema_pg VARCHAR(63) NOT NULL,
  region_codigo VARCHAR(10),
  tamano_bytes BIGINT NOT NULL,
  medicion_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE metricas_crecimiento (
  id_medicion BIGSERIAL PRIMARY KEY,
  esquema_pg VARCHAR(63) NOT NULL,
  tabla_logica VARCHAR(64) NOT NULL,
  filas BIGINT NOT NULL,
  tamano_bytes BIGINT,
  medicion_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE metricas_consulta (
  id_benchmark BIGSERIAL PRIMARY KEY,
  nombre_consulta VARCHAR(80) NOT NULL,
  origen VARCHAR(20) NOT NULL,
  esquema_pg VARCHAR(63),
  duracion_ms NUMERIC(12,3) NOT NULL,
  filas_resultado BIGINT,
  plan_resumen TEXT,
  ejecutado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE metricas_rendimiento_sync (
  id BIGSERIAL PRIMARY KEY,
  operacion VARCHAR(40) NOT NULL,
  registros_procesados BIGINT NOT NULL,
  duracion_ms INTEGER NOT NULL,
  registros_por_seg NUMERIC(12,2),
  nodo TEXT,
  registrado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bitacora_recuperacion_dr (
  id_evento BIGSERIAL PRIMARY KEY,
  tipo_evento VARCHAR(40) NOT NULL,
  region_codigo VARCHAR(10),
  esquema_pg VARCHAR(63),
  detalle TEXT NOT NULL,
  duracion_ms INTEGER,
  exito BOOLEAN NOT NULL DEFAULT TRUE,
  registrado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- 2. VALIDAR PASOS 1 Y 2 + NODO GLOBAL
-- =========================================================
DO $$
BEGIN
  IF to_regclass('public.persona') IS NULL THEN
    RAISE EXCEPTION 'Falta PASO 1. Ejecutar: 1. esquema/1. delivery_db_distribuida.sql';
  END IF;
  IF (SELECT COUNT(*) FROM public.persona) = 0 THEN
    RAISE EXCEPTION 'Falta PASO 2. Ejecutar: 2. datos-semilla/2. delivery_db_distribuida_seed.sql';
  END IF;
END $$;

CREATE TABLE nodo_global.catalogo_maestro (
  id_catalogo        UUID PRIMARY KEY,
  tipo_catalogo      VARCHAR(40) NOT NULL,
  codigo             VARCHAR(40) NOT NULL,
  nombre             VARCHAR(120) NOT NULL,
  descripcion        TEXT,
  orden_presentacion SMALLINT,
  activo             BOOLEAN NOT NULL,
  sincronizado_en    TIMESTAMPTZ NOT NULL DEFAULT now(),
  version_registro   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tipo_catalogo, codigo)
);

CREATE TABLE nodo_global.nodo_registro (
  region_codigo    VARCHAR(10) PRIMARY KEY,
  nombre_nodo      VARCHAR(80) NOT NULL,
  activo           BOOLEAN NOT NULL,
  es_nodo_global   BOOLEAN NOT NULL,
  sincronizado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE nodo_global.regla_fragmentacion (
  id_regla         INTEGER PRIMARY KEY,
  nombre_tabla     VARCHAR(64) NOT NULL,
  clave_fragmento  VARCHAR(40) NOT NULL,
  criterio         TEXT NOT NULL,
  nodo_ejemplo     VARCHAR(10),
  sincronizado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE nodo_global.saga_monitoreo (
  id_saga            UUID PRIMARY KEY,
  region_codigo      VARCHAR(10) NOT NULL,
  tipo_operacion     VARCHAR(50) NOT NULL,
  estado             VARCHAR(20) NOT NULL,
  id_pedido          UUID,
  fecha_creacion     TIMESTAMPTZ NOT NULL,
  fecha_finalizacion TIMESTAMPTZ,
  sincronizado_en    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE nodo_global.resumen_pedidos_region (
  region_codigo   VARCHAR(10) PRIMARY KEY,
  total_pedidos   BIGINT NOT NULL DEFAULT 0,
  monto_total     NUMERIC(14,2) NOT NULL DEFAULT 0,
  ultimo_pedido   TIMESTAMPTZ,
  sincronizado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- 3. ESTRUCTURA REGIONAL (sin vertical en persona; pedido/bitácora unificados)
-- =========================================================
CREATE OR REPLACE FUNCTION frag.crear_estructura_nodo_regional(p_esquema TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', p_esquema);

  EXECUTE format($q$
    CREATE TABLE %1$I.catalogo_maestro (
      id_catalogo UUID PRIMARY KEY, tipo_catalogo VARCHAR(40) NOT NULL,
      codigo VARCHAR(40) NOT NULL, nombre VARCHAR(120) NOT NULL,
      descripcion TEXT, orden_presentacion SMALLINT, activo BOOLEAN NOT NULL,
      replicado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
      version_registro TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (tipo_catalogo, codigo)
    );
    CREATE TABLE %1$I.nodo_registro (
      region_codigo VARCHAR(10) PRIMARY KEY, nombre_nodo VARCHAR(80) NOT NULL,
      activo BOOLEAN NOT NULL, es_nodo_global BOOLEAN NOT NULL,
      replicado_en TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE %1$I.regla_fragmentacion (
      id_regla INTEGER PRIMARY KEY, nombre_tabla VARCHAR(64) NOT NULL,
      clave_fragmento VARCHAR(40) NOT NULL, criterio TEXT NOT NULL,
      nodo_ejemplo VARCHAR(10), replicado_en TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE %1$I.persona (
      id_persona UUID PRIMARY KEY,
      id_tipo_persona UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      id_tipo_documento UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      numero_documento VARCHAR(20) NOT NULL, nombres VARCHAR(120), apellidos VARCHAR(120),
      razon_social VARCHAR(200), correo TEXT, telefono VARCHAR(30),
      fecha_nacimiento DATE, direccion TEXT, activo BOOLEAN NOT NULL DEFAULT TRUE,
      fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now(),
      fecha_modificacion TIMESTAMPTZ NOT NULL DEFAULT now(),
      region_codigo VARCHAR(10) NOT NULL,
      version_registro TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (id_tipo_documento, numero_documento)
    );
    CREATE TABLE %1$I.usuario (
      id_usuario UUID PRIMARY KEY, id_persona UUID NOT NULL UNIQUE REFERENCES %1$I.persona(id_persona),
      id_rol UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      nombre_acceso TEXT NOT NULL, contrasena_hash TEXT NOT NULL,
      cuenta_activa BOOLEAN NOT NULL DEFAULT TRUE, correo_verificado BOOLEAN NOT NULL DEFAULT FALSE,
      telefono_verificado BOOLEAN NOT NULL DEFAULT FALSE, fecha_registro TIMESTAMPTZ NOT NULL DEFAULT now(),
      fecha_ultimo_acceso TIMESTAMPTZ, intentos_fallidos SMALLINT NOT NULL DEFAULT 0,
      bloqueado_hasta TIMESTAMPTZ
    );
    CREATE TABLE %1$I.cliente (
      id_cliente UUID PRIMARY KEY, id_usuario UUID NOT NULL UNIQUE REFERENCES %1$I.usuario(id_usuario),
      fecha_alta_cliente TIMESTAMPTZ NOT NULL DEFAULT now(),
      id_preferencia_notificacion UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      acepta_publicidad BOOLEAN NOT NULL DEFAULT FALSE, idioma_preferido VARCHAR(10) NOT NULL DEFAULT 'es',
      moneda_preferida VARCHAR(3) NOT NULL DEFAULT 'PEN', notas TEXT
    );
    CREATE TABLE %1$I.repartidor (
      id_repartidor UUID PRIMARY KEY, id_persona UUID NOT NULL UNIQUE REFERENCES %1$I.persona(id_persona),
      id_usuario UUID UNIQUE REFERENCES %1$I.usuario(id_usuario),
      id_tipo_vehiculo UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      placa VARCHAR(15), disponible BOOLEAN NOT NULL DEFAULT TRUE
    );
    CREATE TABLE %1$I.comercio (
      id_comercio UUID PRIMARY KEY, nombre VARCHAR(160) NOT NULL, ruc VARCHAR(20),
      telefono VARCHAR(30), correo TEXT, direccion TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT TRUE
    );
    CREATE TABLE %1$I.proveedor (
      id_proveedor UUID PRIMARY KEY, id_persona UUID NOT NULL UNIQUE REFERENCES %1$I.persona(id_persona),
      activo BOOLEAN NOT NULL DEFAULT TRUE, notas TEXT
    );
    CREATE TABLE %1$I.comercio_proveedor (
      id_comercio UUID NOT NULL REFERENCES %1$I.comercio(id_comercio) ON DELETE CASCADE,
      id_proveedor UUID NOT NULL REFERENCES %1$I.proveedor(id_proveedor) ON DELETE CASCADE,
      notas TEXT, fecha_alta TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (id_comercio, id_proveedor)
    );
    CREATE TABLE %1$I.categoria_producto (
      id_categoria UUID PRIMARY KEY, id_comercio UUID NOT NULL REFERENCES %1$I.comercio(id_comercio) ON DELETE CASCADE,
      nombre VARCHAR(120) NOT NULL, UNIQUE (id_comercio, nombre)
    );
    CREATE TABLE %1$I.producto (
      id_producto UUID PRIMARY KEY, id_comercio UUID NOT NULL REFERENCES %1$I.comercio(id_comercio) ON DELETE CASCADE,
      id_categoria UUID REFERENCES %1$I.categoria_producto(id_categoria) ON DELETE SET NULL,
      nombre VARCHAR(160) NOT NULL, descripcion TEXT,
      precio NUMERIC(12,2) NOT NULL CHECK (precio >= 0), disponible BOOLEAN NOT NULL DEFAULT TRUE
    );
    CREATE TABLE %1$I.pedido (
      id_pedido UUID NOT NULL, id_cliente UUID NOT NULL, id_comercio UUID NOT NULL,
      id_repartidor UUID, id_estado_pedido UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      nombre_cliente VARCHAR(240) NOT NULL, nombre_comercio VARCHAR(160) NOT NULL,
      direccion_entrega TEXT NOT NULL, referencia_entrega TEXT,
      subtotal NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
      costo_envio NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (costo_envio >= 0),
      total NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
      fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now(),
      fecha_confirmacion TIMESTAMPTZ, fecha_entrega_real TIMESTAMPTZ,
      PRIMARY KEY (id_pedido, fecha_creacion)
    ) PARTITION BY RANGE (fecha_creacion);
    CREATE TABLE %1$I.pedido_default PARTITION OF %1$I.pedido DEFAULT;
    CREATE TABLE %1$I.detalle_pedido (
      id_detalle_pedido UUID PRIMARY KEY, id_pedido UUID NOT NULL,
      id_producto UUID NOT NULL REFERENCES %1$I.producto(id_producto),
      nombre_producto VARCHAR(160) NOT NULL, cantidad INTEGER NOT NULL CHECK (cantidad > 0),
      precio_unitario NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
      importe_linea NUMERIC(12,2) NOT NULL CHECK (importe_linea >= 0),
      fecha_creacion_pedido TIMESTAMPTZ NOT NULL,
      UNIQUE (id_pedido, id_producto)
    );
    CREATE TABLE %1$I.pago (
      id_pago UUID PRIMARY KEY, id_pedido UUID NOT NULL UNIQUE,
      id_metodo_pago UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      id_estado_pago UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      monto NUMERIC(12,2) NOT NULL CHECK (monto >= 0), fecha_pago TIMESTAMPTZ,
      fecha_creacion_pedido TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE %1$I.ruta_reparto (
      id_ruta UUID PRIMARY KEY, id_repartidor UUID NOT NULL REFERENCES %1$I.repartidor(id_repartidor),
      fecha_planificacion DATE NOT NULL,
      id_estado_ruta UUID NOT NULL REFERENCES %1$I.catalogo_maestro(id_catalogo),
      hora_inicio_real TIMESTAMPTZ, hora_fin_real TIMESTAMPTZ,
      distancia_kilometros NUMERIC(10,2), observaciones TEXT,
      fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE %1$I.parada_ruta (
      id_parada UUID PRIMARY KEY, id_ruta UUID NOT NULL REFERENCES %1$I.ruta_reparto(id_ruta) ON DELETE CASCADE,
      id_pedido UUID NOT NULL, orden_visita INTEGER NOT NULL CHECK (orden_visita > 0),
      hora_estimada_llegada TIMESTAMPTZ, hora_llegada_real TIMESTAMPTZ, hora_salida_real TIMESTAMPTZ,
      fecha_creacion_pedido TIMESTAMPTZ,
      UNIQUE (id_ruta, id_pedido), UNIQUE (id_ruta, orden_visita)
    );
    CREATE TABLE %1$I.bitacora_evento (
      id_evento UUID NOT NULL, fecha_hora TIMESTAMPTZ NOT NULL DEFAULT now(),
      tipo_evento VARCHAR(50) NOT NULL, tabla_afectada VARCHAR(64), id_registro UUID,
      descripcion TEXT, datos_adicionales JSONB, id_usuario UUID, nodo_origen VARCHAR(10),
      PRIMARY KEY (id_evento, fecha_hora)
    ) PARTITION BY RANGE (fecha_hora);
    CREATE TABLE %1$I.bitacora_evento_default PARTITION OF %1$I.bitacora_evento DEFAULT;
    CREATE TABLE %1$I.saga_transaccion (
      id_saga UUID PRIMARY KEY, tipo_operacion VARCHAR(50) NOT NULL, estado VARCHAR(20) NOT NULL,
      id_pedido UUID, payload JSONB, fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now(),
      fecha_finalizacion TIMESTAMPTZ
    );
    CREATE TABLE %1$I.saga_paso (
      id_paso UUID PRIMARY KEY, id_saga UUID NOT NULL REFERENCES %1$I.saga_transaccion(id_saga) ON DELETE CASCADE,
      orden_paso SMALLINT NOT NULL CHECK (orden_paso > 0), nombre_paso VARCHAR(80) NOT NULL,
      estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE', nodo_ejecutor VARCHAR(10),
      detalle JSONB, fecha_ejecucion TIMESTAMPTZ, UNIQUE (id_saga, orden_paso)
    );
  $q$, p_esquema);

  PERFORM frag.crear_indices_nodo_regional(p_esquema);
END;
$$;

CREATE OR REPLACE FUNCTION frag.crear_indices_nodo_regional(p_esquema TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_persona_correo ON %1$I.persona (lower(correo))', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_usuario_persona ON %1$I.usuario (id_persona)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_cliente_usuario ON %1$I.cliente (id_usuario)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_comercio_activo ON %1$I.comercio (activo) WHERE activo', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_producto_comercio ON %1$I.producto (id_comercio)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_pedido_cliente ON %1$I.pedido (id_cliente)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_pedido_comercio ON %1$I.pedido (id_comercio)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_pedido_fecha ON %1$I.pedido (fecha_creacion)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_detalle_pedido ON %1$I.detalle_pedido (id_pedido)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_pago_pedido ON %1$I.pago (id_pedido)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_bitacora_fecha ON %1$I.bitacora_evento (fecha_hora)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_saga_estado ON %1$I.saga_transaccion (estado)', p_esquema);
END;
$$;

CREATE OR REPLACE FUNCTION frag.crear_particiones_mensuales(
  p_esquema TEXT, p_tabla TEXT, p_meses_adelante INT DEFAULT 3
) RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_mes DATE := date_trunc('month', CURRENT_DATE)::DATE;
  v_fin DATE;
  v_part TEXT;
  v_creadas INT := 0;
  i INT;
BEGIN
  FOR i IN 0..p_meses_adelante LOOP
    v_fin := (v_mes + INTERVAL '1 month')::DATE;
    v_part := format('%s_%s', p_tabla, to_char(v_mes, 'YYYY_MM'));
    BEGIN
      EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
        p_esquema, v_part, p_esquema, p_tabla, v_mes, v_fin);
      v_creadas := v_creadas + 1;
    EXCEPTION WHEN duplicate_table THEN NULL;
    END;
    v_mes := v_fin;
  END LOOP;
  RETURN v_creadas;
END;
$$;

SELECT frag.crear_estructura_nodo_regional('nodo_lim_n');
SELECT frag.crear_estructura_nodo_regional('nodo_lim_s');
SELECT frag.crear_estructura_nodo_regional('nodo_aqp');
SELECT frag.crear_particiones_mensuales('nodo_lim_n', 'pedido');
SELECT frag.crear_particiones_mensuales('nodo_lim_s', 'pedido');
SELECT frag.crear_particiones_mensuales('nodo_aqp', 'pedido');
SELECT frag.crear_particiones_mensuales('nodo_lim_n', 'bitacora_evento');
SELECT frag.crear_particiones_mensuales('nodo_lim_s', 'bitacora_evento');
SELECT frag.crear_particiones_mensuales('nodo_aqp', 'bitacora_evento');

-- Índices en public para migración por region_codigo
CREATE INDEX IF NOT EXISTS idx_public_persona_region ON public.persona (region_codigo);
CREATE INDEX IF NOT EXISTS idx_public_usuario_region ON public.usuario (region_codigo);
CREATE INDEX IF NOT EXISTS idx_public_cliente_region ON public.cliente (region_codigo);
CREATE INDEX IF NOT EXISTS idx_public_pedido_region ON public.pedido (region_codigo);
CREATE INDEX IF NOT EXISTS idx_public_pedido_region_fecha ON public.pedido (region_codigo, fecha_creacion);
CREATE INDEX IF NOT EXISTS idx_public_detalle_region ON public.detalle_pedido (region_codigo);
CREATE INDEX IF NOT EXISTS idx_public_pago_region ON public.pago (region_codigo);
CREATE INDEX IF NOT EXISTS idx_public_bitacora_region ON public.bitacora_evento (region_codigo);

-- =========================================================
-- 4. RÉPLICA INCREMENTAL
-- =========================================================
CREATE OR REPLACE FUNCTION frag.registrar_cambio_replica()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_id TEXT; v_ver TIMESTAMPTZ; v_payload JSONB;
BEGIN
  IF TG_TABLE_NAME = 'catalogo_maestro' THEN
    v_id := COALESCE(NEW.id_catalogo, OLD.id_catalogo)::TEXT;
    v_ver := now();
    v_payload := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  ELSIF TG_TABLE_NAME = 'nodo_registro' THEN
    v_id := COALESCE(NEW.region_codigo, OLD.region_codigo);
    v_ver := now(); v_payload := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  ELSIF TG_TABLE_NAME = 'regla_fragmentacion' THEN
    v_id := COALESCE(NEW.id_regla, OLD.id_regla)::TEXT;
    v_ver := now(); v_payload := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  END IF;
  INSERT INTO frag.replica_cambios (tabla_logica, operacion, id_registro, version_origen, payload)
  VALUES (TG_TABLE_NAME, SUBSTRING(TG_OP, 1, 1), v_id, v_ver, v_payload);
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER tg_replica_catalogo_maestro
  AFTER INSERT OR UPDATE OR DELETE ON public.catalogo_maestro
  FOR EACH ROW EXECUTE PROCEDURE frag.registrar_cambio_replica();

CREATE TRIGGER tg_replica_nodo_registro
  AFTER INSERT OR UPDATE OR DELETE ON public.nodo_registro
  FOR EACH ROW EXECUTE PROCEDURE frag.registrar_cambio_replica();

CREATE TRIGGER tg_replica_regla_fragmentacion
  AFTER INSERT OR UPDATE OR DELETE ON public.regla_fragmentacion
  FOR EACH ROW EXECUTE PROCEDURE frag.registrar_cambio_replica();

CREATE OR REPLACE FUNCTION frag.resolver_conflicto_lww(
  p_tabla TEXT, p_esquema TEXT, p_id TEXT, p_version_nueva TIMESTAMPTZ, p_version_local TIMESTAMPTZ
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  IF p_version_local IS NULL OR p_version_nueva >= p_version_local THEN
    RETURN TRUE;
  END IF;
  INSERT INTO frag.replica_conflictos (tabla_logica, esquema_destino, id_registro, valor_primario, valor_replica)
  VALUES (p_tabla, p_esquema, p_id,
    jsonb_build_object('version_local', p_version_local),
    jsonb_build_object('version_nueva', p_version_nueva, 'estrategia', 'LWW_rechazado'));
  RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION frag.procesar_fila_replica_catalogo(
  p_operacion CHAR(1), p_id UUID, p_esquema TEXT, p_version TIMESTAMPTZ
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_local TIMESTAMPTZ;
BEGIN
  IF p_operacion = 'D' THEN
    EXECUTE format('DELETE FROM %I.catalogo_maestro WHERE id_catalogo = %L', p_esquema, p_id);
    RETURN;
  END IF;
  EXECUTE format('SELECT version_registro FROM %I.catalogo_maestro WHERE id_catalogo = %L', p_esquema, p_id) INTO v_local;
  IF NOT frag.resolver_conflicto_lww('catalogo_maestro', p_esquema, p_id::TEXT, p_version, v_local) THEN RETURN; END IF;
  EXECUTE format($q$
    INSERT INTO %1$I.catalogo_maestro (id_catalogo, tipo_catalogo, codigo, nombre, descripcion,
      orden_presentacion, activo, replicado_en, version_registro)
    SELECT id_catalogo, tipo_catalogo, codigo, nombre, descripcion, orden_presentacion, activo, now(), %3$L::timestamptz
    FROM public.catalogo_maestro WHERE id_catalogo = %2$L
    ON CONFLICT (id_catalogo) DO UPDATE SET
      tipo_catalogo = EXCLUDED.tipo_catalogo, codigo = EXCLUDED.codigo, nombre = EXCLUDED.nombre,
      descripcion = EXCLUDED.descripcion, orden_presentacion = EXCLUDED.orden_presentacion,
      activo = EXCLUDED.activo, replicado_en = now(), version_registro = EXCLUDED.version_registro
  $q$, p_esquema, p_id, p_version);
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_replica_incremental_cola()
RETURNS TABLE(out_tabla TEXT, out_destino TEXT, out_procesados INT) LANGUAGE plpgsql AS $$
DECLARE
  v_c RECORD;
  v_cnt INT := 0;
  v_esquema TEXT;
BEGIN
  IF NOT pg_try_advisory_lock(hashtext('frag.replica_incremental')) THEN RETURN; END IF;

  FOR v_c IN SELECT DISTINCT tabla_logica, id_registro, operacion, version_origen
             FROM frag.replica_cambios WHERE NOT procesado AND tabla_logica = 'catalogo_maestro' LOOP
    IF v_c.operacion = 'D' THEN
      DELETE FROM nodo_global.catalogo_maestro WHERE id_catalogo = v_c.id_registro::UUID;
    ELSE
      INSERT INTO nodo_global.catalogo_maestro
        (id_catalogo, tipo_catalogo, codigo, nombre, descripcion, orden_presentacion, activo, sincronizado_en, version_registro)
      SELECT id_catalogo, tipo_catalogo, codigo, nombre, descripcion, orden_presentacion, activo, now(), v_c.version_origen
      FROM public.catalogo_maestro WHERE id_catalogo = v_c.id_registro::UUID
      ON CONFLICT (id_catalogo) DO UPDATE SET
        nombre = EXCLUDED.nombre, activo = EXCLUDED.activo, sincronizado_en = now(), version_registro = EXCLUDED.version_registro;
    END IF;
    v_cnt := v_cnt + 1;
  END LOOP;

  FOR v_esquema IN SELECT esquema_pg FROM frag.mapa_nodos WHERE NOT es_primario AND activo LOOP
    FOR v_c IN SELECT id_registro, operacion, version_origen FROM frag.replica_cambios
               WHERE NOT procesado AND tabla_logica = 'catalogo_maestro' LOOP
      PERFORM frag.procesar_fila_replica_catalogo(v_c.operacion, v_c.id_registro::UUID, v_esquema, v_c.version_origen);
    END LOOP;
    out_tabla := 'catalogo_maestro'; out_destino := v_esquema; out_procesados := v_cnt; RETURN NEXT;
  END LOOP;

  FOR v_c IN SELECT * FROM frag.replica_cambios WHERE NOT procesado AND tabla_logica = 'nodo_registro' LOOP
    FOR v_esquema IN SELECT esquema_pg FROM frag.mapa_nodos WHERE activo LOOP
      IF v_c.operacion = 'D' THEN
        EXECUTE format('DELETE FROM %I.nodo_registro WHERE region_codigo = %L', v_esquema, v_c.id_registro);
      ELSE
        EXECUTE format($q$INSERT INTO %1$I.nodo_registro SELECT region_codigo, nombre_nodo, activo, es_nodo_global, now()
          FROM nodo_global.nodo_registro WHERE region_codigo = %2$L
          ON CONFLICT (region_codigo) DO UPDATE SET nombre_nodo = EXCLUDED.nombre_nodo, activo = EXCLUDED.activo$q$,
          v_esquema, v_c.id_registro);
      END IF;
    END LOOP;
  END LOOP;

  UPDATE frag.replica_cambios SET procesado = TRUE, procesado_en = now() WHERE NOT procesado;
  PERFORM pg_advisory_unlock(hashtext('frag.replica_incremental'));
END;
$$;

CREATE OR REPLACE FUNCTION frag.actualizar_replica_control(
  p_tabla TEXT, p_esquema TEXT, p_ins INT, p_upd INT, p_del INT,
  p_duracion INT, p_error TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE frag.replica_control SET
    ultima_sync = now(),
    duracion_sync_ms = p_duracion,
    filas_sincronizadas = p_ins + p_upd,
    filas_insertadas = p_ins,
    filas_actualizadas = p_upd,
    filas_eliminadas = p_del,
    cantidad_errores = CASE WHEN p_error IS NULL THEN cantidad_errores ELSE cantidad_errores + 1 END,
    ultimo_mensaje_error = COALESCE(p_error, ultimo_mensaje_error),
    en_sync = (p_error IS NULL)
  WHERE tabla_logica = p_tabla AND esquema_destino = p_esquema;
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_catalogo_maestro_a(p_esquema TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_inicio TIMESTAMPTZ := clock_timestamp();
  v_ins INT := 0; v_upd INT := 0; v_del INT := 0;
BEGIN
  EXECUTE format($q$
    INSERT INTO %1$I.catalogo_maestro AS d
    SELECT id_catalogo, tipo_catalogo, codigo, nombre, descripcion, orden_presentacion, activo, now()
    FROM nodo_global.catalogo_maestro s
    ON CONFLICT (id_catalogo) DO UPDATE SET
      tipo_catalogo = EXCLUDED.tipo_catalogo, codigo = EXCLUDED.codigo,
      nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion,
      orden_presentacion = EXCLUDED.orden_presentacion, activo = EXCLUDED.activo,
      replicado_en = now()
    WHERE (d.tipo_catalogo, d.codigo, d.nombre, d.activo) IS DISTINCT FROM
          (EXCLUDED.tipo_catalogo, EXCLUDED.codigo, EXCLUDED.nombre, EXCLUDED.activo)
  $q$, p_esquema);
  GET DIAGNOSTICS v_upd = ROW_COUNT;

  EXECUTE format($q$
    DELETE FROM %1$I.catalogo_maestro d
    WHERE NOT EXISTS (SELECT 1 FROM nodo_global.catalogo_maestro s WHERE s.id_catalogo = d.id_catalogo)
  $q$, p_esquema);
  GET DIAGNOSTICS v_del = ROW_COUNT;

  PERFORM frag.actualizar_replica_control('catalogo_maestro', p_esquema, v_ins, v_upd, v_del,
    (EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio)::INT));
  RETURN v_upd + v_del;
EXCEPTION WHEN OTHERS THEN
  PERFORM frag.actualizar_replica_control('catalogo_maestro', p_esquema, 0, 0, 0, 0, SQLERRM);
  RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_nodo_registro_a(p_esquema TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_inicio TIMESTAMPTZ := clock_timestamp(); v_cnt INT;
BEGIN
  EXECUTE format($q$
    INSERT INTO %1$I.nodo_registro AS d
    SELECT region_codigo, nombre_nodo, activo, es_nodo_global, now() FROM nodo_global.nodo_registro s
    ON CONFLICT (region_codigo) DO UPDATE SET
      nombre_nodo = EXCLUDED.nombre_nodo, activo = EXCLUDED.activo,
      es_nodo_global = EXCLUDED.es_nodo_global, replicado_en = now()
  $q$, p_esquema);
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  EXECUTE format('DELETE FROM %I.nodo_registro d WHERE NOT EXISTS (
    SELECT 1 FROM nodo_global.nodo_registro s WHERE s.region_codigo = d.region_codigo)', p_esquema);
  PERFORM frag.actualizar_replica_control('nodo_registro', p_esquema, 0, v_cnt, 0,
    (EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio)::INT));
  RETURN v_cnt;
EXCEPTION WHEN OTHERS THEN
  PERFORM frag.actualizar_replica_control('nodo_registro', p_esquema, 0, 0, 0, 0, SQLERRM);
  RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_regla_fragmentacion_a(p_esquema TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_inicio TIMESTAMPTZ := clock_timestamp(); v_cnt INT;
BEGIN
  EXECUTE format($q$
    INSERT INTO %1$I.regla_fragmentacion AS d
    SELECT id_regla, nombre_tabla, clave_fragmento, criterio, nodo_ejemplo, now()
    FROM nodo_global.regla_fragmentacion s
    ON CONFLICT (id_regla) DO UPDATE SET
      nombre_tabla = EXCLUDED.nombre_tabla, clave_fragmento = EXCLUDED.clave_fragmento,
      criterio = EXCLUDED.criterio, nodo_ejemplo = EXCLUDED.nodo_ejemplo, replicado_en = now()
  $q$, p_esquema);
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  EXECUTE format('DELETE FROM %I.regla_fragmentacion d WHERE NOT EXISTS (
    SELECT 1 FROM nodo_global.regla_fragmentacion s WHERE s.id_regla = d.id_regla)', p_esquema);
  PERFORM frag.actualizar_replica_control('regla_fragmentacion', p_esquema, 0, v_cnt, 0,
    (EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio)::INT));
  RETURN v_cnt;
EXCEPTION WHEN OTHERS THEN
  PERFORM frag.actualizar_replica_control('regla_fragmentacion', p_esquema, 0, 0, 0, 0, SQLERRM);
  RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_primario_global()
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_inicio TIMESTAMPTZ := clock_timestamp();
BEGIN
  INSERT INTO nodo_global.catalogo_maestro AS d
  SELECT id_catalogo, tipo_catalogo, codigo, nombre, descripcion, orden_presentacion, activo, now()
  FROM public.catalogo_maestro s
  ON CONFLICT (id_catalogo) DO UPDATE SET
    tipo_catalogo = EXCLUDED.tipo_catalogo, codigo = EXCLUDED.codigo, nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion, orden_presentacion = EXCLUDED.orden_presentacion,
    activo = EXCLUDED.activo, sincronizado_en = now();

  INSERT INTO nodo_global.nodo_registro AS d
  SELECT region_codigo, nombre_nodo, activo, es_nodo_global, now() FROM public.nodo_registro s
  ON CONFLICT (region_codigo) DO UPDATE SET
    nombre_nodo = EXCLUDED.nombre_nodo, activo = EXCLUDED.activo,
    es_nodo_global = EXCLUDED.es_nodo_global, sincronizado_en = now();

  INSERT INTO nodo_global.regla_fragmentacion AS d
    (id_regla, nombre_tabla, clave_fragmento, criterio, nodo_ejemplo, sincronizado_en)
  SELECT r.id_regla, r.tabla, r.clave_fragmento, r.criterio, r.nodo_ejemplo, now()
  FROM public.regla_fragmentacion r
  ON CONFLICT (id_regla) DO UPDATE SET
    nombre_tabla = EXCLUDED.nombre_tabla, clave_fragmento = EXCLUDED.clave_fragmento,
    criterio = EXCLUDED.criterio, nodo_ejemplo = EXCLUDED.nodo_ejemplo, sincronizado_en = now();

  PERFORM frag.actualizar_replica_control('catalogo_maestro', 'nodo_global', 0, 1, 0,
    (EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio)::INT));
  INSERT INTO frag.auditoria_cluster (tipo_evento, detalle, duracion_ms, exito)
  VALUES ('SYNC_PRIMARIO', 'Sincronización incremental public → nodo_global', 
    (EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio)::INT), TRUE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO frag.auditoria_cluster (tipo_evento, detalle, exito)
  VALUES ('SYNC_PRIMARIO', SQLERRM, FALSE);
  RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_replicas_globales(p_forzar_completa BOOLEAN DEFAULT FALSE)
RETURNS TABLE(out_tabla TEXT, out_esquema TEXT, out_filas INTEGER) AS $$
DECLARE v_rec RECORD; v_filas INT; v_inc RECORD;
BEGIN
  IF NOT p_forzar_completa AND EXISTS (SELECT 1 FROM frag.replica_cambios WHERE NOT procesado LIMIT 1) THEN
    FOR v_inc IN SELECT * FROM frag.sincronizar_replica_incremental_cola() LOOP
      out_tabla := v_inc.out_tabla; out_esquema := v_inc.out_destino; out_filas := v_inc.out_procesados; RETURN NEXT;
    END LOOP;
    RETURN;
  END IF;
  PERFORM frag.sincronizar_primario_global();
  IF p_forzar_completa THEN
    DELETE FROM frag.replica_cambios WHERE NOT procesado;
  END IF;
  FOR v_rec IN SELECT esquema_pg FROM frag.mapa_nodos WHERE NOT es_primario AND activo ORDER BY esquema_pg LOOP
    v_filas := frag.sincronizar_catalogo_maestro_a(v_rec.esquema_pg);
    out_tabla := 'catalogo_maestro'; out_esquema := v_rec.esquema_pg; out_filas := v_filas; RETURN NEXT;
    v_filas := frag.sincronizar_nodo_registro_a(v_rec.esquema_pg);
    out_tabla := 'nodo_registro'; out_esquema := v_rec.esquema_pg; out_filas := v_filas; RETURN NEXT;
    v_filas := frag.sincronizar_regla_fragmentacion_a(v_rec.esquema_pg);
    out_tabla := 'regla_fragmentacion'; out_esquema := v_rec.esquema_pg; out_filas := v_filas; RETURN NEXT;
    UPDATE frag.nodo_heartbeat SET ultima_conexion = now(), tiempo_respuesta_ms = 5, estado = 'ONLINE'
    WHERE esquema_pg = v_rec.esquema_pg;
  END LOOP;
  UPDATE frag.replica_cambios SET procesado = TRUE, procesado_en = now() WHERE NOT procesado;
END;
$$ LANGUAGE plpgsql;

SELECT * FROM frag.sincronizar_replicas_globales(TRUE);

-- =========================================================
-- 5. MIGRACIÓN POR ENTIDAD (transaccional por región)
-- =========================================================
CREATE OR REPLACE FUNCTION frag.migrar_persona_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.persona
    SELECT id_persona, id_tipo_persona, id_tipo_documento, numero_documento,
           nombres, apellidos, razon_social, correo, telefono, fecha_nacimiento,
           direccion, activo, fecha_creacion, fecha_modificacion, region_codigo, now()
    FROM public.persona WHERE region_codigo = %2$L
    ON CONFLICT (id_persona) DO UPDATE SET nombres = EXCLUDED.nombres, correo = EXCLUDED.correo, version_registro = now()$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  RETURN v_filas;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_usuarios_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.usuario
    SELECT id_usuario, id_persona, id_rol, nombre_acceso, contrasena_hash, cuenta_activa,
           correo_verificado, telefono_verificado, fecha_registro, fecha_ultimo_acceso,
           intentos_fallidos, bloqueado_hasta
    FROM public.usuario WHERE region_codigo = %2$L$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  RETURN v_filas;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_comercio_catalogo_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_total BIGINT := 0; v_filas BIGINT;
BEGIN
  EXECUTE format('INSERT INTO %I.repartidor SELECT id_repartidor, id_persona, id_usuario, id_tipo_vehiculo, placa, disponible FROM public.repartidor WHERE region_codigo = %L', p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  EXECUTE format('INSERT INTO %I.comercio SELECT id_comercio, nombre, ruc, telefono, correo, direccion, activo FROM public.comercio WHERE region_codigo = %L', p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  EXECUTE format('INSERT INTO %I.proveedor SELECT id_proveedor, id_persona, activo, notas FROM public.proveedor WHERE region_codigo = %L', p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  EXECUTE format('INSERT INTO %I.comercio_proveedor SELECT id_comercio, id_proveedor, notas, fecha_alta FROM public.comercio_proveedor WHERE region_codigo = %L', p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  EXECUTE format('INSERT INTO %I.categoria_producto SELECT id_categoria, id_comercio, nombre FROM public.categoria_producto WHERE region_codigo = %L', p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  EXECUTE format('INSERT INTO %I.producto SELECT id_producto, id_comercio, id_categoria, nombre, descripcion, precio, disponible FROM public.producto WHERE region_codigo = %L', p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_cliente_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.cliente
    SELECT id_cliente, id_usuario, fecha_alta_cliente, id_preferencia_notificacion,
           acepta_publicidad, idioma_preferido, moneda_preferida, notas
    FROM public.cliente WHERE region_codigo = %2$L$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  RETURN v_filas;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_pedidos_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_total BIGINT := 0; v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.pedido
    SELECT id_pedido, id_cliente, id_comercio, id_repartidor, id_estado_pedido,
           nombre_cliente, nombre_comercio, direccion_entrega, referencia_entrega,
           subtotal, costo_envio, total, fecha_creacion, fecha_confirmacion, fecha_entrega_real
    FROM public.pedido WHERE region_codigo = %2$L
    ON CONFLICT (id_pedido, fecha_creacion) DO UPDATE SET total = EXCLUDED.total$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  EXECUTE format($q$INSERT INTO %1$I.detalle_pedido (id_detalle_pedido, id_pedido, id_producto, nombre_producto,
           cantidad, precio_unitario, importe_linea, fecha_creacion_pedido)
    SELECT d.id_detalle_pedido, d.id_pedido, d.id_producto, d.nombre_producto, d.cantidad, d.precio_unitario,
           d.importe_linea, p.fecha_creacion
    FROM public.detalle_pedido d
    JOIN public.pedido p ON p.region_codigo = d.region_codigo AND p.id_pedido = d.id_pedido
    WHERE p.region_codigo = %2$L
    ON CONFLICT (id_detalle_pedido) DO UPDATE SET importe_linea = EXCLUDED.importe_linea$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  EXECUTE format($q$INSERT INTO %1$I.pago (id_pago, id_pedido, id_metodo_pago, id_estado_pago, monto, fecha_pago, fecha_creacion_pedido)
    SELECT pg.id_pago, pg.id_pedido, pg.id_metodo_pago, pg.id_estado_pago, pg.monto, pg.fecha_pago, p.fecha_creacion
    FROM public.pago pg
    JOIN public.pedido p ON p.region_codigo = pg.region_codigo AND p.id_pedido = pg.id_pedido
    WHERE p.region_codigo = %2$L
    ON CONFLICT (id_pago) DO UPDATE SET monto = EXCLUDED.monto$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_rutas_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_total BIGINT := 0; v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.ruta_reparto
    SELECT id_ruta, id_repartidor, fecha_planificacion, id_estado_ruta, hora_inicio_real, hora_fin_real,
           distancia_kilometros, observaciones, fecha_creacion
    FROM public.ruta_reparto WHERE region_codigo = %2$L
    ON CONFLICT (id_ruta) DO NOTHING$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  EXECUTE format($q$INSERT INTO %1$I.parada_ruta (id_parada, id_ruta, id_pedido, orden_visita,
           hora_estimada_llegada, hora_llegada_real, hora_salida_real, fecha_creacion_pedido)
    SELECT pr.id_parada, pr.id_ruta, pr.id_pedido, pr.orden_visita,
           pr.hora_estimada_llegada, pr.hora_llegada_real, pr.hora_salida_real, pe.fecha_creacion
    FROM public.parada_ruta pr
    JOIN public.ruta_reparto rr ON rr.region_codigo = pr.region_codigo AND rr.id_ruta = pr.id_ruta
    LEFT JOIN public.pedido pe ON pe.region_codigo = pr.region_codigo AND pe.id_pedido = pr.id_pedido
    WHERE rr.region_codigo = %2$L
    ON CONFLICT (id_parada) DO NOTHING$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_bitacora_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.bitacora_evento
    SELECT id_evento, fecha_hora, tipo_evento, tabla_afectada, id_registro,
           descripcion, datos_adicionales, id_usuario, nodo_origen
    FROM public.bitacora_evento WHERE region_codigo = %2$L$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  RETURN v_filas;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_sagas_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_total BIGINT := 0; v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.saga_transaccion
    SELECT id_saga, tipo_operacion, estado, id_pedido, payload, fecha_creacion, fecha_finalizacion
    FROM public.saga_transaccion WHERE region_codigo = %2$L
    ON CONFLICT (id_saga) DO UPDATE SET estado = EXCLUDED.estado$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  EXECUTE format($q$INSERT INTO %1$I.saga_paso
    SELECT sp.id_paso, sp.id_saga, sp.orden_paso, sp.nombre_paso, sp.estado, sp.nodo_ejecutor, sp.detalle, sp.fecha_ejecucion
    FROM public.saga_paso sp
    JOIN public.saga_transaccion st ON st.id_saga = sp.id_saga
    WHERE st.region_codigo = %2$L
    ON CONFLICT (id_paso) DO UPDATE SET estado = EXCLUDED.estado$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION frag.limpiar_fragmentos_nodo(p_esquema TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format(
    'TRUNCATE %1$I.saga_paso, %1$I.saga_transaccion, %1$I.parada_ruta, %1$I.ruta_reparto,
              %1$I.pago, %1$I.bitacora_evento, %1$I.detalle_pedido, %1$I.pedido,
              %1$I.cliente, %1$I.producto, %1$I.categoria_producto, %1$I.comercio_proveedor,
              %1$I.proveedor, %1$I.comercio, %1$I.repartidor, %1$I.usuario, %1$I.persona CASCADE',
    p_esquema);
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_region_a_nodo(p_region TEXT, p_esquema TEXT)
RETURNS TABLE(out_entidad TEXT, out_filas BIGINT) LANGUAGE plpgsql AS $$
DECLARE v_filas BIGINT; v_inicio TIMESTAMPTZ;
BEGIN
  v_inicio := clock_timestamp();
  PERFORM frag.limpiar_fragmentos_nodo(p_esquema);
  PERFORM frag.crear_particiones_mensuales(p_esquema, 'pedido');
  PERFORM frag.crear_particiones_mensuales(p_esquema, 'bitacora_evento');

  v_filas := frag.migrar_persona_a_nodo(p_esquema, p_region);
  out_entidad := 'persona'; out_filas := v_filas; RETURN NEXT;
  v_filas := frag.migrar_usuarios_a_nodo(p_esquema, p_region);
  out_entidad := 'usuario'; out_filas := v_filas; RETURN NEXT;
  v_filas := frag.migrar_comercio_catalogo_a_nodo(p_esquema, p_region);
  out_entidad := 'comercio_catalogo'; out_filas := v_filas; RETURN NEXT;
  v_filas := frag.migrar_cliente_a_nodo(p_esquema, p_region);
  out_entidad := 'cliente'; out_filas := v_filas; RETURN NEXT;
  v_filas := frag.migrar_pedidos_a_nodo(p_esquema, p_region);
  out_entidad := 'pedido+derivados'; out_filas := v_filas; RETURN NEXT;
  v_filas := frag.migrar_rutas_a_nodo(p_esquema, p_region);
  out_entidad := 'ruta+paradas'; out_filas := v_filas; RETURN NEXT;
  v_filas := frag.migrar_bitacora_a_nodo(p_esquema, p_region);
  out_entidad := 'bitacora_evento'; out_filas := v_filas; RETURN NEXT;
  v_filas := frag.migrar_sagas_a_nodo(p_esquema, p_region);
  out_entidad := 'saga+pasos'; out_filas := v_filas; RETURN NEXT;

  INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, esquema_pg, detalle, duracion_ms, exito)
  VALUES ('MIGRACION_REGION', p_region, p_esquema, 'Migración completa de fragmentos', 
    (EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio)::INT), TRUE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, esquema_pg, detalle, exito)
  VALUES ('MIGRACION_REGION', p_region, p_esquema, SQLERRM, FALSE);
  RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION frag.migrar_fragmentos_a_nodos()
RETURNS TABLE(out_region TEXT, out_esquema TEXT, out_entidad TEXT, out_filas BIGINT) AS $$
DECLARE
  v_rec RECORD;
  v_sub RECORD;
BEGIN
  -- Nota: SAVEPOINT/ROLLBACK no son válidos dentro de FUNCTION en PL/pgSQL.
  -- Cada región se migra secuencialmente; si falla una, aborta toda la transacción del script.
  FOR v_rec IN SELECT region_codigo, esquema_pg FROM frag.mapa_nodos WHERE NOT es_primario ORDER BY region_codigo LOOP
    BEGIN
      FOR v_sub IN SELECT * FROM frag.migrar_region_a_nodo(v_rec.region_codigo, v_rec.esquema_pg) LOOP
        out_region := v_rec.region_codigo;
        out_esquema := v_rec.esquema_pg;
        out_entidad := v_sub.out_entidad;
        out_filas := v_sub.out_filas;
        RETURN NEXT;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, esquema_pg, detalle, exito)
      VALUES ('MIGRACION_ERROR', v_rec.region_codigo, v_rec.esquema_pg, SQLERRM, FALSE);
      RAISE WARNING 'Error migrando región %: %', v_rec.region_codigo, SQLERRM;
      RAISE;
    END;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Migración con COMMIT por región (usa PROCEDURE; válido para aislamiento transaccional).
-- Ejecutar manualmente si se desea: CALL frag.migrar_fragmentos_con_commit_por_region();
CREATE OR REPLACE PROCEDURE frag.migrar_fragmentos_con_commit_por_region()
LANGUAGE plpgsql AS $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN SELECT region_codigo, esquema_pg FROM frag.mapa_nodos WHERE NOT es_primario ORDER BY region_codigo LOOP
    BEGIN
      PERFORM frag.migrar_region_a_nodo(v_rec.region_codigo, v_rec.esquema_pg);
      COMMIT;
      INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, esquema_pg, detalle, exito)
      VALUES ('MIGRACION_COMMIT_REGION', v_rec.region_codigo, v_rec.esquema_pg, 'Región migrada y confirmada', TRUE);
    EXCEPTION WHEN OTHERS THEN
      ROLLBACK;
      INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, esquema_pg, detalle, exito)
      VALUES ('MIGRACION_ROLLBACK_REGION', v_rec.region_codigo, v_rec.esquema_pg, SQLERRM, FALSE);
      RAISE WARNING 'Rollback región %: %', v_rec.region_codigo, SQLERRM;
    END;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_saga_monitoreo_incremental()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_rec RECORD; v_total INT := 0; v_n INT;
BEGIN
  FOR v_rec IN SELECT region_codigo, esquema_pg FROM frag.mapa_nodos WHERE NOT es_primario LOOP
    EXECUTE format($q$
      INSERT INTO nodo_global.saga_monitoreo AS m
      SELECT id_saga, %2$L, tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now()
      FROM %1$I.saga_transaccion
      ON CONFLICT (id_saga) DO UPDATE SET
        estado = EXCLUDED.estado, fecha_finalizacion = EXCLUDED.fecha_finalizacion, sincronizado_en = now()
    $q$, v_rec.esquema_pg, v_rec.region_codigo);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;
  END LOOP;
  RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION frag.sincronizar_saga_monitoreo()
RETURNS INTEGER LANGUAGE plpgsql AS $$
BEGIN
  RETURN frag.sincronizar_saga_monitoreo_incremental();
EXCEPTION WHEN OTHERS THEN
  DELETE FROM nodo_global.saga_monitoreo;
  INSERT INTO nodo_global.saga_monitoreo
    SELECT id_saga, 'LIM-N', tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now() FROM nodo_lim_n.saga_transaccion
  UNION ALL SELECT id_saga, 'LIM-S', tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now() FROM nodo_lim_s.saga_transaccion
  UNION ALL SELECT id_saga, 'AQP', tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now() FROM nodo_aqp.saga_transaccion;
  RETURN (SELECT COUNT(*)::INT FROM nodo_global.saga_monitoreo);
END;
$$;

-- Validación de integridad
CREATE OR REPLACE FUNCTION frag.validar_integridad_fragmentacion()
RETURNS TABLE(tabla TEXT, origen BIGINT, fragmentado BIGINT, coincide BOOLEAN) LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT 'persona'::TEXT, (SELECT COUNT(*) FROM public.persona),
    (SELECT COUNT(*) FROM nodo_lim_n.persona)+(SELECT COUNT(*) FROM nodo_lim_s.persona)+(SELECT COUNT(*) FROM nodo_aqp.persona),
    (SELECT COUNT(*) FROM public.persona) =
    (SELECT COUNT(*) FROM nodo_lim_n.persona)+(SELECT COUNT(*) FROM nodo_lim_s.persona)+(SELECT COUNT(*) FROM nodo_aqp.persona);
  RETURN QUERY SELECT 'pedido', (SELECT COUNT(*) FROM public.pedido),
    (SELECT COUNT(*) FROM nodo_lim_n.pedido)+(SELECT COUNT(*) FROM nodo_lim_s.pedido)+(SELECT COUNT(*) FROM nodo_aqp.pedido),
    (SELECT COUNT(*) FROM public.pedido) =
    (SELECT COUNT(*) FROM nodo_lim_n.pedido)+(SELECT COUNT(*) FROM nodo_lim_s.pedido)+(SELECT COUNT(*) FROM nodo_aqp.pedido);
  RETURN QUERY SELECT 'detalle_pedido', (SELECT COUNT(*) FROM public.detalle_pedido),
    (SELECT COUNT(*) FROM nodo_lim_n.detalle_pedido)+(SELECT COUNT(*) FROM nodo_lim_s.detalle_pedido)+(SELECT COUNT(*) FROM nodo_aqp.detalle_pedido),
    (SELECT COUNT(*) FROM public.detalle_pedido) =
    (SELECT COUNT(*) FROM nodo_lim_n.detalle_pedido)+(SELECT COUNT(*) FROM nodo_lim_s.detalle_pedido)+(SELECT COUNT(*) FROM nodo_aqp.detalle_pedido);
  RETURN QUERY SELECT 'pago', (SELECT COUNT(*) FROM public.pago),
    (SELECT COUNT(*) FROM nodo_lim_n.pago)+(SELECT COUNT(*) FROM nodo_lim_s.pago)+(SELECT COUNT(*) FROM nodo_aqp.pago),
    (SELECT COUNT(*) FROM public.pago) =
    (SELECT COUNT(*) FROM nodo_lim_n.pago)+(SELECT COUNT(*) FROM nodo_lim_s.pago)+(SELECT COUNT(*) FROM nodo_aqp.pago);
END;
$$;

-- Recuperación de fragmento regional
CREATE OR REPLACE FUNCTION frag.recuperar_fragmento_region(p_region TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_esquema TEXT;
BEGIN
  SELECT esquema_pg INTO v_esquema FROM frag.mapa_nodos WHERE region_codigo = p_region AND NOT es_primario;
  IF v_esquema IS NULL THEN
    RAISE EXCEPTION 'Región % no encontrada o es primaria', p_region;
  END IF;
  PERFORM frag.migrar_region_a_nodo(p_region, v_esquema);
  PERFORM frag.sincronizar_replicas_globales(FALSE);
  PERFORM frag.sincronizar_saga_monitoreo();
  INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, esquema_pg, detalle, exito)
  VALUES ('RECUPERACION', p_region, v_esquema, 'Fragmento regional reconstruido desde public', TRUE);
  RETURN format('Fragmento % recuperado en esquema %', p_region, v_esquema);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, detalle, exito)
  VALUES ('RECUPERACION', p_region, SQLERRM, FALSE);
  RAISE;
END;
$$;

-- =========================================================
-- 6. VISTAS ADMINISTRATIVAS Y ESTADÍSTICAS
-- =========================================================
CREATE OR REPLACE VIEW frag.v_admin_estado_nodos AS
SELECT m.region_codigo, m.esquema_pg, m.nombre_nodo, m.activo,
       h.estado, h.disponible, h.ultima_conexion, h.tiempo_respuesta_ms, h.ultimo_error
FROM frag.mapa_nodos m
LEFT JOIN frag.nodo_heartbeat h ON h.region_codigo = m.region_codigo
ORDER BY m.es_primario DESC, m.region_codigo;

CREATE OR REPLACE VIEW frag.v_admin_replicas AS
SELECT rc.tabla_logica, rc.esquema_destino, rc.region_destino, rc.rol_replica,
       rc.tipo_replicacion, rc.ultima_sync, rc.duracion_sync_ms,
       rc.filas_insertadas, rc.filas_actualizadas, rc.filas_eliminadas,
       rc.cantidad_errores, rc.ultimo_mensaje_error, rc.en_sync
FROM frag.replica_control rc
ORDER BY rc.tabla_logica, rc.esquema_destino;

CREATE OR REPLACE VIEW frag.v_admin_sincronizacion AS
SELECT tipo_evento, region_codigo, esquema_pg, detalle, duracion_ms, exito, registrado_en
FROM frag.auditoria_cluster
ORDER BY registrado_en DESC;

-- v_estadisticas_cluster: definida en sección 6b (función estadisticas_nodo)

CREATE OR REPLACE VIEW frag.v_persona_cluster AS
  SELECT * FROM nodo_lim_n.persona
  UNION ALL SELECT * FROM nodo_lim_s.persona
  UNION ALL SELECT * FROM nodo_aqp.persona;

CREATE OR REPLACE VIEW frag.v_pedido_cluster AS
  SELECT 'LIM-N' AS region_codigo, p.* FROM nodo_lim_n.pedido p
  UNION ALL SELECT 'LIM-S', p.* FROM nodo_lim_s.pedido p
  UNION ALL SELECT 'AQP', p.* FROM nodo_aqp.pedido p;

CREATE OR REPLACE VIEW frag.v_catalogo_por_nodo AS
  SELECT 'nodo_global' AS esquema, 'GLOBAL' AS region, COUNT(*) AS filas FROM nodo_global.catalogo_maestro
  UNION ALL SELECT 'nodo_lim_n', 'LIM-N', COUNT(*) FROM nodo_lim_n.catalogo_maestro
  UNION ALL SELECT 'nodo_lim_s', 'LIM-S', COUNT(*) FROM nodo_lim_s.catalogo_maestro
  UNION ALL SELECT 'nodo_aqp', 'AQP', COUNT(*) FROM nodo_aqp.catalogo_maestro;

CREATE OR REPLACE VIEW frag.v_comparacion_migracion AS
SELECT v.tabla, v.origen AS relacional, v.fragmentado AS fragmentado_por_nodo, v.coincide
FROM frag.validar_integridad_fragmentacion() v
UNION ALL
SELECT 'usuario', (SELECT COUNT(*) FROM public.usuario),
  (SELECT COUNT(*) FROM nodo_lim_n.usuario)+(SELECT COUNT(*) FROM nodo_lim_s.usuario)+(SELECT COUNT(*) FROM nodo_aqp.usuario),
  (SELECT COUNT(*) FROM public.usuario) =
  (SELECT COUNT(*) FROM nodo_lim_n.usuario)+(SELECT COUNT(*) FROM nodo_lim_s.usuario)+(SELECT COUNT(*) FROM nodo_aqp.usuario)
UNION ALL
SELECT 'producto', (SELECT COUNT(*) FROM public.producto),
  (SELECT COUNT(*) FROM nodo_lim_n.producto)+(SELECT COUNT(*) FROM nodo_lim_s.producto)+(SELECT COUNT(*) FROM nodo_aqp.producto),
  (SELECT COUNT(*) FROM public.producto) =
  (SELECT COUNT(*) FROM nodo_lim_n.producto)+(SELECT COUNT(*) FROM nodo_lim_s.producto)+(SELECT COUNT(*) FROM nodo_aqp.producto)
UNION ALL
SELECT 'bitacora_evento', (SELECT COUNT(*) FROM public.bitacora_evento),
  (SELECT COUNT(*) FROM nodo_lim_n.bitacora_evento)+(SELECT COUNT(*) FROM nodo_lim_s.bitacora_evento)+(SELECT COUNT(*) FROM nodo_aqp.bitacora_evento),
  (SELECT COUNT(*) FROM public.bitacora_evento) =
  (SELECT COUNT(*) FROM nodo_lim_n.bitacora_evento)+(SELECT COUNT(*) FROM nodo_lim_s.bitacora_evento)+(SELECT COUNT(*) FROM nodo_aqp.bitacora_evento);

-- =========================================================
-- 6b. CHECKLIST + MEJORAS v3 (consolidado en este script)
-- =========================================================
-- [1] FK FALTANTES + [2] CHECK region_codigo en nodos regionales
-- =========================================================
CREATE OR REPLACE FUNCTION frag.agregar_fks_y_checks_nodo(p_esquema TEXT, p_region TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  -- region_codigo + version_registro en tablas operativas
  BEGIN
    EXECUTE format('ALTER TABLE %I.persona ADD COLUMN IF NOT EXISTS region_codigo VARCHAR(10)', p_esquema);
    EXECUTE format('ALTER TABLE %I.persona ADD COLUMN IF NOT EXISTS version_registro TIMESTAMPTZ NOT NULL DEFAULT now()', p_esquema);
    EXECUTE format('UPDATE %I.persona SET region_codigo = %L WHERE region_codigo IS NULL', p_esquema, p_region);
    EXECUTE format('ALTER TABLE %I.persona ALTER COLUMN region_codigo SET NOT NULL', p_esquema);
    EXECUTE format('ALTER TABLE %I.persona DROP CONSTRAINT IF EXISTS ck_%s_persona_region', p_esquema, replace(p_esquema,'.','_'));
    EXECUTE format('ALTER TABLE %I.persona ADD CONSTRAINT ck_%s_persona_region CHECK (region_codigo = %L)',
      p_esquema, replace(p_esquema,'.','_'), p_region);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- FK pedido → cliente, comercio, repartidor
  BEGIN EXECUTE format('ALTER TABLE %I.pedido DROP CONSTRAINT IF EXISTS fk_pedido_cliente', p_esquema);
    EXECUTE format('ALTER TABLE %I.pedido ADD CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente) REFERENCES %I.cliente(id_cliente)', p_esquema, p_esquema);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE format('ALTER TABLE %I.pedido DROP CONSTRAINT IF EXISTS fk_pedido_comercio', p_esquema);
    EXECUTE format('ALTER TABLE %I.pedido ADD CONSTRAINT fk_pedido_comercio FOREIGN KEY (id_comercio) REFERENCES %I.comercio(id_comercio)', p_esquema, p_esquema);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE format('ALTER TABLE %I.pedido DROP CONSTRAINT IF EXISTS fk_pedido_repartidor', p_esquema);
    EXECUTE format('ALTER TABLE %I.pedido ADD CONSTRAINT fk_pedido_repartidor FOREIGN KEY (id_repartidor) REFERENCES %I.repartidor(id_repartidor)', p_esquema, p_esquema);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- FK pago → pedido (referencia lógica por id_pedido; índice único auxiliar)
  BEGIN EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS uq_%s_pedido_id ON %I.pedido (id_pedido)', replace(p_esquema,'.','_'), p_esquema);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- CHECK adicionales en public (ítem 2)
END;
$$;
SELECT frag.agregar_fks_y_checks_nodo('nodo_lim_n', 'LIM-N');
SELECT frag.agregar_fks_y_checks_nodo('nodo_lim_s', 'LIM-S');
SELECT frag.agregar_fks_y_checks_nodo('nodo_aqp', 'AQP');

-- CHECK global en public: region_codigo válido
DO $$ BEGIN
  ALTER TABLE public.persona DROP CONSTRAINT IF EXISTS ck_persona_region_valida;
  ALTER TABLE public.persona ADD CONSTRAINT ck_persona_region_valida
    CHECK (region_codigo IN ('LIM-N','LIM-S','AQP'));
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.pedido DROP CONSTRAINT IF EXISTS ck_pedido_region_valida;
  ALTER TABLE public.pedido ADD CONSTRAINT ck_pedido_region_valida
    CHECK (region_codigo IN ('LIM-N','LIM-S','AQP'));
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- =========================================================
-- [3] TRIGGERS public → cola fragmento_cambios (ver función unificada más abajo)
-- [4] Sincronización automática de fragmentos
-- =========================================================
CREATE OR REPLACE FUNCTION frag.sincronizar_fila_fragmento(
  p_tabla TEXT, p_region TEXT, p_esquema TEXT, p_operacion CHAR(1), p_id TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_operacion = 'D' THEN
    EXECUTE format('DELETE FROM %I.%I WHERE %s = %L',
      p_esquema, p_tabla,
      CASE p_tabla
        WHEN 'persona' THEN 'id_persona' WHEN 'usuario' THEN 'id_usuario'
        WHEN 'cliente' THEN 'id_cliente' WHEN 'comercio' THEN 'id_comercio'
        WHEN 'pedido' THEN 'id_pedido' WHEN 'detalle_pedido' THEN 'id_detalle_pedido'
        WHEN 'pago' THEN 'id_pago' WHEN 'bitacora_evento' THEN 'id_evento'
      END, p_id);
    RETURN;
  END IF;

  -- UPSERT simplificado: re-migrar fila desde public
  IF p_tabla = 'persona' THEN
    EXECUTE format($q$INSERT INTO %1$I.persona (
        id_persona, id_tipo_persona, id_tipo_documento, numero_documento,
        nombres, apellidos, razon_social, correo, telefono, fecha_nacimiento,
        direccion, activo, fecha_creacion, fecha_modificacion, region_codigo, version_registro)
      SELECT id_persona, id_tipo_persona, id_tipo_documento, numero_documento,
        nombres, apellidos, razon_social, correo, telefono, fecha_nacimiento,
        direccion, activo, fecha_creacion, fecha_modificacion, region_codigo, now()
      FROM public.persona WHERE region_codigo = %2$L AND id_persona = %3$L::uuid
      ON CONFLICT (id_persona) DO UPDATE SET nombres = EXCLUDED.nombres, correo = EXCLUDED.correo,
        version_registro = now()$q$, p_esquema, p_region, p_id);
  ELSIF p_tabla = 'pedido' THEN
    EXECUTE format($q$INSERT INTO %1$I.pedido SELECT id_pedido, id_cliente, id_comercio, id_repartidor,
      id_estado_pedido, nombre_cliente, nombre_comercio, direccion_entrega, referencia_entrega,
      subtotal, costo_envio, total, fecha_creacion, fecha_confirmacion, fecha_entrega_real
      FROM public.pedido WHERE region_codigo = %2$L AND id_pedido = %3$L::uuid
      ON CONFLICT (id_pedido, fecha_creacion) DO UPDATE SET total = EXCLUDED.total$q$, p_esquema, p_region, p_id);
  ELSIF p_tabla = 'comercio' THEN
    EXECUTE format($q$INSERT INTO %1$I.comercio SELECT id_comercio, nombre, ruc, telefono, correo, direccion, activo
      FROM public.comercio WHERE region_codigo = %2$L AND id_comercio = %3$L::uuid
      ON CONFLICT (id_comercio) DO UPDATE SET nombre = EXCLUDED.nombre, activo = EXCLUDED.activo$q$, p_esquema, p_region, p_id);
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION frag.sincronizar_fragmentos_incremental()
RETURNS TABLE(out_region TEXT, out_tabla TEXT, out_procesados INT) LANGUAGE plpgsql AS $$
DECLARE
  v_rec RECORD;
  v_esquema TEXT;
  v_cnt INT := 0;
  v_lock BOOLEAN;
BEGIN
  v_lock := pg_try_advisory_lock(hashtext('frag.sync_fragmentos'));
  IF NOT v_lock THEN
    RAISE NOTICE 'Sincronización en curso (advisory lock activo)';
    RETURN;
  END IF;

  FOR v_rec IN
    SELECT fc.*, m.esquema_pg
    FROM frag.fragmento_cambios fc
    JOIN frag.mapa_nodos m ON m.region_codigo = fc.region_codigo AND NOT m.es_primario
    WHERE NOT fc.procesado
    ORDER BY fc.fecha_cambio
    LIMIT 500
  LOOP
    BEGIN
      PERFORM frag.sincronizar_fila_fragmento(v_rec.tabla_logica, v_rec.region_codigo,
        v_rec.esquema_pg, v_rec.operacion, v_rec.id_registro);
      UPDATE frag.fragmento_cambios SET procesado = TRUE, procesado_en = now() WHERE id_cambio = v_rec.id_cambio;
      v_cnt := v_cnt + 1;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO frag.migracion_metricas (region_codigo, esquema_pg, entidad, filas_migradas, errores)
      VALUES (v_rec.region_codigo, v_rec.esquema_pg, v_rec.tabla_logica, 0, 1);
      INSERT INTO frag.auditoria_cluster (tipo_evento, region_codigo, detalle, exito)
      VALUES ('SYNC_FRAGMENTO_ERROR', v_rec.region_codigo, SQLERRM, FALSE);
    END;
  END LOOP;

  PERFORM pg_advisory_unlock(hashtext('frag.sync_fragmentos'));
  out_region := 'ALL'; out_tabla := 'fragmento_cambios'; out_procesados := v_cnt;
  RETURN NEXT;
END;
$$;
-- =========================================================
-- [5][6] Particiones futuras y retención
-- =========================================================
CREATE OR REPLACE FUNCTION frag.mantener_particiones_cluster(p_meses_adelante INT DEFAULT 6)
RETURNS TABLE(out_esquema TEXT, out_tabla TEXT, out_creadas INT) LANGUAGE plpgsql AS $$
DECLARE v_rec RECORD; v_n INT;
BEGIN
  FOR v_rec IN SELECT esquema_pg FROM frag.mapa_nodos WHERE NOT es_primario LOOP
    v_n := frag.crear_particiones_mensuales(v_rec.esquema_pg, 'pedido', p_meses_adelante);
    out_esquema := v_rec.esquema_pg; out_tabla := 'pedido'; out_creadas := v_n; RETURN NEXT;
    v_n := frag.crear_particiones_mensuales(v_rec.esquema_pg, 'bitacora_evento', p_meses_adelante);
    out_esquema := v_rec.esquema_pg; out_tabla := 'bitacora_evento'; out_creadas := v_n; RETURN NEXT;
  END LOOP;
END;
$$;
CREATE OR REPLACE FUNCTION frag.purgar_particiones_antiguas(
  p_esquema TEXT, p_tabla TEXT, p_meses_retener INT DEFAULT 12
) RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_limite DATE := date_trunc('month', CURRENT_DATE - (p_meses_retener || ' months')::interval)::DATE;
  v_part RECORD;
  v_drop INT := 0;
BEGIN
  FOR v_part IN
    SELECT c.relname AS part_name
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    JOIN pg_class p ON p.oid = i.inhparent
    JOIN pg_namespace n ON n.oid = p.relnamespace
    WHERE n.nspname = p_esquema AND p.relname = p_tabla
      AND c.relname NOT LIKE '%_default'
  LOOP
  BEGIN
    IF v_part.part_name ~ '^\w+_(\d{4})_(\d{2})$' THEN
      IF to_date(substring(v_part.part_name from '(\d{4}_\d{2})$'), 'YYYY_MM') < v_limite THEN
        EXECUTE format('DROP TABLE IF EXISTS %I.%I', p_esquema, v_part.part_name);
        v_drop := v_drop + 1;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  END LOOP;
  RETURN v_drop;
END;
$$;
-- =========================================================
-- [7] Balanceo / cambio de región
-- =========================================================
CREATE OR REPLACE FUNCTION frag.cambiar_region_entidad(
  p_tabla TEXT, p_id UUID, p_region_origen TEXT, p_region_destino TEXT
) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_esquema_o TEXT; v_esquema_d TEXT;
BEGIN
  IF p_region_origen = p_region_destino THEN
    RETURN 'Sin cambio: misma región';
  END IF;
  SELECT esquema_pg INTO v_esquema_o FROM frag.mapa_nodos WHERE region_codigo = p_region_origen AND NOT es_primario;
  SELECT esquema_pg INTO v_esquema_d FROM frag.mapa_nodos WHERE region_codigo = p_region_destino AND NOT es_primario;

  IF p_tabla = 'cliente' THEN
    UPDATE public.cliente SET region_codigo = p_region_destino, nodo_origen = p_region_destino
    WHERE region_codigo = p_region_origen AND id_cliente = p_id;
    UPDATE public.usuario SET region_codigo = p_region_destino, nodo_origen = p_region_destino
    WHERE id_usuario = (SELECT id_usuario FROM public.cliente WHERE id_cliente = p_id);
    UPDATE public.persona SET region_codigo = p_region_destino, nodo_origen = p_region_destino
    WHERE id_persona = (SELECT id_persona FROM public.usuario WHERE id_usuario =
      (SELECT id_usuario FROM public.cliente WHERE id_cliente = p_id));
  ELSIF p_tabla = 'comercio' THEN
    UPDATE public.comercio SET region_codigo = p_region_destino, nodo_origen = p_region_destino
    WHERE region_codigo = p_region_origen AND id_comercio = p_id;
  ELSE
    RAISE EXCEPTION 'Tabla % no soportada para cambio de región', p_tabla;
  END IF;

  PERFORM frag.recuperar_fragmento_region(p_region_origen);
  PERFORM frag.recuperar_fragmento_region(p_region_destino);
  INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, detalle, exito)
  VALUES ('CAMBIO_REGION', p_region_destino,
    format('Entidad % en %s movida de %s a %s', p_tabla, p_id, p_region_origen, p_region_destino), TRUE);
  RETURN format('Región cambiada: %s → %s', p_region_origen, p_region_destino);
END;
$$;
-- =========================================================
-- [8] Recuperación automática al volver ONLINE
-- [9] Detección de conflictos
-- [10] Versionado
-- =========================================================
CREATE OR REPLACE FUNCTION frag.detectar_conflictos_replica()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_rec RECORD; v_cnt INT := 0;
BEGIN
  FOR v_rec IN
    SELECT 'catalogo_maestro' AS tabla, 'nodo_lim_n'::TEXT AS esquema_pg,
           g.id_catalogo::TEXT AS id_reg, row_to_json(g) AS prim, row_to_json(r) AS sec
    FROM nodo_global.catalogo_maestro g
    JOIN nodo_lim_n.catalogo_maestro r ON r.id_catalogo = g.id_catalogo
    WHERE (g.nombre, g.activo) IS DISTINCT FROM (r.nombre, r.activo)
    UNION ALL
    SELECT 'catalogo_maestro', 'nodo_lim_s',
           g.id_catalogo::TEXT, row_to_json(g), row_to_json(r)
    FROM nodo_global.catalogo_maestro g
    JOIN nodo_lim_s.catalogo_maestro r ON r.id_catalogo = g.id_catalogo
    WHERE (g.nombre, g.activo) IS DISTINCT FROM (r.nombre, r.activo)
    UNION ALL
    SELECT 'catalogo_maestro', 'nodo_aqp',
           g.id_catalogo::TEXT, row_to_json(g), row_to_json(r)
    FROM nodo_global.catalogo_maestro g
    JOIN nodo_aqp.catalogo_maestro r ON r.id_catalogo = g.id_catalogo
    WHERE (g.nombre, g.activo) IS DISTINCT FROM (r.nombre, r.activo)
    LIMIT 50
  LOOP
    INSERT INTO frag.replica_conflictos (tabla_logica, esquema_destino, id_registro, valor_primario, valor_replica)
    VALUES (v_rec.tabla, v_rec.esquema_pg, v_rec.id_reg, v_rec.prim::jsonb, v_rec.sec::jsonb);
    v_cnt := v_cnt + 1;
  END LOOP;
  RETURN v_cnt;
END;
$$;
CREATE OR REPLACE FUNCTION frag.procesar_nodo_online(p_region TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_estado TEXT;
BEGIN
  SELECT estado INTO v_estado FROM frag.nodo_heartbeat WHERE region_codigo = p_region;
  IF v_estado = 'ONLINE' THEN
    PERFORM frag.recuperar_fragmento_region(p_region);
    PERFORM frag.sincronizar_replicas_globales(FALSE);
    PERFORM frag.sincronizar_fragmentos_incremental();
    PERFORM frag.sincronizar_resumen_pedidos_region();
    INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, detalle, exito)
    VALUES ('AUTO_RECUPERACION', p_region, 'Nodo ONLINE: fragmentos y réplicas sincronizados', TRUE);
    RETURN format('Nodo % recuperado automáticamente', p_region);
  END IF;
  RETURN format('Nodo % en estado % — sin acción', p_region, v_estado);
END;
$$;
CREATE OR REPLACE FUNCTION frag.sincronizar_resumen_pedidos_region()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM nodo_global.resumen_pedidos_region;
  INSERT INTO nodo_global.resumen_pedidos_region
  SELECT 'LIM-N', COUNT(*), COALESCE(SUM(total),0), MAX(fecha_creacion), now() FROM nodo_lim_n.pedido
  UNION ALL SELECT 'LIM-S', COUNT(*), COALESCE(SUM(total),0), MAX(fecha_creacion), now() FROM nodo_lim_s.pedido
  UNION ALL SELECT 'AQP', COUNT(*), COALESCE(SUM(total),0), MAX(fecha_creacion), now() FROM nodo_aqp.pedido;
END;
$$;
-- =========================================================
-- [11][12] Métricas de migración por región/entidad
-- =========================================================
CREATE OR REPLACE FUNCTION frag.registrar_metrica_migracion(
  p_region TEXT, p_esquema TEXT, p_entidad TEXT, p_filas BIGINT, p_errores INT, p_ms INT
) RETURNS VOID LANGUAGE sql AS $$
  INSERT INTO frag.migracion_metricas (region_codigo, esquema_pg, entidad, filas_migradas, errores, duracion_ms)
  VALUES ($1, $2, $3, $4, $5, $6);
$$;
-- =========================================================
-- [13][14] Métricas espacio y crecimiento
-- =========================================================
CREATE OR REPLACE FUNCTION frag.medir_espacio_nodos()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_rec RECORD; v_bytes BIGINT; v_cnt INT := 0;
BEGIN
  FOR v_rec IN SELECT region_codigo, esquema_pg FROM frag.mapa_nodos LOOP
    SELECT COALESCE(SUM(pg_total_relation_size(c.oid)), 0) INTO v_bytes
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = v_rec.esquema_pg AND c.relkind IN ('r','p');
    INSERT INTO frag.metricas_espacio_nodo (esquema_pg, region_codigo, tamano_bytes)
    VALUES (v_rec.esquema_pg, v_rec.region_codigo, v_bytes);
    v_cnt := v_cnt + 1;
  END LOOP;
  RETURN v_cnt;
END;
$$;
CREATE OR REPLACE FUNCTION frag.medir_crecimiento_tablas()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_esquema TEXT;
  v_tabla TEXT;
  v_filas BIGINT;
  v_bytes BIGINT;
  v_cnt INT := 0;
BEGIN
  FOREACH v_esquema IN ARRAY ARRAY['nodo_lim_n','nodo_lim_s','nodo_aqp'] LOOP
    FOREACH v_tabla IN ARRAY ARRAY['persona','cliente','pedido','producto','bitacora_evento'] LOOP
      EXECUTE format('SELECT COUNT(*) FROM %I.%I', v_esquema, v_tabla) INTO v_filas;
      SELECT pg_total_relation_size(format('%I.%I', v_esquema, v_tabla)::regclass) INTO v_bytes;
      INSERT INTO frag.metricas_crecimiento (esquema_pg, tabla_logica, filas, tamano_bytes)
      VALUES (v_esquema, v_tabla, v_filas, v_bytes);
      v_cnt := v_cnt + 1;
    END LOOP;
  END LOOP;
  RETURN v_cnt;
END;
$$;
-- =========================================================
-- [15][21] Benchmark consultas + EXPLAIN
-- =========================================================
CREATE OR REPLACE FUNCTION frag.benchmark_consulta(p_nombre TEXT, p_sql_public TEXT, p_sql_nodo TEXT, p_esquema TEXT)
RETURNS TABLE(origen TEXT, duracion_ms NUMERIC, filas BIGINT) LANGUAGE plpgsql AS $$
DECLARE v_inicio TIMESTAMPTZ; v_filas BIGINT; v_ms NUMERIC; v_plan TEXT;
BEGIN
  v_inicio := clock_timestamp();
  EXECUTE p_sql_public INTO v_filas;
  v_ms := EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio);
  INSERT INTO frag.metricas_consulta (nombre_consulta, origen, duracion_ms, filas_resultado)
  VALUES (p_nombre, 'public', v_ms, v_filas);
  origen := 'public'; duracion_ms := v_ms; filas := v_filas; RETURN NEXT;

  v_inicio := clock_timestamp();
  EXECUTE replace(p_sql_nodo, '{esquema}', p_esquema) INTO v_filas;
  v_ms := EXTRACT(MILLISECOND FROM clock_timestamp() - v_inicio);
  INSERT INTO frag.metricas_consulta (nombre_consulta, origen, esquema_pg, duracion_ms, filas_resultado)
  VALUES (p_nombre, 'nodo', v_ms, v_filas);
  origen := p_esquema; duracion_ms := v_ms; filas := v_filas; RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION frag.ejecutar_explain_benchmark()
RETURNS TABLE(consulta TEXT, origen TEXT, plan TEXT) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'EXPLAIN (FORMAT TEXT) SELECT COUNT(*) FROM public.pedido WHERE region_codigo = ''LIM-N''' INTO plan;
  consulta := 'pedidos LIM-N'; origen := 'public'; RETURN NEXT;
  EXECUTE 'EXPLAIN (FORMAT TEXT) SELECT COUNT(*) FROM nodo_lim_n.pedido' INTO plan;
  consulta := 'pedidos LIM-N'; origen := 'nodo_lim_n'; RETURN NEXT;
END;
$$;
-- =========================================================
-- [18-20] Índices compuestos y JOIN adicionales
-- =========================================================
CREATE OR REPLACE FUNCTION frag.crear_indices_avanzados_nodo(p_esquema TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_pedido_cli_fecha ON %1$I.pedido (id_cliente, fecha_creacion DESC)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_pedido_com_fecha ON %1$I.pedido (id_comercio, fecha_creacion DESC)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_detalle_ped_prod ON %1$I.detalle_pedido (id_pedido, id_producto)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_producto_cat ON %1$I.producto (id_categoria, id_comercio)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_usuario_rol ON %1$I.usuario (id_rol, cuenta_activa)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_parada_ruta ON %1$I.parada_ruta (id_ruta, id_pedido)', p_esquema);
  EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%1$s_ruta_repartidor ON %1$I.ruta_reparto (id_repartidor, fecha_planificacion)', p_esquema);
END;
$$;
SELECT frag.crear_indices_avanzados_nodo('nodo_lim_n');
SELECT frag.crear_indices_avanzados_nodo('nodo_lim_s');
SELECT frag.crear_indices_avanzados_nodo('nodo_aqp');

-- =========================================================
-- [22][23] Reconstruir nodo + validar duplicados
-- =========================================================
CREATE OR REPLACE FUNCTION frag.reconstruir_nodo_completo(p_region TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_esquema TEXT; v_dup BIGINT;
BEGIN
  SELECT esquema_pg INTO v_esquema FROM frag.mapa_nodos WHERE region_codigo = p_region AND NOT es_primario;
  IF NOT frag.validar_sin_duplicados_recuperacion(p_region) THEN
    RAISE EXCEPTION 'Duplicados detectados antes de reconstrucción en %', p_region;
  END IF;
  PERFORM frag.limpiar_fragmentos_nodo(v_esquema);
  PERFORM frag.migrar_region_a_nodo(p_region, v_esquema);
  PERFORM frag.sincronizar_replicas_globales(FALSE);
  INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, esquema_pg, detalle, exito)
  VALUES ('RECONSTRUCCION_COMPLETA', p_region, v_esquema, 'Nodo reconstruido desde cero', TRUE);
  RETURN format('Nodo % (%s) reconstruido', p_region, v_esquema);
END;
$$;
CREATE OR REPLACE FUNCTION frag.validar_sin_duplicados_recuperacion(p_region TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_esquema TEXT; v_cnt BIGINT;
BEGIN
  SELECT esquema_pg INTO v_esquema FROM frag.mapa_nodos WHERE region_codigo = p_region AND NOT es_primario;
  EXECUTE format('SELECT COUNT(*) - COUNT(DISTINCT id_persona) FROM %I.persona', v_esquema) INTO v_cnt;
  IF v_cnt > 0 THEN RETURN FALSE; END IF;
  EXECUTE format('SELECT COUNT(*) - COUNT(DISTINCT id_pedido) FROM %I.pedido', v_esquema) INTO v_cnt;
  IF v_cnt > 0 THEN RETURN FALSE; END IF;
  RETURN TRUE;
END;
$$;
-- =========================================================
-- [29-31] Simulaciones de prueba
-- =========================================================
CREATE OR REPLACE FUNCTION frag.simular_caida_nodo(p_region TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
  UPDATE frag.nodo_heartbeat SET estado = 'OFFLINE', disponible = FALSE, ultimo_error = 'Simulación de caída', ultima_conexion = now()
  WHERE region_codigo = p_region;
  INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, detalle, exito)
  VALUES ('SIM_CAIDA', p_region, 'Simulación: nodo marcado OFFLINE', TRUE);
  RETURN format('Nodo % en OFFLINE', p_region);
END;
$$;
CREATE OR REPLACE FUNCTION frag.simular_recuperacion_nodo(p_region TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
  UPDATE frag.nodo_heartbeat SET estado = 'ONLINE', disponible = TRUE, ultimo_error = NULL, ultima_conexion = now()
  WHERE region_codigo = p_region;
  RETURN frag.procesar_nodo_online(p_region);
END;
$$;
CREATE OR REPLACE FUNCTION frag.simular_perdida_comunicacion(p_region TEXT, p_duracion_seg INT DEFAULT 60)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
  UPDATE frag.nodo_heartbeat SET estado = 'DEGRADADO', disponible = FALSE,
    ultimo_error = format('Sin comunicación simulada %s s', p_duracion_seg), ultima_conexion = now() - (p_duracion_seg || ' seconds')::interval
  WHERE region_codigo = p_region;
  INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, detalle, exito)
  VALUES ('SIM_SIN_COMUNICACION', p_region, format('Comunicación perdida %s segundos', p_duracion_seg), TRUE);
  RETURN format('Nodo % en DEGRADADO', p_region);
END;
$$;
-- =========================================================
-- [32-34] Pruebas consistencia, integridad, huérfanos
-- =========================================================
CREATE OR REPLACE FUNCTION frag.prueba_consistencia_post_sync()
RETURNS TABLE(prueba TEXT, resultado BOOLEAN, detalle TEXT) LANGUAGE plpgsql AS $$
DECLARE v_ok BOOLEAN;
BEGIN
  SELECT bool_and(coincide) INTO v_ok FROM frag.validar_integridad_fragmentacion();
  prueba := 'Conteos public vs fragmentos'; resultado := COALESCE(v_ok, FALSE);
  detalle := CASE WHEN v_ok THEN 'OK' ELSE 'Diferencias detectadas' END; RETURN NEXT;

  SELECT COUNT(*) = 0 INTO v_ok FROM frag.replica_conflictos WHERE NOT resuelto;
  prueba := 'Conflictos de réplica pendientes'; resultado := v_ok;
  detalle := CASE WHEN v_ok THEN 'Sin conflictos' ELSE 'Hay conflictos abiertos' END; RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION frag.prueba_integridad_referencial_nodo(p_esquema TEXT)
RETURNS TABLE(prueba TEXT, huerfanos BIGINT) LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY EXECUTE format(
    $q$SELECT 'usuario sin persona'::TEXT, COUNT(*) FROM %1$I.usuario u
      WHERE NOT EXISTS (SELECT 1 FROM %1$I.persona p WHERE p.id_persona = u.id_persona)$q$, p_esquema);
  RETURN QUERY EXECUTE format(
    $q$SELECT 'detalle sin producto', COUNT(*) FROM %1$I.detalle_pedido d
      WHERE NOT EXISTS (SELECT 1 FROM %1$I.producto pr WHERE pr.id_producto = d.id_producto)$q$, p_esquema);
  RETURN QUERY EXECUTE format(
    $q$SELECT 'pedido sin cliente', COUNT(*) FROM %1$I.pedido pe
      WHERE NOT EXISTS (SELECT 1 FROM %1$I.cliente c WHERE c.id_cliente = pe.id_cliente)$q$, p_esquema);
END;
$$;
CREATE OR REPLACE FUNCTION frag.verificar_datos_huerfanos()
RETURNS TABLE(esquema TEXT, tipo TEXT, cantidad BIGINT) LANGUAGE plpgsql AS $$
DECLARE v_esquema TEXT;
BEGIN
  FOREACH v_esquema IN ARRAY ARRAY['nodo_lim_n','nodo_lim_s','nodo_aqp'] LOOP
    RETURN QUERY SELECT v_esquema, p.prueba, p.huerfanos FROM frag.prueba_integridad_referencial_nodo(v_esquema) p WHERE p.huerfanos > 0;
  END LOOP;
END;
$$;
-- =========================================================
-- [35-38] Concurrencia sync + limpieza colas
-- =========================================================
CREATE OR REPLACE FUNCTION frag.limpiar_replica_cambios_antiguos(p_dias INT DEFAULT 30)
RETURNS INTEGER LANGUAGE sql AS $$
  WITH del AS (
    DELETE FROM frag.replica_cambios WHERE procesado AND procesado_en < now() - ($1 || ' days')::interval RETURNING 1
  ) SELECT COUNT(*)::INT FROM del;
$$;
CREATE OR REPLACE FUNCTION frag.limpiar_fragmento_cambios_antiguos(p_dias INT DEFAULT 30)
RETURNS INTEGER LANGUAGE sql AS $$
  WITH del AS (
    DELETE FROM frag.fragmento_cambios WHERE procesado AND procesado_en < now() - ($1 || ' days')::interval RETURNING 1
  ) SELECT COUNT(*)::INT FROM del;
$$;
-- =========================================================
-- [16-17][40] VISTAS monitoreo
-- =========================================================
CREATE OR REPLACE VIEW frag.v_tamano_fragmentos AS
SELECT n.nspname AS esquema, c.relname AS tabla,
       pg_total_relation_size(c.oid) AS bytes,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamano
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('nodo_lim_n','nodo_lim_s','nodo_aqp','nodo_global')
  AND c.relkind IN ('r','p')
ORDER BY bytes DESC;

CREATE OR REPLACE VIEW frag.v_comparacion_tiempos_consulta AS
SELECT nombre_consulta, origen, esquema_pg, duracion_ms, filas_resultado, ejecutado_en
FROM frag.metricas_consulta ORDER BY ejecutado_en DESC;

CREATE OR REPLACE VIEW frag.v_disponibilidad_cluster AS
SELECT
  COUNT(*) FILTER (WHERE h.estado = 'ONLINE' AND h.disponible) AS nodos_online,
  COUNT(*) FILTER (WHERE h.estado = 'OFFLINE' OR NOT h.disponible) AS nodos_offline,
  COUNT(*) FILTER (WHERE h.estado = 'DEGRADADO') AS nodos_degradados,
  COUNT(*) AS total_nodos,
  ROUND(100.0 * COUNT(*) FILTER (WHERE h.estado = 'ONLINE' AND h.disponible) /
    NULLIF(COUNT(*) FILTER (WHERE NOT m.es_primario), 0), 1) AS pct_disponibilidad
FROM frag.mapa_nodos m
LEFT JOIN frag.nodo_heartbeat h ON h.region_codigo = m.region_codigo
WHERE NOT m.es_primario;

CREATE OR REPLACE VIEW frag.v_crecimiento_reciente AS
SELECT esquema_pg, tabla_logica, filas, pg_size_pretty(tamano_bytes) AS tamano, medicion_en
FROM frag.metricas_crecimiento ORDER BY medicion_en DESC;

CREATE OR REPLACE VIEW frag.v_espacio_por_nodo AS
SELECT esquema_pg, region_codigo, pg_size_pretty(tamano_bytes) AS tamano, medicion_en
FROM frag.metricas_espacio_nodo ORDER BY medicion_en DESC;


CREATE OR REPLACE FUNCTION frag.corregir_fk_particionadas_nodo(p_esquema TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('ALTER TABLE %I.detalle_pedido ADD COLUMN IF NOT EXISTS fecha_creacion_pedido TIMESTAMPTZ', p_esquema);
  EXECUTE format(
    'UPDATE %I.detalle_pedido d SET fecha_creacion_pedido = p.fecha_creacion FROM %I.pedido p WHERE p.id_pedido = d.id_pedido AND d.fecha_creacion_pedido IS NULL',
    p_esquema, p_esquema);
  EXECUTE format('ALTER TABLE %I.pago ADD COLUMN IF NOT EXISTS fecha_creacion_pedido TIMESTAMPTZ', p_esquema);
  EXECUTE format(
    'UPDATE %I.pago pg SET fecha_creacion_pedido = p.fecha_creacion FROM %I.pedido p WHERE p.id_pedido = pg.id_pedido AND pg.fecha_creacion_pedido IS NULL',
    p_esquema, p_esquema);
  BEGIN
    EXECUTE format('ALTER TABLE %I.detalle_pedido DROP CONSTRAINT IF EXISTS fk_detalle_pedido', p_esquema);
    EXECUTE format(
      'ALTER TABLE %I.detalle_pedido ADD CONSTRAINT fk_detalle_pedido FOREIGN KEY (id_pedido, fecha_creacion_pedido) REFERENCES %I.pedido(id_pedido, fecha_creacion)',
      p_esquema, p_esquema);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    EXECUTE format('ALTER TABLE %I.pago DROP CONSTRAINT IF EXISTS fk_pago_pedido', p_esquema);
    EXECUTE format(
      'ALTER TABLE %I.pago ADD CONSTRAINT fk_pago_pedido FOREIGN KEY (id_pedido, fecha_creacion_pedido) REFERENCES %I.pedido(id_pedido, fecha_creacion)',
      p_esquema, p_esquema);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    EXECUTE format('ALTER TABLE %I.parada_ruta DROP CONSTRAINT IF EXISTS fk_parada_pedido', p_esquema);
    EXECUTE format('ALTER TABLE %I.parada_ruta ADD COLUMN IF NOT EXISTS fecha_creacion_pedido TIMESTAMPTZ', p_esquema);
    EXECUTE format(
      'UPDATE %I.parada_ruta pr SET fecha_creacion_pedido = p.fecha_creacion FROM %I.pedido p WHERE p.id_pedido = pr.id_pedido AND pr.fecha_creacion_pedido IS NULL',
      p_esquema, p_esquema);
    EXECUTE format(
      'ALTER TABLE %I.parada_ruta ADD CONSTRAINT fk_parada_pedido FOREIGN KEY (id_pedido, fecha_creacion_pedido) REFERENCES %I.pedido(id_pedido, fecha_creacion)',
      p_esquema, p_esquema);
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
$$;

-- Fragmentación derivada y horizontal: cola fragmento_cambios (función unificada)
CREATE OR REPLACE FUNCTION frag.registrar_cambio_fragmento()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_region TEXT; v_id TEXT;
BEGIN
  v_region := COALESCE(NEW.region_codigo, OLD.region_codigo);
  IF TG_TABLE_NAME = 'detalle_pedido' THEN
    SELECT p.region_codigo INTO v_region FROM public.pedido p
    WHERE p.region_codigo = COALESCE(NEW.region_codigo, OLD.region_codigo)
      AND p.id_pedido = COALESCE(NEW.id_pedido, OLD.id_pedido);
    v_id := COALESCE(NEW.id_detalle_pedido, OLD.id_detalle_pedido)::TEXT;
  ELSIF TG_TABLE_NAME = 'pago' THEN
    SELECT p.region_codigo INTO v_region FROM public.pedido p
    WHERE p.region_codigo = COALESCE(NEW.region_codigo, OLD.region_codigo)
      AND p.id_pedido = COALESCE(NEW.id_pedido, OLD.id_pedido);
    v_id := COALESCE(NEW.id_pago, OLD.id_pago)::TEXT;
  ELSIF TG_TABLE_NAME = 'parada_ruta' THEN
    SELECT rr.region_codigo INTO v_region FROM public.ruta_reparto rr
    WHERE rr.region_codigo = COALESCE(NEW.region_codigo, OLD.region_codigo)
      AND rr.id_ruta = COALESCE(NEW.id_ruta, OLD.id_ruta);
    v_id := COALESCE(NEW.id_parada, OLD.id_parada)::TEXT;
  ELSIF TG_TABLE_NAME = 'saga_paso' THEN
    SELECT st.region_codigo INTO v_region FROM public.saga_transaccion st
    WHERE st.id_saga = COALESCE(NEW.id_saga, OLD.id_saga);
    v_id := COALESCE(NEW.id_paso, OLD.id_paso)::TEXT;
  ELSIF TG_TABLE_NAME = 'persona' THEN v_id := COALESCE(NEW.id_persona, OLD.id_persona)::TEXT;
  ELSIF TG_TABLE_NAME = 'usuario' THEN v_id := COALESCE(NEW.id_usuario, OLD.id_usuario)::TEXT;
  ELSIF TG_TABLE_NAME = 'cliente' THEN v_id := COALESCE(NEW.id_cliente, OLD.id_cliente)::TEXT;
  ELSIF TG_TABLE_NAME = 'comercio' THEN v_id := COALESCE(NEW.id_comercio, OLD.id_comercio)::TEXT;
  ELSIF TG_TABLE_NAME = 'pedido' THEN v_id := COALESCE(NEW.id_pedido, OLD.id_pedido)::TEXT;
  ELSIF TG_TABLE_NAME = 'bitacora_evento' THEN v_id := COALESCE(NEW.id_evento, OLD.id_evento)::TEXT;
  ELSE RETURN COALESCE(NEW, OLD);
  END IF;
  IF v_region IS NULL OR v_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;
  INSERT INTO frag.fragmento_cambios (tabla_logica, region_codigo, operacion, id_registro, version_origen)
  VALUES (TG_TABLE_NAME, v_region, SUBSTRING(TG_OP, 1, 1), v_id, now());
  RETURN COALESCE(NEW, OLD);
END;
$$;
DO $$ DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['persona','usuario','cliente','comercio','pedido','detalle_pedido','pago','bitacora_evento','parada_ruta','saga_paso'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS tg_frag_%s ON public.%I', t, t);
    EXECUTE format('CREATE TRIGGER tg_frag_%s AFTER INSERT OR UPDATE OR DELETE ON public.%I
      FOR EACH ROW EXECUTE PROCEDURE frag.registrar_cambio_fragmento()', t, t);
  END LOOP;
END $$;

-- ALTA: Fragmentación derivada vía tabla padre
-- =========================================================
CREATE OR REPLACE FUNCTION frag.migrar_pedidos_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_total BIGINT := 0; v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.pedido
    SELECT id_pedido, id_cliente, id_comercio, id_repartidor, id_estado_pedido,
           nombre_cliente, nombre_comercio, direccion_entrega, referencia_entrega,
           subtotal, costo_envio, total, fecha_creacion, fecha_confirmacion, fecha_entrega_real
    FROM public.pedido WHERE region_codigo = %2$L
    ON CONFLICT (id_pedido, fecha_creacion) DO UPDATE SET total = EXCLUDED.total$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  EXECUTE format($q$INSERT INTO %1$I.detalle_pedido (id_detalle_pedido, id_pedido, id_producto, nombre_producto,
           cantidad, precio_unitario, importe_linea, fecha_creacion_pedido)
    SELECT d.id_detalle_pedido, d.id_pedido, d.id_producto, d.nombre_producto, d.cantidad, d.precio_unitario,
           d.importe_linea, p.fecha_creacion
    FROM public.detalle_pedido d
    JOIN public.pedido p ON p.region_codigo = d.region_codigo AND p.id_pedido = d.id_pedido
    WHERE p.region_codigo = %2$L
    ON CONFLICT (id_detalle_pedido) DO UPDATE SET importe_linea = EXCLUDED.importe_linea$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  EXECUTE format($q$INSERT INTO %1$I.pago (id_pago, id_pedido, id_metodo_pago, id_estado_pago, monto, fecha_pago, fecha_creacion_pedido)
    SELECT pg.id_pago, pg.id_pedido, pg.id_metodo_pago, pg.id_estado_pago, pg.monto, pg.fecha_pago, p.fecha_creacion
    FROM public.pago pg
    JOIN public.pedido p ON p.region_codigo = pg.region_codigo AND p.id_pedido = pg.id_pedido
    WHERE p.region_codigo = %2$L
    ON CONFLICT (id_pago) DO UPDATE SET monto = EXCLUDED.monto$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  RETURN v_total;
END;
$$;
CREATE OR REPLACE FUNCTION frag.migrar_rutas_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_total BIGINT := 0; v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.ruta_reparto
    SELECT id_ruta, id_repartidor, fecha_planificacion, id_estado_ruta, hora_inicio_real, hora_fin_real,
           distancia_kilometros, observaciones, fecha_creacion
    FROM public.ruta_reparto WHERE region_codigo = %2$L
    ON CONFLICT (id_ruta) DO NOTHING$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  EXECUTE format($q$INSERT INTO %1$I.parada_ruta (id_parada, id_ruta, id_pedido, orden_visita,
           hora_estimada_llegada, hora_llegada_real, hora_salida_real, fecha_creacion_pedido)
    SELECT pr.id_parada, pr.id_ruta, pr.id_pedido, pr.orden_visita,
           pr.hora_estimada_llegada, pr.hora_llegada_real, pr.hora_salida_real, pe.fecha_creacion
    FROM public.parada_ruta pr
    JOIN public.ruta_reparto rr ON rr.region_codigo = pr.region_codigo AND rr.id_ruta = pr.id_ruta
    LEFT JOIN public.pedido pe ON pe.region_codigo = pr.region_codigo AND pe.id_pedido = pr.id_pedido
    WHERE rr.region_codigo = %2$L
    ON CONFLICT (id_parada) DO NOTHING$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  RETURN v_total;
END;
$$;
CREATE OR REPLACE FUNCTION frag.migrar_sagas_a_nodo(p_esquema TEXT, p_region TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_total BIGINT := 0; v_filas BIGINT;
BEGIN
  EXECUTE format($q$INSERT INTO %1$I.saga_transaccion
    SELECT id_saga, tipo_operacion, estado, id_pedido, payload, fecha_creacion, fecha_finalizacion
    FROM public.saga_transaccion WHERE region_codigo = %2$L
    ON CONFLICT (id_saga) DO UPDATE SET estado = EXCLUDED.estado$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;

  EXECUTE format($q$INSERT INTO %1$I.saga_paso
    SELECT sp.id_paso, sp.id_saga, sp.orden_paso, sp.nombre_paso, sp.estado, sp.nodo_ejecutor, sp.detalle, sp.fecha_ejecucion
    FROM public.saga_paso sp
    JOIN public.saga_transaccion st ON st.id_saga = sp.id_saga
    WHERE st.region_codigo = %2$L
    ON CONFLICT (id_paso) DO UPDATE SET estado = EXCLUDED.estado$q$, p_esquema, p_region);
  GET DIAGNOSTICS v_filas = ROW_COUNT; v_total := v_total + v_filas;
  RETURN v_total;
END;
$$;
-- Migración genérica con UPSERT (optimización)
CREATE OR REPLACE FUNCTION frag.migrar_tabla_region(
  p_esquema TEXT, p_region TEXT, p_tabla TEXT, p_sql_insert TEXT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_filas BIGINT;
BEGIN
  EXECUTE p_sql_insert;
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  PERFORM frag.registrar_metrica_migracion(p_region, p_esquema, p_tabla, v_filas, 0, NULL);
  RETURN v_filas;
EXCEPTION WHEN OTHERS THEN
  PERFORM frag.registrar_metrica_migracion(p_region, p_esquema, p_tabla, 0, 1, NULL);
  RAISE;
END;
$$;
-- =========================================================
-- ALTA: Recuperación desde nodo réplica (no solo public)
-- =========================================================
CREATE OR REPLACE FUNCTION frag.recuperar_desde_nodo_replica(p_region_caida TEXT, p_region_fuente TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_esq_caida TEXT; v_esq_fuente TEXT;
BEGIN
  SELECT esquema_pg INTO v_esq_caida FROM frag.mapa_nodos WHERE region_codigo = p_region_caida AND NOT es_primario;
  SELECT esquema_pg INTO v_esq_fuente FROM frag.mapa_nodos WHERE region_codigo = p_region_fuente AND NOT es_primario;
  IF v_esq_caida IS NULL OR v_esq_fuente IS NULL THEN
    RAISE EXCEPTION 'Regiones inválidas para recuperación: % -> %', p_region_caida, p_region_fuente;
  END IF;

  PERFORM frag.limpiar_fragmentos_nodo(v_esq_caida);

  EXECUTE format('INSERT INTO %I.catalogo_maestro SELECT * FROM %I.catalogo_maestro ON CONFLICT DO NOTHING', v_esq_caida, v_esq_fuente);
  EXECUTE format('INSERT INTO %I.persona SELECT * FROM %I.persona ON CONFLICT DO NOTHING', v_esq_caida, v_esq_fuente);
  EXECUTE format('INSERT INTO %I.pedido SELECT * FROM %I.pedido ON CONFLICT DO NOTHING', v_esq_caida, v_esq_fuente);

  INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, esquema_pg, detalle, exito)
  VALUES ('RECUPERACION_DESDE_REPLICA', p_region_caida, v_esq_caida,
    format('Datos copiados desde nodo réplica %s (%s)', p_region_fuente, v_esq_fuente), TRUE);
  RETURN format('Nodo % recuperado desde réplica %', p_region_caida, p_region_fuente);
END;
$$;
-- =========================================================
-- MEDIA: Heartbeat timeout, enrutamiento, saga incremental
-- =========================================================
CREATE OR REPLACE FUNCTION frag.detectar_nodos_offline_timeout()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_timeout INT; v_cnt INT;
BEGIN
  SELECT valor::INT INTO v_timeout FROM frag.config_cluster WHERE clave = 'heartbeat_timeout_seg';
  UPDATE frag.nodo_heartbeat SET estado = 'OFFLINE', disponible = FALSE,
    ultimo_error = 'Timeout: sin heartbeat'
  WHERE NOT esquema_pg = 'nodo_global'
    AND estado = 'ONLINE'
    AND ultima_conexion < now() - (v_timeout || ' seconds')::interval;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  RETURN v_cnt;
END;
$$;
CREATE OR REPLACE FUNCTION frag.enrutar_consulta(p_region TEXT, p_sql TEXT)
RETURNS SETOF RECORD LANGUAGE plpgsql AS $$
DECLARE v_esquema TEXT;
BEGIN
  SELECT esquema_pg INTO v_esquema FROM frag.mapa_nodos WHERE region_codigo = p_region AND NOT es_primario;
  IF v_esquema IS NULL THEN RAISE EXCEPTION 'Región % no enrutable', p_region; END IF;
  RETURN QUERY EXECUTE replace(p_sql, '{nodo}', v_esquema);
END;
$$;
-- Función helper para consultas tipadas
CREATE OR REPLACE FUNCTION frag.consultar_pedidos_region(p_region TEXT)
RETURNS TABLE(id_pedido UUID, total NUMERIC, fecha_creacion TIMESTAMPTZ) LANGUAGE plpgsql AS $$
DECLARE v_esquema TEXT;
BEGIN
  SELECT esquema_pg INTO v_esquema FROM frag.mapa_nodos WHERE region_codigo = p_region AND NOT es_primario;
  RETURN QUERY EXECUTE format('SELECT id_pedido, total, fecha_creacion FROM %I.pedido ORDER BY fecha_creacion DESC LIMIT 100', v_esquema);
END;
$$;
CREATE OR REPLACE FUNCTION frag.sincronizar_saga_monitoreo_incremental()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_rec RECORD; v_total INT := 0; v_n INT;
BEGIN
  FOR v_rec IN SELECT region_codigo, esquema_pg FROM frag.mapa_nodos WHERE NOT es_primario LOOP
    EXECUTE format($q$
      INSERT INTO nodo_global.saga_monitoreo AS m
      SELECT id_saga, %2$L, tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now()
      FROM %1$I.saga_transaccion
      ON CONFLICT (id_saga) DO UPDATE SET
        estado = EXCLUDED.estado, fecha_finalizacion = EXCLUDED.fecha_finalizacion, sincronizado_en = now()
    $q$, v_rec.esquema_pg, v_rec.region_codigo);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;
  END LOOP;
  RETURN v_total;
END;
$$;
-- Reemplazar saga sync simple
CREATE OR REPLACE FUNCTION frag.sincronizar_saga_monitoreo()
RETURNS INTEGER LANGUAGE plpgsql AS $$
BEGIN
  RETURN frag.sincronizar_saga_monitoreo_incremental();
EXCEPTION WHEN OTHERS THEN
  DELETE FROM nodo_global.saga_monitoreo;
  INSERT INTO nodo_global.saga_monitoreo
    SELECT id_saga, 'LIM-N', tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now() FROM nodo_lim_n.saga_transaccion
  UNION ALL SELECT id_saga, 'LIM-S', tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now() FROM nodo_lim_s.saga_transaccion
  UNION ALL SELECT id_saga, 'AQP', tipo_operacion, estado, id_pedido, fecha_creacion, fecha_finalizacion, now() FROM nodo_aqp.saga_transaccion;
  RETURN (SELECT COUNT(*)::INT FROM nodo_global.saga_monitoreo);
END;
$$;
-- Validación regional por trigger
CREATE OR REPLACE FUNCTION frag.validar_region_esquema()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_region_esperada TEXT;
BEGIN
  SELECT region_codigo INTO v_region_esperada FROM frag.mapa_nodos
  WHERE esquema_pg = TG_TABLE_SCHEMA AND NOT es_primario;
  IF v_region_esperada IS NOT NULL AND NEW.region_codigo IS NOT NULL AND NEW.region_codigo <> v_region_esperada THEN
    RAISE EXCEPTION 'Región % no permitida en esquema % (esperada %)', NEW.region_codigo, TG_TABLE_SCHEMA, v_region_esperada;
  END IF;
  RETURN NEW;
END;
$$;
-- =========================================================
-- OPTIMIZACIÓN: índices compuestos + vista estadísticas unificada
-- =========================================================
CREATE INDEX IF NOT EXISTS idx_public_pedido_region_fecha_est ON public.pedido (region_codigo, fecha_creacion);
CREATE INDEX IF NOT EXISTS idx_public_pedido_cliente_fecha ON public.pedido (id_cliente, fecha_creacion);
CREATE INDEX IF NOT EXISTS idx_public_pedido_comercio_fecha ON public.pedido (id_comercio, fecha_creacion);

DO $$ DECLARE s TEXT; BEGIN
  FOREACH s IN ARRAY ARRAY['nodo_lim_n','nodo_lim_s','nodo_aqp'] LOOP
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_ped_reg_fecha ON %I.pedido (fecha_creacion)', replace(s,'.','_'), s);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_ped_cli_fecha ON %I.pedido (id_cliente, fecha_creacion)', replace(s,'.','_'), s);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_ped_com_fecha ON %I.pedido (id_comercio, fecha_creacion)', replace(s,'.','_'), s);
  END LOOP;
END $$;

DROP VIEW IF EXISTS frag.v_estadisticas_lim_n;
DROP VIEW IF EXISTS frag.v_estadisticas_lim_s;
DROP VIEW IF EXISTS frag.v_estadisticas_aqp;

CREATE OR REPLACE FUNCTION frag.estadisticas_nodo(p_region TEXT DEFAULT NULL)
RETURNS TABLE(region TEXT, entidad TEXT, total BIGINT) LANGUAGE plpgsql AS $$
DECLARE v_rec RECORD; v_ent TEXT;
  v_tablas TEXT[] := ARRAY['persona','cliente','pedido','producto','detalle_pedido','pago'];
BEGIN
  FOR v_rec IN
    SELECT region_codigo, esquema_pg FROM frag.mapa_nodos
    WHERE NOT es_primario AND (p_region IS NULL OR region_codigo = p_region)
  LOOP
    FOREACH v_ent IN ARRAY v_tablas LOOP
      RETURN QUERY EXECUTE format(
        'SELECT %L::TEXT, %L::TEXT, COUNT(*)::BIGINT FROM %I.%I',
        v_rec.region_codigo, v_ent, v_rec.esquema_pg, v_ent);
    END LOOP;
  END LOOP;
END;
$$;
CREATE OR REPLACE VIEW frag.v_estadisticas_cluster AS
  SELECT * FROM frag.estadisticas_nodo(NULL);

CREATE OR REPLACE VIEW frag.v_desbalance_regiones AS
WITH stats AS (
  SELECT region, entidad, total FROM frag.v_estadisticas_cluster
)
SELECT entidad,
       MAX(total) AS max_regional, MIN(total) AS min_regional,
       ROUND(100.0 * (MAX(total) - MIN(total)) / NULLIF(MAX(total), 0), 2) AS pct_desbalance
FROM stats GROUP BY entidad HAVING MAX(total) > MIN(total);

-- =========================================================
-- VALIDACIONES PROFUNDAS
-- =========================================================
CREATE OR REPLACE FUNCTION frag.validar_integridad_profunda()
RETURNS TABLE(metrica TEXT, origen NUMERIC, fragmentado NUMERIC, coincide BOOLEAN) LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT 'count_persona'::TEXT,
    (SELECT COUNT(*)::NUMERIC FROM public.persona),
    (SELECT COUNT(*)::NUMERIC FROM nodo_lim_n.persona)+(SELECT COUNT(*) FROM nodo_lim_s.persona)+(SELECT COUNT(*) FROM nodo_aqp.persona),
    (SELECT COUNT(*) FROM public.persona) = (SELECT COUNT(*) FROM nodo_lim_n.persona)+(SELECT COUNT(*) FROM nodo_lim_s.persona)+(SELECT COUNT(*) FROM nodo_aqp.persona);

  RETURN QUERY SELECT 'sum_total_pedidos',
    (SELECT COALESCE(SUM(total),0) FROM public.pedido),
    (SELECT COALESCE(SUM(total),0) FROM nodo_lim_n.pedido)+(SELECT COALESCE(SUM(total),0) FROM nodo_lim_s.pedido)+(SELECT COALESCE(SUM(total),0) FROM nodo_aqp.pedido),
    (SELECT COALESCE(SUM(total),0) FROM public.pedido) =
    (SELECT COALESCE(SUM(total),0) FROM nodo_lim_n.pedido)+(SELECT COALESCE(SUM(total),0) FROM nodo_lim_s.pedido)+(SELECT COALESCE(SUM(total),0) FROM nodo_aqp.pedido);

  RETURN QUERY SELECT 'min_fecha_pedido',
    EXTRACT(EPOCH FROM (SELECT MIN(fecha_creacion) FROM public.pedido)),
    EXTRACT(EPOCH FROM (SELECT MIN(fecha_creacion) FROM frag.v_pedido_cluster)),
    (SELECT MIN(fecha_creacion) FROM public.pedido) = (SELECT MIN(fecha_creacion) FROM frag.v_pedido_cluster);

  RETURN QUERY SELECT 'max_fecha_pedido',
    EXTRACT(EPOCH FROM (SELECT MAX(fecha_creacion) FROM public.pedido)),
    EXTRACT(EPOCH FROM (SELECT MAX(fecha_creacion) FROM frag.v_pedido_cluster)),
    (SELECT MAX(fecha_creacion) FROM public.pedido) = (SELECT MAX(fecha_creacion) FROM frag.v_pedido_cluster);

  RETURN QUERY SELECT 'checksum_persona_docs',
    (SELECT SUM(hashtext(numero_documento::TEXT))::NUMERIC FROM public.persona),
    (SELECT SUM(hashtext(numero_documento::TEXT))::NUMERIC FROM frag.v_persona_cluster),
    (SELECT SUM(hashtext(numero_documento::TEXT)) FROM public.persona) =
    (SELECT SUM(hashtext(numero_documento::TEXT)) FROM frag.v_persona_cluster);
END;
$$;
CREATE OR REPLACE FUNCTION frag.validar_huerfanos_derivados()
RETURNS TABLE(esquema TEXT, tipo TEXT, cantidad BIGINT) LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY SELECT 'nodo_lim_n'::TEXT, 'detalle sin pedido',
    (SELECT COUNT(*) FROM nodo_lim_n.detalle_pedido d WHERE NOT EXISTS (
      SELECT 1 FROM nodo_lim_n.pedido p WHERE p.id_pedido = d.id_pedido));
  RETURN QUERY SELECT 'nodo_lim_n', 'pago sin pedido',
    (SELECT COUNT(*) FROM nodo_lim_n.pago pg WHERE NOT EXISTS (
      SELECT 1 FROM nodo_lim_n.pedido p WHERE p.id_pedido = pg.id_pedido));
  RETURN QUERY SELECT 'nodo_lim_n', 'parada sin ruta',
    (SELECT COUNT(*) FROM nodo_lim_n.parada_ruta pr WHERE NOT EXISTS (
      SELECT 1 FROM nodo_lim_n.ruta_reparto r WHERE r.id_ruta = pr.id_ruta));
  RETURN QUERY SELECT 'nodo_lim_n', 'saga_paso sin saga',
    (SELECT COUNT(*) FROM nodo_lim_n.saga_paso sp WHERE NOT EXISTS (
      SELECT 1 FROM nodo_lim_n.saga_transaccion st WHERE st.id_saga = sp.id_saga));
END;
$$;
CREATE OR REPLACE FUNCTION frag.verificar_replicas_antes_migracion()
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_pend INT; v_desync INT;
BEGIN
  SELECT COUNT(*) INTO v_pend FROM frag.replica_cambios WHERE NOT procesado;
  SELECT COUNT(*) INTO v_desync FROM frag.replica_control WHERE NOT en_sync AND tabla_logica = 'catalogo_maestro';
  IF v_pend > 0 THEN
    PERFORM frag.sincronizar_replica_incremental_cola();
  END IF;
  IF EXISTS (SELECT 1 FROM frag.replica_control WHERE NOT en_sync AND tabla_logica = 'catalogo_maestro') THEN
    RAISE EXCEPTION 'Réplicas de catálogo no sincronizadas. Ejecutar frag.sincronizar_replicas_globales(TRUE)';
  END IF;
  RETURN TRUE;
END;
$$;
-- =========================================================
-- SIMULACIÓN: apagar_nodo / encender_nodo + DR
-- =========================================================
CREATE OR REPLACE FUNCTION frag.apagar_nodo(p_region TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE frag.mapa_nodos SET activo = FALSE WHERE region_codigo = p_region;
  UPDATE frag.nodo_heartbeat SET estado = 'OFFLINE', disponible = FALSE,
    ultimo_error = 'apagar_nodo', ultima_conexion = now() WHERE region_codigo = p_region;
  INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, detalle, exito)
  VALUES ('APAGAR_NODO', p_region, 'Nodo apagado (simulación)', TRUE);
END;
$$;
CREATE OR REPLACE FUNCTION frag.encender_nodo(p_region TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE frag.mapa_nodos SET activo = TRUE WHERE region_codigo = p_region;
  UPDATE frag.nodo_heartbeat SET estado = 'ONLINE', disponible = TRUE, ultimo_error = NULL, ultima_conexion = now()
  WHERE region_codigo = p_region;
  PERFORM frag.procesar_nodo_online(p_region);
  INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, region_codigo, detalle, exito)
  VALUES ('ENCENDER_NODO', p_region, 'Nodo encendido y recuperado', TRUE);
END;
$$;
CREATE OR REPLACE FUNCTION frag.simular_fallo_sincronizacion()
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO frag.replica_cambios (tabla_logica, operacion, id_registro, version_origen)
  VALUES ('catalogo_maestro', 'U', '00000000-0000-0000-0000-000000000000', now());
  BEGIN
    PERFORM frag.sincronizar_replica_incremental_cola();
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO frag.bitacora_recuperacion_dr (tipo_evento, detalle, exito)
    VALUES ('SIM_FALLO_SYNC', SQLERRM, FALSE);
    PERFORM frag.sincronizar_replicas_globales(TRUE);
    RETURN 'Fallo simulado; recuperación con sync completa ejecutada';
  END;
  RETURN 'Sync incremental OK';
END;
$$;
CREATE OR REPLACE FUNCTION frag.simular_perdida_conectividad(p_region TEXT, p_segundos INT DEFAULT 90)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
  UPDATE frag.nodo_heartbeat SET estado = 'DEGRADADO', disponible = FALSE,
    ultima_conexion = now() - (p_segundos || ' seconds')::interval,
    ultimo_error = format('Pérdida de conectividad %s s', p_segundos)
  WHERE region_codigo = p_region;
  PERFORM frag.detectar_nodos_offline_timeout();
  PERFORM frag.sincronizar_replicas_globales(FALSE);
  PERFORM frag.sincronizar_fragmentos_incremental();
  RETURN format('Conectividad restaurada para %', p_region);
END;
$$;
CREATE OR REPLACE FUNCTION frag.ejecutar_escenario_dr(p_region TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_fuente TEXT;
BEGIN
  v_fuente := CASE p_region WHEN 'LIM-N' THEN 'LIM-S' WHEN 'LIM-S' THEN 'LIM-N' ELSE 'LIM-N' END;
  PERFORM frag.apagar_nodo(p_region);
  PERFORM frag.recuperar_desde_nodo_replica(p_region, v_fuente);
  PERFORM frag.encender_nodo(p_region);
  RETURN format('Escenario DR completado para %', p_region);
END;
$$;
-- Ejecutar migración
SELECT * FROM frag.migrar_fragmentos_a_nodos();
SELECT frag.sincronizar_saga_monitoreo() AS filas_saga_monitoreo;
SELECT frag.corregir_fk_particionadas_nodo('nodo_lim_n');
SELECT frag.corregir_fk_particionadas_nodo('nodo_lim_s');
SELECT frag.corregir_fk_particionadas_nodo('nodo_aqp');
SELECT frag.mantener_particiones_cluster(6);
SELECT frag.medir_espacio_nodos();
SELECT frag.medir_crecimiento_tablas();
SELECT frag.sincronizar_resumen_pedidos_region();
SELECT frag.detectar_nodos_offline_timeout();
-- detectar_conflictos_replica: opcional (comparación catálogo global vs réplicas)
DO $$ BEGIN
  PERFORM frag.detectar_conflictos_replica();
EXCEPTION WHEN OTHERS THEN
  INSERT INTO frag.auditoria_cluster (tipo_evento, detalle, exito)
  VALUES ('DETECTAR_CONFLICTOS', SQLERRM, FALSE);
END $$;


-- =========================================================
-- 7. CONSULTAS DE VERIFICACIÓN
-- =========================================================
SELECT 'Matriz de decisión' AS seccion;
SELECT tabla_logica,
       CASE WHEN replicar THEN 'Sí' ELSE 'No' END AS replicar,
       CASE WHEN frag_horizontal THEN 'Sí' ELSE 'No' END AS horizontal,
       CASE WHEN frag_derivada THEN 'Derivada' WHEN frag_vertical THEN 'Vertical' ELSE 'No' END AS tipo_extra,
       estrategia, criterio_decision
FROM matriz_fragmentacion ORDER BY id;

SELECT 'Fragmentación derivada' AS seccion;
SELECT * FROM fragmentacion_derivada ORDER BY id;

SELECT 'Estado de nodos (heartbeat)' AS seccion;
SELECT * FROM frag.v_admin_estado_nodos;

SELECT 'Réplicas — control ampliado' AS seccion;
SELECT * FROM frag.v_admin_replicas LIMIT 12;

SELECT 'Integridad public vs fragmentos' AS seccion;
SELECT * FROM frag.v_comparacion_migracion;

SELECT 'Estadísticas por nodo' AS seccion;
SELECT * FROM frag.v_estadisticas_cluster;

SELECT 'Sagas — monitoreo central' AS seccion;
SELECT region_codigo, estado, COUNT(*) AS sagas FROM nodo_global.saga_monitoreo
GROUP BY region_codigo, estado ORDER BY region_codigo, estado;

SELECT 'Integridad profunda' AS seccion;
SELECT * FROM frag.validar_integridad_profunda();

SELECT 'Huérfanos derivados' AS seccion;
SELECT * FROM frag.validar_huerfanos_derivados();

SELECT 'Disponibilidad del clúster' AS seccion;
SELECT * FROM frag.v_disponibilidad_cluster;

SELECT 'Tamaño de fragmentos' AS seccion;
SELECT esquema, tabla, tamano FROM frag.v_tamano_fragmentos LIMIT 15;

SELECT 'Pruebas de consistencia' AS seccion;
SELECT * FROM frag.prueba_consistencia_post_sync();

SELECT 'Réplica parcial — resumen pedidos' AS seccion;
SELECT * FROM nodo_global.resumen_pedidos_region;

