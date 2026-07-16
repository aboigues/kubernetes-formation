# Dockerfile pour TaskFlow Backend API
# Image de base : Python 3.12 Alpine
#
# Pourquoi Alpine plutôt que slim (Debian) : 0 CVE OS HIGH/CRITICAL contre 22.
# Pourquoi 3.12 et pas 3.13 : psycopg2-binary 2.9.9 (requirements.txt) publie des
# wheels musllinux jusqu'à cp312 seulement. En 3.13, pip compilerait depuis les
# sources et le build échouerait. Monter en 3.13 impose psycopg2-binary >= 2.9.10.
FROM python:3.12-alpine

# Métadonnées
LABEL maintainer="TaskFlow Team"
LABEL description="Backend API pour l'application TaskFlow (Flask + PostgreSQL + Redis)"
LABEL version="1.0"

# Créer un utilisateur non-root
# Alpine fournit addgroup/adduser (busybox) et non groupadd/useradd (Debian)
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser -h /home/appuser appuser && \
    mkdir -p /app /home/appuser && \
    chown -R appuser:appuser /app /home/appuser

# Définir le répertoire de travail
WORKDIR /app

# Copier les dépendances Python
COPY requirements.txt .

# Installer les dépendances
# - psycopg2-binary : Driver PostgreSQL
# - redis : Client Redis
# - flask : Framework web
# - gunicorn : Serveur WSGI pour production
RUN pip install --no-cache-dir -r requirements.txt && \
    rm -rf /root/.cache

# Copier le code de l'application
COPY app.py .

# Changer le propriétaire du code
RUN chown -R appuser:appuser /app

# Basculer vers l'utilisateur non-root
USER appuser

# Variables d'environnement par défaut
ENV PYTHONUNBUFFERED=1 \
    HOME=/home/appuser

# Exposer le port 5000
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Lancer l'application avec gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "--log-level", "info", "app:app"]
