# Configuración de Elasticsearch y Kibana - Toppin Backend

## Descripción
Esta configuración permite que tu aplicación Rails envíe logs directamente a Elasticsearch, donde pueden ser visualizados y analizados usando Kibana.

## Contenedores en EasyPanel

### Elasticsearch (elasticsearch-logs)
- **URL interna**: `http://web_elasticsearch-logs:9200/`
- **Variables de entorno**:
  ```
  ELASTIC_PASSWORD=elasticsearch-logs
  discovery.type=single-node
  xpack.security.enabled=true
  ```

### Kibana (kibana-logs)
- **URL interna**: `http://web_kibana-logs:5601/`
- **Variables de entorno**:
  ```
  ELASTICSEARCH_HOSTS=http://web_elasticsearch-logs:9200/
  SERVER_HOST=0.0.0.0
  ```

## Configuración en tu aplicación Rails

### Variables de entorno necesarias
Añade estas variables a tu contenedor de Rails en EasyPanel:

```bash
ELASTICSEARCH_HOST=web_elasticsearch-logs
ELASTICSEARCH_PORT=9200
ELASTICSEARCH_SCHEME=http
ELASTICSEARCH_USER=elastic
ELASTICSEARCH_PASSWORD=elasticsearch-logs
ENABLE_ELASTICSEARCH_LOGGING=true
```

### Instalación de dependencias
Después de configurar las variables, ejecuta:

```bash
bundle install
```

## Características implementadas

### 1. Logger personalizado
- Envía logs automáticamente a Elasticsearch
- Crea índices diarios: `toppin-backend-logs-YYYY.MM.DD`
- Incluye metadata como timestamp, nivel, environment, hostname, etc.

### 2. Logging estructurado
- Usa Lograge para logs JSON estructurados
- Captura información de requests HTTP
- Incluye user_id, IP, user-agent, etc.

### 3. Manejo de errores
- Fallback a STDOUT si Elasticsearch no está disponible
- No bloquea la aplicación si hay problemas de conectividad

## Visualización en Kibana

### Acceso a Kibana
1. Ve a la URL de tu Kibana en EasyPanel
2. Crea un Index Pattern: `toppin-backend-logs-*`
3. Usa `timestamp` como campo de tiempo

### Dashboards sugeridos
- **Logs por nivel**: Gráfico de barras por ERROR, WARN, INFO
- **Requests por endpoint**: Top endpoints más utilizados
- **Errores por usuario**: Identificar usuarios con más errores
- **Performance**: Tiempo de respuesta de requests

## Monitoreo y alertas

### Logs importantes a monitorear
- **ERROR**: Errores de aplicación
- **WARN**: Advertencias que pueden indicar problemas
- **Performance**: Requests lentos (>1000ms)

### Queries útiles en Kibana
```
# Errores en las últimas 24h
level:"ERROR" AND @timestamp:[now-24h TO now]

# Requests lentos
duration:>1000

# Errores de un usuario específico
user_id:123 AND level:"ERROR"
```

## Troubleshooting

### Si no llegan logs a Elasticsearch
1. Verifica que `ENABLE_ELASTICSEARCH_LOGGING=true`
2. Revisa la conectividad entre contenedores
3. Confirma las credenciales de Elasticsearch
4. Verifica los logs de la aplicación Rails

### Conexión fallida
- Los logs seguirán apareciendo en STDOUT como fallback
- Revisa la configuración de red entre contenedores
- Verifica que Elasticsearch esté funcionando correctamente

## Índices y retention
Los logs se almacenan en índices diarios. Para gestionar el espacio:
- Configura Index Lifecycle Management (ILM) en Elasticsearch
- Establece políticas de retention (ej: 30 días)
- Monitorea el uso de espacio en disco