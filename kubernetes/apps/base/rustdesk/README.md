# Rustdesk

### Getting the rustdesk server key

```bash
kubectl -n rustdesk logs deploy/rustdesk-server -c hbbs | grep -i key
```

### Generating rustdesk password

```bash
pass-cli password generate passphrase | clip
```
