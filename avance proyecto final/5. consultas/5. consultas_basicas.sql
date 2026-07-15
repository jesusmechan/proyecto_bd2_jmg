-- =========================================================
-- PASO 5 — Consultas basicas y complejas SQL
-- delivery_db_distribuida
--
-- Ejecutar despues del paso 1 y 2:
--   psql -d delivery_db_distribuida -f "5. consultas/5. consultas_basicas.sql"
--
-- C1–C13  : basicas (filtros, JOIN, agregacion, DML demo)
-- C14–C25 : complejas (CTE, ventanas, EXISTS, pivote, sagas, JSONB)
-- =========================================================

-- ------------------------------------------------------------
-- C1 — Listado simple con filtro
-- Descripcion: Obtiene los 10 productos disponibles con mayor
--   precio en la region LIM-N (Lima Norte).
-- Tecnica: SELECT, WHERE, ORDER BY, LIMIT.
-- Tablas: producto.
-- ------------------------------------------------------------
SELECT region_codigo, nombre, precio, disponible
FROM producto
WHERE region_codigo = 'LIM-N' AND disponible = TRUE
ORDER BY precio DESC
LIMIT 10;

-- ------------------------------------------------------------
-- C2 — JOIN pedido + catalogo de estados
-- Descripcion: Muestra los 15 pedidos mas recientes de LIM-N
--   con el nombre del cliente, comercio, estado legible y total.
--   Usa campos desnormalizados del pedido (sin cruzar nodos).
-- Tecnica: INNER JOIN con catalogo_maestro.
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- C3 — JOIN detalle + producto
-- Descripcion: Cruza lineas de detalle con el catalogo actual
--   de productos en LIM-S para comparar el nombre guardado en
--   el pedido con el nombre vigente del producto.
-- Tecnica: INNER JOIN por clave compuesta (region + id).
-- Tablas: detalle_pedido, producto.
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- C4 — Agregacion: ventas por comercio
-- Descripcion: Calcula total de pedidos, monto acumulado y
--   ticket promedio por comercio, solo para pedidos activos
--   (confirmados, en camino o entregados).
-- Tecnica: GROUP BY, COUNT, SUM, AVG, filtro por estado.
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- C5 — Agregacion: pedidos por estado y region
-- Descripcion: Resume la cantidad de pedidos y el monto total
--   agrupados por region y estado (creado, confirmado, etc.).
-- Tecnica: GROUP BY con JOIN a catalogo de estados.
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
SELECT
  pe.region_codigo,
  cm.codigo AS estado_pedido,
  COUNT(*) AS cantidad,
  ROUND(SUM(pe.total), 2) AS monto_total
FROM pedido pe
JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_estado_pedido
GROUP BY pe.region_codigo, cm.codigo
ORDER BY pe.region_codigo, cm.codigo;

-- ------------------------------------------------------------
-- C6 — Subconsulta: comercios con mas de 50 productos
-- Descripcion: Identifica comercios cuyo catalogo supera los
--   50 productos, uniendo una subconsulta agregada con la
--   tabla comercio para mostrar el nombre del local.
-- Tecnica: Subconsulta en FROM, HAVING, INNER JOIN.
-- Tablas: comercio, producto.
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- C7 — Repartidores disponibles por region
-- Descripcion: Cuenta cuantos repartidores estan libres u
--   ocupados en cada region, usando agregacion condicional.
-- Tecnica: COUNT con FILTER (WHERE).
-- Tablas: repartidor.
-- ------------------------------------------------------------
SELECT
  r.region_codigo,
  COUNT(*) FILTER (WHERE r.disponible) AS libres,
  COUNT(*) FILTER (WHERE NOT r.disponible) AS ocupados,
  COUNT(*) AS total
FROM repartidor r
GROUP BY r.region_codigo
ORDER BY r.region_codigo;

