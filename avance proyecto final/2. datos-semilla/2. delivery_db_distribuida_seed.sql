-- =========================================================
-- Carga masiva de datos: delivery_db_distribuida
-- Carpeta: 2. datos-semilla  |  Orden: PASO 2 (después del paso 1)
--
--   psql -f "1. esquema/1. delivery_db_distribuida.sql"
--   psql -d delivery_db_distribuida -f "2. datos-semilla/2. delivery_db_distribuida_seed.sql"
--   psql -d delivery_db_distribuida -f "3. fragmentacion/3. delivery_db_fragmentacion_hv.sql"
--
-- Volúmenes generados (pedido / detalle_pedido / pago = 100 000 c/u):
--   LIM-N : 120 personas, 100 clientes, 20 repartidores, 25 comercios, 42 000 pedidos
--   LIM-S : 100 personas,  80 clientes, 15 repartidores, 20 comercios, 33 000 pedidos
--   AQP   :  80 personas,  65 clientes, 12 repartidores, 15 comercios, 25 000 pedidos
--   Total : 100 000 pedidos, 100 000 detalles (1 por pedido), 100 000 pagos (1 por pedido)
-- =========================================================

-- Limpia datos regionales previos (conserva nodo_registro y catalogo_maestro)
TRUNCATE saga_paso, saga_transaccion, bitacora_evento,
         parada_ruta, ruta_reparto, pago, detalle_pedido, pedido,
         producto, categoria_producto, comercio_proveedor,
         proveedor, comercio, repartidor, cliente, usuario, persona;

-- UUID determinístico (solo hex válido: 0-9, a-f)
-- p_tipo: 1=persona 2=usuario 3=cliente 4=repartidor 5=comercio 6=proveedor
--         7=categoria 8=producto 9=pedido 10=detalle 11=pago 12=ruta 13=parada 14=saga
-- proveedor: siempre vinculado a persona (natural o jurídica)
-- p_region: 1=LIM-N  2=LIM-S  3=AQP
CREATE OR REPLACE FUNCTION seed_uuid(p_tipo INT, p_region INT, p_n BIGINT)
RETURNS UUID LANGUAGE sql IMMUTABLE AS $$
  SELECT (
    lpad(to_hex(p_tipo), 8, '0') || '-' ||
    lpad(to_hex(p_region), 4, '0') || '-' ||
    '4001-8001-' ||
    lpad(to_hex(p_n), 12, '0')
  )::uuid;
$$;

-- =========================================================
-- Generación masiva por región
-- =========================================================
DO $$
DECLARE
  v_regiones      TEXT[] := ARRAY['LIM-N', 'LIM-S', 'AQP'];
  v_region        TEXT;
  v_reg_idx       INT;
  v_personas      INT;
  v_clientes      INT;
  v_repartidores  INT;
  v_comercios     INT;
  v_proveedores   INT;
  v_pedidos       INT;
  v_nombres       TEXT[] := ARRAY['María','Juan','Carlos','Ana','Luis','Rosa','Pedro','Lucía','Miguel','Elena','Jorge','Carmen','Diego','Patricia','Fernando','Sofía','Ricardo','Valeria','Andrés','Gabriela'];
  v_apellidos     TEXT[] := ARRAY['García','Rodríguez','López','Martínez','González','Pérez','Sánchez','Ramírez','Torres','Flores','Chávez','Rojas','Díaz','Vargas','Castro','Quispe','Mamani','Huamán','Silva','Mendoza'];
  v_tipos_com     TEXT[] := ARRAY['Restaurante','Pollería','Cevichería','Pizzería','Cafetería','Pastelería','Comida Rápida','Sushi Bar','Chifa','Delivery Saludable'];
  v_tipos_cat     TEXT[] := ARRAY['Platos','Bebidas','Postres','Promociones','Combos','Entradas'];
  v_tipos_prod    TEXT[] := ARRAY['Especial','Clásico','Premium','Familiar','Individual','Del día'];
  v_metodos_pago  TEXT[] := ARRAY['EFECTIVO','TARJETA','YAPE','PLIN','TRANSFERENCIA'];
  v_estados_pago  TEXT[] := ARRAY['PENDIENTE','PAGADO','RECHAZADO'];
  v_vehiculos     TEXT[] := ARRAY['MOTO','BICI','AUTO'];
  v_estados_ruta  TEXT[] := ARRAY['PLANIFICADA','EN_PROGRESO','FINALIZADA','CANCELADA'];
  v_prefs         TEXT[] := ARRAY['TODAS','SOLO_PEDIDOS','NINGUNA'];
  v_distritos     TEXT[];
  i               INT;
  j               INT;
  k               INT;
  v_id_persona    UUID;
  v_id_usuario    UUID;
  v_id_cliente    UUID;
  v_id_repartidor UUID;
  v_id_comercio   UUID;
  v_id_proveedor  UUID;
  v_id_categoria  UUID;
  v_id_producto   UUID;
  v_id_pedido     UUID;
  v_id_ruta       UUID;
  v_id_parada     UUID;
  v_id_tipo_natural UUID;
  v_id_tipo_juridica UUID;
  v_id_doc_dni UUID;
  v_id_doc_ruc UUID;
  v_nombre_com    TEXT;
  v_estado        TEXT;
  v_precio        NUMERIC(12,2);
  v_nombre_per    TEXT;
  v_nombre_prov   TEXT;
  v_rep_idx       INT;
  v_offset_doc    INT;
  v_pedido_global INT := 0;
  v_bitacora      INT := 0;
  v_saga          INT := 0;
  v_filas         INT;
  v_rec           RECORD;
