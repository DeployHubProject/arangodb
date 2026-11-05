#!/usr/bin/env bash
# Create/refresh a Cloud Armor allowlist policy (default DENY, allow listed CIDRs).
#
# Usage: ./cloud-armor.sh <policy-name> <cidr-file>
#   cidr-file: one CIDR per line (e.g. 203.0.113.10/32); blank lines and # comments ignored.
#
# Safe to re-run: existing allow rules are replaced with the contents of the file.
# Cloud Armor allows a limited number of ranges per rule, so CIDRs are batched
# 10 per rule at priorities 1000, 1001, ...
set -euo pipefail

POLICY="${1:?policy name required}"
FILE="${2:?cidr file required}"
BATCH=10

mapfile -t CIDRS < <(grep -vE '^\s*(#|$)' "$FILE" | tr -d '[:space:]')
[ "${#CIDRS[@]}" -gt 0 ] || { echo "no CIDRs found in $FILE" >&2; exit 1; }
for c in "${CIDRS[@]}"; do
  [[ "$c" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]] || { echo "invalid CIDR: $c" >&2; exit 1; }
  [ "$c" != "0.0.0.0/0" ] || { echo "refusing 0.0.0.0/0: that defeats the allowlist" >&2; exit 1; }
done

if ! gcloud compute security-policies describe "$POLICY" >/dev/null 2>&1; then
  gcloud compute security-policies create "$POLICY" \
    --description "ArangoDB developer read-only access (allowlist)"
fi

# New policies default to ALLOW; flip the default rule to deny.
gcloud compute security-policies rules update 2147483647 \
  --security-policy "$POLICY" --action deny-403

# Remove old allow rules (priorities 1000-1099) so removed IPs are actually revoked.
for p in $(gcloud compute security-policies rules list --security-policy "$POLICY" \
             --format='value(priority)' | awk '$1>=1000 && $1<=1099'); do
  gcloud compute security-policies rules delete "$p" --security-policy "$POLICY" --quiet
done

prio=1000
for ((i=0; i<${#CIDRS[@]}; i+=BATCH)); do
  ranges=$(IFS=,; echo "${CIDRS[*]:i:BATCH}")
  gcloud compute security-policies rules create "$prio" \
    --security-policy "$POLICY" --src-ip-ranges "$ranges" --action allow
  prio=$((prio+1))
done

echo "Policy '$POLICY': default deny + ${#CIDRS[@]} allowed range(s)."
