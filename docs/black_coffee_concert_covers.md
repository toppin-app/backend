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
3. Brave Image Search, solo si el proceso tiene habilitada la busqueda web y el
   servidor tiene `BRAVE_SEARCH_API_KEY`.

Una coincidencia web solo se acepta si:

- al menos el 75% de las palabras significativas del nombre aparecen en el
  resultado;
- aparece la fecha exacta del concierto;
- aparece la sala o la ciudad, cuando se dispone de esos datos;
- las dimensiones declaradas no son inferiores a 240 px por lado.

Se consultan como maximo diez resultados y solo se intenta descargar las tres
mejores coincidencias. La busqueda se ejecuta una sola vez por concierto.

## Resultado y seguridad

- Una imagen aceptada se descarga, valida y guarda como binario interno mediante
  `VenueImage`. No se deja la URL externa como portada operativa.
- Se valida HTTP 200, `Content-Type` de imagen, contenido no vacio, limite de 25 MB
  y un maximo de cuatro redirecciones.
- Cada redireccion se vuelve a validar y se bloquean hosts locales, direcciones
  privadas y redes reservadas para evitar SSRF.
- Se guarda procedencia, URL original, pagina de resultado, confianza y evidencia
  de coincidencia en `venue_images.author_attributions`.
- Una respuesta 429, 5xx, timeout, error DNS o caida de Songkick/Brave es
  reintentable: el concierto existente no cambia de estado.
- Solo cuando todas las vias habilitadas concluyen que no existe una imagen
  verificable, un concierto existente pasa a `rejected` con motivo `bad_photos`,
  deja de ser visible y deja de estar destacado. No se elimina fisicamente.
- Durante una importacion, el concierto se omite antes de crear el `Venue` si no
  se recupera una portada valida.

## Configuracion

La busqueda web requiere esta variable solo en el servidor:

```text
BRAVE_SEARCH_API_KEY=...
```

Sin esa variable se puede ejecutar la recuperacion desde Songkick, pero el
dashboard no permite activar el fallback web. En una importacion, la ausencia de
la clave nunca hace que se cree un concierto sin portada.

## Metricas

Las importaciones y los lotes registran por separado:

- peticiones de ficha a la fuente;
- busquedas de imagen;
- descargas de imagen;
- portadas recuperadas desde la fuente;
- portadas recuperadas desde busqueda;
- conciertos omitidos o rechazados por falta de portada;
- errores temporales pendientes de reintento.

## Consideraciones de uso

Que una imagen aparezca en un buscador no concede automaticamente derechos para
reutilizarla. La procedencia queda guardada para auditoria, pero el responsable
del producto debe verificar que su uso y almacenamiento sean compatibles con la
licencia del sitio de origen y con los terminos de Songkick y Brave. No se debe
activar la busqueda web masiva sin esa validacion.
