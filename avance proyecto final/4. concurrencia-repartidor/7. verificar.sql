-- PASO 4.7 — Verificar resultado de la demo
-- \cd '4. concurrencia-repartidor'
-- \i '7. verificar.sql'


SELECT
  region_codigo,
  id_repartidor,
  placa,
  disponible
FROM repartidor
WHERE region_codigo = 'LIM-N' AND placa = 'DEMO-01';


SELECT
  p.id_pedido,
  p.id_repartidor,
  cm.codigo AS estado,
  p.direccion_entrega
FROM pedido p
JOIN catalogo_maestro cm ON cm.id_catalogo = p.id_estado_pedido
WHERE p.region_codigo = 'LIM-N'
  AND p.id_pedido IN (
    '00000009-0001-4001-8001-000000009991',
    '00000009-0001-4001-8001-000000009992'
  )
ORDER BY p.id_pedido;