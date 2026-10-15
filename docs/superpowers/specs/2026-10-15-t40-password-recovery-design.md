# T40 — Recuperación de contraseña con prueba privada

Estado: propuesta para revisión. No implementada ni desplegada.

## Objetivo y límites

Cerrar el cambio de contraseña por email sin prueba privada, conservando el flujo de recuperación y las versiones Mobile ya instaladas. No rotar credenciales, exigir variables nuevas, modificar el login social ni cambiar el producto visualmente.

El controlador actual acepta email y contraseña nueva si cualquier cliente ha verificado previamente una recuperación. El cliente Mobile actual ya envía el código de seis cifras al finalizar, pero Rails lo ignora. Una recuperación verificada no es una autorización pública para cambiar la contraseña.

## Alternativas

1. Exigir únicamente el código ya enviado: compatible, pero una prueba de seis cifras necesita un límite estricto de intentos también en el último paso.
2. Exigir exclusivamente un token nuevo: mayor entropía, pero rompe la recuperación en las aplicaciones instaladas que no lo envían.
3. **Recomendación: token privado nuevo y compatibilidad acotada con el código existente.** La aplicación nueva usa el token; la antigua debe demostrar que conoce el código correcto, con un presupuesto independiente de intentos y sin aceptar nunca solo un email.

## Contrato y persistencia

- Al verificar correctamente el código, emitir un token criptográficamente aleatorio. Guardar solo su digest en la recuperación y devolver el token únicamente en esa respuesta.
- Mobile pasa el token en memoria entre las dos pantallas y lo envía al finalizar; no lo persiste ni lo registra en logs.
- El token pertenece a esa recuperación/email y vence, como máximo, al vencer el código original. No extender automáticamente los diez minutos existentes.
- Añadir campos de digest y contador de intentos de reset mediante una migración aditiva. No reutilizar el contador de verificación: un código válido en el quinto intento debe seguir permitiendo finalizar.
- Sin token, aceptar el código correcto de una recuperación verificada vigente para compatibilidad. Limitar a cinco intentos fallidos de prueba en el reset, serializados en base de datos. Si se envía un token inválido, rechazarlo; no degradar silenciosamente a otro mecanismo.
- Ausencia de prueba, prueba errónea, email ajeno, caducidad o prueba consumida no modifican la contraseña. La ausencia de prueba no permite agotar por sí sola el contador de códigos.
- Una nueva recuperación invalida las anteriores para ese email. Un cambio correcto consume todas las pruebas de recuperación pendientes de esa cuenta, no solo una fila, para evitar reutilizar otra autorización antigua.

## Atomicidad y errores

Comprobar prueba, vigencia y estado actual dentro de una transacción con bloqueos de filas en orden consistente por cuenta. El guardado de contraseña y la invalidación de pruebas se confirman juntos. Si falla la validación o la escritura, no consumir la autorización válida; si falla el consumo, tampoco cambiar la contraseña. Dos resets concurrentes con la misma prueba permiten un solo cambio.

Generar los códigos con una fuente criptográfica y serializar la verificación y sus intentos. Conservar los mensajes traducidos y el cooldown. No ocultar errores inesperados ni enviar emails/SMS reales durante los tests.

Filtrar códigos, tokens y contraseñas en Rails. Retirar los objetos Axios completos de los logs de estas pantallas y del servicio, porque pueden contener el cuerpo de la petición.

## Verificación exigida

- Convertir las caracterizaciones T40 en rechazos reales antes de tocar producción.
- Integración HTTP: prueba omitida, token/código incorrecto, email distinto, no verificado, vencimiento exacto, replay, nueva recuperación, contraseña débil y cuenta eliminada.
- Compatibilidad: petición exacta de Mobile anterior con código y petición nueva con token; quinto intento de verificación correcto y presupuesto separado en reset.
- Dos conexiones MySQL: token simultáneo, código simultáneo, intentos concurrentes y rollback ante fallo del consumo.
- Mobile: token transmitido entre pantallas, fallback compatible, error recuperable y ausencia de secretos en los logs; no probar solamente los mocks.
- Regresión de autenticación, registro y recuperación; suite global con fallos previos identificados por nombre.
- Migración hacia delante/atrás sobre una base desechable. No operar sobre datos reales ni afirmar despliegue por publicar un commit.

## Entrega

Rails: commit validado y push conforme a las instrucciones del repositorio. Mobile: commit local, sin push en esta tarea salvo autorización expresa. Coordinar despliegue de la migración antes del código que la utiliza. Mantener la compatibilidad descrita hasta retirar clientes antiguos mediante otra decisión explícita.
