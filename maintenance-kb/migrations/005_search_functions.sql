BEGIN;
CREATE INDEX maintenance_items_name_trgm ON maintenance_kb.maintenance_service_items USING gin (normalized_name gin_trgm_ops);
CREATE INDEX maintenance_alias_trgm ON maintenance_kb.maintenance_service_aliases USING gin (normalized_alias gin_trgm_ops);

CREATE OR REPLACE FUNCTION maintenance_kb.hybrid_search(query_text text, query_embedding vector DEFAULT NULL, result_limit integer DEFAULT 10)
RETURNS TABLE(item_code text, item_name text, category_name text, match_method text, score double precision)
LANGUAGE sql STABLE SET search_path = maintenance_kb, public AS $$
WITH candidates AS (
  SELECT i.id, i.item_code, i.item_name, c.category_name,
    CASE
      WHEN lower(i.item_code) = lower(query_text) THEN 'item_code'
      WHEN i.normalized_name = lower(btrim(query_text)) THEN 'exact_name'
      WHEN EXISTS (SELECT 1 FROM maintenance_service_aliases a WHERE a.service_item_id=i.id AND a.normalized_alias=lower(btrim(query_text))) THEN 'alias'
      WHEN query_embedding IS NOT NULL AND e.embedding IS NOT NULL THEN 'vector'
      ELSE 'text'
    END AS match_method,
    GREATEST(
      CASE WHEN lower(i.item_code)=lower(query_text) THEN 1.0 ELSE 0 END,
      CASE WHEN i.normalized_name=lower(btrim(query_text)) THEN 0.98 ELSE similarity(i.normalized_name, lower(query_text))*0.8 END,
      COALESCE((SELECT max(CASE WHEN a.normalized_alias=lower(btrim(query_text)) THEN 0.96 ELSE similarity(a.normalized_alias,lower(query_text))*0.75 END) FROM maintenance_service_aliases a WHERE a.service_item_id=i.id),0),
      CASE WHEN query_embedding IS NOT NULL AND e.embedding IS NOT NULL THEN (1-(e.embedding <=> query_embedding))*0.7 ELSE 0 END
    )::double precision AS score
  FROM maintenance_service_items i
  JOIN maintenance_categories c ON c.id=i.category_id
  LEFT JOIN LATERAL (SELECT embedding FROM maintenance_service_embeddings x WHERE x.service_item_id=i.id ORDER BY x.updated_at DESC LIMIT 1) e ON true
  WHERE i.is_active AND i.status='approved'
)
SELECT item_code,item_name,category_name,match_method,score FROM candidates ORDER BY score DESC LIMIT greatest(1,least(result_limit,50));
$$;
COMMIT;

