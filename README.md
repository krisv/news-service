# News Service

A real-time news posting and discussion platform built with Flask and WebSockets. Features categorized labels, PostgreSQL storage, API key authentication, and instant updates across all connected clients.

## Live Deployment

🌐 **Production URL**: https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com

The service is deployed on OpenShift and ready to use!

## Features

### Core Functionality
- 🎨 **Modern Dark Theme**: Moltbook-inspired design with IBM Plex Mono font and cyan/orange accents
- ⚡ **Real-time Updates**: WebSocket-powered instant news and comment updates
- 🏷️ **Categorized Labels**: Organize news with category:value tags (topic:AI, company:Red Hat, etc.)
- 🔍 **Smart Filtering**: Filter news by labels with searchable dropdown (UI) or API parameters
- 💬 **Named Comments**: Configured username used automatically for all comments
- 🔔 **Live Badges**: Comment counters update in real-time with glow animations
- 📱 **Responsive Design**: Works beautifully on desktop and mobile

### Storage & Security
- 🗄️ **PostgreSQL Backend**: Production-ready database with automatic fallback to in-memory
- 🔐 **API Key Authentication**: Secure posting and deletion of content
- ⚙️ **Settings Modal**: Configure username and API key in browser (stored in localStorage)
- 🗑️ **Delete Functionality**: Remove news items and comments (requires API key)
- 💾 **Backup & Restore**: Scripts to download/upload PostgreSQL backups to local machine

### Developer Features
- 🔗 **Source URLs**: Optional links to original articles
- 📊 **Pagination**: Control results with max_results and last_seen parameters
- 🎯 **Label Categories**: Color-coded by category (topic=cyan, company=orange, etc.)
- 📦 **Docker Ready**: Optimized multi-stage build with security updates

## Technology Stack

- **Backend**: Flask 3.1, Flask-SocketIO 5.4, Gunicorn 23.0, Python 3.12
- **Database**: PostgreSQL 16 (with in-memory fallback)
- **Frontend**: Vanilla JavaScript, Tailwind CSS, IBM Plex Mono, Socket.IO client
- **Container**: Docker (quay.io/krisv/news-service:latest)
- **Deployment**: OpenShift with persistent volumes for DB and backups

## Quick Start

### Option 1: Use the Deployed Service

#### Configure Your Settings
1. Open https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com
2. Click the gear icon (⚙️) in top-right corner
3. Set your username (required for commenting)
4. Set API key (required for posting/deleting) - ask admin for key

#### Browse and Comment
- View news items with labels
- Filter by label using the dropdown
- Click "Comments" to expand discussions
- Click + icon to add comments (requires username)

#### Post News
- Click the floating + button (requires API key)
- Add title, content, optional source URL
- Add labels in format: `topic:AI, company:Red Hat, type:blog-post`

### Option 2: Run Locally with Docker
```bash
docker pull quay.io/krisv/news-service:latest
docker run -d -p 8080:8080 quay.io/krisv/news-service:latest
```

Then open http://localhost:8080

## Label System

### Label Format
Labels use a `category:value` format for better organization:

**Common Categories:**
- `topic:` - AI, Cloud, Security, Kubernetes, DevOps
- `company:` - Red Hat, OpenAI, Microsoft, Google
- `technology:` - OpenClaw, Ansible, Podman
- `type:` - press-release, blog-post, tweet, video

**Example:**
```
topic:AI, company:Red Hat, type:press-release
```

### Label Colors
Labels are automatically color-coded by category:
- 🔵 **topic:** Cyan
- 🟠 **company:** Orange
- 🟣 **technology:** Purple
- 🟢 **type:** Green
- ⚪ **Uncategorized:** Cyan (default)

## API Documentation

### Base URL
```
https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com
```

### Authentication
Some endpoints require an API key passed in the `X-API-Key` header:
```bash
-H "X-API-Key: your-api-key-here"
```

### Endpoints

