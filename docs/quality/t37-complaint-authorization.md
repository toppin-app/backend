# T37 — Separar denuncias y moderación

Validación focal: 15 de octubre de 2026.

## Resultado

La autenticación no limitaba las denuncias por rol: cualquier cuenta podía leer el listado y los detalles, modificar denuncias ajenas, cambiar su autor o destinatario, aplicar un bloqueo global y borrar la evidencia. El envío y la moderación compartían los mismos parámetros permitidos. El perfil HTML y su paginación AJAX también mostraban al usuario denunciado quién lo había denunciado.

`ComplaintsController` ahora reserva `index`, `new`, `show`, `edit`, `update` y `destroy` a administradores, antes de buscar la denuncia. Las cuentas normales reciben 403. El administrador conserva los filtros, los controles de bloquear/ignorar/borrar y sus respuestas HTML/JSON.

El envío mantiene el contrato móvil: `to_user_id`, `reason`, `text`, `reason_key` y `block_user`. El servidor asigna el autor autenticado. Los campos `action_taken` y `status` no se aceptan durante el envío; la denuncia comienza sin revisar. `block_user: true` conserva el bloqueo personal del denunciante, sin bloquear globalmente al destinatario.

La actualización administrativa sólo acepta `action_taken`. Autor, destinatario y evidencia no se reescriben desde la moderación. El formulario de edición muestra esos datos como lectura y permite seleccionar la acción. El formulario de creación no ofrece un autor elegido por el cliente.

Las denuncias recibidas sólo se consultan y muestran para administradores en el perfil. La paginación recibida de una cuenta normal devuelve 403, incluso con un valor vacío o con otro ID de perfil. El acceso general al perfil y la política de bloqueos personales no cambian.

## Pruebas

Se reemplazaron los tests de scaffold de denuncias por integración sin fixtures compartidas, con usuarios persistidos y JWT reales. Las dos suites T37 contienen 40 tests:

- Anónimos, JWT inválido/expirado/revocado y cuentas bloqueadas.
- Denunciante, destinatario y tercero sin acceso global ni permisos de moderación/borrado.
- Inyección de autor, destinatario, evidencia y campos de moderación.
- Envío móvil con bloqueo personal, sin él y con un bloqueo ya existente.
- Administración legítima, filtros, formularios y controles HTML, bloqueo global y denuncias históricas sin destinatario.
- Privacidad del historial recibido por HTML y AJAX, manteniendo el perfil JSON.

Antes de cambiar producción, las suites T37 dieron **40 tests, 120 assertions, 22 failures y 1 error**. Los fallos demostraron acceso 200 en lugar de 403, borrado efectivo, reasignación y moderación inyectada; el error provenía de procesar una paginación vacía antes de autorizarla.

Después del cambio, la ejecución conjunta con T36 dio **137 tests, 481 assertions, 0 failures, 0 errors y 0 skips**:

```sh
bundle exec rails test \
  test/controllers/complaints_controller_test.rb \
  test/controllers/users/complaint_privacy_test.rb \
  test/controllers/catalog_authorization_test.rb --seed 54321
```

Se ejecutó en una copia y base desechables con `RAILS_ENV=test`. El bootstrap temporal tenía el antiguo default `complaints.action_taken = 'none'`, que el enum lee como `nil`; se alineó únicamente ese default a `'no_action'` según la migración existente `20260128124500`, sin backfill ni cambios de schema/migraciones del repositorio.

La revisión independiente detectó una redirección HTML incompatible: tras guardar, una cuenta normal terminaba en el detalle ahora administrativo. Se reprodujo con **dos tests, un fallo y cero errores**, se redirigió a su propio perfil y se conservó el destino anterior para administradores. Se añadieron controles positivos de historial enviado HTML/AJAX y rechazo antes de buscar un ID inexistente. T37 contiene finalmente **45 tests**; junto con T36: **142 tests, 495 assertions, 0 failures/errors/skips**, seed 12345. Regresión de autenticación, registro, recuperación, likes, Stripe, suscripciones, usuarios, logging y T24 más estas suites: **448 tests, 1624 assertions, 0 failures/errors/skips**, seed 54321.

Suite global original en el mismo entorno: **603 tests, 1129 assertions, 0 failures, 297 errors**. Final: **738 tests, 1624 assertions, 0 failures, 290 errors**. No aparece ningún test con error nuevo; la diferencia son los siete scaffold de denuncias reemplazados. [Inventario nominal de errores previos](t36-t37-existing-suite-errors.txt). La revisión posterior no encontró defectos críticos o importantes pendientes en este cambio.

Los tests mantienen reales los controladores, las vistas, las consultas, los callbacks, la persistencia y la autenticación. Sólo sustituyen los constructores SDK de Twilio al mostrar perfiles y la búsqueda del pack compilado en las solicitudes HTML, porque el entorno desechable no contiene ese artefacto. No se contactaron proveedores ni se usaron datos reales.

## Límites

No se ejecutó un cliente móvil ni se desplegó el cambio. La suite global no está verde: quedan incompatibilidades previas de fixtures/esquema (`user_filter_preferences.gender`) y cuatro tests de categorías de intereses retiradas. El fallo de registro `split` sobre Integer documentado anteriormente no llega a ejecutarse en esta suite global, por el fallo anterior de fixtures; no se ha reparado ni certificado aquí. La política global de CSRF queda sin cambios; el entorno de tests la desactiva y no se afirma cobertura de CSRF por estas pruebas de permisos.