-- ------------------------------------------------------------
-- C8 — Pagos por metodo y estado
-- Descripcion: Agrupa los pagos por region, metodo (efectivo,
--   tarjeta, Yape, etc.) y estado (pendiente, pagado, etc.),
--   mostrando cantidad de operaciones y monto total.
-- Tecnica: GROUP BY con doble JOIN a catalogo_maestro.
-- Tablas: pago, catalogo_maestro.
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- C9 — Rutas de reparto con paradas
-- Descripcion: Lista rutas de reparto con su estado, distancia
--   y numero de paradas asociadas (pedidos en el recorrido).
-- Tecnica: LEFT JOIN + GROUP BY para contar paradas.
-- Tablas: ruta_reparto, parada_ruta, catalogo_maestro.
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- C10 — Bitacora: eventos por tipo
-- Descripcion: Cuenta cuantos eventos de auditoria existen por
--   region y tipo de evento (ej. PEDIDO_ENTREGADO, PEDIDO_CREADO).
-- Tecnica: GROUP BY, ORDER BY descendente.
-- Tablas: bitacora_evento.
-- ------------------------------------------------------------
SELECT
  region_codigo,
  tipo_evento,
  COUNT(*) AS eventos
FROM bitacora_evento
GROUP BY region_codigo, tipo_evento
ORDER BY eventos DESC
LIMIT 15;

-- ------------------------------------------------------------
-- C11 — Vista de fragmentacion
-- Descripcion: Consulta la vista v_resumen_fragmentacion que
--   documenta como se distribuye cada tabla del sistema por
--   region/nodo (criterio de fragmentacion horizontal).
-- Tecnica: SELECT sobre vista predefinida.
-- Tablas: v_resumen_fragmentacion.
-- ------------------------------------------------------------
SELECT * FROM v_resumen_fragmentacion;

-- ------------------------------------------------------------
-- C12 — INSERT de prueba (transaccion)
-- Descripcion: Demuestra una insercion en bitacora dentro de
--   una transaccion (BEGIN/ROLLBACK) para no persistir datos
--   de prueba. Verifica el registro insertado antes del rollback.
-- Tecnica: BEGIN, INSERT, SELECT, ROLLBACK.
-- Tablas: bitacora_evento.
-- ------------------------------------------------------------
BEGIN;
INSERT INTO bitacora_evento (region_codigo, tipo_evento, tabla_afectada, descripcion, nodo_origen)
VALUES ('LIM-N', 'CONSULTA_DEMO', 'pedido', 'Registro de prueba desde consultas_basicas.sql', 'LIM-N');
SELECT id_evento, tipo_evento, fecha_hora, descripcion
FROM bitacora_evento
WHERE tipo_evento = 'CONSULTA_DEMO'
ORDER BY fecha_hora DESC
LIMIT 1;
ROLLBACK;

-- ------------------------------------------------------------
-- C13 — UPDATE de prueba (sin confirmar cambios)
-- Descripcion: Ejecuta un UPDATE de demostracion (asigna la
--   misma descripcion, sin cambiar datos reales) dentro de una
--   transaccion que se revierte con ROLLBACK.
-- Tecnica: BEGIN, UPDATE con subconsulta FROM, ROLLBACK.
-- Tablas: producto.
-- ------------------------------------------------------------
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

-- =========================================================
-- CONSULTAS COMPLEJAS
-- =========================================================

-- ------------------------------------------------------------
-- C14 — CTE + ventana: top 3 comercios por region
-- Descripcion: Calcula ventas por comercio y region, luego
--   rankea con RANK() para obtener los 3 comercios con mayor
--   monto en cada fragmento regional.
-- Tecnica: CTE encadenadas, RANK() OVER (PARTITION BY).
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
WITH ventas AS (
  SELECT
    p.region_codigo,
    p.nombre_comercio,
    COUNT(*) AS pedidos,
    ROUND(SUM(p.total), 2) AS monto
  FROM pedido p
  JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
  WHERE cm.codigo IN ('ENTREGADO', 'EN_CAMINO', 'CONFIRMADO')
  GROUP BY p.region_codigo, p.nombre_comercio
),
rankeado AS (
  SELECT
    region_codigo,
    nombre_comercio,
    pedidos,
    monto,
    RANK() OVER (PARTITION BY region_codigo ORDER BY monto DESC) AS puesto
  FROM ventas
)
SELECT region_codigo, puesto, nombre_comercio, pedidos, monto
FROM rankeado
WHERE puesto <= 3
ORDER BY region_codigo, puesto;

