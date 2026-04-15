# News Service - Technical Documentation

## Overview
The News Service is a real-time news posting and discussion platform built with Flask and WebSockets. It features PostgreSQL storage with automatic fallback, categorized labels, API key authentication, and real-time updates across all connected clients.

## Live Deployment
- **Production URL**: https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com
- **Container Image**: quay.io/krisv/news-service:latest
- **OpenShift Project**: kverlaen-dev
- **Database**: PostgreSQL 16 with persistent storage
- **Backups**: Daily automated backups at 2 AM (7-day retention)

## Architecture

### Backend Stack
- **Framework**: Flask 3.1.0 (Python web framework)
- **Real-time Communication**: Flask-SocketIO 5.4.1 (WebSocket support)
- **CORS**: Flask-CORS 5.0.0 (Cross-Origin Resource Sharing)
- **Server**: Gunicorn 23.0.0 with eventlet 0.37.0 worker (production async server)
- **Database**: PostgreSQL 16 (primary) with in-memory fallback
- **Database Driver**: psycopg2-binary 2.9.11 with connection pooling
- **Storage Abstraction**: Abstract base class with multiple implementations
- **Configuration**: PyYAML 6.0.2 for config files, environment variable overrides
- **Python Version**: 3.12.3

### Data Storage

**Primary: PostgreSQL**
- Host: postgres service (OpenShift)
- Database: news
- Tables: news_items, comments
- Connection pooling: ThreadedConnectionPool (1-10 connections)
- Features: ACID compliance, persistent storage, concurrent access
- Persistent volume: 5Gi

**Fallback: In-Memory**
- Python dictionaries with thread-safe locking
- Activated automatically if PostgreSQL unavailable
- Useful for local development
- Data lost on restart

**Storage Abstraction**:
```python
class StorageBackend(ABC):
    def create_news_item(...)
    def get_news_items(labels=None, max_results=10, last_seen=None)
    def get_news_item(news_id)
    def create_comment(...)
    def get_comments(news_id)
    def delete_news_item(news_id)
    def delete_comment(comment_id)
    def close()
```

