# T24 — Regeneración semanal y mensual sin perder compras

Validación: 7 de octubre de 2026. Alcance: crons de regeneración de `toppin_rails-develop`; no cambia el consumo de SuperSweet/boosts ni la política global de suscripciones.

## Regla aplicada

- Premium/Supreme: una vez por semana natural, comenzando el lunes a las 00:00 en `Europe/Madrid`, el saldo de SuperSweet se eleva a **5 como mínimo**. `0 → 5`, `3 → 5`, `5 → 5`, `12 → 12`. No suma cinco ni reduce un saldo comprado.
- El boost mensual conserva la regla existente: **+1** una vez por mes natural en Madrid, incluyendo saldos comprados. `7 → 8`.
- Estos crons excluyen suscripciones con vencimiento conocido menor o igual al instante de la ejecución. Mantienen la compatibilidad con suscripciones históricas sin vencimiento registrado. No certifican que la autorización de suscripciones del resto de la aplicación esté corregida (T26).
- La ruta histórica `users/cron_regenerate_superlike` comparte el periodo de pago con el cron semanal. El refill gratuito conserva su condición anterior: saldo cero y último uso hace al menos **168 horas transcurridas**, cantidad uno; un último uso nulo sigue sin calificar. Se verificaron los cambios de horario de primavera y otoño.

## Causa y corrección

El cron semanal asignaba siempre cinco y reutilizaba `last_superlike_given`, que también cambia al consumir. Podía reducir compras y el consumo reciente podía impedir la siguiente regeneración. El cron mensual calculaba el saldo desde un objeto leído antes de escribir, permitiendo perder un crédito concurrente. La ruta histórica de pago tenía otra ventana de siete días sin registrar el grant.

`SubscriptionConsumableRegeneration` selecciona IDs por lotes y escribe cada usuario mediante un único `UPDATE` condicionado por su ID, suscripción vigente y marcador de periodo. Saldo, marcador y `updated_at` cambian juntos; una repetición del mismo periodo no toca ninguno. `updated_at` conserva el mayor valor entre el timestamp persistido y el instante de ejecución: no retrocede si otra escritura lo avanzó mientras esperaba el cron. MySQL evalúa las condiciones y el saldo después de adquirir el bloqueo de la fila. No se sustituyen los mecanismos de crédito de Stripe.

La selección por ID evita los bloqueos de rango del índice de suscripción: una primera versión con un `UPDATE` global reprodujo un deadlock al cancelar una suscripción concurrentemente. La variante final superó ese mismo test. No se leen saldos para calcular los nuevos valores en Ruby ni se reutiliza una decisión de elegibilidad tomada antes del bloqueo.

## Migración y despliegue

La migración `20261007120000` añade `last_weekly_super_sweet_given`, separado del timestamp de consumo, y copia conservadoramente `last_superlike_given` cuando existe. No cambia saldos ni timestamps de consumo.

El historial anterior no distingue grant y consumo: una actividad de esta misma semana puede posponer el primer refill hasta el lunes siguiente. Este criterio evita repetir un refill ya realizado durante la semana del cambio. Los tests ejecutan realmente la migración hacia adelante y atrás, comprueban el backfill y ese primer lunes siguiente. La reversión elimina únicamente el marcador nuevo; el despliegue requiere la migración antes de ejecutar el código nuevo y evitar crons de versiones antiguas durante la transición.

Solo se incorporaron a `schema.rb` la versión y el campo nuevo. Persisten las omisiones anteriores del esquema (T08), incluido `last_monthly_boost_given`, cuya migración ya existía; no se reconstruyó el esquema completo en esta tarea.

## Tests y evidencia

