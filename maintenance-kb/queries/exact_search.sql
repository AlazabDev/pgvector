SELECT i.item_code,i.item_name,c.category_name
FROM maintenance_kb.maintenance_service_items i JOIN maintenance_kb.maintenance_categories c ON c.id=i.category_id
WHERE i.is_active AND i.status='approved' AND (lower(i.item_code)=lower(:'query') OR i.normalized_name=lower(btrim(:'query')));

