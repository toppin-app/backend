# Likes administrativos: aislar fallos de notificación

## Cambio acotado

`UsersController#create_like` conserva el guardado y las reglas existentes.
Las excepciones del constructor Firebase y del envío se contienen por dispositivo:
no impiden la redirección, no deshacen el like y no interrumpen los demás envíos.
El panel confirma el like y añade un aviso si alguna notificación falla.
El log registra únicamente la clase del error y el ID de la interacción, no el
mensaje del proveedor, credenciales, contenido del push o tokens de dispositivos.

No se modifica el servicio compartido, no se añaden reintentos automáticos ni se
cambia el comportamiento anterior de respuestas HTTP FCM que no lanzan excepción.
La repetición secuencial conserva la fila existente; no es una nueva garantía de
idempotencia concurrente del endpoint administrativo.

## Pruebas

Pruebas HTTP reales con Devise y persistencia MySQL; solo Firebase se sustituye
en su frontera externa. Se cubren rechazo OAuth, error durante envío con otro
dispositivo disponible, éxito/payload, token vacío legacy, repetición tras fallo
y prohibición a usuarios normales. La prueba de logging exige que no aparezcan
el mensaje sensible ni el token sintético.

- RED con el controlador de HEAD: 6 tests, 23 assertions, 3 errores esperados
  (dos rechazos Signet y un Timeout); los otros tres casos ya funcionaban.
- GREEN con la corrección: 6 tests, 54 assertions, sin fallos/errores/skips.
- Suite global: 778 tests, 1854 assertions, 0 fallos, 290 errores previos.
  Los nombres de los 290 coinciden exactamente con el inventario
  `t36-t37-existing-suite-errors.txt`: ninguno nuevo ni desaparecido.
- La ejecución adicional de archivos sin fixtures globales produjo 484 tests,
  1840 assertions y cuatro errores previos de RegistrationsControllerTest por
  la tabla retirada `interest_categories`; no se ocultan ni se corrigen aquí.
- Regresión seleccionada, excluyendo únicamente ese archivo de registro ya
  fallido: **480 tests, 1840 assertions, 0 fallos/errores/skips**, seed 54321.
  Se seleccionaron los archivos con `self.fixture_table_names = []`; no se
  presenta esta selección como sustituto de la suite global anterior.

Ejecución en la copia de Rails del contenedor de seguridad existente, con Ruby
3.0.6, MySQL/Redis desechables, `RAILS_ENV=test`, red Docker interna y sin claves
reales. El repositorio está montado en solo lectura; los archivos probados se
copiaron a la copia temporal y se comprobó sintaxis. No se migró una base real.

## Comprobación del proveedor y entrega

Consulta de solo lectura en `backend-ruby` mediante la consola de Easypanel:
el fichero de cuenta de servicio existe, tiene el tipo esperado, proyecto y
dominio coherentes con el endpoint FCM y clave presente. Un único intento de
obtener autorización OAuth, sin enviar ninguna notificación, reproduce
`Signet::AuthorizationError` con `account not found`. Solo se mostraron booleanos
y la clase de excepción; no se imprimió ninguna clave ni access token.

El código evita que este rechazo convierta un like guardado en una página de
error, pero **no restaura la cuenta de Google ni las notificaciones**. Eso requiere
revisar la identidad en Google/Firebase antes de modificar claves o permisos.
No se alteraron credenciales, usuarios reales, likes, variables, migraciones,
grupos TestFlight o servicios desplegados durante esta corrección.
