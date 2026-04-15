"""
News Service - Flask application with real-time updates
Supports PostgreSQL with automatic fallback to in-memory storage
"""
from flask import Flask, request, jsonify, render_template
from flask_socketio import SocketIO, emit
from flask_cors import CORS
from storage import create_storage
import atexit
import yaml
import os
from functools import wraps

app = Flask(__name__)
app.config['SECRET_KEY'] = 'news-service-secret-key'
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Initialize storage backend (PostgreSQL with in-memory fallback)
storage = create_storage()

# Load configuration for API key
config_path = os.path.join(os.path.dirname(__file__), 'config.yaml')
api_key = None
try:
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
        api_key = config.get('security', {}).get('api_key', '')

        # Override with environment variable if present
        if os.environ.get('API_KEY'):
            api_key = os.environ.get('API_KEY')

        if api_key:
            print(f"✓ API key authentication enabled")
        else:
            print("⚠ API key authentication disabled (no key configured)")
except Exception as e:
    print(f"⚠ Could not load API key from config: {e}")

# API key authentication decorator
def require_api_key(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Skip authentication if no API key is configured
        if not api_key:
            return f(*args, **kwargs)

        # Check for API key in header
        provided_key = request.headers.get('X-API-Key')
        if not provided_key or provided_key != api_key:
            return jsonify({'error': 'Invalid or missing API key'}), 401

        return f(*args, **kwargs)
    return decorated_function

# Cleanup on exit
@atexit.register
def cleanup():
    storage.close()


@app.route('/')
def index():
    """Serve the main UI"""
    return render_template('index.html')


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for OpenShift"""
    return jsonify({'status': 'healthy', 'service': 'news-service'}), 200


@app.route('/api/news', methods=['POST'])
@require_api_key
def create_news():
    """Create a new news item with optional source URL and labels"""
    data = request.get_json()

    if not data or 'title' not in data or 'content' not in data:
        return jsonify({'error': 'Title and content are required'}), 400

    # Extract source_url (optional)
    source_url = data.get('source_url', None)

    # Extract labels (optional)
    labels = data.get('labels', [])
    if not isinstance(labels, list):
        return jsonify({'error': 'Labels must be an array'}), 400

    news_item = storage.create_news_item(
        title=data['title'],
        content=data['content'],
        source_url=source_url,
        labels=labels
    )

    # Broadcast new news item via WebSocket
    socketio.emit('new_news', news_item)

    return jsonify(news_item), 201


@app.route('/api/news', methods=['GET'])
def get_news():
    """
    Get news items with optional filtering

    Query parameters:
    - labels: Comma-separated list of labels to filter by (OR condition)
    - max_results: Maximum number of results (default: 10)
    - last_seen: News item ID - return only items more recent than this
    """
    # Parse query parameters
    labels_param = request.args.get('labels', '')
    labels = [label.strip() for label in labels_param.split(',') if label.strip()] if labels_param else None

    max_results = request.args.get('max_results', 10, type=int)
    if max_results < 1:
        max_results = 10
    if max_results > 100:
        max_results = 100  # Cap at 100 for performance

    last_seen = request.args.get('last_seen', None)

    # Get items from storage
    items = storage.get_news_items(
        labels=labels,
        max_results=max_results,
        last_seen=last_seen
    )

    return jsonify(items), 200


@app.route('/api/news/<news_id>', methods=['GET'])
def get_news_item(news_id):
    """Get a specific news item"""
    news_item = storage.get_news_item(news_id)

    if not news_item:
        return jsonify({'error': 'News item not found'}), 404

    return jsonify(news_item), 200


@app.route('/api/news/<news_id>/comments', methods=['POST'])
def create_comment(news_id):
    """Add a comment to a news item"""
    data = request.get_json()

    if not data or 'content' not in data or 'name' not in data:
        return jsonify({'error': 'Comment content and name are required'}), 400

    comment = storage.create_comment(
        news_id=news_id,
        name=data['name'],
        content=data['content']
    )

    if not comment:
        return jsonify({'error': 'News item not found'}), 404

    # Broadcast new comment via WebSocket
    socketio.emit('new_comment', {
        'news_id': news_id,
        'comment': comment
    })

    return jsonify(comment), 201


@app.route('/api/news/<news_id>/comments', methods=['GET'])
def get_comments(news_id):
    """Get all comments for a news item"""
    news_item = storage.get_news_item(news_id)

    if not news_item:
        return jsonify({'error': 'News item not found'}), 404

    comments = storage.get_comments(news_id)

    return jsonify(comments), 200


@app.route('/api/news/<news_id>', methods=['DELETE'])
@require_api_key
def delete_news(news_id):
    """Delete a news item and all its comments"""
    deleted = storage.delete_news_item(news_id)

    if not deleted:
        return jsonify({'error': 'News item not found'}), 404

    # Broadcast deletion via WebSocket
    socketio.emit('delete_news', {'news_id': news_id})

    return jsonify({'message': 'News item deleted'}), 200


@app.route('/api/news/<news_id>/comments/<comment_id>', methods=['DELETE'])
@require_api_key
def delete_comment(news_id, comment_id):
    """Delete a specific comment"""
    deleted = storage.delete_comment(comment_id)

    if not deleted:
        return jsonify({'error': 'Comment not found'}), 404

    # Broadcast deletion via WebSocket
    socketio.emit('delete_comment', {
        'news_id': news_id,
        'comment_id': comment_id
    })

    return jsonify({'message': 'Comment deleted'}), 200


@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connection"""
    print(f'Client connected: {request.sid}')


@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnection"""
    print(f'Client disconnected: {request.sid}')


if __name__ == '__main__':
    # Run with SocketIO for development
    socketio.run(app, host='0.0.0.0', port=8080, debug=True)
