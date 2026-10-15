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

### Subida autorizada y confirmada

Tras la autorización expresa del usuario, `xcodebuild -exportArchive` con destino `upload` confirmó `Uploaded toppin release` y `EXPORT SUCCEEDED`. El registro de distribución del archive confirma `Uploaded to Apple`, estado `success`, sin errores, aplicación1613498095, equipoKZ84MRK499 y build1, el15/10/2026 a las13:01:56UTC (15:01:56 en Madrid). Se conserva versión54.0(1), sin segunda subida ni incremento de versión.

Los avisos por dSYM ausentes de Agora y Hermes no impidieron la entrega; siguen como limitación de diagnóstico de fallos nativos. No se fabricaron símbolos ni se ocultaron los avisos. No se envió la aplicación a revisión ni se publicó en App Store.

La comprobación posterior de TestFlight en el navegador quedó en el acceso de App Store Connect sin terminar de cargar, incluso tras una recarga. Por tanto, se confirma la aceptación de la subida, pero no la finalización del procesamiento ni la disponibilidad para testers. El problema de cuenta/rol del asistente gráfico no se considera resuelto; la vía CLI con firma administrada sí permitió entregar el build.

## Despliegue

El usuario autorizó después desplegar lo último en `backend-ruby` y `backend-ruby-dev`. La inspección de desarrollo muestra despliegue automático deshabilitado, sin scripts registrados ni comando de arranque personalizado visible. La fuente de producción apunta a `toppin-app/backend`, rama `main`; no se modificó.

El preflight de solo lectura en la consola de desarrollo devolvió `Rails.env=development`, `password_recoveries=false` y migración20261015120000 sin aplicar. Falta incluso la tabla de la migración20251127000000, anterior a T40. La migración original solo crea esa tabla e índices, pero falta inventariar las demás pendientes y comprobar producción antes de decidir la aplicación segura. No se ejecutó ninguna migración ni se desplegó/reinició ninguno de los dos servicios. No ejecutar a ciegas todas las migraciones pendientes. Publicar el commit no prueba que esté desplegado.

Los logs aportados contienen credenciales en argumentos de build; no se copian aquí ni se rotan. Las variables existentes se conservan.
