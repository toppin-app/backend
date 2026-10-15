# T27 — Likes idempotentes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplicar cada operación de like y su descuento una sola vez, conservando las dos fases de SugarSweet.
**Architecture:** Recibo mínimo persistente por actor/UUID, transacción que bloquea ambos participantes por ID y transición existente sin reescribir consentimiento. Un transporte Mobile compartido identifica y encola operaciones por sesión/destinatario; Home e historial protegen además sus efectos visuales.
**Tech Stack:** Rails 6, MySQL, Minitest, React Native, Jest, UUID ya instalado.
**Spec:** `docs/superpowers/specs/2026-10-15-t27-like-idempotency-design.md`

## Global Constraints

- No modificar T28/T29/T30/T31/T25, ni limpiar datos históricos o añadir índice único de parejas.
- Sin dependencias nuevas, credenciales nuevas ni reenvíos automáticos. Mantener solicitudes sin UUID y respuestas de operaciones nuevas.
- Recibo sin mensajes en texto ni copias históricas de perfiles. No borrar recibos automáticamente. Reintentos Mobile garantizados en memoria durante la sesión, no tras cerrar el proceso.
- Commit/push Rails, commit local sin push Mobile; tests reales en base desechable, sin proveedores.

## Review Focus

- El retry del último crédito debe resolverse antes de validar saldo: Task 1.
- Un UUID antiguo tras otra decisión no revive el match ni vuelve a descontar: Task 1.
- El mensaje SugarSweet enviado antes de terminar el SuperSweet debe esperar, no perderse: Task 2.
- Una operación encolada de la cuenta anterior no puede enviarse con la sesión nueva: Task 2.
- Un fallo de Jbuilder o persistencia no puede dejar cobros sin recibo: Task 1.

---

### Task 1: Recibo, transacción y replay seguro en Rails

**Files:**
- Create: `db/migrate/20261015121000_create_swipe_operation_receipts.rb`, `app/models/swipe_operation_receipt.rb`, `app/services/swipe_operation.rb`.
- Modify: `app/controllers/user_match_requests_controller.rb`, `db/schema.rb` (solo tabla/version nueva).
- Test: `test/controllers/likes_flow_test.rb`, `test/controllers/swipe_idempotency_test.rb`, `test/controllers/swipe_concurrency_test.rb`, `test/migrations/swipe_operation_receipts_test.rb`.

**Interfaces:**
- `POST /send_match.json` añade parámetro opcional `operation_id` UUID. Mismo actor/UUID con otra huella devuelve 409 sin mutaciones.
- `SwipeOperation.call(actor:, target_id:, operation_id:, payload:) { ... }` ejecuta transición solo si es nueva y devuelve resultado renderizable; huella SHA256 de parámetros tipados en orden estable incluyendo mensaje.
- `SwipeOperationReceipt`: `user_id`, `target_user_id`, `operation_id` nullable, `request_fingerprint`, `result` JSON mínimo y timestamps. Índice único `(user_id, operation_id)` y búsqueda de último recibo `(user_id,target_user_id,id)`. No guardar datos de perfil; actor borrado no debe quedar bloqueado por una nueva FK restrictiva.
- Resultado mínimo: tipo `match` con `user_match_request_id` o directiva `sugar_play/next_in/message` estática. Replay reconstruye representación actual autorizada; desaparecido/rechazado/bloqueado: éxito no-op `is_match:false,sugar_play:false,already_applied:true`.

- [ ] **Step 1: Tests RED de duplicados.** Cambiar la caracterización de likes repetidos y añadir SuperSweet/dislike/recibo con último crédito. Aserciones independientes:

```ruby
assert_equal 4, actor.reload.likes_left # saldo inicial 5, dos POST de la misma operación
assert_equal 1, UserMatchRequest.where(user_id: actor.id, target_user: target.id).count
assert_equal 1, SwipeOperationReceipt.where(user_id: actor.id, operation_id: operation_id).count
```

