-- PASO 4.3 — SIN CONTROL (problema) | VENTANA 1 | Pedido A
-- \cd '4. concurrencia-repartidor'
-- \i '3. sin_control_ventana1.sql'
--
-- Orden con Ventana 2:
--   1) Este script (ventana 1)
--   2) 4. sin_control_ventana2.sql (ventana 2)
--   3) Enter en ventana 1
--   4) Enter en ventana 2


BEGIN;

SELECT
  region_codigo,
  id_repartidor,
  placa,
  disponible
FROM repartidor
WHERE region_codigo = 'LIM-N' AND placa = 'DEMO-01';

UPDATE repartidor
SET disponible = FALSE
WHERE region_codigo = 'LIM-N' AND placa = 'DEMO-01' AND disponible = TRUE;

UPDATE pedido
SET id_repartidor = (
      SELECT id_repartidor FROM repartidor
      WHERE region_codigo = 'LIM-N' AND placa = 'DEMO-01'
    ),
    id_estado_pedido = id_catalogo_por_tipo_codigo('ESTADO_PEDIDO', 'EN_CAMINO')
WHERE region_codigo = 'LIM-N'
  AND id_pedido = '00000009-0001-4001-8001-000000009991';

COMMIT;