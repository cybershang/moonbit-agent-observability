#!/bin/sh
set -eu

# GreptimeDB HTTP SQL endpoint
GREPTIME_URL="${GREPTIME_URL:-http://localhost:4000}"
DB="public"
SQL_FILE="${SQL_FILE:-/flows.sql}"

sql() {
    stmt="$1"
    echo "  -> $(echo "$stmt" | head -1 | cut -c1-80)..."
    resp=$(curl -sf -X POST "${GREPTIME_URL}/v1/sql?db=${DB}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "sql=${stmt}" 2>&1) || {
        echo "     FAILED: ${resp}"
        return 1
    }
    echo "     OK"
}

echo "==> Executing SQL from ${SQL_FILE}..."

if [ ! -f "$SQL_FILE" ]; then
    echo "ERROR: SQL file not found: ${SQL_FILE}"
    exit 1
fi

# Strip comments, collapse into single line, split on semicolons, execute each statement
sed 's/--.*$//' "$SQL_FILE" | tr '\n' ' ' | tr ';' '\n' > /tmp/stmts.txt
while IFS= read -r stmt; do
    stmt=$(echo "$stmt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$stmt" ] && continue
    sql "$stmt"
done < /tmp/stmts.txt

echo ""
echo "==> Done! GenAI Flow metrics will populate automatically."
echo ""
echo "   Verify with:"
echo "     mysql -h 127.0.0.1 -P 4002 -e 'SELECT * FROM genai_token_usage_1m LIMIT 5'"
echo ""
