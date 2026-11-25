DROP TABLE IF EXISTS study_session_audit;
DROP TABLE IF EXISTS study_sessions;
DROP FUNCTION IF EXISTS audit_study_session();
DROP FUNCTION IF EXISTS bump_change_seq();
DROP SEQUENCE IF EXISTS sync_change_seq;
DROP TABLE IF EXISTS user_preferences;
DROP TABLE IF EXISTS users;
