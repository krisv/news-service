# Security Policy

## Security Measures

### Container Security

**Base Image:**
- Python 3.12.3-alpine (minimal attack surface)
- Multi-stage build to exclude build tools from runtime
- Regular security updates via `apk upgrade`

**Runtime:**
- Non-root user (UID 1001)
- Read-only filesystem where possible
- Minimal runtime dependencies (only libpq for PostgreSQL)
- Health checks enabled

### Application Security

**Authentication:**
- API key required for POST/DELETE operations
- Key stored in OpenShift Secret (not in code)
- Environment variable override support

**Input Validation:**
- Required fields validated before processing
- SQL injection prevented via parameterized queries (psycopg2)
- XSS prevention via HTML escaping in frontend

**Database:**
- Connection pooling with limits (max 10 connections)
- Prepared statements for all queries
- Password never logged or exposed

**Network:**
- TLS termination at OpenShift route (edge mode)
- CORS configured (restrict in production)
- WebSocket over TLS

### Data Security

**Sensitive Data:**
- Passwords stored in OpenShift Secrets
- API keys stored in browser localStorage (client-side)
- Database credentials never in version control
- `.gitignore` excludes config.yaml and backups

**Backup Security:**
- Backups stored in persistent volume with access controls
- Restore requires manual confirmation
- Backup files use gzip compression

## Known Limitations

1. **Comments Don't Require Authentication**
   - By design for public discussion
   - Consider adding rate limiting if abused

2. **Client-Side Username Storage**
   - Stored in localStorage, not validated server-side
   - Users can change display name freely

3. **No Rate Limiting**
   - API endpoints not rate-limited
   - Consider adding in production

4. **API Key in Browser**
   - Stored in localStorage (clear on shared computers)
   - Consider more secure authentication (OAuth, JWT)

## Vulnerability Scanning

Container images are automatically scanned by Quay.io:

**Latest Scan Results:**
https://quay.io/repository/krisv/news-service?tab=vulnerabilities

**Typical Vulnerabilities:**
- Base OS packages (Alpine apk packages)
- Python standard library (follows Python security releases)
- Third-party Python packages (updated in requirements.txt)

## Security Updates

### Updating Python Dependencies

1. Check for security advisories:
   ```bash
   pip list --outdated
   pip-audit  # if installed
   ```

2. Update requirements.txt with patched versions

3. Rebuild and redeploy:
   ```bash
   build-and-push.bat  # or .sh
   ```

### Updating Base Image

1. Update Dockerfile FROM line to latest Python 3.12.x-alpine

2. Rebuild image (includes latest Alpine security updates)

### Monitoring Vulnerabilities

**Automated Scanning:**
- Quay.io scans on every push
- Check vulnerability tab in Quay repository

**Manual Checks:**
```bash
# Scan with Docker Scout (if available)
docker scout cves quay.io/krisv/news-service:latest

# Or use Trivy
trivy image quay.io/krisv/news-service:latest
```

## Reporting Security Issues

### For Production Use

If you discover a security vulnerability:

1. **DO NOT** open a public GitHub issue
2. Contact the maintainer privately
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

### For This Demo Project

This is a demonstration project. Security issues can be:
- Reported via GitHub issues
- Fixed via pull requests
- Discussed in public

## Security Best Practices for Deployment

### OpenShift/Kubernetes

1. **Use Secrets for Credentials:**
   ```bash
   oc create secret generic postgres-credentials \
     --from-literal=POSTGRES_USER=krisv \
     --from-literal=POSTGRES_PASSWORD=secure-password \
     --from-literal=API_KEY=secure-api-key
   ```

2. **Enable Network Policies:**
   - Restrict pod-to-pod communication
   - Only allow necessary traffic

3. **Configure Resource Limits:**
   - Prevent resource exhaustion
   - Already configured in deployment.yaml

4. **Enable Pod Security Standards:**
   - Enforce non-root containers
   - Drop unnecessary capabilities

5. **Use TLS for Routes:**
   - Already configured (edge termination)
   - Consider re-encrypt or passthrough for end-to-end encryption

