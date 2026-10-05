# T03 — Cobertura de autenticación, fotos, chat y recuperación

Validación: 5 de octubre de 2026. Este cambio contiene únicamente tests y documentación. No corrige autorización ni lógica de producción.

## Cobertura

| Suite | Tests | Comportamiento observable |
| --- | ---: | --- |
| `test/channels/application_cable/connection_test.rb` | 10 | Identidad real mediante JWT; propietario, tercero, admin y anónimo; firma inválida, expiración y usuario inexistente; caracterización T33. |
| `test/controllers/twilio_controller_test.rb` | 7 | Autenticación HTTP real, revocación y bloqueo; identidad y servicio enviados al SDK; tercero/admin; fallo de configuración del proveedor. |
| `test/controllers/user_media_controller_test.rb` | 19 | CRUD persistido y permisos actuales; JWT inválido/expirado/revocado; admin y bloqueo; subida real de GIF sintético, miniatura y borrado físico; rechazo/fallo de moderación; caracterización T35. |
| `test/controllers/password_recoveries_controller_test.rb` | 18 | Validación, cuenta eliminada/inexistente, envío del código persistido, cooldown, proveedor fallido, último código, expiración/intentos máximos, contraseña débil, consumo de recuperación y caracterización T40 entre clientes diferentes. |
| `test/models/password_recovery_test.rb` | 10 | Persistencia de intentos/verificación, expiración, quinto intento, cooldown por email normalizado, códigos pendientes y retención. |

Los tests usan usuarios y registros reales en transacciones, sin cargar las fixtures compartidas. JWT/Devise/Warden, callbacks, validaciones, CarrierWave, MiniMagick y eliminación de archivos se ejecutan realmente. Las imágenes son sintéticas y se almacenan en directorios temporales que se eliminan al salir del test.

Los únicos sustitutos externos son `Twilio::REST::Client.new`, `Twilio::JWT::AccessToken.new`, `Mailjet::Send.create` y `Aws::Rekognition::Client.new`. Todos los casos de solicitud de email, incluidos los rechazados, aíslan Mailjet; un envío inesperado provoca un fallo del test. Las credenciales Twilio se sustituyen por valores ficticios durante el bloque y se restauran. No se envían emails/SMS ni se contacta a proveedores.

## Caracterizaciones de defectos existentes

Los siguientes tests verdes prueban que el defecto sigue presente; **no establecen una política de seguridad aceptable**. Cuando se implemente cada corrección, hay que cambiar estas expectativas para exigir rechazo y añadir la regresión correspondiente.

- **T33:** websocket acepta JWT con `jti` revocado y usuarios bloqueados o eliminados. HTTP sí rechaza JWT revocados y usuarios bloqueados en las rutas cubiertas.
- **T35:** un tercero puede consultar, modificar y eliminar fotos ajenas. `create` acepta un `user_id` ajeno y `update` permite transferir el propietario. La respuesta de `create` devuelve las fotos del usuario autenticado aunque el registro se haya creado para otra cuenta.
- **T40:** una vez existe una recuperación verificada, otro cliente anónimo o una cuenta autenticada diferente puede cambiar la contraseña enviando únicamente email y contraseña nueva. El test anónimo verifica el código desde una sesión distinta a la que después realiza el reset.
- **T11 / moderación:** `update` guarda la imagen antes de moderarla; un fallo del proveedor deja el archivo guardado. El rechazo explícito elimina la imagen nueva. Los tests no afirman que la imagen anterior se conserve.
- **Fiabilidad de recuperación:** un error de Mailjet devuelve 500 pero deja la recuperación pendiente y su cooldown. El propietario no recibe un email real en estos tests.
- **Fiabilidad de Twilio:** el error de configuración se propaga; la acción no tiene manejo propio del fallo. El token se devuelve como cadena JWT sin comillas, con tipo de contenido JSON; no se presupone un objeto JSON.

## Ejecución focal

Usar exclusivamente `RAILS_ENV=test`, una base desechable, `PARALLEL_WORKERS=1` y una clave JWT de prueba. Requiere las dependencias Rails, MySQL e ImageMagick disponibles.

