BEGIN;
REVOKE ALL ON SCHEMA maintenance_kb FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA maintenance_kb FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA maintenance_kb FROM PUBLIC;
-- Grant explicit privileges to application roles in the deployment environment.
COMMIT;

