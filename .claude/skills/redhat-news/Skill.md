---
name: redhat-news
description: Monitor Red Hat news - fetch articles, post comments, track processed items
---

# Red Hat News Monitoring

Automated script that monitors news, identifies new articles, and logs activity.

## Label System

News articles use categorized labels with the format `category:value`:

- **topic:** - Subject areas (e.g., `topic:AI`, `topic:Cloud`, `topic:Security`)
- **company:** - Organizations (e.g., `company:Red Hat`, `company:OpenAI`)
- **technology:** - Specific tools/projects (e.g., `technology:OpenClaw`, `technology:Kubernetes`)
- **type:** - Content types (e.g., `type:press-release`, `type:blog-post`, `type:tweet`)

**Filtering:** Use the full label including category when filtering (e.g., `--labels "topic:AI,company:Red Hat"`).

## Usage

### 1. Fetch News (session ID auto-generated)
```bash
python .claude/skills/redhat-news/news_monitor.py
```

Returns a session ID like `20260401-134530`.

**With filters:**
```bash
# Filter by topic
python .claude/skills/redhat-news/news_monitor.py --labels "topic:AI" --max-results 20

# Filter by multiple categories
python .claude/skills/redhat-news/news_monitor.py --labels "topic:AI,company:Red Hat"

# Filter by content type
python .claude/skills/redhat-news/news_monitor.py --labels "type:blog-post"
```

### 2. Post Comment
```bash
python .claude/skills/redhat-news/news_monitor.py --session-id 20260401-134530 --post-comment ARTICLE_ID "Comment text"
```

### 3. Send Log (with memory update)
```bash
python .claude/skills/redhat-news/news_monitor.py --send-log 20260401-134530 --with-memory MOST_RECENT_ARTICLE_ID
```

## Example

```bash
# Fetch news (generates session ID)
python .claude/skills/redhat-news/news_monitor.py
# Output: Session ID: 20260401-134530

# Fetch only AI-related articles
python .claude/skills/redhat-news/news_monitor.py --labels "topic:AI,topic:Agents" --max-results 5

# Fetch Red Hat company news
python .claude/skills/redhat-news/news_monitor.py --labels "company:Red Hat"

# Post comment
python .claude/skills/redhat-news/news_monitor.py --session-id 20260401-134530 \
  --post-comment "abc-123" "Great article!"

# Send log and mark most recent article as last seen
python .claude/skills/redhat-news/news_monitor.py --send-log 20260401-134530 \
  --with-memory "abc-123"
```

## What It Does

- Fetches articles from News Service API with optional label filtering
- Checks `article_memory.json` for last seen article
- Identifies new articles since last seen (newest-first order)
- Supports filtering by categorized labels and limiting results
- Logs all operations to readable text files `logs/task-news-YYYYMMDD-HHMMSS.log`
- Submits to Agent Inbox on `--send-log` (constructs JSON from log file)

## Files

- **Script**: `.claude/skills/redhat-news/news_monitor.py`
- **Memory**: `article_memory.json` (last seen article ID)
- **Logs**: `logs/task-news-YYYYMMDD-HHMMSS.log` (plain text format)
