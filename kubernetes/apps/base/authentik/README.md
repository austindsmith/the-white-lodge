# Authentik

## Commands

### Rerunning init when adding a new secret in blueprints

```bash
flux reconcile helmrelease authentik -n authentik
kubectl rollout restart deploy/authentik-server -n authentik
kubectl rollout restart deploy/authentik-worker -n authentik
```

### Generating an application primary key

```bash
python3 -c "import uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, 'Teleport admins'))" | clip
```

### Generating client id

```bash
pass-cli password generate random --length 40 --symbols false | clip
```

### Generating client secret

```bash
pass-cli password generate random --length 128 --symbols false | clip
```
