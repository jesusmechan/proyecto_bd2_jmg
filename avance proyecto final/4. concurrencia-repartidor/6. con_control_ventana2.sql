-- PASO 4.6 — CON CONTROL (solucion) | VENTANA 2 | Pedido B
-- \cd '4. concurrencia-repartidor'
-- \i '6. con_control_ventana2.sql'
--
-- Ejecutar DESPUES de que Ventana 1 haya hecho BEGIN + reservar,
-- y ANTES de que Ventana 1 haga COMMIT.


BEGIN;

SELECT *
FROM reservar_repartidor_disponible(
  'LIM-N', '00000009-0001-4001-8001-000000009992'
) AS resultado;

COMMIT;
