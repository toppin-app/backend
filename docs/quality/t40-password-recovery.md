# T40 — Recuperación privada y atómica

Validación backend y Mobile: 15 de octubre de 2026. Revisión final independiente y corrección de su hallazgo importante completadas. No hay despliegue.

## Corrección

El reset rechaza email sin prueba. Verificar emite un token aleatorio de 32 bytes, persiste solo SHA256 y conserva el vencimiento original de diez minutos. Mobile anterior puede finalizar con su código correcto, con cinco intentos de reset separados de la verificación. Un token inválido nunca degrada a código; omitir la prueba no consume intentos.

Los tres endpoints serializan por cuenta y releen la recuperación más reciente. Contraseña y consumo de todas las pruebas se confirman juntos; un fallo de consumo revierte también la contraseña. Una nueva solicitud vence las anteriores. No se rescata un código antiguo después de verificar otro más nuevo. Se usa SecureRandom y se rechaza la caducidad exacta.

Se mantienen cooldown, traducciones, clientes anteriores y prueba válida ante contraseña débil. Entradas estructuradas en email/contraseña devuelven400 en vez de500. El idioma queda limitado a la petición con I18n.with_locale: el setter anterior contaminaba otras solicitudes y provocaba fallos de formularios según el orden de pruebas.

## Logs y migración

Se filtran código/token/contraseña HTTP. Una prueba DEBUG demostró que MySQL además interpolaba el código en SQL: un filtro acotado del suscriptor sustituye SQL/binds de password_recoveries en una copia del evento de logging. Conserva duración, nombre/runtime, evento original, SQL real y diagnósticos de otras tablas. No cambia credenciales ni requiere variables nuevas.

La migración20261015120000 añade reset_token_digest nullable y reset_attempts default0/no-null, sin cambiar contraseñas ni verificaciones existentes; se prueba up/down con filas reales. Debe ejecutarse antes de desplegar. schema.rb omitía toda password_recoveries: se incluyó solo esa tabla según la migración original y los campos nuevos, sin reconciliar el resto de T08.

## Evidencia

- Antes de producción: RED44tests/185assertions/11failures/0errors; ampliación47/190/13failures y un error real por email Integer.
- Contra código original: cuatro carreras, cuatro fallos y cero errores; ambos resets devolvían200, seis pruebas inválidas se aceptaban y verificación llegaba a seis intentos. Rollback: un test/un fallo/cero errores porque la contraseña ya se había confirmado.
- RED de idioma: petición ES cambiaba EN del llamante. RED de logger SQL: exponía el código918273 pese al filtro HTTP.
- Focal tras revisión: **62tests/327assertions/0failures/errors/skips**, seed54321. HTTP, modelo, cinco carreras MySQL, migración, logging real y re-registro con correo de cuenta eliminada.
- Regresión T03/T24/T36/T37+T40: **477tests/1778assertions/0failures/errors/skips**, seed54321.
- Global tras revisión: **767tests/1778assertions/0failures/290errores previos/0skips**, seed12345. Los 290 nombres coinciden exactamente con el [inventario T36/T37](t36-t37-existing-suite-errors.txt), sin errores nuevos. No se declara verde la suite global.

```sh
bundle exec rails test test/controllers/password_recoveries_controller_test.rb test/models/password_recovery_test.rb test/controllers/password_recovery_concurrency_test.rb test/migrations/private_reset_proof_test.rb test/middleware/sensitive_logging_test.rb --seed 54321
```

La regresión usa los 29 archivos T03/T24, las tres suites T36/T37 y los dos archivos nuevos de concurrencia/migración. MySQL/Redis desechables, red Docker interna, secretos ficticios y proveedores sustituidos. Las barreras conservan SQL/transacciones reales y verifican CONNECTION_ID distinto. En los helpers se corrigieron forwarding de keywords Ruby y limpieza del callback sintético de fallo; no se sustituyó la persistencia.

## Revisión final

La revisión independiente detectó que buscar un usuario solo por email podía seleccionar una cuenta eliminada en vez de la cuenta activa re-registrada con ese correo. Se aplicó únicamente en la base desechable la migración de índice de email ya existente20251124162600. Tres pruebas nuevas con ambas cuentas y un plan de consulta válido alternativo reprodujeron el problema: **3 tests, 3 fallos, cero errores**. El índice permanece único; se hace invisible al optimizador durante estos casos y se restaura al terminar.

El reset selecciona primero la cuenta activa y conserva el rechazo anterior cuando solo existe una eliminada. Verificación selecciona la activa y vuelve a comprobar que no esté eliminada después de adquirir el lock. Las tres pruebas y toda la regresión pasan tras este cambio. No se modifica globalmente el índice ni el esquema de usuarios de T08.

Única recomendación menor aplazada: las carreras de reset prueban un éxito y un rechazo, pero ambos contendientes usan la misma contraseña; distinguir las contraseñas fortalecería la comprobación de correspondencia con el ganador. No se afirma haber añadido esa cobertura.

## Mobile

El servicio conserva su firma anterior con un cuarto parámetro opcional. La verificación lleva el token a la pantalla de reset mediante parámetros de navegación en memoria; no se añade almacenamiento persistente. Si el servidor anterior no devuelve token, el cliente sigue enviando su código con el contrato anterior. Los logs del flujo ya no imprimen objetos Axios que puedan contener contraseña, código o token.

- Doce pruebas nuevas del servicio y de las pantallas reales, con Axios sustituido únicamente en la frontera HTTP. Cubren token, compatibilidad legacy, navegación, contraseña débil, errores y reenvío con cooldown sin exponer secretos.
- Suite completa: **60 suites, 644 pruebas y 7 snapshots aprobados**.
- ESLint de los cinco archivos cambiados y `git diff --check`: correctos.
- Bundles JS temporales iOS/Android generados correctamente (390/444 assets). No son compilaciones nativas ni una prueba end-to-end con Mailjet.
- Commit Mobile `a24bf40`, únicamente local; no se ha hecho push de la app.

## Límites

Sin Mailjet real, cliente nativo ni base real. Un fallo de email conserva la nueva recuperación y cooldown, como antes; ahora el código nuevo invalida al anterior aunque el envío falle. Enumeración de cuentas, revocación de otras sesiones, CSRF general y T08 quedan sin modificar. T27 fue aplazada por el usuario antes de realizar cambios de implementación; no forma parte de esta entrega.
