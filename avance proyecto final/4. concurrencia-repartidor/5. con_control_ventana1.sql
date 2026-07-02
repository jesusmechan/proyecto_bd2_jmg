-- PASO 4.5 — CON CONTROL (solucion) | VENTANA 1 | Pedido A
-- \cd '4. concurrencia-repartidor'
-- \i '5. con_control_ventana1.sql'
--
-- Orden con Ventana 2:
--   1) Este script (ventana 1) — no hacer COMMIT hasta el prompt
--   2) 6. con_control_ventana2.sql (ventana 2) — queda en espera
--   3) Enter en ventana 1 (COMMIT)
--   4) Ventana 2 termina con ok = false

BEGIN;

SELECT *
FROM reservar_repartidor_disponible(
  'LIM-N', '00000009-0001-4001-8001-000000009991'
) AS resultado;


COMMIT;
