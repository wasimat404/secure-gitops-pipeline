# syntax=docker/dockerfile:1.7
# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: builder — install deps into a venv we can copy into the runtime.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: runtime — distroless. No shell, no apt, no package manager.
#   - Trivy has dramatically less to flag.
#   - Runs as nonroot (uid 65532) by default.
# ─────────────────────────────────────────────────────────────────────────────
FROM gcr.io/distroless/python3-debian12:nonroot

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app/ /app/

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH=/app \
    APP_VERSION=0.1.0

EXPOSE 8080

# Distroless python image's entrypoint is /usr/bin/python3, so CMD is just args.
CMD ["/opt/venv/bin/gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]

