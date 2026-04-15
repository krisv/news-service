# News Service Dockerfile - Multi-stage build for security
# Build stage - use latest Python 3.12 patch
FROM python:3.12-alpine AS builder

# Update all Alpine packages to latest security patches
RUN apk update && apk upgrade --no-cache

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    musl-dev \
    postgresql-dev \
    linux-headers

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip==26.0 setuptools==78.1.1 wheel==0.46.2 && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime stage - use latest Python 3.12 patch
FROM python:3.12-alpine

# Update all Alpine packages to latest security patches
RUN apk update && apk upgrade --no-cache

# Install only runtime dependencies
RUN apk add --no-cache \
    libpq \
    wget \
    && adduser -D -u 1001 appuser

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Upgrade pip, setuptools, wheel in runtime stage as well
RUN pip install --no-cache-dir --upgrade pip==26.0 setuptools==78.1.1 wheel==0.46.2

# Set working directory
WORKDIR /app

# Copy application files
COPY app.py .
COPY storage.py .
COPY config.yaml .
COPY templates/ templates/
COPY static/ static/

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose port 8080 (OpenShift compatible)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run with gunicorn using eventlet worker for SocketIO support
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--worker-class", "eventlet", "-w", "1", "app:app"]
