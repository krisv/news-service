"""
Storage abstraction layer for news service
Supports both PostgreSQL and in-memory storage with automatic fallback
"""
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any
import uuid
import threading
import psycopg2
import psycopg2.pool
from psycopg2.extras import RealDictCursor
import yaml
import os


def serialize_datetime(dt: Any) -> str:
    """Convert datetime to ISO format string for JSON serialization"""
    if isinstance(dt, datetime):
        # If timezone-aware, convert to UTC and remove tzinfo
        if dt.tzinfo is not None:
            dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt.isoformat() + 'Z'
    return dt


class StorageBackend(ABC):
    """Abstract base class for storage backends"""

    @abstractmethod
    def create_news_item(self, title: str, content: str, source_url: Optional[str] = None, labels: Optional[List[str]] = None) -> Dict[str, Any]:
        """Create a new news item"""
        pass

    @abstractmethod
    def get_news_items(
        self,
        labels: Optional[List[str]] = None,
        max_results: int = 10,
        last_seen: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Get news items with optional filtering

        Args:
            labels: Filter by labels (returns items with ANY of these labels)
            max_results: Maximum number of results to return
            last_seen: Return only items more recent than this news item ID
        """
        pass

    @abstractmethod
    def get_news_item(self, news_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific news item by ID"""
        pass

    @abstractmethod
    def create_comment(self, news_id: str, name: str, content: str) -> Optional[Dict[str, Any]]:
        """Add a comment to a news item"""
        pass

    @abstractmethod
    def get_comments(self, news_id: str) -> List[Dict[str, Any]]:
        """Get all comments for a news item"""
        pass

    @abstractmethod
    def delete_news_item(self, news_id: str) -> bool:
        """Delete a news item and all its comments"""
        pass

    @abstractmethod
    def delete_comment(self, comment_id: str) -> bool:
        """Delete a specific comment"""
        pass

    @abstractmethod
    def close(self):
        """Close connections and cleanup"""
        pass


class PostgreSQLStorage(StorageBackend):
    """PostgreSQL storage backend"""

    def __init__(self, config: Dict[str, Any]):
        """Initialize PostgreSQL connection pool"""
        self.config = config
        self.pool = psycopg2.pool.ThreadedConnectionPool(
            minconn=config.get('min_connections', 1),
            maxconn=config.get('max_connections', 10),
            host=config['host'],
            port=config['port'],
            database=config['database'],
            user=config['username'],
            password=config['password'],
            connect_timeout=config.get('connection_timeout', 5)
        )
        print(f"✓ Connected to PostgreSQL at {config['host']}:{config['port']}/{config['database']}")

    def _get_conn(self):
        """Get a connection from the pool"""
        return self.pool.getconn()

    def _return_conn(self, conn):
        """Return a connection to the pool"""
        self.pool.putconn(conn)

    def create_news_item(self, title: str, content: str, source_url: Optional[str] = None, labels: Optional[List[str]] = None) -> Dict[str, Any]:
        """Create a new news item"""
        news_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat() + 'Z'
        labels = labels or []

        conn = self._get_conn()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO news_items (id, title, content, source_url, labels, timestamp)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING id, title, content, source_url, labels, timestamp
                    """,
                    (news_id, title, content, source_url, labels, timestamp)
                )
                result = dict(cur.fetchone())
                conn.commit()

                # Convert timestamp to ISO string
                result['timestamp'] = serialize_datetime(result.get('timestamp'))

                # Add empty comments array
                result['comments'] = []
                return result
        finally:
            self._return_conn(conn)

    def get_news_items(
        self,
        labels: Optional[List[str]] = None,
        max_results: int = 10,
        last_seen: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Get news items with optional filtering"""
        conn = self._get_conn()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Build query with filters
                query = "SELECT id, title, content, source_url, labels, timestamp FROM news_items WHERE 1=1"
                params = []

                # Filter by labels (OR condition - any matching label)
                if labels:
                    query += " AND labels && %s"
                    params.append(labels)

                # Filter by last_seen (only items newer than this one)
                if last_seen:
                    # Get the timestamp of the last_seen item
                    cur.execute("SELECT timestamp FROM news_items WHERE id = %s", (last_seen,))
                    row = cur.fetchone()
                    if row:
                        query += " AND timestamp > %s"
                        params.append(row['timestamp'])

                # Order and limit
                query += " ORDER BY timestamp DESC LIMIT %s"
                params.append(max_results)

                cur.execute(query, params)
                items = [dict(row) for row in cur.fetchall()]

                # Convert timestamps to ISO strings and fetch comments
                for item in items:
                    item['timestamp'] = serialize_datetime(item.get('timestamp'))
                    item['comments'] = self.get_comments(item['id'])

                return items
        finally:
            self._return_conn(conn)

    def get_news_item(self, news_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific news item by ID"""
        conn = self._get_conn()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, title, content, source_url, labels, timestamp FROM news_items WHERE id = %s",
                    (news_id,)
                )
                row = cur.fetchone()
                if row:
                    item = dict(row)
                    # Convert timestamp to ISO string
                    item['timestamp'] = serialize_datetime(item.get('timestamp'))
                    item['comments'] = self.get_comments(news_id)
                    return item
                return None
        finally:
            self._return_conn(conn)

    def create_comment(self, news_id: str, name: str, content: str) -> Optional[Dict[str, Any]]:
        """Add a comment to a news item"""
        # Check if news item exists
        if not self.get_news_item(news_id):
            return None

        comment_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat() + 'Z'

        conn = self._get_conn()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO comments (id, news_id, name, content, timestamp)
                    VALUES (%s, %s, %s, %s, %s)
                    RETURNING id, name, content, timestamp
                    """,
                    (comment_id, news_id, name, content, timestamp)
                )
                result = dict(cur.fetchone())
                conn.commit()

                # Convert timestamp to ISO string
                result['timestamp'] = serialize_datetime(result.get('timestamp'))

                return result
        finally:
            self._return_conn(conn)

    def get_comments(self, news_id: str) -> List[Dict[str, Any]]:
        """Get all comments for a news item"""
        conn = self._get_conn()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, name, content, timestamp FROM comments WHERE news_id = %s ORDER BY timestamp DESC",
                    (news_id,)
                )
                comments = [dict(row) for row in cur.fetchall()]

                # Convert timestamps to ISO strings
                for comment in comments:
                    comment['timestamp'] = serialize_datetime(comment.get('timestamp'))

                return comments
        finally:
            self._return_conn(conn)

    def delete_news_item(self, news_id: str) -> bool:
        """Delete a news item and all its comments (CASCADE handles comments)"""
        conn = self._get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM news_items WHERE id = %s", (news_id,))
                deleted = cur.rowcount > 0
                conn.commit()
                return deleted
        finally:
            self._return_conn(conn)

    def delete_comment(self, comment_id: str) -> bool:
        """Delete a specific comment"""
        conn = self._get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM comments WHERE id = %s", (comment_id,))
                deleted = cur.rowcount > 0
                conn.commit()
                return deleted
        finally:
            self._return_conn(conn)

    def close(self):
        """Close connection pool"""
        if hasattr(self, 'pool'):
            self.pool.closeall()
            print("✓ PostgreSQL connection pool closed")


