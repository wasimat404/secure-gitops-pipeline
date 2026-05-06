# syntax=docker/dockerfile:1.7
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    APP_VERSION=0.1.0

# Create non-root user and app dir
RUN groupadd -r app && useradd -r -g app -u 65532 app \
 && mkdir -p /app && chown app:app /app

WORKDIR /app

# Install deps as root, then drop privileges
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=app:app app/ /app/

USER app

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
