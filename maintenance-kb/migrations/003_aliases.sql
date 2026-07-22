BEGIN;
CREATE TABLE maintenance_kb.maintenance_service_aliases (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  service_item_id bigint NOT NULL REFERENCES maintenance_kb.maintenance_service_items(id) ON DELETE CASCADE,
  alias_text text NOT NULL CHECK (btrim(alias_text) <> ''),
  normalized_alias text NOT NULL UNIQUE CHECK (btrim(normalized_alias) <> ''),
  source text,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMIT;

