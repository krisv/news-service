#!/usr/bin/env python3
"""
Red Hat News Monitoring Script

Usage:
    python news_monitor.py --session-id SESSION_ID
    python news_monitor.py --session-id SESSION_ID --post-comment ARTICLE_ID "Comment"
    python news_monitor.py --send-log SESSION_ID --with-memory ARTICLE_ID [...]
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional
import urllib.request
import urllib.error
from urllib.parse import urljoin


# Configuration
NEWS_SERVICE_BASE_URL = "https://news-service-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com"
AGENT_INBOX_BASE_URL = "https://agent-inbox-kverlaen-dev.apps.rm2.thpm.p1.openshiftapps.com"

# File paths (relative to project root)
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent
MEMORY_FILE = PROJECT_ROOT / "article_memory.json"
LOGS_DIR = PROJECT_ROOT / "logs"


class NewsMonitor:
    """News monitoring and commenting system"""

    def __init__(self, verbose: bool = False, session_id: Optional[str] = None):
        """Initialize the news monitor"""
        self.verbose = verbose
        self.session_id = session_id or datetime.now().strftime("%Y%m%d-%H%M%S")
        self.setup_logging()
        self.execution_log = []  # Detailed execution trace
        self.log_file_path = None

    def setup_logging(self):
        """Configure logging"""
        level = logging.DEBUG if self.verbose else logging.INFO
        logging.basicConfig(
            level=level,
            format='%(levelname)s: %(message)s'
        )
        self.logger = logging.getLogger(__name__)

    def log_step(self, step_type: str, message: str):
        """Log an execution step"""
        self.execution_log.append(f"{step_type}: {message}")
        if self.verbose:
            self.logger.debug(f"{step_type}: {message}")

    def fetch_news(self, labels: Optional[List[str]] = None, max_results: int = 10) -> List[Dict[str, Any]]:
        """Fetch news articles from the service with optional filtering"""
        url = f"{NEWS_SERVICE_BASE_URL}/api/news"

        # Build query parameters
        params = []
        if labels:
            params.append(f"labels={','.join(labels)}")
        if max_results:
            params.append(f"max_results={max_results}")

        if params:
            url += "?" + "&".join(params)

        self.log_step("TOOL CALL", f"GET {url}")

        try:
            with urllib.request.urlopen(url, timeout=10) as response:
                articles = json.loads(response.read().decode())

                # Log result with truncated response
                result_preview = json.dumps(articles, indent=2)
                result_lines = result_preview.split('\n')
                if len(result_lines) > 10:
                    result_preview = '\n'.join(result_lines[:10]) + f"\n... ({len(result_lines) - 10} more lines)"

                self.log_step("TOOL RESULT", f"Retrieved {len(articles)} articles\n{result_preview}")
                return articles
        except urllib.error.URLError as e:
            self.log_step("ERROR", f"Failed to fetch news: {e}")
            raise
        except json.JSONDecodeError as e:
            self.log_step("ERROR", f"Invalid JSON response: {e}")
            raise

    def load_memory(self) -> Optional[str]:
        """Load last seen article ID from memory file"""
        self.log_step("TOOL CALL", f"Read memory file: article_memory.json")

        if not MEMORY_FILE.exists():
            self.log_step("TOOL RESULT", "Memory file does not exist, no last seen article")
            return None

        try:
            with open(MEMORY_FILE, 'r') as f:
                memory = json.load(f)
                last_seen = memory.get('last_seen_article_id')
                self.log_step("TOOL RESULT", f"Last seen article: {last_seen or 'none'}")
                return last_seen
        except (json.JSONDecodeError, IOError) as e:
            self.log_step("ERROR", f"Failed to read memory file: {e}")
            return None

    def save_memory(self, last_article_id: str):
        """Save last seen article ID to memory file"""
        self.log_step("TOOL CALL", f"Write memory file: article_memory.json")

        try:
            MEMORY_FILE.parent.mkdir(parents=True, exist_ok=True)
            memory = {"last_seen_article_id": last_article_id}
            with open(MEMORY_FILE, 'w') as f:
                json.dump(memory, f, indent=2)
            self.log_step("TOOL RESULT", f"Saved last seen article ID: {last_article_id}")
        except IOError as e:
            self.log_step("ERROR", f"Failed to write memory file: {e}")
            raise

    def identify_new_articles(self, articles: List[Dict[str, Any]], last_seen_id: Optional[str]) -> List[Dict[str, Any]]:
        """Identify new articles since last seen (articles are newest-first order)"""
        if not last_seen_id:
            self.log_step("THINKING", f"No last seen article, all {len(articles)} articles are new")
            return articles

        self.log_step("THINKING", f"Finding new articles since last seen: {last_seen_id}")

        new_articles = []
        for article in articles:
            article_id = article.get('id')

            # Stop when we reach the last seen article
            if article_id == last_seen_id:
                self.log_step("THINKING", f"Reached last seen article, found {len(new_articles)} new articles")
                break

            # Add all articles before last seen
            new_articles.append(article)

        self.log_step("THINKING", f"Found {len(new_articles)} new articles")
        return new_articles

    def post_comment(self, article_id: str, comment_content: str, commenter_name: str = "Claude") -> Dict[str, Any]:
        """Post a comment on a news article"""
        url = f"{NEWS_SERVICE_BASE_URL}/api/news/{article_id}/comments"

        comment_data = {
            "name": commenter_name,
            "content": comment_content
        }

        # Log the full request
        request_data = json.dumps(comment_data, indent=2)
        self.log_step("TOOL CALL", f"POST {url}\nPayload:\n{request_data}")

        try:
            data = json.dumps(comment_data).encode('utf-8')
            req = urllib.request.Request(
                url,
                data=data,
                headers={'Content-Type': 'application/json'},
                method='POST'
            )

            with urllib.request.urlopen(req, timeout=10) as response:
                result = json.loads(response.read().decode())

                # Log result with truncated response
                result_preview = json.dumps(result, indent=2)
                result_lines = result_preview.split('\n')
                if len(result_lines) > 10:
                    result_preview = '\n'.join(result_lines[:10]) + f"\n... ({len(result_lines) - 10} more lines)"

                comment_id = result.get('id')
                self.log_step("TOOL RESULT", f"Comment posted successfully\nComment ID: {comment_id}\nResponse:\n{result_preview}")
                return result
        except urllib.error.HTTPError as e:
            error_msg = e.read().decode() if e.fp else str(e)
            self.log_step("ERROR", f"Failed to post comment: {e.code} - {error_msg}")
            raise
        except urllib.error.URLError as e:
            self.log_step("ERROR", f"Network error posting comment: {e}")
            raise

    def format_article_summary(self, articles: List[Dict[str, Any]], new_articles: List[Dict[str, Any]]) -> str:
        """Format articles as a readable summary"""
        lines = []
        lines.append(f"Total articles: {len(articles)}")
        lines.append(f"New articles: {len(new_articles)}")
        lines.append("")

        if not new_articles:
            lines.append("No new articles to process.")
            return "\n".join(lines)

        lines.append("NEW ARTICLES:")
        lines.append("=" * 80)

        for i, article in enumerate(new_articles, 1):
            lines.append(f"\n[{i}] {article.get('title', 'Untitled')}")
            lines.append(f"    ID: {article.get('id')}")
            lines.append(f"    Published: {article.get('timestamp', 'Unknown')}")

            # Show content preview (first 200 chars)
            content = article.get('content', '')
            if len(content) > 200:
                content = content[:200] + "..."
            lines.append(f"    Content: {content}")

            # Show existing comments
            comments = article.get('comments', [])
            if comments:
                lines.append(f"    Comments ({len(comments)}):")
                for comment in comments[:3]:  # Show max 3 comments
                    lines.append(f"      - {comment.get('name')}: {comment.get('content')[:100]}")
            else:
                lines.append("    Comments: None")

            lines.append("")

        return "\n".join(lines)


    def get_log_file_path(self) -> Path:
        """Get the log file path for the current session"""
        if self.log_file_path is None:
            LOGS_DIR.mkdir(parents=True, exist_ok=True)
            self.log_file_path = LOGS_DIR / f"task-news-{self.session_id}.log"
        return self.log_file_path

    def save_reasoning_log(self) -> Path:
        """Save reasoning/execution trace to log file as plain text"""
        log_file = self.get_log_file_path()

        # Check if this is the first write to the log
        is_new_log = not log_file.exists()

        # Generate reasoning text
        if is_new_log:
            # Include full header for new log files
            reasoning = "\n\n".join([
                "Agent Instruction:",
                "Monitor Red Hat News Service for new articles and post comments.",
                "",
                "Workflow:",
                "1. Fetch news articles",
                "2. Check local memory for last seen article",
                "3. Show new articles since last seen",
                "4. Post comments on articles user selects",
                "5. Send log to Agent Inbox and update memory",
                "",
                "INPUT: Automated execution",
                "",
            ] + self.execution_log + [
                "",
                "OUTPUT: See above execution trace"
            ])
        else:
            # Just append execution log for subsequent operations
            reasoning = "\n\n".join(self.execution_log + [
                "",
                "OUTPUT: See above execution trace"
            ])

        # Load existing log if present and append
        if is_new_log:
            self.log_step("TOOL CALL", f"Write new log file: {log_file}")
            full_reasoning = reasoning
        else:
            self.log_step("TOOL CALL", f"Append to log file: {log_file}")
            with open(log_file, 'r') as f:
                existing_reasoning = f.read()
            # Append new reasoning with separator
            full_reasoning = existing_reasoning + "\n\n" + "=" * 80 + "\n\n" + reasoning

        with open(log_file, 'w') as f:
            f.write(full_reasoning)

        self.log_step("TOOL RESULT", f"Reasoning log saved to {log_file}")
        return log_file


    def run_monitoring(self, labels: Optional[List[str]] = None, max_results: int = 10) -> Dict[str, Any]:
        """Run the news monitoring workflow"""
        self.log_step("INPUT", "Automated news monitoring execution")

        # Fetch news
        if labels:
            self.log_step("THINKING", f"Fetching latest news articles filtered by labels: {', '.join(labels)}")
        else:
            self.log_step("THINKING", "Fetching latest news articles")
        articles = self.fetch_news(labels=labels, max_results=max_results)

        # Load memory
        self.log_step("THINKING", "Loading last seen article from memory")
        last_seen = self.load_memory()

        # Identify new articles
        self.log_step("THINKING", "Identifying new articles since last seen")
        new_articles = self.identify_new_articles(articles, last_seen)

        # Generate summary
        summary = self.format_article_summary(articles, new_articles)
        self.log_step("OUTPUT", summary)

        # Save reasoning log
        log_file = self.save_reasoning_log()

        return {
            "articles": articles,
            "new_articles": new_articles,
            "summary": summary,
            "log_file": str(log_file)
        }


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Red Hat News Monitoring Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example workflow:
  python news_monitor.py --session-id my-session
  python news_monitor.py --session-id my-session --post-comment ARTICLE_ID "Comment"
  python news_monitor.py --send-log my-session --with-memory ARTICLE_ID
        """
    )

    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose logging'
    )

    parser.add_argument(
        '--session-id',
        metavar='SESSION_ID',
        help='Session ID to group operations into one log file'
    )

    parser.add_argument(
        '--send-log',
        metavar='SESSION_ID',
        help='Send log to Agent Inbox and optionally update memory'
    )

    parser.add_argument(
        '--with-memory',
        metavar='ARTICLE_ID',
        help='Most recent article ID to mark as last seen when using --send-log'
    )

    parser.add_argument(
        '--post-comment',
        nargs=2,
        metavar=('ARTICLE_ID', 'COMMENT'),
        help='Post a comment on a specific article'
    )

    parser.add_argument(
        '--labels',
        metavar='LABELS',
        help='Comma-separated list of labels to filter by (e.g., "AI,Red Hat")'
    )

    parser.add_argument(
        '--max-results',
        type=int,
        default=10,
        metavar='N',
        help='Maximum number of results to return (default: 10, max: 100)'
    )

    args = parser.parse_args()

    # Handle send-log separately (doesn't need full monitor initialization)
    if args.send_log:
        session_id = args.send_log
        log_file = LOGS_DIR / f"task-news-{session_id}.log"

        if not log_file.exists():
            print(f"[ERROR] Log file not found: {log_file}", file=sys.stderr)
            return 1

        try:
            # Update memory if article ID provided
            if args.with_memory:
                last_seen_id = args.with_memory
                print(f"Updating memory with last seen article: {last_seen_id}")

                MEMORY_FILE.parent.mkdir(parents=True, exist_ok=True)
                memory = {"last_seen_article_id": last_seen_id}
                with open(MEMORY_FILE, 'w') as f:
                    json.dump(memory, f, indent=2)
                print(f"[OK] Updated last seen article ID")

            # Load reasoning from log file
            with open(log_file, 'r') as f:
                reasoning = f.read()

            print(f"Sending log to Agent Inbox...")

            # Construct task JSON with hardcoded values and datetime from filename
            task_log = {
                "id": f"task-news-{session_id}",
                "title": f"News Monitoring - {session_id}",
                "agent_id": "claude",
                "agent_name": "Claude",
                "agent_description": "News monitoring agent that posts comments on Red Hat news articles",
                "status": "completed",
                "reasoning": reasoning
            }

            # Submit to Agent Inbox
            url = f"{AGENT_INBOX_BASE_URL}/api/tasks"
            data = json.dumps(task_log).encode('utf-8')
            req = urllib.request.Request(
                url,
                data=data,
                headers={'Content-Type': 'application/json'},
                method='POST'
            )

            with urllib.request.urlopen(req, timeout=10) as response:
                result = json.loads(response.read().decode())
                print(f"[OK] Log submitted to Agent Inbox")
                return 0

        except FileNotFoundError:
            print(f"[ERROR] Log file not found: {log_file}", file=sys.stderr)
            return 1
        except urllib.error.HTTPError as e:
            error_msg = e.read().decode() if e.fp else str(e)
            print(f"[ERROR] Failed to submit: {e.code} - {error_msg}", file=sys.stderr)
            return 1
        except Exception as e:
            print(f"[ERROR] {e}", file=sys.stderr)
            return 1

    # Initialize monitor
    monitor = NewsMonitor(verbose=args.verbose, session_id=args.session_id)

    try:
        # Handle comment posting
        if args.post_comment:
            article_id, comment = args.post_comment
            monitor.log_step("INPUT", f"Post comment on article {article_id}")
            print(f"Posting comment on article {article_id}...")

            result = monitor.post_comment(article_id, comment)
            print(f"[OK] Comment posted successfully!")
            print(f"  Comment ID: {result.get('id')}")
            print(f"  Timestamp: {result.get('timestamp')}")

            # Log output
            monitor.log_step("OUTPUT", f"Posted comment on article {article_id}, Comment ID: {result.get('id')}")

            # Save reasoning log
            log_file = monitor.save_reasoning_log()

            print(f"[OK] Log updated: {log_file}")
            print(f"[INFO] Session ID: {monitor.session_id}")

            return 0

        # Run monitoring
        # Parse labels
        labels = None
        if args.labels:
            labels = [label.strip() for label in args.labels.split(',')]

        # Validate max_results
        max_results = args.max_results
        if max_results < 1:
            max_results = 10
        if max_results > 100:
            max_results = 100

        print("Fetching Red Hat news...")
        result = monitor.run_monitoring(labels=labels, max_results=max_results)

        # Display summary
        print("\n" + "=" * 80)
        print(result['summary'])
        print("=" * 80)
        print(f"\n[OK] Log saved: {result['log_file']}")
        print(f"[INFO] Session ID: {monitor.session_id}")

        return 0

    except Exception as e:
        print(f"\n[ERROR] {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
