# PGAdmin4

Resetting postgres password manually (avoid)

```bash
kubectl exec -n cloudnative-pg -it app-cluster-1 -- \
  psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'NEWPASSWORD';"
```
