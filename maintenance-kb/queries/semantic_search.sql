SELECT i.item_code,i.item_name,c.category_name,1-(e.embedding <=> :'embedding'::vector) AS similarity
FROM maintenance_kb.maintenance_service_embeddings e
JOIN maintenance_kb.maintenance_service_items i ON i.id=e.service_item_id
JOIN maintenance_kb.maintenance_categories c ON c.id=i.category_id
WHERE i.is_active AND i.status='approved' ORDER BY e.embedding <=> :'embedding'::vector LIMIT 10;

