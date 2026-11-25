-- Foundation schema: identities, preferences and study sessions with an
-- offline-sync change feed and an append-only audit trail.
--
-- Identity is owned by Neon Auth. users.id is the JWT `sub` claim, so the API
-- never stores passwords. Rows are created lazily the first time a verified
-- token is seen.

CREATE TABLE users (
    id            uuid        PRIMARY KEY,
    email         text        NOT NULL CHECK (char_length(email) BETWEEN 3 AND 320),
    display_name  text        CHECK (display_name IS NULL OR char_length(display_name) <= 200),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now()
);
-- Not unique: an identity provider may recreate a user with the same email
-- under a new subject, and the subject is the authority.
CREATE INDEX users_email_idx ON users (lower(email));

CREATE TABLE user_preferences (
    user_id                uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    timezone               text        NOT NULL DEFAULT 'Asia/Kolkata',
    daily_target_minutes   integer     NOT NULL DEFAULT 360  CHECK (daily_target_minutes  BETWEEN 0 AND 1440),
    weekly_target_minutes  integer     NOT NULL DEFAULT 3000 CHECK (weekly_target_minutes BETWEEN 0 AND 10080),
    updated_at             timestamptz NOT NULL DEFAULT now()
);

-- Monotonic change counter shared by every synced table. Clients pull with
-- `since=<last seen change_seq>`. Writes for one user are serialised by a
-- row lock on users (see store.lockUser), so per-user change_seq order always
-- matches commit order and a cursor can never skip a row.
CREATE SEQUENCE sync_change_seq AS bigint;

CREATE TABLE study_sessions (
    -- Generated on the device so an offline retry of the same session is
    -- idempotent instead of creating a duplicate.
    id                 uuid        PRIMARY KEY,
    user_id            uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    mode               text        NOT NULL CHECK (mode IN ('stopwatch', 'countdown', 'pomodoro')),
    started_at         timestamptz NOT NULL,
    ended_at           timestamptz NOT NULL,
    duration_seconds   integer     NOT NULL CHECK (duration_seconds BETWEEN 1 AND 86400),
    planned_seconds    integer     CHECK (planned_seconds IS NULL OR planned_seconds BETWEEN 1 AND 86400),
    subject            text        CHECK (subject IS NULL OR char_length(subject) <= 120),
    notes              text        CHECK (notes IS NULL OR char_length(notes) <= 4000),
    laps_seconds       integer[]   NOT NULL DEFAULT '{}' CHECK (cardinality(laps_seconds) <= 500),
    source_device      text        NOT NULL CHECK (char_length(source_device) BETWEEN 1 AND 120),
    client_updated_at  timestamptz NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    deleted_at         timestamptz,
    change_seq         bigint      NOT NULL DEFAULT nextval('sync_change_seq'),
    CONSTRAINT study_sessions_time_order CHECK (ended_at >= started_at),
    -- Focused time can be shorter than wall time (pauses) but never longer.
    CONSTRAINT study_sessions_duration_within_span
        CHECK (duration_seconds <= EXTRACT(EPOCH FROM (ended_at - started_at)) + 1)
);

CREATE INDEX study_sessions_user_started_idx
    ON study_sessions (user_id, started_at DESC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX study_sessions_user_change_seq_idx
    ON study_sessions (user_id, change_seq);

CREATE FUNCTION bump_change_seq() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.change_seq := nextval('sync_change_seq');
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER study_sessions_bump_change_seq
    BEFORE UPDATE ON study_sessions
    FOR EACH ROW EXECUTE FUNCTION bump_change_seq();

-- Append-only audit trail of every change to a study record.
CREATE TABLE study_session_audit (
    id           bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id   uuid        NOT NULL,
    user_id      uuid        NOT NULL,
    operation    text        NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_row      jsonb,
    new_row      jsonb,
    recorded_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX study_session_audit_session_idx ON study_session_audit (session_id, id);

CREATE FUNCTION audit_study_session() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO study_session_audit (session_id, user_id, operation, old_row, new_row)
    VALUES (
        COALESCE(NEW.id, OLD.id),
        COALESCE(NEW.user_id, OLD.user_id),
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END
    );
    RETURN NULL;
END;
$$;

CREATE TRIGGER study_sessions_audit
    AFTER INSERT OR UPDATE OR DELETE ON study_sessions
    FOR EACH ROW EXECUTE FUNCTION audit_study_session();
