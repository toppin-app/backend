# Desbloqueo de construcción Debian y distribución iOS

Validación: 15 de octubre de 2026.

## Backend

El build original del commit de denuncias falla antes de cargar Rails: APT devuelve404 al descargar paquetes de bullseye-security, terminando con salida100. Se reprodujo el fallo en Docker linux/amd64 con el Dockerfile original y sin credenciales de aplicación.

La corrección conserva Ruby3.0.6, Node20 y los lockfiles. Redirige únicamente los dos hosts conocidos de bullseye-security al archivo oficial de Debian. El mirror principal se conserva: una prueba intermedia que archivaba también main falló al descargar libjpeg, mientras ese paquete seguía disponible en el mirror normal. No se desactivan firmas APT, verificación TLS ni comprobaciones de vigencia. Las dos actualizaciones APT fallan explícitamente si no pueden refrescar índices, para no continuar con índices obsoletos.

Validación real:

- Dockerfile original: RED, paquetes de seguridad404, salida100.
- Dockerfile corregido: instalación completa de dependencias del sistema, Bundle y npm aprobada.
- Construcción completa linux/amd64 con exportación del código confirmado y el Dockerfile corregido: aprobada, imagen `toppin-full-build-validation:20261015`.
- Comprobación posterior sin red: Ruby3.0.6, Node20.20.2, npm10.8.2 y `bundle check` aprobado.
- Contexto temporal sin archivos .env ni claves privadas; sin argumentos de build con credenciales y sin conexiones a proveedores o bases reales.
- Regresión del código que acompaña la entrega:477tests/1778assertions, cero fallos/errores. Global:767tests, cero fallos y los mismos290 errores previos por nombre; no se declara verde.

Esto no convierte Bullseye/Ruby en versiones con soporte actual. La actualización de base/runtime es una tarea separada que necesita validación propia, no un cambio improvisado dentro de este desbloqueo.

## iOS

La cuenta de Toppin aparece en Xcode y tiene acceso al equipo. Solo hay una identidad de desarrollo local utilizable; no se revocó ni exportó ninguna clave. El usuario autorizó crear Apple Distribution, pero finalmente no fue necesario crear otro certificado local: la exportación explícita con firma automática utilizó un certificado **Cloud Managed Apple Distribution** ya disponible, con vencimiento indicado02/06/2027.

`xcodebuild -exportArchive` terminó con **EXPORT SUCCEEDED**, usando destino `export`, equipoKZ84MRK499 y sin incrementar versión/build. Se verificó el IPA extraído con `codesign --verify --deep --strict`: válido en disco y satisface su Designated Requirement. La cadena de firma es Apple Distribution de TOPPIN GLOBAL COMPANY SOCIEDAD LIMITADA, con identificador `app.toppin` y el equipo esperado. Conserva versión54.0/build1; notificaciones de producción y get-task-allow=false.

El archivo se conserva fuera de Git en `entregas/ios-54.0-1/toppin.ipa`, junto a las opciones y el resumen de distribución. SHA256: `b283a05db9a097ad59516d678d9a03791901c30586aeeaa9f9baad0cf915e76a`.

Límite: el asistente gráfico de firma automática de Xcode sigue rechazando el rol devuelto como Agent, aunque Ajustes lo muestra como Admin. La exportación por línea de comandos evita ese bloqueo usando la firma administrada existente. Hubo un aviso no fatal sobre proveedor de App Store Connect durante la exportación. Un IPA firmado no demuestra que App Store Connect haya aceptado su subida; no se afirma carga ni publicación hasta verificar su resultado. No se cambia el rol de la cuenta, Team, bundleID ni credenciales para esquivar el problema.

## Despliegue

La inspección de Easypanel se limitó al servicio `backend-ruby-dev`. Despliegue automático deshabilitado, sin scripts registrados ni comando de arranque personalizado visible. Publicar el commit no prueba que esté desplegado. Antes de arrancar T40 se debe comprobar y ejecutar su migración20261015120000. No ejecutar a ciegas todas las migraciones pendientes ni tocar `backend-ruby`.

Los logs aportados contienen credenciales en argumentos de build; no se copian aquí ni se rotan. Las variables existentes se conservan.
