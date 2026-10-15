# T40 — Recuperación privada Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Impedir resets sin prueba privada y conservar las versiones Mobile anteriores.
**Architecture:** Token aleatorio con digest persistido, código anterior como compatibilidad limitada y transacción por cuenta para comprobar y consumir la prueba. Mobile transmite el token en memoria; Rails sigue admitiendo el código correcto de clientes anteriores.
**Tech Stack:** Rails 6, MySQL, Minitest, React Native, Jest; sin dependencias nuevas.
**Spec:** `docs/superpowers/specs/2026-10-15-t40-password-recovery-design.md`

## Global Constraints

- Diez minutos de vigencia máxima, cinco intentos fallidos de reset separados de los cinco de verificación; no renovar el plazo al verificar.
- No rotar credenciales, exigir variables nuevas, cambiar login social ni introducir persistencia Mobile del token.
- Rails commit y push; Mobile commit local sin push. Base desechable y proveedores sustituidos; no despliegue ni cambios reales de datos.
- Preservar cambios ajenos y registrar los errores previos de la suite global por nombre, sin convertirlos en éxitos.

## Review Focus

- Verificar el quinto código correcto no puede impedir el reset: prueba de presupuestos separados en Task 1.
- Un token inválido acompañado de un código correcto no debe degradar a fallback: Task 1.
- Nueva solicitud simultánea con un reset no deja pruebas antiguas utilizables: dos conexiones y orden de locks en Task 1.
- Un fallo al consumir la prueba no puede dejar la contraseña cambiada: rollback inducido en Task 1.
- Nuevo Mobile contra servidor antiguo debe seguir funcionando con el código: Task 2.

---

### Task 1: Proteger y consumir la prueba en Rails

**Files:**
- Modify: `app/models/password_recovery.rb`, `app/controllers/password_recoveries_controller.rb`, `config/initializers/filter_parameter_logging.rb`, `db/schema.rb` (solo campos nuevos/version).
- Create: `app/services/password_recovery_reset.rb`, `db/migrate/20261015120000_add_private_reset_proof_to_password_recoveries.rb`.
- Test: `test/controllers/password_recoveries_controller_test.rb`, `test/models/password_recovery_test.rb`, `test/controllers/password_recovery_concurrency_test.rb`, `test/migrations/private_reset_proof_test.rb`, `test/middleware/sensitive_logging_test.rb`.

**Interfaces:**
- `PasswordRecovery#verify_code(code)` conserva `success/error/message` y añade `recovery_token` solo en éxito.
- `PasswordRecoveryReset.call(email:, new_password:, recovery_token: nil, code: nil)` devuelve resultado con `status` HTTP y `body` JSON; no renderiza ni envía email.
- `verify_code` HTTP añade `recovery_token`; `reset_password` consume `recovery_token` o el `code` legacy, nunca solo email. Campos nuevos: `reset_token_digest:string` y `reset_attempts:integer, default:0, null:false`.

- [ ] **Step 1: Escribir pruebas de rechazo antes del código.** Cambiar ambas caracterizaciones T40 y añadir prueba inválida/omitida, otro email, vencimiento exacto y replay. Aserciones centrales:

```ruby
assert_response :forbidden
assert owner.reload.valid_password?('Original123!')
assert_equal 1, PasswordRecovery.for_email(owner.email).count
```

- [ ] **Step 2: Ejecutar RED.** `bundle exec rails test test/controllers/password_recoveries_controller_test.rb test/models/password_recovery_test.rb --seed 54321`; observar rechazo esperado frente al éxito inseguro actual, no confundir errores de setup con RED.
- [ ] **Step 3: Añadir migración y servicio mínimo.** Generar código y token con `SecureRandom`; almacenar SHA256 del token, comparar en tiempo constante. Enlazar todas las acciones de recuperación al lock del usuario y luego las filas de recuperación en orden estable. Verificación/intentos y comprobación/guardado/consumo son atómicos; nueva recuperación invalida las anteriores; reset exitoso consume todas. Error de validación no consume autorización. Ausencia de prueba devuelve 403 sin gastar presupuesto. Conservar traducciones y cooldown; enviar Mailjet fuera del lock. Filtrar `code`, `recovery_code`, `recovery_token`, `new_password`.
- [ ] **Step 4: Añadir y ejecutar RED/GREEN de concurrencia y errores.** Dos conexiones MySQL distintas, mismo token/código: exactamente un 200 y contraseña correspondiente al ganador; cinco fallos simultáneos no permiten un sexto acierto. Probar quinto intento de verificación correcto seguido de reset, token incorrecto con código correcto, nueva solicitud/reset concurrentes y fallo de `destroy!`/persistencia: contraseña y prueba originales sobreviven juntas. Probar cliente legacy con código correcto, contraseña débil y cuenta eliminada. Usar proveedores ficticios, no sustituir transacciones/autenticación.
- [ ] **Step 5: Verificar migración y regresión.** Migración up/down en base desechable conserva filas y no cambia contraseñas; ejecutar las suites anteriores, migración/logging/concurrencia y la regresión documentada en `docs/quality/t03-boundary-tests.md`. Documentar comandos/resultados en `docs/quality/t40-password-recovery.md`; suite global y comparación con baseline antes de declarar fin.
- [ ] **Step 6: Commit focalizado.** Incluir únicamente archivos T40 y su evidencia: `fix(auth): require a private single-use password reset proof`. Push de Rails tras revisión.

### Task 2: Transmitir la prueba y evitar su filtración en Mobile

**Files:**
- Modify: `../itechtoppin-develop/src/services/passwordRecovery.service.js`, `../itechtoppin-develop/src/screens/PasswordRecoveryVerification.js`, `../itechtoppin-develop/src/screens/PasswordRecoveryReset.js` (y pantalla de solicitud solo si registra cuerpos sensibles).
- Create tests: `../itechtoppin-develop/__tests__/services/passwordRecoveryService.test.js`, `../itechtoppin-develop/__tests__/screens/PasswordRecovery.test.js`.

**Interfaces:** `resetPassword(email, code, newPassword, recoveryToken = null)` añade `recovery_token` cuando está disponible. Navegación a Reset conserva email/code y añade `recoveryToken`; ausencia de token de servidor antiguo usa el contrato anterior con código.

- [ ] **Step 1: Tests RED del contrato y pantallas reales.** Verificación devuelve `recovery_token:'private-proof'`; al introducir la contraseña, la petición final contiene ese token. Servidor antiguo sin token conserva código; error no navega a éxito. Rechazar un AxiosError con secretos en config/data no los imprime ni persiste.
- [ ] **Step 2: Ejecutar RED.** `yarn test __tests__/services/passwordRecoveryService.test.js __tests__/screens/PasswordRecovery.test.js --runInBand --watchman=false`.
- [ ] **Step 3: Implementar el parámetro opcional y su navegación en memoria.** Conservar validaciones/copy existentes; reemplazar logs de objetos Axios por mensajes sin payload ni errores completos. No añadir AsyncStorage ni parámetros secretos a URLs.
- [ ] **Step 4: Verificar GREEN y suite global Mobile.** Misma ejecución focal y `yarn test --runInBand --watchman=false`; compilar bundles JS iOS/Android en directorio temporal, revisar diff. No presentar bundles como build nativa o prueba real de email.
- [ ] **Step 5: Commit local y registro.** `fix(auth): carry private recovery proof without logging secrets`; sin push Mobile. Actualizar resultado T40 en Notion con pruebas, commits, compatibilidad y ausencia de despliegue.
