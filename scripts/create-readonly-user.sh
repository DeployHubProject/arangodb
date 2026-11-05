#!/usr/bin/env bash
# Create (or reset) a read-only ArangoDB user.
#
# Usage: ./create-readonly-user.sh <username> [namespace] [database]
#   namespace defaults to deployhub, database to vulnmgt.
#
# Grants: ro on <database>, ro on all its collections (including future ones),
#         none on _system (no user/database enumeration).
# A random password is generated and printed ONCE. It is never put on a command
# line (kubectl exec args end up in the Kubernetes API audit log); it travels
# over stdin into a 0600 temp file in the pod, which is deleted afterwards.
set -euo pipefail

USER_NAME="${1:?username required}"
NS="${2:-deployhub}"
DB="${3:-vulnmgt}"
POD="${POD:-arangodb-0}"

[[ "$USER_NAME" =~ ^[A-Za-z0-9._@-]+$ ]] || { echo "invalid username" >&2; exit 1; }
[[ "$DB" =~ ^[A-Za-z0-9_-]+$ ]]          || { echo "invalid database name" >&2; exit 1; }
[ "$USER_NAME" != "root" ] || { echo "refusing to touch root" >&2; exit 1; }

PASS="$(openssl rand -hex 24)"   # hex only: safe to embed in JS
REMOTE="/tmp/.ro-user-$$.js"
trap 'kubectl exec -n "$NS" "$POD" -- rm -f "$REMOTE" >/dev/null 2>&1 || true' EXIT

kubectl exec -i -n "$NS" "$POD" -- sh -c "umask 077; cat > $REMOTE" <<JS
const users = require("@arangodb/users");
const u = "$USER_NAME", p = "$PASS", db = "$DB";
if (users.exists(u)) { users.update(u, p, true); } else { users.save(u, p, true); }
users.grantDatabase(u, db, "ro");
users.grantCollection(u, db, "*", "ro");
users.grantDatabase(u, "_system", "none");
print("OK: " + u + " -> " + db + ":ro, _system:none");
JS

kubectl exec -n "$NS" "$POD" -- sh -c \
  "arangosh --server.endpoint tcp://127.0.0.1:8529 --server.username root \
            --server.password \"\$ARANGO_ROOT_PASSWORD\" --javascript.execute $REMOTE"

echo
echo "User: $USER_NAME"
echo "Password (shown once): $PASS"
