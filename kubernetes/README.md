# Kubernetes

## Notes

- Consider switching to RKE2, it's like k3s with better security defaults.

See labels that are usable as selectors for things like services

```bash
kubectl get pods --show-labels
```

Force delete namespace:

```bash
kubectl get namespace media -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/media/finalize" -f -
```

Checking possible chart values:

```bash
helm show values metallb/metallb --version 0.15.2
```

Checking possible chart metadata

```bash
helm show all metallb/metallb --version 0.15.2
```

See spec options for a chart

```bash
kubectl explain externalsecret.spec
```

Template out a chart

```bash
helm template metallb metallb/metallb --version 0.15.2 | grep -E "^kind:|^  name:"
```

## Apps to download

- [x] Gluetun/arr stack
- [x] Pangolin
- [x] Longhorn
- [x] Postgres
- [ ] Airflow
- [x] Dagster
- [x] n8n
- [ ] node-red/rabbitmq
- [x] Semaphore
- [ ] Grafana/monitoring stack
- [x] Authentik
- [ ] Crowdsec
- [ ] Immich
- [ ] Nextcloud
- [ ] Paperless
- [ ] Mealie
- [ ] RustFS

## Deployment oddities

- Qbittorrent not setting custom password
- Cloudnative-pg password needs to be entered in UI as well