BEGIN
  SELECT id_catalogo INTO v_id_tipo_natural
  FROM catalogo_maestro WHERE tipo_catalogo = 'TIPO_PERSONA' AND codigo = 'NATURAL';

  SELECT id_catalogo INTO v_id_tipo_juridica
  FROM catalogo_maestro WHERE tipo_catalogo = 'TIPO_PERSONA' AND codigo = 'JURIDICA';

  SELECT id_catalogo INTO v_id_doc_dni
  FROM catalogo_maestro WHERE tipo_catalogo = 'TIPO_DOCUMENTO' AND codigo = 'DNI';

  SELECT id_catalogo INTO v_id_doc_ruc
  FROM catalogo_maestro WHERE tipo_catalogo = 'TIPO_DOCUMENTO' AND codigo = 'RUC';

  -- Staging para carga masiva pedido + detalle + pago (1:1 y 100k total)
  CREATE TEMP TABLE IF NOT EXISTS tmp_seed_pedidos (
    p                INT PRIMARY KEY,
    estado           TEXT NOT NULL,
    cant             INT NOT NULL,
    envio            NUMERIC(12,2) NOT NULL,
    id_pedido        UUID NOT NULL,
    id_cliente       UUID NOT NULL,
    id_comercio      UUID NOT NULL,
    id_producto      UUID NOT NULL,
    id_repartidor    UUID,
    id_usuario       UUID NOT NULL,
    nombre_cliente   VARCHAR(240) NOT NULL,
    nombre_comercio  VARCHAR(160) NOT NULL,
    nombre_producto  VARCHAR(160) NOT NULL,
    precio           NUMERIC(12,2) NOT NULL,
    subtotal         NUMERIC(12,2) NOT NULL,
    total            NUMERIC(12,2) NOT NULL
  ) ON COMMIT PRESERVE ROWS;

  FOREACH v_region IN ARRAY v_regiones LOOP
    v_reg_idx := array_position(v_regiones, v_region);

    -- Parámetros por región (pedidos suman 100 000)
    IF v_region = 'LIM-N' THEN
      v_personas := 120; v_clientes := 100; v_repartidores := 20;
      v_comercios := 25; v_proveedores := 12; v_pedidos := 42000;
      v_distritos := ARRAY['Los Olivos','Independencia','San Martín de Porres','Comas','Carabayllo'];
      v_offset_doc := 71000000;
    ELSIF v_region = 'LIM-S' THEN
      v_personas := 100; v_clientes := 80; v_repartidores := 15;
      v_comercios := 20; v_proveedores := 10; v_pedidos := 33000;
      v_distritos := ARRAY['Surco','Miraflores','Barranco','Chorrillos','San Borja'];
      v_offset_doc := 72000000;
    ELSE
      v_personas := 80; v_clientes := 65; v_repartidores := 12;
      v_comercios := 15; v_proveedores := 8; v_pedidos := 25000;
      v_distritos := ARRAY['Yanahuara','Cayma','Cerro Colorado','Paucarpata','Sachaca'];
      v_offset_doc := 73000000;
    END IF;

    RAISE NOTICE 'Generando región % ...', v_region;

    -- PERSONAS + USUARIOS + CLIENTES (1..v_clientes)
    FOR i IN 1..v_clientes LOOP
      v_id_persona := seed_uuid(1, v_reg_idx, i);
      v_id_usuario := seed_uuid(2, v_reg_idx, i);
      v_nombre_per := v_nombres[1 + (i % array_length(v_nombres, 1))] || ' ' ||
                      v_apellidos[1 + ((i * 3) % array_length(v_apellidos, 1))];

      INSERT INTO persona (region_codigo, id_persona, id_tipo_persona, id_tipo_documento, numero_documento,
        nombres, apellidos, razon_social, correo, telefono, fecha_nacimiento, direccion, nodo_origen)
      VALUES (v_region, v_id_persona, v_id_tipo_natural, v_id_doc_dni, (v_offset_doc + i)::TEXT,
        split_part(v_nombre_per, ' ', 1),
        split_part(v_nombre_per, ' ', 2) || ' ' || split_part(v_nombre_per, ' ', 3),
        NULL,
        lower(replace(split_part(v_nombre_per, ' ', 1), 'í', 'i')) || '.' || i || '@mail.' || lower(v_region) || '.pe',
        '9' || lpad((80 + v_reg_idx)::TEXT, 2, '0') || lpad(i::TEXT, 7, '0'),
        DATE '1985-01-01' + (i % 5000),
        'Av. Principal ' || i || ', ' || v_distritos[1 + (i % array_length(v_distritos, 1))],
        v_region);

      INSERT INTO usuario (region_codigo, id_usuario, id_persona, id_rol, nombre_acceso,
        contrasena_hash, cuenta_activa, correo_verificado, nodo_origen)
      VALUES (v_region, v_id_usuario, v_id_persona,
        id_catalogo_por_tipo_codigo('ROL', 'CLIENTE'),
        'cliente.' || i || '@' || lower(v_region) || '.pe',
        '$2b$10$seedhashcliente' || i, TRUE, (i % 3 <> 0), v_region);

      v_id_cliente := seed_uuid(3, v_reg_idx, i);
      INSERT INTO cliente (region_codigo, id_cliente, id_usuario, id_preferencia_notificacion,
        acepta_publicidad, nodo_origen)
      VALUES (v_region, v_id_cliente, v_id_usuario,
        id_catalogo_por_tipo_codigo('PREFERENCIA_NOTIFICACION', v_prefs[1 + (i % 3)]), (i % 4 = 0), v_region);
    END LOOP;

    -- PERSONAS + USUARIOS + REPARTIDORES (v_clientes+1 .. v_personas)
    FOR i IN (v_clientes + 1)..v_personas LOOP
      v_id_persona := seed_uuid(1, v_reg_idx, i);
      v_id_usuario := seed_uuid(2, v_reg_idx, i);
      v_rep_idx := i - v_clientes;

      INSERT INTO persona (region_codigo, id_persona, id_tipo_persona, id_tipo_documento, numero_documento,
        nombres, apellidos, razon_social, correo, telefono, direccion, nodo_origen)
      VALUES (v_region, v_id_persona, v_id_tipo_natural, v_id_doc_dni, (v_offset_doc + i)::TEXT,
        'Repartidor' || v_rep_idx,
        v_apellidos[1 + (v_rep_idx % array_length(v_apellidos, 1))],
        NULL,
        'repartidor.' || v_rep_idx || '@' || lower(v_region) || '.pe',
        '9' || lpad((90 + v_reg_idx)::TEXT, 2, '0') || lpad(v_rep_idx::TEXT, 7, '0'),
        'Base logística ' || v_distritos[1 + (v_rep_idx % array_length(v_distritos, 1))],
        v_region);

      INSERT INTO usuario (region_codigo, id_usuario, id_persona, id_rol, nombre_acceso,
        contrasena_hash, nodo_origen)
      VALUES (v_region, v_id_usuario, v_id_persona,
        id_catalogo_por_tipo_codigo('ROL', 'REPARTIDOR'),
        'repartidor.' || v_rep_idx || '@' || lower(v_region) || '.pe',
        '$2b$10$seedhashrepartidor' || v_rep_idx, v_region);

      v_id_repartidor := seed_uuid(4, v_reg_idx, v_rep_idx);
      INSERT INTO repartidor (region_codigo, id_repartidor, id_persona, id_usuario,
        id_tipo_vehiculo, placa, disponible, nodo_origen)
      VALUES (v_region, v_id_repartidor, v_id_persona, v_id_usuario,
        id_catalogo_por_tipo_codigo('TIPO_VEHICULO', v_vehiculos[1 + (v_rep_idx % 3)]),
        CASE WHEN v_rep_idx % 3 = 1 THEN NULL ELSE 'X' || v_reg_idx || '-' || lpad(v_rep_idx::TEXT, 3, '0') END,
        (v_rep_idx % 5 <> 0), v_region);
    END LOOP;

    -- PROVEEDORES: persona JURIDICA con razon_social; nombres y apellidos NULL
    FOR i IN 1..v_proveedores LOOP
      v_id_proveedor := seed_uuid(6, v_reg_idx, i);
      v_id_persona := seed_uuid(1, v_reg_idx, v_personas + i);

      IF i <= GREATEST(1, (v_proveedores + 2) / 3) THEN
        v_nombre_prov := v_nombres[1 + (i % array_length(v_nombres, 1))] || ' ' ||
                         v_apellidos[1 + ((i * 5) % array_length(v_apellidos, 1))] || ' - Insumos';
      ELSE
        v_nombre_prov := 'Proveedor ' || v_region || ' ' ||
                         v_tipos_com[1 + (i % array_length(v_tipos_com, 1))] || ' SAC';
      END IF;

      INSERT INTO persona (region_codigo, id_persona, id_tipo_persona, id_tipo_documento, numero_documento,
        nombres, apellidos, razon_social, correo, telefono, direccion, nodo_origen)
      VALUES (v_region, v_id_persona, v_id_tipo_juridica, v_id_doc_ruc,
        '20' || v_reg_idx || lpad(i::TEXT, 8, '0'),
        NULL,
        NULL,
        v_nombre_prov,
        'prov.' || i || '@' || lower(v_region) || '.pe',
        '01' || lpad((400000 + i)::TEXT, 7, '0'),
        'Zona industrial ' || i || ', ' || v_distritos[1 + (i % array_length(v_distritos, 1))],
        v_region);

      INSERT INTO proveedor (region_codigo, id_proveedor, id_persona, notas, nodo_origen)
      VALUES (v_region, v_id_proveedor, v_id_persona,
        'Proveedor registrado con razón social en persona', v_region);
    END LOOP;

    -- COMERCIOS + CATEGORÍAS + PRODUCTOS
    FOR i IN 1..v_comercios LOOP
      v_id_comercio := seed_uuid(5, v_reg_idx, i);
      v_nombre_com := v_tipos_com[1 + (i % array_length(v_tipos_com, 1))] || ' ' ||
                      v_distritos[1 + (i % array_length(v_distritos, 1))] || ' #' || i;

      INSERT INTO comercio (region_codigo, id_comercio, nombre, ruc, telefono, correo, direccion, nodo_origen)
      VALUES (v_region, v_id_comercio, v_nombre_com,
        '10' || v_reg_idx || lpad(i::TEXT, 8, '0'),
        '01' || lpad((500000 + i)::TEXT, 7, '0'),
        'local.' || i || '@' || lower(v_region) || '.pe',
        'Calle Comercial ' || i || ', ' || v_distritos[1 + (i % array_length(v_distritos, 1))],
        v_region);

      -- Enlazar con 1 a 3 proveedores de la misma región
      FOR j IN 1..(1 + (i % 3)) LOOP
        INSERT INTO comercio_proveedor (region_codigo, id_comercio, id_proveedor, notas)
        VALUES (v_region, v_id_comercio, seed_uuid(6, v_reg_idx, 1 + ((i + j - 1) % v_proveedores)),
          'Abastecimiento tipo ' || j)
        ON CONFLICT DO NOTHING;
      END LOOP;

      -- 4 categorías por comercio
      FOR j IN 1..4 LOOP
        v_id_categoria := seed_uuid(7, v_reg_idx, (i - 1) * 4 + j);
        INSERT INTO categoria_producto (region_codigo, id_categoria, id_comercio, nombre, nodo_origen)
        VALUES (v_region, v_id_categoria, v_id_comercio,
          v_tipos_cat[1 + ((j - 1) % array_length(v_tipos_cat, 1))] || ' ' || j, v_region);

        -- 6 productos por categoría
        FOR k IN 1..6 LOOP
          v_id_producto := seed_uuid(8, v_reg_idx, ((i - 1) * 4 + (j - 1)) * 6 + k);
          v_precio := round((8 + (k * 3.5) + (i % 10) + (j % 5))::numeric, 2);
          INSERT INTO producto (region_codigo, id_producto, id_comercio, id_categoria,
            nombre, descripcion, precio, disponible, nodo_origen)
          VALUES (v_region, v_id_producto, v_id_comercio, v_id_categoria,
            v_tipos_prod[1 + (k % array_length(v_tipos_prod, 1))] || ' - ' || v_nombre_com || ' #' || k,
            'Descripción del producto ' || k || ' del comercio ' || i,
            v_precio, (k % 8 <> 0), v_region);
        END LOOP;
      END LOOP;
    END LOOP;

    -- PEDIDOS + DETALLE + PAGO (carga masiva 1:1:1 vía tmp_seed_pedidos)
    RAISE NOTICE 'Generando % pedidos/detalles/pagos en % ...', v_pedidos, v_region;
    TRUNCATE tmp_seed_pedidos;

    INSERT INTO tmp_seed_pedidos (
      p, estado, cant, envio, id_pedido, id_cliente, id_comercio, id_producto,
      id_repartidor, id_usuario, nombre_cliente, nombre_comercio, nombre_producto,
      precio, subtotal, total)
    SELECT
      b.p,
      b.estado,
      b.cant,
      b.envio,
      seed_uuid(9, v_reg_idx, b.p),
      seed_uuid(3, v_reg_idx, b.cli_n),
      seed_uuid(5, v_reg_idx, b.com_n),
      seed_uuid(8, v_reg_idx, (b.com_n - 1) * 24 + b.prod_n),
      CASE
        WHEN b.estado IN ('EN_CAMINO', 'ENTREGADO', 'CONFIRMADO') AND b.p % 7 <> 0
        THEN seed_uuid(4, v_reg_idx, 1 + ((b.p - 1) % v_repartidores))
        ELSE NULL
      END,
      seed_uuid(2, v_reg_idx, b.cli_n),
      left(trim(per.nombres || ' ' || coalesce(per.apellidos, '')), 240),
      left(com.nombre, 160),
      pr.nombre,
      pr.precio,
      round(pr.precio * b.cant, 2),
      round(pr.precio * b.cant, 2) + b.envio
    FROM (
      SELECT
        gs.p,
        1 + ((gs.p * 7) % v_clientes) AS cli_n,
        1 + ((gs.p - 1) % v_comercios) AS com_n,
        1 + ((gs.p - 1) % 24) AS prod_n,
        1 + (gs.p % 3) AS cant,
        round((4 + (gs.p % 6))::numeric, 2) AS envio,
        CASE
          WHEN gs.p % 20 = 0 THEN 'CANCELADO'
          WHEN gs.p % 5 = 0 THEN 'CREADO'
          WHEN gs.p % 4 = 0 THEN 'CONFIRMADO'
          WHEN gs.p % 3 = 0 THEN 'EN_CAMINO'
          ELSE 'ENTREGADO'
        END AS estado
      FROM generate_series(1, v_pedidos) AS gs(p)
    ) b
    JOIN persona per
      ON per.region_codigo = v_region
     AND per.id_persona = seed_uuid(1, v_reg_idx, b.cli_n)
    JOIN comercio com
      ON com.region_codigo = v_region
     AND com.id_comercio = seed_uuid(5, v_reg_idx, b.com_n)
    JOIN producto pr
      ON pr.region_codigo = v_region
     AND pr.id_producto = seed_uuid(8, v_reg_idx, (b.com_n - 1) * 24 + b.prod_n);

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    IF v_filas <> v_pedidos THEN
      RAISE EXCEPTION 'Región %: se esperaban % pedidos en staging y se generaron %',
        v_region, v_pedidos, v_filas;
    END IF;

    INSERT INTO pedido (region_codigo, id_pedido, id_cliente, id_comercio, id_repartidor,
      id_estado_pedido, nombre_cliente, nombre_comercio, direccion_entrega,
      referencia_entrega, subtotal, costo_envio, total, nodo_origen,
      fecha_confirmacion, fecha_entrega_real)
    SELECT
      v_region,
      t.id_pedido,
      t.id_cliente,
      t.id_comercio,
      t.id_repartidor,
      id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', t.estado),
      t.nombre_cliente,
      t.nombre_comercio,
      'Dirección entrega pedido ' || t.p || ', ' ||
        v_distritos[1 + ((t.p - 1) % array_length(v_distritos, 1))],
      CASE WHEN t.p % 3 = 0 THEN 'Referencia ' || t.p ELSE NULL END,
      t.subtotal,
      t.envio,
      t.total,
      v_region,
      CASE WHEN t.estado <> 'CREADO'
           THEN now() - ((t.p % 30) || ' days')::interval ELSE NULL END,
      CASE WHEN t.estado = 'ENTREGADO'
           THEN now() - ((t.p % 30) || ' days')::interval + interval '45 minutes'
           ELSE NULL END
    FROM tmp_seed_pedidos t;

    INSERT INTO detalle_pedido (region_codigo, id_detalle_pedido, id_pedido, id_producto,
      nombre_producto, cantidad, precio_unitario, importe_linea, nodo_origen)
    SELECT
      v_region,
      seed_uuid(10, v_reg_idx, t.p),
      t.id_pedido,
      t.id_producto,
      t.nombre_producto,
      t.cant,
      t.precio,
      t.subtotal,
      v_region
    FROM tmp_seed_pedidos t;

    INSERT INTO pago (region_codigo, id_pago, id_pedido, id_metodo_pago, id_estado_pago,
      monto, nodo_origen, fecha_pago)
    SELECT
      v_region,
      seed_uuid(11, v_reg_idx, t.p),
      t.id_pedido,
      id_catalogo_por_tipo_codigo(
        'METODO_PAGO',
        v_metodos_pago[1 + ((t.p - 1) % array_length(v_metodos_pago, 1))]
      ),
      id_catalogo_por_tipo_codigo(
        'ESTADO_PAGO',
        CASE
          WHEN t.estado IN ('ENTREGADO', 'EN_CAMINO') THEN 'PAGADO'
          WHEN t.estado = 'CANCELADO' THEN 'DEVUELTO'
          ELSE v_estados_pago[1 + (t.p % 2)]
        END
      ),
      t.total,
      v_region,
      CASE WHEN t.estado IN ('ENTREGADO', 'EN_CAMINO')
           THEN now() - ((t.p % 30) || ' days')::interval ELSE NULL END
    FROM tmp_seed_pedidos t;

    -- Bitácora: muestra (~2%) para no inflar auditoría al volumen de 100k
    INSERT INTO bitacora_evento (region_codigo, tipo_evento, tabla_afectada, id_registro,
      descripcion, id_usuario, nodo_origen, datos_adicionales)
    SELECT
      v_region,
      'PEDIDO_' || t.estado,
      'pedido',
      t.id_pedido,
      'Pedido ' || t.p || ' en estado ' || t.estado || ' (' || v_region || ')',
      t.id_usuario,
      v_region,
      jsonb_build_object('total', t.total, 'estado', t.estado)
    FROM tmp_seed_pedidos t
    WHERE t.p % 50 = 0;

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    v_bitacora := v_bitacora + v_filas;

    -- Sagas cada 100 pedidos (muestra representativa)
    INSERT INTO saga_transaccion (id_saga, tipo_operacion, region_codigo, estado, id_pedido, payload, fecha_finalizacion)
    SELECT
      seed_uuid(14, v_reg_idx, t.p),
      'CREAR_PEDIDO',
      v_region,
      CASE
        WHEN t.estado = 'CANCELADO' THEN 'FALLIDA'
        WHEN t.estado = 'CREADO' THEN 'INICIADA'
        ELSE 'COMPLETADA'
      END,
      t.id_pedido,
      jsonb_build_object('pedido', t.p, 'region', v_region, 'total', t.total),
      CASE WHEN t.estado NOT IN ('CREADO', 'CANCELADO') THEN now() ELSE NULL END
    FROM tmp_seed_pedidos t
    WHERE t.p % 100 = 0;

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    v_saga := v_saga + v_filas;

    INSERT INTO saga_paso (id_saga, orden_paso, nombre_paso, estado, nodo_ejecutor, detalle, fecha_ejecucion)
    SELECT seed_uuid(14, v_reg_idx, t.p), 1, 'validar_stock', 'OK', v_region,
           '{"ok":true}'::jsonb, now()
    FROM tmp_seed_pedidos t WHERE t.p % 100 = 0
    UNION ALL
    SELECT seed_uuid(14, v_reg_idx, t.p), 2, 'crear_pedido', 'OK', v_region,
           jsonb_build_object('id_pedido', t.id_pedido), now()
    FROM tmp_seed_pedidos t WHERE t.p % 100 = 0
    UNION ALL
    SELECT seed_uuid(14, v_reg_idx, t.p), 3, 'registrar_pago',
           CASE WHEN t.estado = 'CANCELADO' THEN 'ERROR'
                WHEN t.estado = 'CREADO' THEN 'PENDIENTE' ELSE 'OK' END,
           v_region, '{}'::jsonb,
           CASE WHEN t.estado NOT IN ('CREADO','CANCELADO') THEN now() ELSE NULL END
    FROM tmp_seed_pedidos t WHERE t.p % 100 = 0
    UNION ALL
    SELECT seed_uuid(14, v_reg_idx, t.p), 4, 'confirmar_pedido',
           CASE WHEN t.estado IN ('ENTREGADO','EN_CAMINO','CONFIRMADO') THEN 'OK'
                WHEN t.estado = 'CANCELADO' THEN 'COMPENSADO' ELSE 'PENDIENTE' END,
           v_region, '{}'::jsonb, NULL
    FROM tmp_seed_pedidos t WHERE t.p % 100 = 0;

    v_pedido_global := v_pedido_global + v_pedidos;
    RAISE NOTICE 'Región %: % pedidos/detalles/pagos insertados.', v_region, v_pedidos;

    -- RUTAS DE REPARTO (agrupar pedidos EN_CAMINO y ENTREGADO por repartidor)
    FOR v_rep_idx IN 1..v_repartidores LOOP
      FOR j IN 1..3 LOOP
        v_id_ruta := seed_uuid(12, v_reg_idx, (v_rep_idx - 1) * 3 + j);
        v_id_repartidor := seed_uuid(4, v_reg_idx, v_rep_idx);
        v_estado := v_estados_ruta[1 + ((v_rep_idx + j) % 4)];

        INSERT INTO ruta_reparto (region_codigo, id_ruta, id_repartidor, fecha_planificacion,
          id_estado_ruta, hora_inicio_real, hora_fin_real, distancia_kilometros, nodo_origen)
        VALUES (v_region, v_id_ruta, v_id_repartidor,
          CURRENT_DATE - (j * 2),
          id_catalogo_por_tipo_codigo('ESTADO_RUTA', v_estado),
          CASE WHEN v_estado <> 'PLANIFICADA' THEN now() - (j || ' days')::interval ELSE NULL END,
          CASE WHEN v_estado = 'FINALIZADA' THEN now() - (j || ' days')::interval + interval '2 hours' ELSE NULL END,
          round((3 + v_rep_idx * 0.5 + j)::numeric, 2), v_region);

        -- Hasta 4 paradas por ruta desde pedidos del repartidor
        k := 0;
        FOR v_rec IN
          SELECT pe.id_pedido
          FROM pedido pe
          WHERE pe.region_codigo = v_region
            AND pe.id_repartidor = v_id_repartidor
            AND pe.id_estado_pedido IN (
              id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'EN_CAMINO'),
              id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'ENTREGADO'),
              id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'CONFIRMADO'))
          ORDER BY pe.fecha_creacion
          LIMIT 4
        LOOP
          k := k + 1;
          v_id_pedido := v_rec.id_pedido;
          v_id_parada := seed_uuid(13, v_reg_idx, ((v_rep_idx - 1) * 3 + (j - 1)) * 4 + k);
          INSERT INTO parada_ruta (region_codigo, id_parada, id_ruta, id_pedido, orden_visita,
            hora_estimada_llegada, hora_llegada_real, nodo_origen)
          VALUES (v_region, v_id_parada, v_id_ruta, v_id_pedido, k,
            now() - (j || ' days')::interval + (k * 20 || ' minutes')::interval,
            CASE WHEN v_estado = 'FINALIZADA' THEN now() - (j || ' days')::interval + (k * 25 || ' minutes')::interval ELSE NULL END,
            v_region)
          ON CONFLICT DO NOTHING;
        END LOOP;
      END LOOP;
    END LOOP;

    RAISE NOTICE 'Región % completada.', v_region;
  END LOOP;

  DROP TABLE IF EXISTS tmp_seed_pedidos;

  RAISE NOTICE 'Total pedidos generados: %', v_pedido_global;
  RAISE NOTICE 'Total eventos bitácora (muestra): %', v_bitacora;
  RAISE NOTICE 'Total sagas (muestra): %', v_saga;
