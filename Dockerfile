# News Service Dockerfile - Red Hat UBI 10 Minimal for enterprise security
FROM registry.access.redhat.com/ubi10/python-312-minimal:latest

# Switch to root for installing dependencies
USER 0

# Update all packages to latest security patches (microdnf for minimal)
RUN microdnf update -y && microdnf clean all

# Install build and runtime dependencies
RUN microdnf install -y \
    gcc \
    postgresql-devel \
    postgresql-libs \
    python3-devel \
    wget \
    && microdnf clean all

# Upgrade pip, setuptools, wheel
RUN pip install --no-cache-dir --upgrade pip==26.0 setuptools==78.1.1 wheel==0.46.2

# Copy requirements and install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Remove build dependencies to reduce image size
RUN microdnf remove -y \
    gcc \
    postgresql-devel \
    python3-devel \
    && microdnf clean all

# Set working directory
WORKDIR /app

# Copy application files
COPY app.py .
COPY storage.py .
COPY config.yaml .
COPY templates/ templates/
COPY static/ static/

# Change ownership to default user (1001) with group ownership for OpenShift
RUN chown -R 1001:0 /app && \
    chmod -R g=u /app

# Switch to non-root user (UBI default)
USER 1001

# Expose port 8080 (OpenShift compatible)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run with gunicorn using eventlet worker for SocketIO support
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--worker-class", "eventlet", "-w", "1", "app:app"]
