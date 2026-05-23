/// Configuración de API para camino_biblico
/// Cambia los valores según el entorno (dev, staging, prod)

class ApiConfig {
  /// URL base de la API
  /// Producción: https://camino-biblico-app.onrender.com/api/v1
  /// Staging: https://camino_biblico-staging.onrender.com/api/v1
  /// Desarrollo Local: http://192.168.1.8:8000/api/v1
  static const String baseUrl = 'https://biblialingo-app.onrender.com/api/v1';

  /// Timeout en segundos para requests HTTP
  static const int requestTimeoutSeconds = 30;

  /// Timeout en segundos para GET requests
  static const int getRequestTimeoutSeconds = 15;

  /// Cambiar a true para ver logs detallados de API
  static const bool enableDebugLogs = false;

  /// Método para cambiar baseUrl en runtime (útil para testing)
  static String get apiBaseUrl => baseUrl;
}

// Nota: Para cambiar el baseUrl sin recompilar:
// 1. En development: Edita [baseUrl] aquí y reconstruye
// 2. En production: Usa environment-specific configurations
//    (build flavors en Android/iOS)
// 3. Para .env dinámico: Agrega flutter_dotenv a pubspec.yaml
//    y carga con: DotEnv().load('.env')


