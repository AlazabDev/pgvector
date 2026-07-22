DO $$ BEGIN
  IF EXISTS (SELECT item_code FROM maintenance_kb.maintenance_service_items GROUP BY item_code HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate item codes'; END IF;
  IF EXISTS (SELECT category_id,normalized_name FROM maintenance_kb.maintenance_service_items GROUP BY category_id,normalized_name HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate normalized names'; END IF;
  IF EXISTS (SELECT normalized_alias FROM maintenance_kb.maintenance_service_aliases GROUP BY normalized_alias HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate aliases'; END IF;
  IF EXISTS (SELECT 1 FROM maintenance_kb.maintenance_service_items WHERE unit='غير محدد') THEN RAISE EXCEPTION 'undefined units'; END IF;
END $$;

