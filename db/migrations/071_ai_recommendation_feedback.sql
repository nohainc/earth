CREATE TABLE ai_recommendation_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  human_id TEXT NOT NULL REFERENCES humans(id),
  recommendation_type TEXT NOT NULL CHECK (recommendation_type IN ('decision_queue','objective','briefing')),
  recommendation_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('approved','dismissed','deferred','viewed')),
  context_snapshot JSONB,
  game_day INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_rec_feedback_human ON ai_recommendation_feedback(human_id, created_at DESC);
