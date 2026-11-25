// Package migrations embeds the SQL schema migrations so the API binary can
// migrate any PostgreSQL 17 database (local Docker, Neon, RDS) on its own.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