-- ------------------------------------------------------------
-- C15 — Ventana: ticket vs promedio regional
-- Descripcion: Para pedidos entregados, compara el total de
--   cada pedido contra el promedio y la suma de su region,
--   mostrando desviacion y porcentaje de participacion.
-- Tecnica: AVG() y SUM() como funciones de ventana.
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
SELECT
  p.region_codigo,
  p.nombre_cliente,
  cm.codigo AS estado,
  p.total,
  ROUND(AVG(p.total) OVER (PARTITION BY p.region_codigo), 2) AS avg_region,
  ROUND(
    p.total - AVG(p.total) OVER (PARTITION BY p.region_codigo),
    2
  ) AS diferencia_vs_region,
  ROUND(
    100.0 * p.total / NULLIF(SUM(p.total) OVER (PARTITION BY p.region_codigo), 0),
    4
  ) AS pct_del_monto_region
FROM pedido p
JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
WHERE cm.codigo = 'ENTREGADO'
ORDER BY p.region_codigo, diferencia_vs_region DESC
LIMIT 20;

-- ------------------------------------------------------------
-- C16 — Embudo de estados (share % por region)
-- Descripcion: Construye un embudo de conversion mostrando
--   cuantos pedidos hay en cada estado y que porcentaje
--   representan dentro de su region.
-- Tecnica: CTE, calculo de porcentaje, ORDER BY con CASE.
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
WITH conteo AS (
  SELECT
    pe.region_codigo,
    cm.codigo AS estado,
    COUNT(*) AS n
  FROM pedido pe
  JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_estado_pedido
  GROUP BY pe.region_codigo, cm.codigo
),
totales AS (
  SELECT region_codigo, SUM(n) AS total_region
  FROM conteo
  GROUP BY region_codigo
)
SELECT
  c.region_codigo,
  c.estado,
  c.n AS cantidad,
  t.total_region,
  ROUND(100.0 * c.n / t.total_region, 2) AS porcentaje
FROM conteo c
JOIN totales t ON t.region_codigo = c.region_codigo
ORDER BY c.region_codigo,
  CASE c.estado
    WHEN 'CREADO' THEN 1
    WHEN 'CONFIRMADO' THEN 2
    WHEN 'EN_CAMINO' THEN 3
    WHEN 'ENTREGADO' THEN 4
    WHEN 'CANCELADO' THEN 5
    ELSE 9
  END;

-- ------------------------------------------------------------
-- C17 — EXISTS: clientes fieles sin cancelaciones
-- Descripcion: Lista clientes que tienen al menos un pedido
--   entregado y ningun pedido cancelado en su region (perfil
--   de cliente recurrente y confiable).
-- Tecnica: EXISTS y NOT EXISTS con subconsultas correlacionadas.
-- Tablas: cliente, usuario, persona, pedido, catalogo_maestro.
-- ------------------------------------------------------------
SELECT
  c.region_codigo,
  per.nombres,
  per.apellidos,
  per.correo
FROM cliente c
JOIN usuario u
  ON u.region_codigo = c.region_codigo AND u.id_usuario = c.id_usuario
JOIN persona per
  ON per.region_codigo = u.region_codigo AND per.id_persona = u.id_persona
WHERE EXISTS (
  SELECT 1
  FROM pedido p
  JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
  WHERE p.region_codigo = c.region_codigo
    AND p.id_cliente = c.id_cliente
    AND cm.codigo = 'ENTREGADO'
)
AND NOT EXISTS (
  SELECT 1
  FROM pedido p
  JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
  WHERE p.region_codigo = c.region_codigo
    AND p.id_cliente = c.id_cliente
    AND cm.codigo = 'CANCELADO'
)
ORDER BY c.region_codigo, per.apellidos
LIMIT 20;

