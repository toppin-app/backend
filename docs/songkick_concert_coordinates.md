# Coordenadas de conciertos Songkick

Los conciertos se guardan en `venues`, donde `latitude` y `longitude` son
obligatorios a nivel de base de datos. Por eso el importador nunca debe intentar
crear un `Venue` con coordenadas vacias.

## Orden de resolucion

El flujo pertenece exclusivamente al importador de conciertos. No consulta ni
reutiliza registros con categoria `festival`.

1. Conserva las coordenadas y la direccion postal publicadas en el JSON-LD del
   listado. Una direccion completa se usa directamente.
2. Solo si el listado no trae calle y ciudad, abre la ficha exacta
   `/concerts/:id` y extrae la direccion y el ID estable del recinto. Si la
   ficha publica `geo`, esas coordenadas tienen prioridad.
3. Busca un local interno no festival con identidad fuerte: mismo ID de recinto
   Songkick o misma sala, calle y ciudad. Si dos coincidencias fuertes apuntan a
   lugares alejados, no reutiliza ninguna.
4. Solo si lo anterior no basta, hace una busqueda de texto de la direccion en
   Google Places y valida pais ES, ciudad, calle, codigo postal y nombre de sala.
   Dos resultados con puntuacion similar y separados mas de un kilometro se
   consideran ambiguos.

Los resultados verificados se guardan en `Rails.cache` durante 180 dias; los
`not_found` y ambiguos, durante 7 dias. Ademas, los siguientes conciertos de la
misma sala reutilizan las coordenadas ya almacenadas localmente.
Los errores reintentables y el estado `unavailable` no se cachean: al corregir
la configuracion de Google Places, el siguiente intento puede recuperarse de
inmediato.

## Fallos y publicacion

Si falta una direccion precisa, el proveedor no esta disponible o la identidad
es ambigua, se crea un item `pending_coordinates` con el motivo y la direccion
recuperada, pero no se intenta el `INSERT` de `Venue`. Asi se evita el antiguo
`Mysql2::Error: Field 'latitude' doesn't have a default value` y nunca se publica
una ubicacion inventada.

La evidencia guardada en `festival_metadata` incluye el ID de recinto Songkick,
el proveedor, la confianza, las señales coincidentes y, cuando aplica, el Place
ID. La categoria del objeto sigue siendo `concierto`; el nombre historico de la
columna JSON no cambia su semantica.

## Configuracion y coste

No se añade ninguna dependencia ni clave nueva. El ultimo respaldo reutiliza la
configuracion que ya usa Black Coffee:

- `GOOGLE_PLACES_API_KEY`, o
- `GOOGLE_MAPS_API_KEY`.

Cada direccion nueva no resuelta localmente puede consumir una llamada de Text
Search de Google Places. La cache y la reutilizacion por recinto evitan repetir
esa llamada. Si ninguna de las dos variables existe, el item queda pendiente de
coordenadas con un error explicito; no se hace fallback silencioso a un servicio
publico de geocoding ni se asigna el centro de la ciudad.

## Pruebas

Los tests usan clientes inyectados y respuestas locales. Cubren direccion de la
ficha, coordenadas de fuente, reutilizacion local, exclusion de festivales,
ambiguedad geografica, cache y el contrato minimo con Google Places; no hacen
peticiones de red.
