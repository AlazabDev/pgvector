BEGIN;
CREATE TABLE maintenance_kb.maintenance_service_embeddings (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  service_item_id bigint NOT NULL REFERENCES maintenance_kb.maintenance_service_items(id) ON DELETE CASCADE,
  model_name text NOT NULL,
  model_version text,
  content_hash text NOT NULL,
  content_text text NOT NULL,
  embedding vector,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (service_item_id, model_name, content_hash)
);
COMMIT;