#### Health Check
```bash
GET /health
```
Returns: `{"status": "healthy", "service": "news-service"}`

#### Get News Items (with filtering)
```bash
GET /api/news?labels=topic:AI,company:Red Hat&max_results=20&last_seen=<news_id>
```

**Query Parameters:**
- `labels` - Comma-separated labels (OR condition - matches ANY label)
- `max_results` - Maximum items to return (default: 10, max: 100)
- `last_seen` - News item ID to get only newer items (for pagination)

**Response:**
```json
[
  {
    "id": "uuid",
    "title": "News Title",
    "content": "Full content...",
    "source_url": "https://example.com/article",
    "labels": ["topic:AI", "company:Red Hat"],
    "timestamp": "2026-04-15T10:30:00Z",
    "comments": [...]
  }
]
```

#### Get Single News Item
```bash
GET /api/news/{news_id}
```

#### Post News Item
```bash
POST /api/news
Content-Type: application/json
X-API-Key: your-api-key-here

{
  "title": "News Title",
  "content": "Full article content...",
  "source_url": "https://example.com/article",
  "labels": ["topic:AI", "company:Red Hat", "type:blog-post"]
}
```
**Note**: `title` and `content` required. `source_url` and `labels` optional. Requires API key.

#### Delete News Item
```bash
DELETE /api/news/{news_id}
X-API-Key: your-api-key-here
```
Deletes the news item and all its comments. Requires API key.

#### Get Comments
```bash
GET /api/news/{news_id}/comments
```

#### Post Comment
```bash
POST /api/news/{news_id}/comments
Content-Type: application/json

{
  "name": "Your Name",
  "content": "Your comment text"
}
```
**Note**: Both `name` and `content` required. No API key needed.

#### Delete Comment
```bash
DELETE /api/news/{news_id}/comments/{comment_id}
X-API-Key: your-api-key-here
```
Requires API key.

## Local Development

### Prerequisites
- Python 3.12 or higher
- PostgreSQL 16 (optional - will fallback to in-memory)
- pip

### Setup

1. **Clone Repository**
   ```bash
   git clone <repo-url>
   cd news-service
   ```

2. **Create Virtual Environment**
   ```bash
   python -m venv venv

   # Windows
   venv\Scripts\activate

   # Linux/Mac
   source venv/bin/activate
   ```

3. **Install Dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure Database (optional)**
   
   Copy `config.yaml.example` to `config.yaml` and edit:
   ```yaml
   database:
     host: localhost
     port: 5432
     database: news
     username: krisv
     password: krisv
     max_connections: 10
     connection_timeout: 5
     max_retries: 3

   security:
     api_key: your-secret-key-here
   ```

   Or use environment variables:
   ```bash
   export DB_PASSWORD=your-password
   export API_KEY=your-api-key
   ```

5. **Initialize Database (if using PostgreSQL)**
   ```bash
   createdb -U krisv news
   psql -U krisv news < schema.sql
   ```

6. **Run the Application**
   ```bash
   python app.py
   ```

7. **Access Locally**
   Open http://localhost:8080

## Docker Build & Deployment

### Automated Build & Push (OpenShift)

**Windows:**
```bash
build-and-push.bat
```

**Linux/Mac:**
```bash
./build-and-push.sh
```

This script:
1. Checks for Docker or Podman
2. Loads Quay.io credentials from `.quay-config`
3. Builds the image with security updates
4. Pushes to quay.io/krisv/news-service:latest

### Manual Build

```bash
# Build image
docker build -t news-service:latest .

# Run container
docker run -d -p 8080:8080 --name news-service news-service:latest

# Push to registry
docker tag news-service:latest quay.io/krisv/news-service:latest
docker login quay.io
docker push quay.io/krisv/news-service:latest
```

## OpenShift Deployment

### Prerequisites
- OpenShift CLI (`oc`) installed
- Access to OpenShift cluster
- Image pushed to quay.io

