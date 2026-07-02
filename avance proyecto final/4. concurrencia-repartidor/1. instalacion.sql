-- =========================================================
-- PASO 4.1 — Instalacion concurrencia REPARTIDOR.disponible
-- Carpeta: 4. concurrencia-repartidor
--
-- Ejecutar UNA vez (después de pasos 1 y 2):
--   psql -d delivery_db_distribuida -f "4. concurrencia-repartidor/1. instalacion.sql"
--
-- Demo en 2 ventanas (desde psql, con \cd a esta carpeta):
--   2. prep.sql
--   3. sin_control_ventana1.sql  +  4. sin_control_ventana2.sql  (problema)
--   2. prep.sql  (reiniciar)
--   5. con_control_ventana1.sql  +  6. con_control_ventana2.sql  (solucion)
--   7. verificar.sql
-- =========================================================

-- Datos de demo
DO $$
DECLARE
  v_region          VARCHAR(10) := 'LIM-N';
  v_id_repartidor   UUID;
  v_id_cliente      UUID;
  v_id_comercio     UUID;
  v_nombre_cliente  TEXT;
  v_nombre_comercio TEXT;
  v_id_pedido_a     UUID := '00000009-0001-4001-8001-000000009991';
  v_id_pedido_b     UUID := '00000009-0001-4001-8001-000000009992';
  v_id_confirmado   UUID := id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'CONFIRMADO');
BEGIN
  SELECT r.id_repartidor INTO v_id_repartidor
  FROM repartidor r
  WHERE r.region_codigo = v_region
  ORDER BY r.id_repartidor
  LIMIT 1;

  IF v_id_repartidor IS NULL THEN
    RAISE EXCEPTION 'Ejecuta primero el paso 2: 2. datos-semilla/2. delivery_db_distribuida_seed.sql';
  END IF;

  UPDATE repartidor SET disponible = FALSE WHERE region_codigo = v_region;
  UPDATE repartidor
  SET disponible = TRUE, placa = 'DEMO-01'
  WHERE region_codigo = v_region AND id_repartidor = v_id_repartidor;

  SELECT c.id_cliente INTO v_id_cliente FROM cliente c
  WHERE c.region_codigo = v_region LIMIT 1;

  SELECT co.id_comercio, co.nombre INTO v_id_comercio, v_nombre_comercio
  FROM comercio co WHERE co.region_codigo = v_region LIMIT 1;

  SELECT left(pe.nombres || ' ' || pe.apellidos, 240) INTO v_nombre_cliente
  FROM persona pe
  JOIN cliente c ON c.region_codigo = pe.region_codigo AND c.id_cliente = v_id_cliente
  JOIN usuario u ON u.region_codigo = c.region_codigo AND u.id_usuario = c.id_usuario
  WHERE pe.region_codigo = v_region AND pe.id_persona = u.id_persona;

  DELETE FROM detalle_pedido
  WHERE region_codigo = v_region AND id_pedido IN (v_id_pedido_a, v_id_pedido_b);
  DELETE FROM pedido
  WHERE region_codigo = v_region AND id_pedido IN (v_id_pedido_a, v_id_pedido_b);

  INSERT INTO pedido (region_codigo, id_pedido, id_cliente, id_comercio, id_repartidor,
    id_estado_pedido, nombre_cliente, nombre_comercio, direccion_entrega,
    subtotal, costo_envio, total, nodo_origen, fecha_confirmacion)
  VALUES
    (v_region, v_id_pedido_a, v_id_cliente, v_id_comercio, NULL,
     v_id_confirmado, v_nombre_cliente, left(v_nombre_comercio, 160),
     'Demo concurrencia pedido A', 25.00, 5.00, 30.00, v_region, now()),
    (v_region, v_id_pedido_b, v_id_cliente, v_id_comercio, NULL,
     v_id_confirmado, v_nombre_cliente, left(v_nombre_comercio, 160),
     'Demo concurrencia pedido B', 18.00, 5.00, 23.00, v_region, now());

  RAISE NOTICE 'Instalacion lista. Repartidor demo: %', v_id_repartidor;
END $$;

CREATE OR REPLACE FUNCTION reservar_repartidor_disponible(
  p_region    VARCHAR,
  p_id_pedido UUID
)
RETURNS TABLE (ok BOOLEAN, id_repartidor UUID, mensaje TEXT)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
  v_id_repartidor UUID;
  v_id_confirmado UUID := id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'CONFIRMADO');
  v_id_en_camino  UUID := id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'EN_CAMINO');
  v_filas_rep     INTEGER;
  v_filas_ped     INTEGER;
BEGIN
  SELECT r.id_repartidor INTO v_id_repartidor
  FROM repartidor r
  WHERE r.region_codigo = p_region
    AND r.disponible = TRUE
  ORDER BY r.id_repartidor
  LIMIT 1
  FOR UPDATE;

  IF v_id_repartidor IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, 'no hay repartidores disponibles';
    RETURN;
  END IF;

  UPDATE repartidor rep
  SET disponible = FALSE
  WHERE rep.region_codigo = p_region
    AND rep.id_repartidor = v_id_repartidor
    AND rep.disponible = TRUE;

  GET DIAGNOSTICS v_filas_rep = ROW_COUNT;

  IF v_filas_rep = 0 THEN
    RETURN QUERY SELECT FALSE, v_id_repartidor, 'repartidor ya fue tomado por otro pedido';
    RETURN;
  END IF;

  UPDATE pedido ped
  SET id_repartidor = v_id_repartidor,
      id_estado_pedido = v_id_en_camino
  WHERE ped.region_codigo = p_region
    AND ped.id_pedido = p_id_pedido
    AND ped.id_repartidor IS NULL
    AND ped.id_estado_pedido = v_id_confirmado;

  GET DIAGNOSTICS v_filas_ped = ROW_COUNT;

  IF v_filas_ped = 0 THEN
    UPDATE repartidor rep SET disponible = TRUE
    WHERE rep.region_codigo = p_region AND rep.id_repartidor = v_id_repartidor;
    RETURN QUERY SELECT FALSE, v_id_repartidor, 'pedido no elegible; repartidor liberado';
    RETURN;
  END IF;

  RETURN QUERY SELECT TRUE, v_id_repartidor, 'repartidor reservado (disponible = FALSE)';
END $$;

CREATE OR REPLACE FUNCTION reset_demo_concurrencia_repartidor()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_repartidor UUID;
BEGIN
  SELECT id_repartidor INTO v_id_repartidor
  FROM repartidor
  WHERE region_codigo = 'LIM-N' AND placa = 'DEMO-01';

  IF v_id_repartidor IS NULL THEN
    RAISE EXCEPTION 'Ejecuta primero: 4. concurrencia-repartidor/1. instalacion.sql';
  END IF;

  UPDATE repartidor SET disponible = FALSE WHERE region_codigo = 'LIM-N';
  UPDATE repartidor SET disponible = TRUE
  WHERE region_codigo = 'LIM-N' AND id_repartidor = v_id_repartidor;

  UPDATE pedido SET id_repartidor = NULL,
    id_estado_pedido = id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'CONFIRMADO')
  WHERE region_codigo = 'LIM-N'
    AND id_pedido IN (
      '00000009-0001-4001-8001-000000009991',
      '00000009-0001-4001-8001-000000009992'
    );
END $$;
