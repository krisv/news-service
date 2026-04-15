-- News Service Database Schema
-- PostgreSQL 12+

-- Create database (run manually if needed)
-- CREATE DATABASE news;
-- \c news;

-- News items table
CREATE TABLE IF NOT EXISTS news_items (
    id UUID PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    source_url TEXT,  -- Optional source URL for the news item
    labels TEXT[] DEFAULT '{}',  -- Array of labels for categorization
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Comments table
CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY,
    news_id UUID NOT NULL REFERENCES news_items(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    content TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_news_items_timestamp ON news_items(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_news_items_labels ON news_items USING GIN(labels);
CREATE INDEX IF NOT EXISTS idx_news_items_source_url ON news_items(source_url) WHERE source_url IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_comments_news_id ON comments(news_id);
CREATE INDEX IF NOT EXISTS idx_comments_timestamp ON comments(timestamp DESC);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to automatically update updated_at
DROP TRIGGER IF EXISTS update_news_items_updated_at ON news_items;
CREATE TRIGGER update_news_items_updated_at
    BEFORE UPDATE ON news_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert default news items
INSERT INTO news_items (id, title, content, source_url, labels, timestamp, created_at, updated_at)
VALUES
    (
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        'Red Hat Launches AI Enterprise Platform',
        'Red Hat has introduced Red Hat AI Enterprise, a unified artificial intelligence platform that spans infrastructure from metal to intelligent agents. This comprehensive solution integrates AI capabilities across the entire technology stack, enabling organizations to deploy and manage AI workloads seamlessly. The platform represents Red Hat''s commitment to democratizing enterprise AI through open technologies and hybrid cloud architectures.',
        'https://www.redhat.com/en/about/press-releases/red-hat-launches-red-hat-ai-enterprise-deliver-unified-ai-platform-spans-metal-agents',
        ARRAY['topic:AI', 'company:Red Hat', 'type:press-release'],
        '2026-02-24T10:00:00Z',
        '2026-02-24T10:00:00Z',
        '2026-02-24T10:00:00Z'
    ),
    (
        'b2c3d4e5-f6a7-4b5c-9d0e-1f2a3b4c5d6e',
        'OpenClaw Creator Joins OpenAI',
        'Peter Steinberger, creator of the AI agent project OpenClaw, announced he is joining OpenAI to advance agent technology accessibility. OpenClaw, described as a playground project that created waves in the AI community, will transition to an independent foundation while remaining open-source. Steinberger stated his goal is to build an agent that even my mum can use, prioritizing widespread adoption of AI agents over commercializing the project independently.',
        'https://steipete.me/posts/2026/openclaw',
        ARRAY['topic:AI', 'topic:Agents', 'company:OpenAI', 'technology:OpenClaw', 'type:blog-post'],
        '2026-02-14T09:00:00Z',
        '2026-02-14T09:00:00Z',
        '2026-02-14T09:00:00Z'
    )
ON CONFLICT (id) DO NOTHING;

-- Insert default comments
INSERT INTO comments (id, news_id, name, content, timestamp)
VALUES
    (
        gen_random_uuid(),
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        'Alex Thompson',
        'This is huge for enterprise AI adoption. Red Hat''s open approach could be a game changer.',
        NOW()
    ),
    (
        gen_random_uuid(),
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        'Maria Garcia',
        'Finally, an AI platform that spans the full stack. Looking forward to testing this out!',
        NOW()
    ),
    (
        gen_random_uuid(),
        'b2c3d4e5-f6a7-4b5c-9d0e-1f2a3b4c5d6e',
        'Jordan Lee',
        'Great move! OpenClaw has been impressive. Excited to see what Peter builds at OpenAI.',
        NOW()
    )
ON CONFLICT (id) DO NOTHING;