| Ejecución | Resultado |
| --- | --- |
| HTTP y concurrencia contra el controlador original, antes de producción | 18 tests/100 assertions: 13 failures; 9 tests/31 assertions: 8 failures; ningún error |
| HTTP y concurrencia finales contra `HEAD` original, antes de los tests adicionales de timestamp/DST | 28 tests/136 assertions: 22 failures, 0 errors |
| Mutación de migración sin backfill | 2 tests/11 assertions: 2 failures, 0 errors |
| Conservación de `updated_at`, antes de añadirlo al SQL | 1 test/3 assertions: 1 failure, 0 errors |
| Monotonía de `updated_at` ante una escritura posterior mientras espera el cron, antes de preservar el mayor timestamp | 2 tests/6 assertions: 2 failures, 0 errors |
| Cooldown gratuito usando días de calendario, antes de conservar 168 horas | 2 tests/6 assertions: 2 failures; los dos tests pasaron contra el controlador original |
| T24 final, seed 54321 | **36 tests, 219 assertions, 0 failures/errors/skips** |
| Regresión T03/autenticación/likes/suscripciones/Stripe/usuarios/verificación/logging junto con T24, seed 12345 | **306 tests, 1129 assertions, 0 failures/errors/skips** |
| Suite global original, Redis sintético vacío, seed 12345 | 567 tests, 919 assertions, 0 failures, **294 errores previos** |
| Suite global final, Redis sintético vacío, seed 12345 | 603 tests, 1138 assertions, 0 failures, **los mismos 294 errores previos**, 0 skips |

Los tests T24 ejercitan HTTP, persistencia y transacciones reales. Los de concurrencia usan conexiones MySQL distintas, verificadas mediante `CONNECTION_ID()`, y una barrera inmediatamente antes del SQL real. Cubren crons simultáneos, ambas rutas semanales, periodo/eligibilidad modificados mientras espera el cron y recibos Stripe reales que acreditan 60 SuperSweet o 10 boosts durante la espera. No hacen llamadas a Stripe ni a otros proveedores. No cargan las fixtures compartidas.

```sh
bundle exec rails test \
  test/controllers/consumable_regeneration_test.rb \
  test/controllers/consumable_regeneration_concurrency_test.rb \
  test/migrations/weekly_super_sweet_marker_test.rb --seed 54321
```

La regresión adicional usa exactamente los archivos de la ejecución de 270 tests documentada en [T03](t03-boundary-tests.md), más los tres archivos T24. Los 294 errores globales previos se enumeran en [el inventario T03](t03-existing-suite-errors.txt): 293 errores de fixtures (`info_item_values.name`) y el registro que falla por `split` sobre un entero. Se compararon los nombres de los tests afectados entre baseline y resultado final: coinciden exactamente. No se corrigieron ni se ocultaron.

## Entorno y límites

Toda la ejecución ocurrió en una red Docker interna con MySQL y Redis desechables, usando `RAILS_ENV=test`, `PARALLEL_WORKERS=1`, `DISABLE_SPRING=1`, secretos sintéticos y sin ficheros de credenciales reales. Se empleó la imagen existente `toppin_rails-develop-rails:latest`. La copia de Rails vive en el contenedor; el repositorio está montado en solo lectura. La base temporal se complementó con las mismas omisiones descritas en T03 y el marcador mensual anterior; no se operó sobre una base real.

Contenedores de verificación: `toppin-t24-20261007-rails`, `toppin-t24-20261007-mysql`, `toppin-t24-20261007-redis`. Red: `toppin-t24-20261007-network`. Se preservaron los contenedores ajenos. Las ejecuciones globales/regresión usaron índices Redis nuevos para evitar presupuestos de login heredados; una repetición inicial con el índice ya usado reprodujo dos 429 de throttling y se volvió a medir el baseline con índices vacíos.

Los avisos anteriores de autoload Rails, Elasticsearch y claves `jti` duplicadas siguen presentes. No hay despliegue ni validación con datos reales. El SQL protege estas regeneraciones frente a créditos Stripe atómicos; no convierte otros escritores antiguos o el consumo en operaciones atómicas (T25).
