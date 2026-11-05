# ArangoDB Statefulset

Run arangodb in cluster using a statefulset and volume mount.

## Read-only developer access (GKE, optional)

Off by default (`ingress.enabled: false`; rendered output is unchanged). When enabled it adds a
dedicated HTTPS ingress for the database, protected by a Cloud Armor IP allowlist.

1. `gcloud compute addresses create <staticIpName> --global`. No manual DNS: external-dns creates the
   Cloudflare record from the ingress host (must be inside its `--domain-filter`).
2. `scripts/cloud-armor.sh <policy> cidrs.txt` (default deny + allow dev CIDRs). Create the
   policy BEFORE enabling the ingress; the BackendConfig references it by name.
3. Set `ingress.enabled/host/staticIpName/backendConfig.securityPolicy` in values. The record must stay DNS-only (not Cloudflare-proxied) or Cloud Armor will not see developer IPs; the chart sets the external-dns annotation for this.
   The chart fails to render if host, static IP or policy is missing.
4. `scripts/create-readonly-user.sh <name>` per developer. Never share the `arangodb` Secret.