- [ ] **Step 2: Ejecutar RED contra el controlador actual.** `bundle exec rails test test/controllers/likes_flow_test.rb test/controllers/swipe_idempotency_test.rb --seed 54321`; aislar primero las expectativas que pueden reproducir el doble descuento sin depender de la tabla nueva.
- [ ] **Step 3: Migración y operación mínima.** Bloquear ambos User por ID ascendente, releer saldo/interacción/recibo dentro. Para UUID conocido, validar huella y resolver sin aplicar. Sin UUID, comparar último recibo completo desde despliegue; no inventar equivalencia histórica desde UMR. Reutilizar la transición actual y sus costes; reemplazar retornos/render interiores por resultado, escrituras con fallo explícito y efectos diferidos. Decisión/saldo/contador/recibo se confirman juntos; serializar respuesta en memoria antes del commit. Jobs, push, broadcasts y eliminación Twilio solo tras commit y solo en operación nueva.
- [ ] **Step 4: Tests RED/GREEN de carreras y compatibilidad.** Dos conexiones MySQL distintas: mismo UUID simultáneo, legacy idéntico, último crédito contra destinos distintos y swipes recíprocos. Probar UUID con otro contenido, like→dislike→retry antiguo, SuperSweet→SugarSweet con mensaje, mensajes distintos, replay con saldo0, UMR eliminado/rechazado/bloqueado y SugarPlay oculto. Inducir fallo de persistencia/serialización: cero cobros parciales, recibos o efectos. No convertir los KNOWN BUG ajenos en expectativas arregladas.
- [ ] **Step 5: Verificar migración y regresión.** Up/down conserva interacciones anteriores y crea índice de recibos correcto. Ejecutar `likes_flow_test`, `swipe_idempotency_test`, `swipe_concurrency_test`, `interactions_history_flow_test`, `likes_queries_test`, `like_delivery_jobs_test` y regresión T03/T24; suite global con comparación nominal del baseline. Documentar límite legacy y ventana commit→enqueue en `docs/quality/t27-like-idempotency.md`.
- [ ] **Step 6: Commit focalizado tras revisión.** `fix(likes): make swipe decisions and debits idempotent`; push Rails validado, sin incluir planes antiguos ni cambios ajenos.

### Task 2: Identidad, cola y guardas inmediatas Mobile

**Files:**
- Create: `../itechtoppin-develop/src/services/swipeOperations.js`, `../itechtoppin-develop/__tests__/services/swipeOperations.test.js`.
- Modify: `../itechtoppin-develop/src/services/userMatch.service.js`, `../itechtoppin-develop/src/screens/Home/HomeScreen/useSwipeAndMatch.tsx`, `../itechtoppin-develop/src/screens/InteractionsHistory/InteractionsHistoryScreen.tsx`.
- Test: `../itechtoppin-develop/__tests__/services/userMatchService.test.js`, `../itechtoppin-develop/__tests__/screens/Home/useSwipeAndMatch.test.ts`, `../itechtoppin-develop/__tests__/screens/InteractionsHistoryScreen.test.tsx`.

**Interfaces:** `enqueueSwipeOperation(payload, send)` devuelve Promise de respuesta Axios; `send(payloadWithOperationId)` solo inicia la petición al corresponder su turno. Usa `sessionGeneration()` existente y UUID criptográfico instalado. `postUserResponseMatchUserSwipe` conserva firma actual; todos sus consumidores quedan cubiertos por el transporte.

- [ ] **Step 1: Tests RED de guardas y transporte.** Invertir ambas caracterizaciones que esperan dos POST; mantener primera promesa pendiente y exigir uno. Prueba del transporte real con Axios simulado: dos iguales comparten envío/UUID, error ambiguo mantiene UUID en retry, intención diferente usa otro UUID; code4xx definitivo libera la operación.
- [ ] **Step 2: Ejecutar RED.** `yarn test __tests__/services/userMatchService.test.js __tests__/screens/Home/useSwipeAndMatch.test.ts __tests__/screens/InteractionsHistoryScreen.test.tsx --runInBand --watchman=false`.
- [ ] **Step 3: Implementar cola e identidad.** Encolar por generación/destinatario, colapsar solo intención igual pendiente, retener UUID ante red/5xx. Generación cambiada limpia estado e impide que una petición antigua encolada salga con credenciales nuevas; las finalizaciones antiguas no borran la operación actual. Eliminar logs de payload/error Axios de este transporte. Guardas `useRef` en Home/historial antes del primer await, esperar promesa completa y liberar en finally; no bloquear ni descartar la segunda intención SugarSweet.
- [ ] **Step 4: Tests RED/GREEN de fases y sesión.** SuperSweet pendiente y SugarSweet confirmado: un POST inicial y otro posterior con UUID distinto y mensaje intacto. Cambio de opinión tras éxito tiene nueva identidad. Logout/login durante espera no envía acciones viejas. Un error libera UI y permite reintento sin doble cobro. Cubrir Home/historial y helper real usado por perfil, boost y PowerSweet, sin reescribir sus pantallas.
- [ ] **Step 5: Verificación y commit local.** Suites focales + `yarn test --runInBand --watchman=false`; typechecks comparados con cinco diagnósticos aplazados y bundles JS iOS/Android temporales. Commit `fix(likes): deduplicate and sequence mobile swipe operations`, sin push. Actualizar Notion con evidencia y límites reales, no afirmar exactamente una vez de proveedores/jobs ni despliegue.