### Database Security

1. **Strong Passwords:**
   - Use generated passwords (not 'krisv')
   - Rotate regularly

2. **Limit Permissions:**
   - PostgreSQL user only needs specific database access
   - No superuser privileges required

3. **Regular Backups:**
   - Automated daily backups configured
   - Test restore procedure regularly

4. **Network Isolation:**
   - Database pod only accessible from app pods
   - No external exposure

### API Key Security

1. **Generation:**
   ```bash
   # Generate secure random key
   openssl rand -base64 32
   ```

2. **Distribution:**
   - Share via secure channel (not email/Slack)
   - Different keys per environment

3. **Rotation:**
   - Rotate keys periodically
   - Update Secret and restart pods

4. **Revocation:**
   - Change key in Secret
   - Restart app pods
   - Inform users of new key

## Compliance Notes

This demonstration project is **NOT** designed for:
- GDPR compliance (no PII handling)
- HIPAA compliance (no health data)
- PCI-DSS compliance (no payment data)
- SOC 2 compliance (no audit trail)

For production use requiring compliance:
- Add audit logging
- Implement data retention policies
- Add user consent mechanisms
- Enable comprehensive monitoring

## Security Checklist for Production

Before deploying to production:

- [ ] Change default passwords (krisv:krisv)
- [ ] Generate strong API key (32+ random characters)
- [ ] Configure CORS for specific origins only
- [ ] Enable rate limiting on API endpoints
- [ ] Set up monitoring and alerting
- [ ] Configure network policies
- [ ] Enable pod security policies
- [ ] Review and minimize container capabilities
- [ ] Set up automated security scanning
- [ ] Implement proper authentication (OAuth/JWT)
- [ ] Add audit logging
- [ ] Configure backup retention policy
- [ ] Test disaster recovery procedures
- [ ] Document incident response plan

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [Python Security Best Practices](https://python.readthedocs.io/en/stable/library/security_warnings.html)
- [OpenShift Security Guide](https://docs.openshift.com/container-platform/latest/security/index.html)

## Updates

- **2026-04-16**: Updated vulnerable packages (second pass):
  - pip: 25.3 → 26.0
  - Flask: 3.1.0 → 3.0.3 (downgraded due to breaking changes in 3.1.x with Flask-SocketIO)
  - Flask-SocketIO: 5.4.1 → 5.5.1
  - packaging: added 24.2 (required by eventlet worker)
  - Added `apk upgrade` in both build and runtime stages for Alpine packages
  - Using `python:3.12-alpine` (latest patch) instead of pinned version
  - **Note**: Flask 3.1.x has Low severity CVEs but introduced breaking session changes incompatible with Flask-SocketIO
- **2026-04-16**: Updated all vulnerable packages (first pass):
  - pip: 24.0 → 25.3
  - setuptools: 70.0.0 → 78.1.1
  - wheel: 0.43.0 → 0.46.2
  - python-socketio: 5.12.0 → 5.14.0
  - eventlet: 0.37.0 → 0.40.3
  - flask-cors: 5.0.0 → 6.0.0
  - requests: 2.32.3 → 2.33.0
- **2026-04-16**: Switched to Alpine-based multi-stage build for reduced attack surface
- **2026-04-16**: Updated to Python 3.12.3 with latest security patches
- **2026-04-16**: Added health checks to Dockerfile

## Known Limitations (Base Image CVEs)

Many "Unknown" severity CVEs are in Alpine Linux base packages (libcrypto3, libssl3, busybox, libexpat, musl, zlib) that come from the `python:3.12-alpine` Docker image. These are maintained by the Python Docker team and Alpine Linux, not this project.

**Mitigation:**
- Using `python:3.12-alpine` (latest) to get newest patches automatically
- Running `apk upgrade` on build to update all packages
- Monitoring Python Docker releases for updated base images

**Cannot fix without:**
- Switching to a different base image (e.g., Debian)
- Waiting for upstream Python/Alpine updates
