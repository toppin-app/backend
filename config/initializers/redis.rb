$redis = Redis.new(url: ENV.fetch('REDIS_URL')) # por ejemplo: redis://localhost:6379
# Puedes ajustar la URL según tu configuración de Redis