-- ------------------------------------------------------------
-- C18 — Multi-JOIN: pedido + detalle + pago
-- Descripcion: Vista integral de pedidos entregados y pagados
--   en AQP: une cabecera, linea de detalle, pago y catalogos
--   de metodo y estado de pago en una sola consulta.
-- Tecnica: Multiples INNER JOIN por claves compuestas regionales.
-- Tablas: pedido, detalle_pedido, pago, catalogo_maestro.
-- ------------------------------------------------------------
SELECT
  pe.region_codigo,
  pe.nombre_cliente,
  pe.nombre_comercio,
  ce.codigo AS estado_pedido,
  dp.nombre_producto,
  dp.cantidad,
  dp.importe_linea,
  mp.codigo AS metodo_pago,
  ep.codigo AS estado_pago,
  pg.monto AS monto_pago
FROM pedido pe
JOIN catalogo_maestro ce ON ce.id_catalogo = pe.id_estado_pedido
JOIN detalle_pedido dp
  ON dp.region_codigo = pe.region_codigo AND dp.id_pedido = pe.id_pedido
JOIN pago pg
  ON pg.region_codigo = pe.region_codigo AND pg.id_pedido = pe.id_pedido
JOIN catalogo_maestro mp ON mp.id_catalogo = pg.id_metodo_pago
JOIN catalogo_maestro ep ON ep.id_catalogo = pg.id_estado_pago
WHERE pe.region_codigo = 'AQP'
  AND ce.codigo = 'ENTREGADO'
  AND ep.codigo = 'PAGADO'
ORDER BY pe.fecha_creacion DESC, dp.importe_linea DESC
LIMIT 25;

-- ------------------------------------------------------------
-- C19 — Productos mas vendidos con ranking global
-- Descripcion: Agrega unidades e ingresos por producto y region,
--   luego aplica DENSE_RANK global (por ingresos) y regional
--   (por unidades) para identificar los mas vendidos.
-- Tecnica: CTE + funciones de ventana DENSE_RANK().
-- Tablas: detalle_pedido, pedido, catalogo_maestro.
-- ------------------------------------------------------------
WITH vendidos AS (
  SELECT
    dp.region_codigo,
    dp.nombre_producto,
    SUM(dp.cantidad) AS unidades,
    ROUND(SUM(dp.importe_linea), 2) AS ingresos
  FROM detalle_pedido dp
  JOIN pedido pe
    ON pe.region_codigo = dp.region_codigo AND pe.id_pedido = dp.id_pedido
  JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_estado_pedido
  WHERE cm.codigo IN ('ENTREGADO', 'EN_CAMINO')
  GROUP BY dp.region_codigo, dp.nombre_producto
)
SELECT
  region_codigo,
  nombre_producto,
  unidades,
  ingresos,
  DENSE_RANK() OVER (ORDER BY ingresos DESC) AS rank_ingresos_global,
  DENSE_RANK() OVER (PARTITION BY region_codigo ORDER BY unidades DESC) AS rank_unidades_region
FROM vendidos
ORDER BY ingresos DESC
LIMIT 15;

-- ------------------------------------------------------------
-- C20 — Pivote: estados de pedido por region
-- Descripcion: Tabla pivote que muestra la cantidad de pedidos
--   en cada estado por region, mas la tasa de cancelacion (%).
-- Tecnica: COUNT con FILTER (pivote condicional).
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
SELECT
  pe.region_codigo,
  COUNT(*) FILTER (WHERE cm.codigo = 'CREADO') AS creado,
  COUNT(*) FILTER (WHERE cm.codigo = 'CONFIRMADO') AS confirmado,
  COUNT(*) FILTER (WHERE cm.codigo = 'EN_CAMINO') AS en_camino,
  COUNT(*) FILTER (WHERE cm.codigo = 'ENTREGADO') AS entregado,
  COUNT(*) FILTER (WHERE cm.codigo = 'CANCELADO') AS cancelado,
  COUNT(*) AS total,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE cm.codigo = 'CANCELADO') / NULLIF(COUNT(*), 0),
    2
  ) AS tasa_cancelacion_pct