### Automated Deployment

**Windows:**
```bash
deploy.bat
```

**Linux/Mac:**
```bash
./deploy.sh
```

This script deploys:
1. PostgreSQL database with 5Gi persistent volume
2. ConfigMap and Secret for configuration
3. News service application
4. Service and Route for external access
5. Backup CronJob (daily at 2 AM, 7-day retention)

### Manual Deployment

1. **Login to OpenShift**
   ```bash
   oc login <your-cluster-url>
   ```

2. **Create or Select Project**
   ```bash
   oc new-project news-service
   # or
   oc project your-project
   ```

3. **Apply Configurations**
   ```bash
   # Database
   oc apply -f openshift/postgres-deployment.yaml

   # Application config
   oc apply -f openshift/configmap.yaml

   # Application
   oc apply -f openshift/deployment.yaml
   oc apply -f openshift/service.yaml
   oc apply -f openshift/route.yaml

   # Backups
   oc apply -f openshift/backup-cronjob.yaml
   ```

4. **Verify Deployment**
   ```bash
   oc get pods
   oc get deployment,svc,route
   ```

5. **Get Route URL**
   ```bash
   oc get route news-service -o jsonpath='{.spec.host}'
   ```

### Configuration

- **App Replicas**: 1 (stateless)
- **DB Replicas**: 1 (with persistent storage)
- **Resources**: 128Mi-512Mi memory, 100m-500m CPU
- **Probes**: Liveness and readiness on `/health`
- **Security**: Non-root user, TLS termination on route
- **Backups**: Daily at 2 AM, stored in 10Gi PVC, 7-day retention

## Database Backup & Restore

There are two backup/restore approaches depending on your use case:

### Approach 1: Local Backup/Restore (Dev/Ops Workflows)

Use these scripts to download backups to your local machine or restore from local files.

**Download Backup:**

Windows: `backup-download.bat`
Linux/Mac: `./backup-download.sh`

Creates: `backups/news-backup-YYYYMMDD-HHMMSS.sql.gz` (local file)

**Restore from Local File:**

Windows: `backup-restore.bat backups\news-backup-20260416-143022.sql.gz`
Linux/Mac: `./backup-restore.sh backups/news-backup-20260416-143022.sql.gz`

**Use Cases:**
- Download backups for safekeeping
- Import/export data between environments
- Local development with production data
- Transfer data to other systems

### Approach 2: OpenShift Backup/Restore (Disaster Recovery)

Automated backups are stored in the OpenShift PVC. Use these for disaster recovery.

**Automated Backups:**
- Schedule: Daily at 2 AM UTC
- Location: postgres-backups PVC (10Gi)
- Retention: 7 days (automatic cleanup)
- Format: `news-backup-YYYYMMDD-HHMMSS.sql.gz`

**Restore from PVC Backup:**

1. List available backups:
   ```bash
   oc exec -it <postgres-pod> -- ls -lh /backups/
   ```

2. Edit and apply restore job:
   ```bash
   # Edit openshift/restore-job.yaml
   # Set BACKUP_FILE to the backup filename
   
   oc apply -f openshift/restore-job.yaml
   ```

3. Monitor restore:
   ```bash
   oc get jobs
   oc logs job/postgres-restore
   ```

**Use Cases:**
- Disaster recovery within OpenShift
- Rollback to automated backup
- No local machine access needed

**Important Notes:**
- Both approaches delete existing data before restoring
- Both ask for confirmation before proceeding
- After restore, restart app pods: `oc delete pod -l app=news-service`

## Data Model

### News Item
```json
{
  "id": "uuid",
  "title": "string",
  "content": "string",
  "source_url": "string (optional)",
  "labels": ["category:value", ...],
  "timestamp": "ISO 8601 datetime",
  "comments": [...]
}
```

### Comment
```json
{
  "id": "uuid",
  "name": "string",
  "content": "string",
  "timestamp": "ISO 8601 datetime"
}
```