END $$;

-- =========================================================
-- Resumen de datos generados
-- =========================================================
SELECT 'persona' AS tabla, region_codigo, COUNT(*) AS filas FROM persona GROUP BY region_codigo
UNION ALL SELECT 'usuario', region_codigo, COUNT(*) FROM usuario GROUP BY region_codigo
UNION ALL SELECT 'cliente', region_codigo, COUNT(*) FROM cliente GROUP BY region_codigo
UNION ALL SELECT 'repartidor', region_codigo, COUNT(*) FROM repartidor GROUP BY region_codigo
UNION ALL SELECT 'comercio', region_codigo, COUNT(*) FROM comercio GROUP BY region_codigo
UNION ALL SELECT 'proveedor', region_codigo, COUNT(*) FROM proveedor GROUP BY region_codigo
UNION ALL SELECT 'comercio_proveedor', region_codigo, COUNT(*) FROM comercio_proveedor GROUP BY region_codigo
UNION ALL SELECT 'categoria_producto', region_codigo, COUNT(*) FROM categoria_producto GROUP BY region_codigo
UNION ALL SELECT 'producto', region_codigo, COUNT(*) FROM producto GROUP BY region_codigo
UNION ALL SELECT 'pedido', region_codigo, COUNT(*) FROM pedido GROUP BY region_codigo
UNION ALL SELECT 'detalle_pedido', region_codigo, COUNT(*) FROM detalle_pedido GROUP BY region_codigo
UNION ALL SELECT 'pago', region_codigo, COUNT(*) FROM pago GROUP BY region_codigo
UNION ALL SELECT 'ruta_reparto', region_codigo, COUNT(*) FROM ruta_reparto GROUP BY region_codigo
UNION ALL SELECT 'parada_ruta', region_codigo, COUNT(*) FROM parada_ruta GROUP BY region_codigo
UNION ALL SELECT 'bitacora_evento', COALESCE(region_codigo, 'TODAS'), COUNT(*) FROM bitacora_evento GROUP BY region_codigo
UNION ALL SELECT 'saga_transaccion', region_codigo, COUNT(*) FROM saga_transaccion GROUP BY region_codigo
ORDER BY tabla, region_codigo;

