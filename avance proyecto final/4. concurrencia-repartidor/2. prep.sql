-- PASO 4.2 — Reiniciar demo (ejecutar antes de cada prueba)
-- \cd '4. concurrencia-repartidor'
-- \i '2. prep.sql'

SELECT reset_demo_concurrencia_repartidor();

SELECT
  'repartidor' AS tabla,
  region_codigo,
  id_repartidor,
  placa,
  disponible
FROM repartidor
WHERE region_codigo = 'LIM-N' AND placa = 'DEMO-01';

SELECT
  'pedido' AS tabla,
  id_pedido,
  id_repartidor,
  cm.codigo AS estado
FROM pedido p
JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
WHERE p.region_codigo = 'LIM-N'
  AND p.id_pedido IN (
    '00000009-0001-4001-8001-000000009991',
    '00000009-0001-4001-8001-000000009992'
  );
