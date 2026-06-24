# Teleport

## Commands

### Setting a password on a local user

```bash
kubectl exec -n teleport deploy/teleport -- tctl users reset austin
```

### Getting tokens for deploying to devices

```bash
kubectl exec -n teleport deploy/teleport-auth -- tctl tokens add --type=node --ttl=1h
kubectl exec -n teleport deploy/teleport-auth -- tctl status
```

### Adding cloudnative-pg certificate

```bash
tctl auth export --type=db-client > teleport-db-client-ca.crt
kubectl -n cloudnative-pg get secret pg-client-ca -o jsonpath='{.data.tls\.crt}' | base64 -d > pg-client-ca.crt

cat pg-client-ca.crt teleport-db-client-ca.crt > client-ca-bundle.crt
kubectl -n cloudnative-pg create secret generic pg-client-ca-bundle \
  --from-file=ca.crt=client-ca-bundle.crt \
  --dry-run=client -o yaml | kubectl apply -f -
```