-- Totales globales de las tablas de alto volumen
SELECT 'pedido' AS tabla, COUNT(*) AS filas FROM pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido
UNION ALL SELECT 'pago', COUNT(*) FROM pago;

-- Pedidos por región y estado
SELECT pe.region_codigo, cm.codigo AS estado_pedido, COUNT(*) AS cantidad, ROUND(SUM(pe.total), 2) AS monto_total
FROM pedido pe
JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_estado_pedido
GROUP BY pe.region_codigo, cm.codigo
ORDER BY pe.region_codigo, cm.codigo;

-- Personas por región y tipo (FK a catalogo_maestro)
SELECT pe.region_codigo, cm.codigo AS tipo_persona_codigo, cm.nombre AS tipo_persona, COUNT(*) AS cantidad
FROM persona pe
JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_tipo_persona
GROUP BY pe.region_codigo, cm.codigo, cm.nombre
ORDER BY pe.region_codigo, cm.codigo;

-- Proveedores: razon_social, documento vía catálogo
SELECT pr.region_codigo, cm_tp.codigo AS tipo_persona,
       pe.razon_social, pe.nombres, pe.apellidos,
       cm_doc.codigo AS tipo_documento, pe.numero_documento,
       pe.correo, pe.telefono
FROM proveedor pr
JOIN persona pe ON pe.region_codigo = pr.region_codigo AND pe.id_persona = pr.id_persona
JOIN catalogo_maestro cm_tp ON cm_tp.id_catalogo = pe.id_tipo_persona
JOIN catalogo_maestro cm_doc ON cm_doc.id_catalogo = pe.id_tipo_documento
ORDER BY pr.region_codigo
LIMIT 20;

-- =========================================================
-- Consultas de exploración (descomentar en psql)
-- =========================================================
-- SELECT * FROM v_resumen_fragmentacion;
-- SELECT region_codigo, nombre_cliente, nombre_comercio, cm.codigo AS estado_pedido, total
-- FROM pedido p JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido LIMIT 20;
-- SELECT p.region_codigo, COUNT(d.id_detalle_pedido) AS lineas, p.total FROM pedido p JOIN detalle_pedido d ON d.region_codigo = p.region_codigo AND d.id_pedido = p.id_pedido GROUP BY p.region_codigo, p.id_pedido, p.total LIMIT 20;
