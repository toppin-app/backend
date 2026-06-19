# Importador FanMusicFest

El importador de festivales de Black Coffee usa el calendario y las fichas publicas de FanMusicFest. Las peticiones respetan `robots.txt`, un delay minimo de diez segundos y un user-agent identificable.

## Datos importados

- URL original del festival.
- Nombre, fechas, recinto, direccion, ciudad y provincia.
- Coordenadas obtenidas de JSON-LD, atributos del mapa, Open Graph o enlaces de mapa.
- Confianza y fuente de las coordenadas.
- Cartel como URL externa, sin descargar el binario.
- Web oficial y primer enlace de entradas disponible.
- Artistas publicados en JSON-LD.
- Descripcion externa en espanol.

Las coordenadas solo se guardan cuando son numericas y entran en limites geograficos compatibles con Espana. No se hace geocoding externo ni se inventan coordenadas.

## Descripciones

La descripcion de FanMusicFest se guarda en `source_description` con estado `needs_review`. No se devuelve a la app hasta que un administrador la marca como `approved`. Rechazarla no elimina el texto, solo impide su publicacion.

## Reprocesado

La operacion `refresh_details` vuelve a consultar fichas de festivales ya importados. Puede ejecutarse como dry-run o aplicar cambios. Por defecto preserva:

- descripcion editorial de Black Coffee;
- enlaces externos que ya hayan sido editados;
- coordenadas que parezcan manuales;
- decisiones previas de aprobacion o rechazo de una descripcion que no haya cambiado.

El reprocesado trabaja sobre `external_source = fanmusicfest` y `external_source_url`, por lo que no crea venues duplicados.

## Limitaciones

- FanMusicFest no publica generos estructurados en todas las fichas.
- Los precios y enlaces de entradas son externos y pueden cambiar.
- Una ficha sin coordenadas sigue siendo importable, pero queda pendiente de revision.
- No se realiza traduccion automatica de contenido editorial.
