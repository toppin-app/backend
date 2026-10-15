# T36 — Proteger las modificaciones administrativas

Validación: 15 de octubre de 2026.

## Resultado

Se añadieron comprobaciones administrativas antes de cargar registros en los controladores de intereses, categorías, valores de perfil y publicidad para `new/edit/create/update/destroy`, y en versiones para `index/edit/update`. Se conserva el helper administrativo existente: las cuentas normales son rechazadas y redirigidas según su comportamiento anterior; no se cambió globalmente la autenticación.

Se preservan las consultas autenticadas de los catálogos/publicidad, el listado público de intereses utilizado en registro y las dos rutas públicas GET y POST de `/app_version`. Esta última POST es una consulta, no una escritura; bloquear todas las POST habría roto la comprobación inicial de Mobile.

## Evidencia

`CatalogAuthorizationTest` contiene 97 pruebas de integración sin fixtures compartidas: anónimos, usuarios normales y administradores; operaciones rechazadas sin cambios de filas o atributos; CRUD administrativo con PATCH/PUT; formularios y lecturas conservadas. La autenticación, controladores, modelos y plantillas se ejecutan realmente; solo se sustituye la búsqueda del pack JavaScript compilado al renderizar HTML, no los permisos ni el contenido del formulario.

Antes del cambio: **97 tests, 227 assertions, 27 failures y 1 error**. Los fallos reproducen escrituras y accesos administrativos desde una cuenta normal. El error corresponde a `AppVersions#edit`, cuya plantilla ya falta; la nueva autorización intercepta esa solicitud no permitida. La administración de versiones funciona por el formulario existente en `index`, que se prueba. No se inventó otra plantilla.

Después: **97 tests, 283 assertions, 0 failures/errors/skips**, seed 54321.

```sh
bundle exec rails test test/controllers/catalog_authorization_test.rb --seed 54321
```

La ejecución combinada inicial con T37 produjo **137 tests, 481 assertions, 0 failures/errors/skips**. La suite global pasó de **603 tests/297 errores** a **733 tests/290 errores**, sin fallos ni errores nuevos: desaparecen los siete scaffold antiguos de denuncias, sustituidos por integración sin fixtures. No está verde globalmente; [el inventario nominal](t36-t37-existing-suite-errors.txt) conserva todos los errores anteriores.

Tras el seguimiento de redirección HTML y controles positivos de T37: **142 tests, 495 assertions**, seed 12345. Regresión T03/T24 más T36/T37: **448 tests, 1624 assertions**, seed 54321. Ambas ejecuciones terminaron sin fallos, errores ni omisiones. Suite global final: **738 tests, 1624 assertions, 0 failures, los mismos 290 errores previos y 0 skips**; los nombres de todos los errores son un subconjunto exacto del baseline. Revisión independiente sin defectos críticos/importantes restantes. Los comandos de la regresión son los 29 archivos documentados en T03/T24 más las tres suites T36/T37 del comando anterior, con Redis sintético vacío por ejecución.

## Entorno y límites

Red Docker interna y MySQL/Redis desechables, `RAILS_ENV=test`, secretos sintéticos y repositorio montado en solo lectura; ejecución en copia temporal. No hubo tráfico a proveedores ni cambios en datos reales. Para representar las migraciones existentes se complementó el esquema temporal descrito en T03 y se aplicaron el rename `info_item_values.value → name`, la retirada de `interest_categories`, las tablas/campos de `users_publis` y el default actual de denuncias. No se modificó el esquema del repositorio ni se abordó T08.

Los errores globales observados en este entorno son 293 incompatibilidades previas de fixtures con `user_filter_preferences.gender` y cuatro tests de una tabla de categorías ya retirada; en el resultado quedan 286 y cuatro respectivamente. Siguen avisos previos de Rails/Elasticsearch. No se compilaron assets de navegador ni se probó un cliente Mobile o un despliegue. El formulario directo `/app_versions/:id/edit` sigue sin plantilla para administradores, como antes.
