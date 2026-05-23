"""
Django production settings for Camino Biblico project.
Configured for Render.com deployment.
"""
import os
import dj_database_url
from .base import *  # noqa: F401,F403

DEBUG = False

# 1. Corregido: Sin espacios y con tu nuevo dominio .com
ALLOWED_HOSTS = os.environ.get(
    'ALLOWED_HOSTS',
    'camino-biblico.com,camino-biblico-app.onrender.com,biblialingo-app.onrender.com'
).split(',')

# Database - PostgreSQL via DATABASE_URL
DATABASES = {
    'default': dj_database_url.config(
        default=os.environ.get('DATABASE_URL'),
        conn_max_age=600,
        conn_health_checks=True,
    )
}

# 2. Corregido: Sin espacios. Esto evita errores de CORS en el Flutter app
CORS_ALLOWED_ORIGINS = os.environ.get(
    'CORS_ALLOWED_ORIGINS',
    'https://camino-biblico.com,https://camino-biblico-app.onrender.com,https://biblialingo-app.onrender.com'
).split(',')

# 3. NUEVO: Necesario para poder iniciar sesión en /admin sin errores 403
CSRF_TRUSTED_ORIGINS = os.environ.get(
    'CSRF_TRUSTED_ORIGINS',
    'https://camino-biblico.com,https://camino-biblico-app.onrender.com,https://biblialingo-app.onrender.com'
).split(',')

# Security settings
SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True

# WhiteNoise for static files
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'