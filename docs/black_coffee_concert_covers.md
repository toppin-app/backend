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
   limites configurados para el crawler. Se revisan JSON-LD, Open Graph, Twitter
   Cards, `src`, lazy loading, `srcset` y datos embebidos.
3. Una imagen binaria confirmada anteriormente para el mismo ID estable de
   artista.
4. Proveedores gratuitos estructurados: MusicBrainz para resolver identidad,
   Wikidata para cruzar identificadores y Wikimedia Commons para obtener un
   archivo con licencia y procedencia registradas.

No se consulta Brave, Google Images ni ningun buscador o API de pago. Tampoco se
hace scraping fragil de resultados de buscadores. Los proveedores implementan
una interfaz comun y pueden ampliarse sin mezclar su logica con el crawler.

Una coincidencia externa no se acepta por nombre solamente. El matcher exige un
ID estable conocido o varias señales estructuradas corroboradas por el contexto
del evento (por ejemplo pais, genero o web oficial); los homonimos y resultados
cercanos quedan ambiguos y no se publican.

## Criterio de portada internalizada

El objetivo final siempre es un archivo binario interno utilizable:

- todos los conciertos del filtro entran en la auditoria; un nombre en la columna
  `venue_images.image` no demuestra que el objeto siga existiendo;
- una imagen binaria interna solo se salta cuando el objeto existe, se puede leer
  y supera la inspeccion tecnica y visual;
- una URL externa entra en el proceso para descargarse y ser reemplazada;
- un concierto sin binario ni URL entra para reintentar la ficha exacta de
  Songkick.

El dashboard separa las referencias registradas en base de datos de los resultados
de la auditoria. Ni una URL ni un nombre de fichero garantizan que la app pueda
mostrar pixeles reales.

## Resultado y seguridad

- Una imagen aceptada se descarga, valida y guarda como binario interno mediante
  `VenueImage`. La URL solo se usa como origen de la descarga y, al persistir el
  archivo correctamente, el atributo `url` se limpia en la misma transaccion.
- Se valida HTTP 200, firma binaria real (aunque el servidor declare
  `binary/octet-stream`), contenido no vacio, limite de 25 MB, dimensiones
  maximas y un maximo de cuatro redirecciones.
- Para portadas de conciertos se decodifica una muestra de pixeles con MiniMagick
  y se rechazan imagenes totalmente o casi transparentes, monocromas o vacias.
  Esta inspeccion visual es exclusiva del flujo de conciertos; no cambia los
  criterios de festivales ni de los internalizadores genericos.
- El exito solo se registra tras recargar `VenueImage`, comprobar que el objeto
  existe en el almacenamiento configurado y volver a inspeccionar el binario
  guardado.
- Cada redireccion se vuelve a validar y se bloquean hosts locales, direcciones
  privadas y redes reservadas para evitar SSRF.
- Se guarda procedencia, URL original, pagina de resultado, confianza y evidencia
  de coincidencia en `venue_images.author_attributions`.
- Una respuesta 429, 5xx, timeout o error DNS conserva su causa reintentable,
  pero si el concierto no tiene otro binario utilizable vuelve a `pending`, queda
  oculto y deja de estar destacado.
- Una coincidencia ausente, ambigua o una portada que no se pudo persistir sigue
  la misma regla `pending` + oculta. No se elimina fisicamente.
- Durante una importacion, un concierto sin portada verificable se crea pendiente
  y oculto; nunca se aprueba ni publica por el mero hecho de haber detectado una
  URL candidata.

## Almacenamiento y configuracion

No se cambia el backend de CarrierWave en esta correccion. `VenueImage` comparte
`BlackCoffeeImageUploader` entre conciertos, festivales y el resto de categorias;
forzar `fog` solo para esta incidencia afectaria tambien sus objetos existentes y
exigiria una migracion/backfill independiente. Se conserva el almacenamiento
`file` que ya fijaba `ImageUploader`, y la postcondicion comprueba que el fichero
existe y se puede leer antes de considerar recuperada una portada.

El contenedor necesita ImageMagick, ya incluido en el `Dockerfile`, para la
inspeccion visual de conciertos. No se anade ninguna gema ni API de imagen de
pago. Las consultas gratuitas aceptan dos opciones de configuracion:

- `CONCERT_COVER_SEARCH_USER_AGENT`: identificacion HTTP del servicio;
- `MUSICBRAINZ_REQUEST_INTERVAL_SECONDS`: intervalo minimo entre peticiones,
  por defecto 1 segundo.

Las credenciales AWS antiguas se retiraron del initializer aunque el backend no
se active; cualquier clave que haya estado en el historial debe revocarse/rotarse.
Una futura migracion a almacenamiento durable debe diseñarse por categoria, usar
variables o credenciales cifradas y copiar/verificar los objetos actuales antes
de cambiar el backend.

## Metricas

Las importaciones y los lotes registran por separado:

- peticiones de ficha a la fuente;
- descargas de imagen;
- portadas recuperadas desde la fuente;
- conciertos creados o devueltos a pendiente por falta de portada;
- errores temporales pendientes de reintento.

## Consideraciones de uso

La procedencia queda guardada para auditoria. El responsable del producto debe
verificar que el uso y almacenamiento de las imagenes sean compatibles con los
terminos de Songkick y con los derechos aplicables a la imagen original.
