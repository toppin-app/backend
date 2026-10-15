# T27 — Likes sin descuentos repetidos

Estado: propuesta para revisión. No implementada ni desplegada. El plan del 29 de septiembre permanece intacto como documento anterior; este diseño acota únicamente T27, no T17/T28/T29/T30.

## Objetivo

Una misma operación repetida o concurrente no vuelve a descontar saldo ni repetir decisiones o programación de sus efectos. Conservar cambios de opinión legítimos, el resultado de SugarPlay y las dos fases actuales de SugarSweet. No migrar ni borrar interacciones históricas.

La prueba existente reproduce dos solicitudes iguales, una fila y dos créditos gastados. La fila de interacción no conserva el mensaje SugarSweet ni la respuesta SugarPlay original. Por ello, comparar solo el usuario o los flags de esa fila no basta: puede bloquear el mensaje legítimo de la segunda fase y no identifica un reintento antiguo después de otra decisión.

## Alternativas

1. Guarda visual y comparación de la decisión actual: menor cambio, pero no protege reintentos antiguos ni todos los mensajes. No basta para prometer idempotencia de una operación.
2. **Recomendación: identificador de operación y recibo mínimo persistente**, junto con transacción y guardas Mobile. Es un cambio interno aditivo del contrato existente y permite distinguir un reintento de una acción diferente.

## Rails

- Aceptar un UUID opcional por operación en el endpoint actual. Vincularlo al usuario autenticado; nunca confiar en un actor enviado por el cliente.
- Añadir una tabla de recibos con índice único por actor/UUID, destinatario, huella tipada de la petición y resultado mínimo. La huella incluye las decisiones y el mensaje, sin almacenar el mensaje en texto en el recibo. Distinguir tipos que el controlador actual trata de forma diferente; no corregir aquí la semántica de booleanos de T28.
- No almacenar una copia del Jbuilder ni de los perfiles: solo tipo de resultado, ID de interacción y directivas SugarPlay/next_in originales. No registrar UUIDs junto a mensajes o credenciales.
- Bloquear las filas de ambos usuarios en orden estable y volver a leer interacción y saldo dentro de la transacción. Esto serializa también los swipes recíprocos sin introducir un índice único sobre parejas históricas.
- Consultar recibos antes de validar saldo: el reintento de una operación que gastó el último crédito debe seguir reconociéndose como ya aplicada.
- Mismo actor/UUID y huella: no ejecutar otra decisión, descuento, avance de contador ni programación de jobs. Reutilizar un UUID con otro destinatario o contenido se rechaza sin efectos.
- Confirmar recibo, decisión y descuento juntos; preparar la respuesta en memoria antes del commit para que un fallo de serialización también revierta todo. Errores de persistencia no dejan un recibo de éxito ni un descuento parcial. Sacar de la sección con bloqueo las llamadas externas; programar efectos solo después de confirmar.
- Al repetir un resultado de match, renderizar datos actuales únicamente si la interacción sigue existiendo y el actor sigue siendo participante. No revivir un match eliminado/rechazado ni devolver perfiles que ahora estén bloqueados. En esos casos devolver un éxito sin nueva acción, explícitamente marcado como ya aplicado. SugarPlay conserva su directiva si sigue siendo visible; no sortea otra ni avanza el contador.

## Compatibilidad anterior

Conservar las solicitudes sin UUID y las respuestas existentes para acciones nuevas. Guardar también su huella y resultado mínimo a partir del despliegue. Una repetición inmediata de la última petición idéntica al mismo destinatario se reconoce sin volver a aplicar efectos; una petición diferente mantiene su comportamiento.

No inventar un backfill desde filas que no contienen el mensaje ni la decisión completa de cada participante. Sin UUID no se puede identificar con certeza un reintento anterior al despliegue, o un reintento antiguo que llega después de otra decisión. Tampoco se puede distinguir una repetición intencional idéntica de un duplicado inmediato en esos clientes. Estas limitaciones deben quedar explícitas en la entrega; no prometer exactamente una vez universal.

## Mobile

- Instrumentar el helper compartido de `send_match` para cubrir Home, historial, perfil, boosts y PowerSweet sin duplicar reglas por pantalla. Usar UUID y generador aleatorio ya instalados, sin dependencias nuevas.
- Dos envíos pendientes de la misma intención comparten la operación. Retener su UUID ante una respuesta ambigua de red/servidor para que el reintento no vuelva a gastar. Un cambio de intención crea otro UUID.
- Encolar acciones distintas al mismo destinatario mientras termina la anterior. SugarSweet utiliza dos UUID: el SuperSweet inicial y el mensaje posterior; la segunda acción no debe perderse por una guarda basada solo en destinatario.
- Home e historial añaden guardas síncronas para evitar también navegación, Analytics o actualización visual duplicadas. Esperar la promesa real y liberar el estado pendiente en `finally`.
- Vincular las operaciones a la cuenta y limpiar el estado al salir/cambiar de cuenta. Esta primera entrega garantiza reintentos durante la sesión en memoria; no promete conservar operaciones ambiguas tras cerrar el proceso. Persistirlas requeriría una política y pruebas adicionales.

## Verificación exigida

- Convertir las tres caracterizaciones conocidas de doble envío/descuento en expectativas correctas antes de modificar producción.
- HTTP: like, dislike, SuperSweet y SugarSweet repetidos; último crédito; UUID reutilizado con otro contenido; cambio de opinión; saldo insuficiente sin mutaciones.
- MySQL con conexiones distintas: dos envíos simultáneos iguales, últimos créditos contra destinatarios distintos, swipes recíprocos y rollback ante fallo de guardado.
- Ningún doble enqueue por el mismo recibo; no confundir esto con idempotencia del propio worker, que sigue siendo T30. Una caída después del commit y antes del enqueue es un límite conocido hasta incorporar entrega durable/outbox.
- Replay antiguo después de otra decisión, interacción eliminada, usuario bloqueado y SugarPlay ya no visible no provocan mutaciones ni exposición histórica de perfiles.
- Mobile: llamadas en el mismo ciclo de render, éxito/error/reintento ambiguo, identidad de cuenta, dos fases SugarSweet con primera promesa pendiente y demás consumidores del helper.
- Migración hacia delante/atrás en base desechable y regresión completa Mobile/Rails, nombrando errores previos sin ocultarlos.

## Entrega y exclusiones

No corregir en esta tarea el modelo direccional de consentimiento (T28), la política global de bloqueos (T29), los jobs reintentados (T30), la autorización de matches ajenos (T31) ni el resto de consumos (T25). No borrar recibos automáticamente: quitarlos permitiría que se volviera a aplicar un UUID antiguo; una política de retención necesita preservar la deduplicación.

Rails: migración antes del código, commit validado y push. Mobile: commit local sin push salvo autorización expresa. No ejecutar migraciones sobre datos reales ni declarar despliegue por publicar código.