FROM pedido pe
JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_estado_pedido
GROUP BY pe.region_codigo
ORDER BY pe.region_codigo;

-- ------------------------------------------------------------
-- C21 — LATERAL: producto mas caro por comercio
-- Descripcion: Para cada comercio de LIM-S, obtiene el producto
--   disponible de mayor precio usando una subconsulta lateral
--   que se evalua por cada fila de comercio.
-- Tecnica: CROSS JOIN LATERAL con LIMIT 1.
-- Tablas: comercio, producto.
-- ------------------------------------------------------------
SELECT
  c.region_codigo,
  c.nombre AS comercio,
  top.nombre AS producto_top,
  top.precio,
  top.disponible
FROM comercio c
CROSS JOIN LATERAL (
  SELECT pr.nombre, pr.precio, pr.disponible
  FROM producto pr
  WHERE pr.region_codigo = c.region_codigo
    AND pr.id_comercio = c.id_comercio
    AND pr.disponible = TRUE
  ORDER BY pr.precio DESC
  LIMIT 1
) top
WHERE c.region_codigo = 'LIM-S'
ORDER BY top.precio DESC
LIMIT 15;

-- ------------------------------------------------------------
-- C22 — Repartidores: carga de trabajo y ticket promedio
-- Descripcion: Mide el desempeno de cada repartidor: entregas
--   asignadas, ticket promedio, monto gestionado y porcentaje
--   de participacion dentro de su region.
-- Tecnica: CTE + ventana SUM() OVER (PARTITION BY).
-- Tablas: pedido, repartidor, persona, catalogo_maestro.
-- ------------------------------------------------------------
WITH entregas AS (
  SELECT
    pe.region_codigo,
    pe.id_repartidor,
    COUNT(*) AS entregas,
    ROUND(AVG(pe.total), 2) AS ticket_promedio,
    ROUND(SUM(pe.total), 2) AS monto_gestionado
  FROM pedido pe
  JOIN catalogo_maestro cm ON cm.id_catalogo = pe.id_estado_pedido
  WHERE pe.id_repartidor IS NOT NULL
    AND cm.codigo IN ('ENTREGADO', 'EN_CAMINO')
  GROUP BY pe.region_codigo, pe.id_repartidor
)
SELECT
  e.region_codigo,
  per.nombres || ' ' || per.apellidos AS repartidor,
  tv.codigo AS vehiculo,
  r.disponible,
  e.entregas,
  e.ticket_promedio,
  e.monto_gestionado,
  ROUND(
    100.0 * e.entregas / NULLIF(SUM(e.entregas) OVER (PARTITION BY e.region_codigo), 0),
    2
  ) AS pct_entregas_region
FROM entregas e
JOIN repartidor r
  ON r.region_codigo = e.region_codigo AND r.id_repartidor = e.id_repartidor
JOIN persona per
  ON per.region_codigo = r.region_codigo AND per.id_persona = r.id_persona
JOIN catalogo_maestro tv ON tv.id_catalogo = r.id_tipo_vehiculo
ORDER BY e.region_codigo, e.entregas DESC
LIMIT 20;

-- ------------------------------------------------------------
-- C23 — Sagas fallidas con paso en ERROR
-- Descripcion: Audita transacciones distribuidas (patron Saga)
--   que fallaron, mostrando el paso con error y datos extraidos
--   del campo JSONB payload (numero de pedido y total).
-- Tecnica: JOIN saga + pasos, operador JSONB ->>.
-- Tablas: saga_transaccion, saga_paso.
-- ------------------------------------------------------------
SELECT
  st.region_codigo,
  st.id_saga,
  st.estado AS estado_saga,
  st.tipo_operacion,
  sp.nombre_paso,
  sp.estado AS estado_paso,
  sp.nodo_ejecutor,
  st.payload->>'pedido' AS nro_pedido_seed,
  st.payload->>'total' AS total_payload,
  st.fecha_creacion