class InMemoryStorage(StorageBackend):
    """In-memory storage backend (original implementation)"""

    def __init__(self):
        """Initialize in-memory storage"""
        self.news_items: Dict[str, Dict[str, Any]] = {}
        self.lock = threading.Lock()
        self._initialize_default_news()
        print("✓ Using in-memory storage (fallback mode)")

    def _get_timestamp(self):
        """Get current timestamp in ISO format"""
        return datetime.utcnow().isoformat() + 'Z'

    def _initialize_default_news(self):
        """Initialize default news items"""
        with self.lock:
            if len(self.news_items) == 0:
                # Red Hat AI Enterprise news
                news_id_1 = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
                self.news_items[news_id_1] = {
                    'id': news_id_1,
                    'title': 'Red Hat Launches AI Enterprise Platform',
                    'content': 'Red Hat has introduced Red Hat AI Enterprise, a unified artificial intelligence platform that spans infrastructure from metal to intelligent agents. This comprehensive solution integrates AI capabilities across the entire technology stack, enabling organizations to deploy and manage AI workloads seamlessly. The platform represents Red Hat\'s commitment to democratizing enterprise AI through open technologies and hybrid cloud architectures.',
                    'source_url': 'https://www.redhat.com/en/about/press-releases/red-hat-launches-red-hat-ai-enterprise-deliver-unified-ai-platform-spans-metal-agents',
                    'labels': ['topic:AI', 'company:Red Hat', 'type:press-release'],
                    'timestamp': '2026-02-24T10:00:00Z',
                    'comments': [
                        {
                            'id': str(uuid.uuid4()),
                            'name': 'Alex Thompson',
                            'content': 'This is huge for enterprise AI adoption. Red Hat\'s open approach could be a game changer.',
                            'timestamp': self._get_timestamp()
                        },
                        {
                            'id': str(uuid.uuid4()),
                            'name': 'Maria Garcia',
                            'content': 'Finally, an AI platform that spans the full stack. Looking forward to testing this out!',
                            'timestamp': self._get_timestamp()
                        }
                    ]
                }

                # OpenClaw news
                news_id_2 = 'b2c3d4e5-f6a7-4b5c-9d0e-1f2a3b4c5d6e'
                self.news_items[news_id_2] = {
                    'id': news_id_2,
                    'title': 'OpenClaw Creator Joins OpenAI',
                    'content': 'Peter Steinberger, creator of the AI agent project OpenClaw, announced he is joining OpenAI to advance agent technology accessibility. OpenClaw, described as a playground project that created waves in the AI community, will transition to an independent foundation while remaining open-source. Steinberger stated his goal is to build an agent that even my mum can use, prioritizing widespread adoption of AI agents over commercializing the project independently.',
                    'source_url': 'https://steipete.me/posts/2026/openclaw',
                    'labels': ['topic:AI', 'topic:Agents', 'company:OpenAI', 'technology:OpenClaw', 'type:blog-post'],
                    'timestamp': '2026-02-14T09:00:00Z',
                    'comments': [
                        {
                            'id': str(uuid.uuid4()),
                            'name': 'Jordan Lee',
                            'content': 'Great move! OpenClaw has been impressive. Excited to see what Peter builds at OpenAI.',
                            'timestamp': self._get_timestamp()
                        }
                    ]
                }

                print(f"Initialized {len(self.news_items)} default news items")

    def create_news_item(self, title: str, content: str, source_url: Optional[str] = None, labels: Optional[List[str]] = None) -> Dict[str, Any]:
        """Create a new news item"""
        news_id = str(uuid.uuid4())
        timestamp = self._get_timestamp()
        labels = labels or []

        news_item = {
            'id': news_id,
            'title': title,
            'content': content,
            'source_url': source_url,
            'labels': labels,
            'timestamp': timestamp,
            'comments': []
        }

        with self.lock:
            self.news_items[news_id] = news_item

        return news_item

    def get_news_items(
        self,
        labels: Optional[List[str]] = None,
        max_results: int = 10,
        last_seen: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Get news items with optional filtering"""
        with self.lock:
            items = list(self.news_items.values())

        # Filter by labels (OR condition - any matching label)
        if labels:
            items = [
                item for item in items
                if any(label in item.get('labels', []) for label in labels)
            ]

        # Filter by last_seen
        if last_seen:
            last_seen_item = next((item for item in items if item['id'] == last_seen), None)
            if last_seen_item:
                last_seen_timestamp = last_seen_item['timestamp']
                items = [item for item in items if item['timestamp'] > last_seen_timestamp]

        # Sort by timestamp, newest first
        items.sort(key=lambda x: x['timestamp'], reverse=True)

        # Limit results
        return items[:max_results]

    def get_news_item(self, news_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific news item by ID"""
        with self.lock:
            return self.news_items.get(news_id)

    def create_comment(self, news_id: str, name: str, content: str) -> Optional[Dict[str, Any]]:
        """Add a comment to a news item"""
        with self.lock:
            news_item = self.news_items.get(news_id)

        if not news_item:
            return None

        comment_id = str(uuid.uuid4())
        timestamp = self._get_timestamp()

        comment = {
            'id': comment_id,
            'name': name,
            'content': content,
            'timestamp': timestamp
        }

        with self.lock:
            self.news_items[news_id]['comments'].append(comment)

        return comment

    def get_comments(self, news_id: str) -> List[Dict[str, Any]]:
        """Get all comments for a news item"""
        with self.lock:
            news_item = self.news_items.get(news_id)

        if not news_item:
            return []

        # Return comments sorted by timestamp, newest first
        return sorted(news_item['comments'], key=lambda x: x['timestamp'], reverse=True)

    def delete_news_item(self, news_id: str) -> bool:
        """Delete a news item and all its comments"""
        with self.lock:
            if news_id in self.news_items:
                del self.news_items[news_id]
                return True
            return False

    def delete_comment(self, comment_id: str) -> bool:
        """Delete a specific comment"""
        with self.lock:
            for news_item in self.news_items.values():
                for i, comment in enumerate(news_item['comments']):
                    if comment['id'] == comment_id:
                        news_item['comments'].pop(i)
                        return True
            return False

    def close(self):
        """No cleanup needed for in-memory storage"""
        pass


def create_storage() -> StorageBackend:
    """
    Create and return a storage backend
    Tries PostgreSQL first, falls back to in-memory if connection fails
    """
    # Load configuration
    config_path = os.path.join(os.path.dirname(__file__), 'config.yaml')

    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        db_config = config.get('database', {})

        # Override with environment variables if present
        if os.environ.get('DB_PASSWORD'):
            db_config['password'] = os.environ.get('DB_PASSWORD')
    except Exception as e:
        print(f"⚠ Could not load config.yaml: {e}")
        print("→ Falling back to in-memory storage")
        return InMemoryStorage()

    # Try PostgreSQL
    max_retries = db_config.get('max_retries', 3)
    for attempt in range(max_retries):
        try:
            storage = PostgreSQLStorage(db_config)
            # Test connection by running a simple query
            conn = storage._get_conn()
            try:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                storage._return_conn(conn)
            except:
                storage._return_conn(conn)
                raise
            return storage
        except Exception as e:
            if attempt < max_retries - 1:
                print(f"⚠ PostgreSQL connection attempt {attempt + 1} failed: {e}")
            else:
                print(f"⚠ PostgreSQL connection failed after {max_retries} attempts: {e}")
                print("→ Falling back to in-memory storage")

    # Fallback to in-memory
    return InMemoryStorage()