```sh
bundle exec rails test \
  test/channels/application_cable/connection_test.rb \
  test/controllers/twilio_controller_test.rb \
  test/controllers/user_media_controller_test.rb \
  test/controllers/password_recoveries_controller_test.rb \
  test/models/password_recovery_test.rb --seed 54321
```

Resultado: **64 tests, 223 assertions, 0 failures, 0 errors, 0 skips**. También se comprobó el orden con seed 12345.

La regresión seleccionada de autenticación/sesión/throttling, likes/historial, suscripciones, Stripe, usuarios, verificación telefónica y logging, junto con T03, produjo **270 tests, 910 assertions, 0 failures/errors/skips**. Se ejecutaron estos archivos adicionales:

```text
test/controllers/users/sessions_controller_test.rb
test/controllers/session_status_controller_test.rb
test/controllers/users/login_throttling_test.rb
test/services/login_attempt_limiter_test.rb
test/controllers/likes_flow_test.rb
test/controllers/interactions_history_flow_test.rb
test/jobs/like_delivery_jobs_test.rb
test/models/likes_queries_test.rb
test/controllers/subscription_access_test.rb
test/controllers/subscription_call_limits_test.rb
test/controllers/subscription_lifecycle_test.rb
test/controllers/subscription_management_test.rb
test/models/subscription_entitlements_test.rb
test/controllers/stripe_controller_test.rb
test/controllers/stripe_webhooks_controller_test.rb
test/services/stripe_consumable_credit_test.rb
test/services/stripe_subscription_replacement_test.rb
test/controllers/users_controller_test.rb
test/controllers/phone_verifications_controller_test.rb
test/models/phone_verification_test.rb
test/middleware/sensitive_logging_test.rb
```

La regresión de throttling requiere un Redis desechable: `LOGIN_LIMITER_TEST_REDIS_URL` y `REDIS_URL` deben apuntar a bases sintéticas aisladas. Reutilizar la base de aplicación entre ejecuciones puede conservar presupuestos de login y devolver 429 en tests de sesión. Se comprobó esa limitación y se usaron bases vacías para la ejecución global final; no se borraron datos de Redis compartido.

## Suite global y limitaciones

`bundle exec rails test --seed 12345`, con Redis de prueba vacío: **567 tests, 919 assertions, 0 failures, 294 errors, 0 skips**. No hay errores de las cinco suites T03. La suite global **no está verde**:

- 293 tests fallan antes de ejecutar su comportamiento por `ActiveRecord::Fixture::FixtureError: table "info_item_values" has no columns named "name"`.
- `Users::RegistrationsControllerTest#test_signup_persists_a_complete_verified_registration_and_its_interests` falla por `ActionView::Template::Error: undefined method split for 0:Integer`.
- Algunos fallos de setup añaden errores secundarios de teardown (`any?` sobre nil), sin aumentar el número de tests afectados.

El [inventario de errores](t03-existing-suite-errors.txt) nombra los 294 tests afectados. Se reprodujeron ambas causas con los tests originales extraídos de `git archive HEAD test` en otra copia temporal: `InfoItemValuesControllerTest` dio 7 errores de fixtures y 0 assertions; la suite de registro dio 4 tests, 9 assertions y el mismo error de `split`. No se arreglaron ni se omitieron silenciosamente estos problemas.

`schema.rb` no permite reconstruir por sí solo todas las tablas/campos que usa el código (T08). Solo se complementó la base **temporal** con `users.language`, `users.block_reason_key`, `users.phone`, migraciones de blocks/phone_verifications/password_recoveries/TMDB, `tmdb_user_data.release_date`, nombre de tabla `tmdb_user_series_data` y campos de estado/acción/motivo/bloqueo de denuncias. No se modificaron schema ni migraciones y no se operó sobre una base real.

Permanecen avisos previos de autoload de Rails, Elasticsearch y claves `jti` duplicadas en los tests existentes de sesión. No se cubren el worker asíncrono del webhook Twilio, la API real de los proveedores, clientes móviles ni despliegue. T03 aporta cobertura; no certifica que T35/T33/T40/T11 estén corregidas.