## Default News Items

The service initializes with 2 default news items:

1. **Red Hat Launches AI Enterprise Platform** (Feb 24, 2026)
   - Labels: topic:AI, company:Red Hat, type:press-release
   - Source: https://www.redhat.com/...
   - Includes 2 sample comments

2. **OpenClaw Creator Joins OpenAI** (Feb 14, 2026)
   - Labels: topic:AI, topic:Agents, company:OpenAI, technology:OpenClaw, type:blog-post
   - Source: https://steipete.me/posts/2026/openclaw
   - Includes 1 sample comment

## UI Features

### Design
- **Theme**: Dark (#1a1a1b) with cyan (#00d9ff) and orange (#ff6b35) accents
- **Font**: IBM Plex Mono (via Google Fonts)
- **Animations**: Glowing effects, smooth transitions, pulse animations

### Components
- **Settings Modal**: Gear icon (⚙️) in header - configure username and API key
- **Floating + Button**: Orange gradient button for posting news (disabled until API key set)
- **News Cards**: Hover effects, 3-line content truncation, delete button (if API key set)
- **Label Filter**: Dropdown with category grouping, max 10 suggestions, type to filter
- **Comment Section**: Add comment button disabled until username set
- **Delete Buttons**: Trash icon for news items and comments (requires API key)

### Real-Time Features
- New news appears instantly via WebSocket
- Comment badges increment live with glow animation
- Comments appear in expanded sections
- Deletions update all clients immediately
- No page refresh required

## News Monitoring Skill

This repository includes an automated news monitoring Python script for agents.

### Location
`.claude/skills/redhat-news/`

### What It Does

The monitoring skill:
- 📡 Fetches news from the API with label filtering
- 🔍 Tracks last seen article (article_memory.json)
- 🆕 Identifies new articles since last check
- 💬 Posts comments on articles
- 📝 Logs all operations to text files
- 📬 Submits to Agent Inbox for processing

### Quick Usage

**Fetch all news:**
```bash
python .claude/skills/redhat-news/news_monitor.py
```

**Fetch AI-related news:**
```bash
python .claude/skills/redhat-news/news_monitor.py --labels "topic:AI" --max-results 10
```

**Fetch Red Hat company news:**
```bash
python .claude/skills/redhat-news/news_monitor.py --labels "company:Red Hat"
```

**Post comment:**
```bash
python .claude/skills/redhat-news/news_monitor.py --session-id 20260416-134530 \
  --post-comment "news-item-uuid" "Great article!"
```

### Label Filtering

The skill supports the categorized label system:
- `topic:AI`, `topic:Cloud`, `topic:Security`
- `company:Red Hat`, `company:OpenAI`
- `technology:OpenClaw`, `technology:Kubernetes`
- `type:press-release`, `type:blog-post`

**Examples:**
```bash
# Multiple labels (OR condition)
--labels "topic:AI,topic:Agents"

# Company news
--labels "company:Red Hat"

# Specific content type
--labels "type:blog-post"
```

### Files Generated

- **Memory**: `article_memory.json` - Tracks last seen article ID
- **Logs**: `logs/task-news-YYYYMMDD-HHMMSS.log` - Plain text operation logs

### Documentation

See `.claude/skills/redhat-news/Skill.md` for complete documentation.

## Troubleshooting

### Service Not Responding
```bash
# Check pod status
oc get pods

# Check logs
oc logs -l app=news-service
oc logs -l app=news-service-db

# Describe deployment
oc describe deployment news-service
```

### Database Connection Issues
- Check PostgreSQL pod is running: `oc get pods -l app=news-service-db`
- Check logs: `oc logs -l app=news-service-db`
- Service falls back to in-memory if DB unavailable
- Check config in Secret: `oc get secret postgres-credentials -o yaml`

### API Key Not Working
- Verify API key is set in Secret: `oc get secret postgres-credentials -o yaml`
- Check app logs for authentication messages
- Ensure `X-API-Key` header is included in requests

### Comment Posting Fails
- **Error**: "Please set your username in settings first"
  - **Solution**: Click gear icon, set username, save settings

- **Error**: "Comment content and name are required"
  - **Solution**: Ensure JSON includes both fields when using API directly

### WebSocket Issues
- WebSocket connections work through the OpenShift route
- Check browser console for connection errors
- Verify TLS termination is set to `edge` on route

### Backup/Restore Issues
- Ensure PostgreSQL pod is running
- Check you're logged into OpenShift: `oc whoami`
- Database connections are terminated before restore
- After restore, restart app pods to refresh connections

## File Structure

```
news-service/
├── .claude/
│   ├── skills/
│   │   ├── news-service.yaml      # Skill configuration
│   │   └── news-service.md        # Skill documentation
│   └── agents/
│       └── communication-manager.yaml  # Communication subagent
├── openshift/
│   ├── deployment.yaml            # App deployment
│   ├── service.yaml               # App service
│   ├── route.yaml                 # App route (TLS edge)
│   ├── postgres-deployment.yaml   # PostgreSQL with PVC
│   ├── configmap.yaml             # Config and credentials
│   └── backup-cronjob.yaml        # Daily backup job
├── static/
│   └── styles.css                 # Custom CSS (dark theme)
├── templates/
│   └── index.html                 # Frontend UI
├── backups/                       # Local backup storage (gitignored)
├── app.py                         # Flask application
├── storage.py                     # Storage abstraction layer
├── schema.sql                     # PostgreSQL schema
├── requirements.txt               # Python dependencies
├── config.yaml                    # Config (gitignored, use config.yaml.example)
├── Dockerfile                     # Container definition (Python 3.12)
├── build-and-push.bat/.sh         # Build and push scripts
├── deploy.bat/.sh                 # OpenShift deployment scripts
├── backup-download.bat/.sh        # Download DB backup
├── backup-restore.bat/.sh         # Restore DB backup
└── README.md                      # This file
```

## Security

### Quick Summary
- ✅ Alpine-based multi-stage build (minimal attack surface)
- ✅ Non-root user (UID 1001)
- ✅ TLS termination on OpenShift route
- ✅ API key authentication for mutations
- ✅ SQL injection prevention (parameterized queries)
- ✅ XSS protection (HTML escaping)
- ✅ Secrets stored in OpenShift, not in code

### Considerations
- ⚠️ API key in browser localStorage (clear on shared devices)
- ⚠️ No rate limiting (add for production)
- ⚠️ Comments don't require auth (by design)

### Full Security Documentation
See **[SECURITY.md](SECURITY.md)** for:
- Detailed security measures
- Known limitations
- Vulnerability scanning
- Security best practices
- Production deployment checklist
- How to report security issues

### Vulnerability Scanning
Container image is scanned by Quay.io. View latest:
```
https://quay.io/repository/krisv/news-service?tab=vulnerabilities
```

## Performance Notes

- WebSocket connections scale with clients
- PostgreSQL connection pooling (1-10 connections)
- In-memory fallback for development/testing
- Comment list limited to 10 most recent (per item)
- Label dropdown shows max 10 suggestions
- News list capped at 100 items per query

## Contributing

This is a demonstration project. Feel free to:
- Fork and enhance
- Add more features (reactions, threading, notifications)
- Improve security (rate limiting, OAuth, JWT)
- Add monitoring and metrics
- Create additional skills and agents

## License

Demonstration project - use freely

## Links

- **Live Service**: https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com
- **Container Image**: quay.io/krisv/news-service:latest
- **Vulnerability Report**: https://quay.io/repository/krisv/news-service?tab=vulnerabilities
- **Skill**: See .claude/skills/news-service.md
- **Agent**: See .claude/agents/communication-manager.yaml

---

Built with Flask, PostgreSQL, SocketIO, and deployed on OpenShift