FROM saga_transaccion st
JOIN saga_paso sp ON sp.id_saga = st.id_saga
WHERE st.estado = 'FALLIDA'
  AND sp.estado = 'ERROR'
ORDER BY st.fecha_creacion DESC
LIMIT 15;

-- ------------------------------------------------------------
-- C24 — HAVING: comercios de alto volumen y baja cancelacion
-- Descripcion: Filtra comercios con al menos 500 pedidos y
--   tasa de cancelacion menor al 8%, ordenados por monto
--   entregado (perfil de locales estables y rentables).
-- Tecnica: GROUP BY + HAVING con agregacion condicional FILTER.
-- Tablas: pedido, catalogo_maestro.
-- ------------------------------------------------------------
SELECT
  p.region_codigo,
  p.nombre_comercio,
  COUNT(*) AS pedidos,
  COUNT(*) FILTER (WHERE cm.codigo = 'CANCELADO') AS cancelados,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE cm.codigo = 'CANCELADO') / COUNT(*),
    2
  ) AS tasa_cancelacion_pct,
  ROUND(SUM(p.total) FILTER (WHERE cm.codigo = 'ENTREGADO'), 2) AS monto_entregado
FROM pedido p
JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
GROUP BY p.region_codigo, p.nombre_comercio
HAVING COUNT(*) >= 500
   AND 100.0 * COUNT(*) FILTER (WHERE cm.codigo = 'CANCELADO') / COUNT(*) < 8
ORDER BY monto_entregado DESC NULLS LAST
LIMIT 15;

-- ------------------------------------------------------------
-- C25 — Comparativo regional: ingreso y pagos digitales
-- Descripcion: Compara las tres regiones en ingreso de pedidos
--   entregados, ticket promedio y adopcion de medios digitales
--   (Yape, Plin, tarjeta, transferencia) con pago confirmado.
-- Tecnica: CTE base + agregacion con FILTER y porcentaje.
-- Tablas: pedido, pago, catalogo_maestro.
-- ------------------------------------------------------------
WITH base AS (
  SELECT
    pe.region_codigo,
    pe.total,
    ce.codigo AS estado_pedido,
    mp.codigo AS metodo_pago,
    ep.codigo AS estado_pago
  FROM pedido pe
  JOIN catalogo_maestro ce ON ce.id_catalogo = pe.id_estado_pedido
  JOIN pago pg
    ON pg.region_codigo = pe.region_codigo AND pg.id_pedido = pe.id_pedido
  JOIN catalogo_maestro mp ON mp.id_catalogo = pg.id_metodo_pago
  JOIN catalogo_maestro ep ON ep.id_catalogo = pg.id_estado_pago
)
SELECT
  region_codigo,
  COUNT(*) AS pedidos_con_pago,
  ROUND(SUM(total) FILTER (WHERE estado_pedido = 'ENTREGADO'), 2) AS ingreso_entregado,
  ROUND(AVG(total) FILTER (WHERE estado_pedido = 'ENTREGADO'), 2) AS ticket_entregado,
  COUNT(*) FILTER (
    WHERE metodo_pago IN ('YAPE', 'PLIN', 'TARJETA', 'TRANSFERENCIA')
      AND estado_pago = 'PAGADO'
  ) AS pagos_digitales_ok,
  ROUND(
    100.0 * COUNT(*) FILTER (
      WHERE metodo_pago IN ('YAPE', 'PLIN', 'TARJETA', 'TRANSFERENCIA')
        AND estado_pago = 'PAGADO'
    ) / NULLIF(COUNT(*), 0),
    2
  ) AS pct_digital
FROM base
GROUP BY region_codigo
ORDER BY ingreso_entregado DESC NULLS LAST;