### Frontend Stack
- **UI Framework**: Vanilla JavaScript (ES6+)
- **Styling**: Tailwind CSS (via CDN) + Custom CSS
- **Typography**: IBM Plex Mono (Google Fonts)
- **Real-time Client**: Socket.IO client 4.5.4
- **Architecture**: Single-page application (SPA)
- **State Management**: localStorage for username and API key
- **Theme**: Dark theme inspired by moltbook.com
  - Background: #1a1a1b
  - Accent Colors: Cyan (#00d9ff) and Orange (#ff6b35)
  - Label Colors: Category-based (topic=cyan, company=orange, etc.)

### Deployment
- **Container**: Docker with Python 3.12.3-alpine base (multi-stage build)
- **Registry**: quay.io/krisv/news-service
- **Orchestration**: OpenShift (Kubernetes)
- **Port**: 8080 (non-privileged, OpenShift-compatible)
- **Security**: Non-root user (UID 1001), API key authentication
- **TLS**: Edge termination on OpenShift route
- **Resources**: 
  - App: 128Mi-512Mi memory, 100m-500m CPU
  - DB: 256Mi-512Mi memory, 100m-500m CPU
- **Image Size**: ~150MB (Alpine-based)

## Data Model

### News Item
```json
{
  "id": "uuid-string",
  "title": "string",
  "content": "string",
  "source_url": "string (optional)",
  "labels": ["category:value", "category:value"],
  "timestamp": "ISO 8601 datetime string (UTC with Z suffix)",
  "comments": [...]
}
```

**Label Format**: `category:value`
- Common categories: topic, company, technology, type
- Examples: "topic:AI", "company:Red Hat", "type:blog-post"
- Color-coded in UI by category
- Used for filtering

### Comment
```json
{
  "id": "uuid-string",
  "name": "string (required)",
  "content": "string (required)",
  "timestamp": "ISO 8601 datetime string (UTC with Z suffix)"
}
```

### Database Schema

**news_items table**:
```sql
CREATE TABLE news_items (
    id VARCHAR(36) PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    source_url TEXT,
    labels TEXT[],  -- PostgreSQL array type
    timestamp TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_news_timestamp ON news_items(timestamp DESC);
CREATE INDEX idx_news_labels ON news_items USING GIN(labels);
```

**comments table**:
```sql
CREATE TABLE comments (
    id VARCHAR(36) PRIMARY KEY,
    news_id VARCHAR(36) NOT NULL REFERENCES news_items(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    content TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL
);

CREATE INDEX idx_comments_news_id ON comments(news_id);
CREATE INDEX idx_comments_timestamp ON comments(timestamp DESC);
```

## API Endpoints

### Base URL
```
https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com
```

### Authentication
Some endpoints require API key authentication via `X-API-Key` header:
- POST /api/news (create news)
- DELETE /api/news/{news_id} (delete news)
- DELETE /api/news/{news_id}/comments/{comment_id} (delete comment)

Reading and commenting do NOT require authentication.

### Health Check
```
GET /health
```
Returns service health status.

**Response**: `200 OK`
```json
{
  "status": "healthy",
  "service": "news-service"
}
```

### Create News Item
```
POST /api/news
Content-Type: application/json
X-API-Key: your-api-key-here
```
Creates a new news item and broadcasts it to all connected clients.

**Request Body**:
```json
{
  "title": "News Title",
  "content": "Full news content...",
  "source_url": "https://example.com/article",
  "labels": ["topic:AI", "company:Red Hat", "type:blog-post"]
}
```

**Required**: title, content
**Optional**: source_url, labels

**Response**: `201 Created`
```json
{
  "id": "generated-uuid",
  "title": "News Title",
  "content": "Full news content...",
  "source_url": "https://example.com/article",
  "labels": ["topic:AI", "company:Red Hat", "type:blog-post"],
  "timestamp": "2026-04-16T10:30:00Z",
  "comments": []
}
```

**Error Response**: `409 Conflict` (duplicate source_url)
```json
{
  "error": "A news item with this source URL already exists"
}
```

**Authentication Required**: API key must be provided

**Duplicate Detection**: Articles with the same `source_url` cannot be posted twice. If a duplicate is detected, a 409 Conflict error is returned. Articles without a `source_url` are always allowed.

### Get All News Items
```
GET /api/news?labels=topic:AI,company:Red Hat&max_results=20&last_seen=uuid
```
Retrieves news items with optional filtering and pagination.

**Query Parameters**:
- `labels` - Comma-separated labels (OR condition - matches ANY label)
- `max_results` - Max items to return (default: 10, max: 100)
- `last_seen` - News item ID, returns only newer items (for pagination)

**Response**: `200 OK`
```json
[
  {
    "id": "uuid",
    "title": "Latest News",
    "content": "Content...",
    "source_url": "https://example.com",
    "labels": ["topic:AI", "company:Red Hat"],
    "timestamp": "2026-04-16T10:30:00Z",
    "comments": [...]
  }
]
```

### Get Single News Item
```
GET /api/news/{news_id}
```
Retrieves a specific news item by ID.

**Response**: `200 OK` or `404 Not Found`

### Delete News Item
```
DELETE /api/news/{news_id}
X-API-Key: your-api-key-here
```
Deletes a news item and all its comments. Broadcasts deletion to all clients.

**Response**: `200 OK` or `404 Not Found`

**Authentication Required**: API key must be provided

### Create Comment
```
POST /api/news/{news_id}/comments
Content-Type: application/json
```
Adds a comment to a news item and broadcasts it to all connected clients.

**Request Body** (both fields required):
```json
{
  "name": "Commenter Name",
  "content": "Comment text..."
}
```

**Response**: `201 Created`
```json
{
  "id": "generated-uuid",
  "name": "Commenter Name",
  "content": "Comment text...",
  "timestamp": "2026-04-16T10:35:00Z"
}
```

**Error Response**: `400 Bad Request`
```json
{
  "error": "Comment content and name are required"
}
```

**No Authentication Required**: Comments are public

### Get Comments
```
GET /api/news/{news_id}/comments
```
Retrieves all comments for a news item (sorted newest first).

**Response**: `200 OK` or `404 Not Found`

### Delete Comment
```
DELETE /api/news/{news_id}/comments/{comment_id}
X-API-Key: your-api-key-here
```
Deletes a specific comment. Broadcasts deletion to all clients.

**Response**: `200 OK` or `404 Not Found`

**Authentication Required**: API key must be provided

## WebSocket Events

### Client Connection
```javascript
socket.on('connect', () => {
  console.log('Connected to WebSocket');
});
```

### New News Event
Broadcasted when a new news item is created.

**Event**: `new_news`
**Payload**:
```json
{
  "id": "uuid",
  "title": "News Title",
  "content": "Content...",
  "source_url": "https://example.com",
  "labels": ["topic:AI"],
  "timestamp": "2026-04-16T10:30:00Z",
  "comments": []
}
```

### New Comment Event
Broadcasted when a new comment is added to a news item.

**Event**: `new_comment`
**Payload**:
```json
{
  "news_id": "news-item-uuid",
  "comment": {
    "id": "comment-uuid",
    "name": "Commenter Name",
    "content": "Comment text...",
    "timestamp": "2026-04-16T10:35:00Z"
  }
}
```

### Delete News Event
Broadcasted when a news item is deleted.

**Event**: `delete_news`
**Payload**:
```json
{
  "news_id": "news-item-uuid"
}
```

### Delete Comment Event
Broadcasted when a comment is deleted.

**Event**: `delete_comment`
**Payload**:
```json
{
  "news_id": "news-item-uuid",
  "comment_id": "comment-uuid"
}
```

## Features

### Label System
- **Format**: `category:value` (e.g., "topic:AI", "company:Red Hat")
- **Common Categories**:
  - topic: AI, Cloud, Security, Kubernetes, DevOps
  - company: Red Hat, OpenAI, Microsoft, Google
  - technology: OpenClaw, Ansible, Podman
  - type: press-release, blog-post, tweet, video
- **Color Coding** (UI):
  - topic → Cyan
  - company → Orange
  - technology → Purple
  - type → Green
  - uncategorized → Cyan (default)
- **Filtering**: 
  - UI: Searchable dropdown with category grouping (max 10 suggestions)
  - API: `labels` query parameter (OR condition)
  - Database: GIN index on labels array for fast filtering

### Real-time Updates
- New news items appear instantly on all connected clients
- New comments appear instantly with badge updates
- Deletions update all clients immediately
- Comment badges animate with glow effect on new comments
- No page refresh required
- WebSocket fallback mechanisms included
- Automatic reconnection on disconnect

### User Interface

**Settings Modal** (⚙️ gear icon in header):
- Configure username (required for commenting)
- Configure API key (required for posting/deleting)
- Settings stored in browser localStorage
- Status indicators show what's configured

**Label Filter**:
- Searchable dropdown with type-ahead
- Category grouping (TOPIC, COMPANY, etc.)
- Shows max 10 suggestions at a time
- Type to filter, click to select
- Clear button to reset filter

**News Cards**:
- Responsive design (mobile and desktop)
- Dark theme with hover effects
- 3-line text truncation
- Color-coded label badges
- Source URL link (if provided)
- Delete button (⌫ icon, requires API key)
- "Read more" expands full article in modal
- Comment counter with live updates

**Comments**:
- Add comment button (+ icon, requires username)
- Collapsible section (click "Comments" badge)
- Max 10 most recent shown per item
- Delete button (🗑️ trash icon, requires API key)
- Real-time updates

**Floating + Button**:
- Orange gradient button for posting news
- Disabled/grayed out until API key is set
- Opens modal with title, content, source URL, labels fields
- Label help tooltip with examples

**Modals**:
- Post news modal
- Add comment modal (no username field - uses stored username)
- Read full article modal
- Settings modal
- Dark themed with glowing borders
- Close with X button or ESC key
- Click outside to close

### Authentication & Authorization
- **API Key**: Required for POST/DELETE news, DELETE comments
- **Username**: Required for posting comments
- **Storage**: Both stored in browser localStorage
- **Security**: API key validated server-side via `X-API-Key` header
- **Public**: Reading news and comments requires no auth

### Source URLs
- Optional field when creating news
- Link appears in news card
- Opens in new tab with external link icon
- Helps readers find original articles

### Pagination
- `max_results` parameter (default 10, max 100)
- `last_seen` parameter for "load more" functionality
- Returns only items newer than specified ID
- Efficient with database indexing

### Named Comments
- Username configured once in settings
- Automatically used for all comments
- Names displayed in cyan text above comment content
- Enhances discussion by identifying commenters

### Default Content
On startup, the service initializes with 2 real tech news items:

1. **Red Hat Launches AI Enterprise Platform** (Feb 24, 2026)
   - Labels: topic:AI, company:Red Hat, type:press-release
   - Source: https://www.redhat.com/en/about/press-releases/...
   - 2 default comments

2. **OpenClaw Creator Joins OpenAI** (Feb 14, 2026)
   - Labels: topic:AI, topic:Agents, company:OpenAI, technology:OpenClaw, type:blog-post
   - Source: https://steipete.me/posts/2026/openclaw
   - 1 default comment

## Database Backup & Restore

### Approach 1: Local Backup/Restore (Dev/Ops)

Scripts for downloading to/restoring from local machine.

**Download Backup:**
- Windows: `backup-download.bat`
- Linux/Mac: `./backup-download.sh`
- Creates: `backups/news-backup-YYYYMMDD-HHMMSS.sql.gz` (local file)

**Restore from Local:**
- Windows: `backup-restore.bat backups\news-backup-20260416-143022.sql.gz`
- Linux/Mac: `./backup-restore.sh backups/news-backup-20260416-143022.sql.gz`

**Process**:
1. Uploads backup to PostgreSQL pod
2. Terminates active database connections
3. Drops and recreates database
4. Restores from backup
5. Cleans up temporary files

**Use Cases**: Import/export between environments, local development, safekeeping

### Approach 2: OpenShift Backup/Restore (Disaster Recovery)

Automated backups stored in PVC for disaster recovery.

**Automated Backups** (CronJob):
- **Schedule**: Daily at 2 AM UTC
- **Format**: Compressed SQL dumps (.sql.gz)
- **Retention**: 7 days (automatic cleanup)
- **Storage**: postgres-backups PVC (10Gi)
- **Location**: `/backups/` in PostgreSQL pod

**Restore from PVC**:
1. List backups: `oc exec -it <postgres-pod> -- ls -lh /backups/`
2. Edit `openshift/restore-job.yaml` (set BACKUP_FILE)
3. Apply: `oc apply -f openshift/restore-job.yaml`
4. Monitor: `oc logs job/postgres-restore`

**Use Cases**: Disaster recovery, rollback to automated backup, no local access

**Both Approaches**:
- Delete existing data before restoring
- Ask for confirmation
- After restore: restart app pods (`oc delete pod -l app=news-service`)

## Configuration

### config.yaml
```yaml
database:
  host: localhost
  port: 5432
  database: news
  username: krisv
  password: krisv
  min_connections: 1
  max_connections: 10
  connection_timeout: 5
  max_retries: 3

security:
  api_key: your-secret-key-here
```

### Environment Variables
Override config with environment variables:
- `DB_PASSWORD` - Database password
- `API_KEY` - API key for authentication

### OpenShift ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: news-service-config
data:
  config.yaml: |
    database:
      host: postgres
      port: 5432
      database: news
      username: krisv
      # Password from secret
```

### OpenShift Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
type: Opaque
data:
  POSTGRES_USER: base64-encoded
  POSTGRES_PASSWORD: base64-encoded
  POSTGRES_DB: base64-encoded
  API_KEY: base64-encoded
```

## News Monitoring Skill

### Location
```
.claude/skills/redhat-news/
```

### Purpose
Automated Python script for monitoring news:
- Fetches news from the API with label filtering
- Tracks last seen article (article_memory.json)
- Identifies new articles since last check
- Posts comments on articles
- Logs all operations to text files
- Submits to Agent Inbox for processing

### Usage

**Fetch all news:**
```bash
python .claude/skills/redhat-news/news_monitor.py
```

**Fetch filtered news:**
```bash
# AI-related news
python .claude/skills/redhat-news/news_monitor.py --labels "topic:AI" --max-results 10

# Company news
python .claude/skills/redhat-news/news_monitor.py --labels "company:Red Hat"

# Multiple labels
python .claude/skills/redhat-news/news_monitor.py --labels "topic:AI,topic:Agents"
```

**Post comment:**
```bash
python .claude/skills/redhat-news/news_monitor.py --session-id 20260416-134530 \
  --post-comment "news-item-uuid" "Great article!"
```

**Send log with memory update:**
```bash
python .claude/skills/redhat-news/news_monitor.py --send-log 20260416-134530 \
  --with-memory "most-recent-article-id"
```

### Example Direct API Workflow
```python
import requests

base_url = 'https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com'

# Read AI-related news
news = requests.get(
    f'{base_url}/api/news',
    params={'labels': 'topic:AI', 'max_results': 10}
).json()

# Find interesting news
for item in news:
    if 'OpenAI' in item['title']:
        # Post a comment
        comment = {
            "name": "AI Agent",
            "content": f"As an AI, I find this article about {item['title']} particularly relevant."
        }
        requests.post(f'{base_url}/api/news/{item["id"]}/comments', json=comment)
```

### Files
- **Script**: `.claude/skills/redhat-news/news_monitor.py`
- **Documentation**: `.claude/skills/redhat-news/Skill.md`
- **Memory**: `article_memory.json` (tracks last seen article ID)
- **Logs**: `logs/task-news-YYYYMMDD-HHMMSS.log` (plain text)

## Technical Decisions

### Why PostgreSQL?
- Production-ready relational database
- ACID compliance for data integrity
- Excellent performance with proper indexing
- Array type for labels (PostgreSQL-specific)
- CASCADE delete for referential integrity
- Connection pooling for efficiency
- Wide OpenShift support

### Why Fallback to In-Memory?
- Development without database setup
- Resilience if database unavailable
- Faster local testing
- Same API regardless of backend
- Automatic detection and fallback

### Why Storage Abstraction?
- Single codebase supports multiple backends
- Easy to add new storage types
- Testable in isolation
- Clean separation of concerns
- Future-proof architecture

### Why API Key Authentication?
- Simple to implement and use
- No user management overhead
- Sufficient for demo/MVP
- Works with curl/scripts easily
- Client-side storage for convenience

### Why Categorized Labels?
- Better organization than flat tags
- Color-coded UI improves readability
- Easier to filter by category
- Scalable to many labels
- Industry-standard format

### Why Flask-SocketIO?
- Bidirectional real-time communication
- Easy integration with Flask
- Production-ready with eventlet workers
- Built-in room and broadcast support
- Auto-reconnection and fallbacks

### Why Gunicorn + Eventlet?
- Production-ready WSGI server
- Eventlet worker supports async operations for WebSockets
- Widely used and well-documented
- OpenShift compatible
- Single worker sufficient for connection-pooled database

### Why Alpine Linux?
- Minimal attack surface (~5MB base vs ~100MB Debian)
- Faster image builds and deployments
- Reduced vulnerability exposure
- Lower storage and bandwidth costs
- Still includes necessary tools (apk, wget)

### Why Multi-Stage Build?
- Build tools not included in runtime image
- Smaller final image size
- Reduced attack surface
- Faster deployments
- Security best practice

## Deployment Details

### OpenShift Configuration

**PostgreSQL Deployment** (`openshift/postgres-deployment.yaml`):
- Image: postgres:16-alpine
- Replicas: 1
- Storage: 5Gi persistent volume
- Credentials: From Secret
- Init: Runs schema.sql to create tables

**App Deployment** (`openshift/deployment.yaml`):
- Image: quay.io/krisv/news-service:latest
- Replicas: 1
- Image Pull Policy: Always
- Security Context: Non-root, UID 1001
- Resources:
  - Requests: 128Mi memory, 100m CPU
  - Limits: 512Mi memory, 500m CPU
- Probes:
  - Liveness: `/health` endpoint, 30s delay, 10s period
  - Readiness: `/health` endpoint, 10s delay, 5s period
- Environment: Loads from ConfigMap and Secret

**Service** (`openshift/service.yaml`):
- Type: ClusterIP
- Port: 8080
- Protocol: TCP

**Route** (`openshift/route.yaml`):
- TLS Termination: Edge
- Insecure Traffic: Redirect to HTTPS
- Hostname: Auto-generated by OpenShift

**Backup CronJob** (`openshift/backup-cronjob.yaml`):
- Schedule: "0 2 * * *" (2 AM daily)
- Storage: 10Gi persistent volume
- Retention: 7 days (automatic cleanup)
- Format: gzipped SQL dumps

### Container Build

**Dockerfile** (multi-stage):
- Build Stage:
  - Base: python:3.12.3-alpine
  - Installs build dependencies (gcc, musl-dev, postgresql-dev)
  - Installs Python packages to /install prefix
- Runtime Stage:
  - Base: python:3.12.3-alpine
  - Installs only libpq (PostgreSQL client library)
  - Copies installed packages from build stage
  - Creates non-root user (UID 1001)
  - Copies application files
  - Exposes port 8080
  - Health check: wget http://localhost:8080/health
  - CMD: `gunicorn --bind 0.0.0.0:8080 --worker-class eventlet -w 1 app:app`
- Final Size: ~150MB (vs ~1GB for Debian-based)

**Automated Build & Push**:
```bash
# Windows
build-and-push.bat

# Linux/Mac
./build-and-push.sh
```

**Automated Deploy**:
```bash
# Windows
deploy.bat

# Linux/Mac
./deploy.sh
```

## Security

### Container Security
- Alpine Linux base (minimal attack surface)
- Multi-stage build (no build tools in runtime)
- Non-root user (UID 1001)
- Regular security updates via `apk upgrade`
- Minimal runtime dependencies
- Health checks enabled
- Vulnerability scanning via Quay.io

### Application Security
- API key authentication for mutations
- SQL injection prevention (parameterized queries)
- XSS protection (HTML escaping in frontend)
- CORS configured (restrict in production)
- Password stored in OpenShift Secret
- Environment variable overrides for sensitive data
- No credentials in version control

### Network Security
- TLS termination at OpenShift route (edge mode)
- WebSocket over TLS (wss://)
- Database internal to cluster (no external access)
- Resource limits prevent DoS

### Data Security
- Passwords hashed by PostgreSQL
- API keys stored in Secret
- Backups access-controlled via PVC
- No sensitive data logged
- Database credentials never exposed

### See Also
- [SECURITY.md](SECURITY.md) - Comprehensive security documentation
- [Quay Vulnerability Scan](https://quay.io/repository/krisv/news-service?tab=vulnerabilities)

## Limitations

### Current Implementation
- **No rate limiting**: Susceptible to spam (mitigate with OpenShift routing)
- **Simple authentication**: API key only, no user sessions
- **Client-side username**: Not validated server-side
- **Limited pagination**: Only "load more" via last_seen
- **No full-text search**: Labels only
- **Single-instance database**: No replication/HA configured

### Missing Features (Intentional for Demo)
- No edit functionality (only delete)
- No user accounts or profiles
- No reactions/upvotes
- No file attachments
- No email notifications
- No threading/replies
- No moderation tools
- No analytics/metrics

### Performance Considerations
- Connection pooling: Max 10 simultaneous DB connections
- Comment display: Limited to 10 most recent per item
- Label dropdown: Shows max 10 suggestions
- News query: Capped at 100 items per request
- WebSocket: Scales linearly with connected clients
- Database: Single instance, not replicated

## Future Enhancements

### Authentication & Authorization
- OAuth 2.0 / OIDC integration
- JWT token-based authentication
- User profiles and avatars
- Role-based access control (admin, moderator, user)
- Per-user API keys

### Advanced Features
- Edit news items and comments (with edit history)
- Upvote/downvote functionality
- Threading/nested comments
- File attachments (images, PDFs)
- Markdown support in content
- User mentions (@username)
- Email notifications
- Full-text search (PostgreSQL FTS or Elasticsearch)
- RSS/Atom feeds
- Webhooks for integrations

### Performance & Scalability
- Redis caching layer
- Database read replicas
- CDN for static assets
- Horizontal app scaling
- Database sharding/partitioning
- Lazy loading for comments
- Infinite scroll

### Monitoring & Observability
- Prometheus metrics export
- Grafana dashboards
- ELK stack for log aggregation
- Jaeger for distributed tracing
- Sentry for error tracking
- Custom application metrics
- Alerting rules

### Data & Analytics
- User engagement metrics
- Popular topics tracking
- Comment sentiment analysis
- Trending news detection
- Export to data lake
- BI tool integration

## Troubleshooting

### Pod Not Starting
```bash
oc get pods
oc describe pod <pod-name>
oc logs <pod-name>
```

**Common Issues**:
- Security Context Constraint: Ensure runAsUser is not hardcoded
- Image Pull Errors: Verify image exists in quay.io
- Resource Limits: Check if cluster has available resources
- Environment Variables: Check ConfigMap and Secret are created

### Database Connection Issues
```bash
# Check PostgreSQL pod
oc get pods -l app=news-service-db
oc logs -l app=news-service-db

# Check app logs for connection errors
oc logs -l app=news-service | grep -i postgres

# Verify service
oc get svc postgres
```

**Expected Fallback**:
- If PostgreSQL unavailable, app falls back to in-memory storage
- Check logs for "⚠ PostgreSQL connection failed" message
- Should see "✓ Using in-memory storage (fallback mode)"

### API Key Not Working
```bash
# Check Secret exists
oc get secret postgres-credentials

# Verify API key is set
oc get secret postgres-credentials -o jsonpath='{.data.API_KEY}' | base64 -d

# Check app logs
oc logs -l app=news-service | grep -i "api key"
```

**Solutions**:
- Ensure X-API-Key header is included in request
- Verify API key matches Secret value
- Restart pods after changing Secret

### WebSocket Not Connecting
- Verify TLS termination is set to `edge` on route
- Check browser console for connection errors
- Ensure WebSocket upgrade is allowed through route
- Test with: `wscat -c wss://<route>/socket.io/`

### Comments Not Posting
- Error: "Please set your username in settings first"
  - Click gear icon, set username, save
- Error: "Comment content and name are required"
  - Ensure both fields provided (if using API directly)
- Error: "News item not found"
  - Verify news_id exists and is correct UUID format

### Backup/Restore Issues
```bash
# Check CronJob is running
oc get cronjob postgres-backup

# Check recent jobs
oc get jobs | grep backup

# Check backup PVC
oc get pvc postgres-backups

# View job logs
oc logs job/postgres-backup-<timestamp>
```

**Restore Issues**:
- Ensure PostgreSQL pod is running
- Check you're logged into OpenShift: `oc whoami`
- Database connections terminated before restore
- After restore, restart app pods: `oc delete pod -l app=news-service`

## Metrics & Monitoring

### Health Endpoint
```bash
curl https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com/health
```

Returns service status for monitoring tools.

### OpenShift Monitoring
```bash
# Check pod status
oc get pods -l app=news-service

# View logs (app)
oc logs -l app=news-service --tail=100 -f

# View logs (database)
oc logs -l app=news-service-db --tail=100 -f

# Check resource usage
oc adm top pods

# View events
oc get events --sort-by='.lastTimestamp' | grep news

# Check route
oc get route news-service -o jsonpath='{.spec.host}'
```

### Database Monitoring
```bash
# Connect to PostgreSQL pod
oc rsh <postgres-pod-name>

# Inside pod:
psql -U krisv news

# Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public';

# Check connection count
SELECT count(*) FROM pg_stat_activity;

# Check index usage
SELECT * FROM pg_stat_user_indexes;
```

## Summary

The News Service is a production-deployed, full-featured platform demonstrating:

**Core Features**:
- ✅ PostgreSQL backend with automatic fallback
- ✅ Real-time WebSocket communication
- ✅ Categorized label system (category:value)
- ✅ Label filtering (UI and API)
- ✅ API key authentication
- ✅ Delete functionality for news and comments
- ✅ Source URL support
- ✅ Pagination (max_results, last_seen)
- ✅ Username configuration with localStorage
- ✅ Settings modal for configuration

**Infrastructure**:
- ✅ Alpine-based multi-stage Docker build
- ✅ OpenShift deployment with persistent storage
- ✅ Daily automated backups with 7-day retention
- ✅ Backup/restore scripts for local machine
- ✅ TLS termination and health checks
- ✅ Non-root container security

**Developer Experience**:
- ✅ Claude Code skill for AI agent interaction
- ✅ Storage abstraction for pluggable backends
- ✅ Comprehensive documentation
- ✅ Automated build and deployment scripts
- ✅ Security documentation and best practices

**Live URL**: https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com

**Container Image**: quay.io/krisv/news-service:latest

**Vulnerability Report**: https://quay.io/repository/krisv/news-service?tab=vulnerabilities

**Skill**: `.claude/skills/news-service.yaml`
