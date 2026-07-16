# Portadas de conciertos de Black Coffee

## Objetivo

Ningun concierto nuevo debe publicarse sin una portada binaria valida. El mismo
flujo se usa durante la importacion de Songkick y en la herramienta de reparacion
del dashboard para conciertos existentes.

La herramienta se abre desde:

1. Black Coffee.
2. Importar Songkick.
3. Recuperar portadas.

El proceso se ejecuta como jobs encadenados en el servidor, se puede monitorizar
sin mantener el navegador abierto y se puede cancelar. Cancelarlo conserva lo que
ya se haya procesado.

## Orden de recuperacion

Para cada concierto se prueban, en este orden:

1. La URL de imagen que ya vino en los metadatos de la importacion.
2. La ficha exacta del evento en Songkick, respetando `robots.txt`, el delay y los
   limites configurados para el crawler.

No se consulta Brave, Google Images ni ningun buscador o API de pago. Tampoco se
hace scraping fragil de resultados de buscadores. La herramienta depende solo de
la fuente original que ya usa el importador.

## Criterio de portada internalizada

El objetivo final siempre es un archivo binario interno:

- una imagen binaria interna queda fuera del proceso;
- una URL externa entra en el proceso para descargarse y ser reemplazada;
- un concierto sin binario ni URL entra para reintentar la ficha exacta de
  Songkick.

El dashboard desglosa estas tres cantidades para explicar el total. Que una URL
se vea actualmente en la app no significa que ya este internalizada.

## Resultado y seguridad

- Una imagen aceptada se descarga, valida y guarda como binario interno mediante
  `VenueImage`. La URL solo se usa como origen de la descarga y, al persistir el
  archivo correctamente, el atributo `url` se limpia en la misma transaccion.
- Se valida HTTP 200, `Content-Type` de imagen, contenido no vacio, limite de 25 MB
  y un maximo de cuatro redirecciones.
- Cada redireccion se vuelve a validar y se bloquean hosts locales, direcciones
  privadas y redes reservadas para evitar SSRF.
- Se guarda procedencia, URL original, pagina de resultado, confianza y evidencia
  de coincidencia en `venue_images.author_attributions`.
- Una respuesta 429, 5xx, timeout, error DNS o caida de Songkick es
  reintentable: el concierto existente no cambia de estado.
- Solo cuando todas las vias habilitadas concluyen que no existe una imagen
  verificable, un concierto existente pasa a `rejected` con motivo `bad_photos`,
  deja de ser visible y deja de estar destacado. No se elimina fisicamente.
- Durante una importacion, el concierto se omite antes de crear el `Venue` si no
  se recupera una portada valida.

## Metricas

Las importaciones y los lotes registran por separado:

- peticiones de ficha a la fuente;
- descargas de imagen;
- portadas recuperadas desde la fuente;
- conciertos omitidos o rechazados por falta de portada;
- errores temporales pendientes de reintento.

## Consideraciones de uso

La procedencia queda guardada para auditoria. El responsable del producto debe
verificar que el uso y almacenamiento de las imagenes sean compatibles con los
terminos de Songkick y con los derechos aplicables a la imagen original.
