-- =========================================================
-- PASO 5 — Consultas basicas SQL
-- delivery_db_distribuida
--
-- Ejecutar despues del paso 1 y 2:
--   psql -d delivery_db_distribuida -f "5. consultas/5. consultas_basicas.sql"
--
-- Consultas para manipulacion y analisis (exposicion).
-- =========================================================

\echo '========== C1 — Listado simple con filtro =========='
SELECT region_codigo, nombre, precio, disponible
FROM producto
WHERE region_codigo = 'LIM-N' AND disponible = TRUE
ORDER BY precio DESC
LIMIT 10;

\echo '========== C2 — JOIN pedido + cliente (via nombres desnormalizados) =========='
SELECT
  p.region_codigo,
  p.id_pedido,
  p.nombre_cliente,
  p.nombre_comercio,
  cm.codigo AS estado,
  p.total,
  p.fecha_creacion
FROM pedido p
JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
WHERE p.region_codigo = 'LIM-N'
ORDER BY p.fecha_creacion DESC
LIMIT 15;

\echo '========== C3 — JOIN detalle + producto =========='
SELECT
  dp.region_codigo,
  dp.id_pedido,
  dp.nombre_producto,
  dp.cantidad,
  dp.precio_unitario,
  dp.importe_linea,
  pr.nombre AS nombre_actual_producto
FROM detalle_pedido dp
JOIN producto pr
  ON pr.region_codigo = dp.region_codigo AND pr.id_producto = dp.id_producto
WHERE dp.region_codigo = 'LIM-S'
LIMIT 15;

\echo '========== C4 — Agregacion: ventas por comercio =========='
SELECT
  p.region_codigo,
  p.nombre_comercio,
  COUNT(*) AS total_pedidos,
  ROUND(SUM(p.total), 2) AS monto_total,
  ROUND(AVG(p.total), 2) AS ticket_promedio
FROM pedido p
JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
WHERE cm.codigo IN ('ENTREGADO', 'EN_CAMINO', 'CONFIRMADO')
GROUP BY p.region_codigo, p.nombre_comercio
ORDER BY monto_total DESC
LIMIT 10;

\echo '========== C5 — Agregacion: pedidos por estado y region =========='
SELECT
  pe.region_codigo,
  cm.codigo AS estado_pedido,
  COUNT(*) AS cantidad,
  ROUND(SUM(pe.total), 2) AS monto_total
FROM pedido pe
JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_estado_pedido
GROUP BY pe.region_codigo, cm.codigo
ORDER BY pe.region_codigo, cm.codigo;

\echo '========== C6 — Subconsulta: comercios con mas de 50 productos =========='
SELECT c.region_codigo, c.nombre, cnt.total_productos
FROM comercio c
JOIN (
  SELECT region_codigo, id_comercio, COUNT(*) AS total_productos
  FROM producto
  GROUP BY region_codigo, id_comercio
  HAVING COUNT(*) > 50
) cnt ON cnt.region_codigo = c.region_codigo AND cnt.id_comercio = c.id_comercio
ORDER BY cnt.total_productos DESC
LIMIT 10;

\echo '========== C7 — Repartidores disponibles por region =========='
SELECT
  r.region_codigo,
  COUNT(*) FILTER (WHERE r.disponible) AS libres,
  COUNT(*) FILTER (WHERE NOT r.disponible) AS ocupados,
  COUNT(*) AS total
FROM repartidor r
GROUP BY r.region_codigo
ORDER BY r.region_codigo;

\echo '========== C8 — Pagos por metodo y estado =========='
SELECT
  pg.region_codigo,
  cm_mp.codigo AS metodo_pago,
  cm_ep.codigo AS estado_pago,
  COUNT(*) AS cantidad,
  ROUND(SUM(pg.monto), 2) AS monto
FROM pago pg
JOIN catalogo_maestro cm_mp ON cm_mp.id_catalogo = pg.id_metodo_pago
JOIN catalogo_maestro cm_ep ON cm_ep.id_catalogo = pg.id_estado_pago
GROUP BY pg.region_codigo, cm_mp.codigo, cm_ep.codigo
ORDER BY pg.region_codigo, monto DESC;

\echo '========== C9 — Rutas de reparto con paradas =========='
SELECT
  rr.region_codigo,
  rr.id_ruta,
  cm.codigo AS estado_ruta,
  COUNT(pr.id_parada) AS total_paradas,
  rr.distancia_kilometros
FROM ruta_reparto rr
JOIN catalogo_maestro cm ON cm.id_catalogo = rr.id_estado_ruta
LEFT JOIN parada_ruta pr
  ON pr.region_codigo = rr.region_codigo AND pr.id_ruta = rr.id_ruta
GROUP BY rr.region_codigo, rr.id_ruta, cm.codigo, rr.distancia_kilometros
ORDER BY total_paradas DESC
LIMIT 10;

\echo '========== C10 — Bitacora: ultimos eventos por tipo =========='
SELECT
  region_codigo,
  tipo_evento,
  COUNT(*) AS eventos
FROM bitacora_evento
GROUP BY region_codigo, tipo_evento
ORDER BY eventos DESC
LIMIT 15;

\echo '========== C11 — Vista de fragmentacion =========='
SELECT * FROM v_resumen_fragmentacion;

\echo '========== C12 — INSERT de prueba (transaccion) =========='
BEGIN;
INSERT INTO bitacora_evento (region_codigo, tipo_evento, tabla_afectada, descripcion, nodo_origen)
VALUES ('LIM-N', 'CONSULTA_DEMO', 'pedido', 'Registro de prueba desde consultas_basicas.sql', 'LIM-N');
SELECT id_evento, tipo_evento, fecha_hora, descripcion
FROM bitacora_evento
WHERE tipo_evento = 'CONSULTA_DEMO'
ORDER BY fecha_hora DESC
LIMIT 1;
ROLLBACK;

\echo '========== C13 — UPDATE de prueba (sin confirmar cambios) =========='
BEGIN;
UPDATE producto p
SET descripcion = p.descripcion
FROM (
  SELECT region_codigo, id_producto FROM producto
  WHERE region_codigo = 'LIM-N' AND disponible = TRUE
  LIMIT 1
) s
WHERE p.region_codigo = s.region_codigo AND p.id_producto = s.id_producto;
SELECT region_codigo, nombre, disponible FROM producto
WHERE region_codigo = 'LIM-N' AND disponible = TRUE LIMIT 3;
ROLLBACK;

\echo ''
\echo 'Consultas basicas ejecutadas correctamente.'
