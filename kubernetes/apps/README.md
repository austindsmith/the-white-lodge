# Media

## Documentation

- Make instructions for end users

## Commands

### Rendering a `resourceset`

```bash
flux-operator build rset -f resourceset.yaml
```

### Applying a `resourceset` outside of git

```bash
kubectl apply -f resourceset.yaml
kubectl get resourceset -n media
kubectl describe resourceset sonarr-family -n media
```

### Deleting a `resourceset` outside of > [!IMPORTANT]

```bash
kubectl delete -f resourceset.yaml
```

### Force re-applying `resourceset`

```bash
kubectl annotate resourceset arr-apps \
  -n media \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" \
  --overwrite
```

## Migration

### Containers

- [x] Autobrr
- [x] Bazarr
- [ ] Flaresolverr
- [ ] Immich
- [x] Homepage
- [ ] Mealie
- [ ] ntfy/notifier
- [x] Plex
- [x] Prowlarr
- [x] qBittorrent
- [x] Radarr
- [ ] Readarr
- [x] Sabnzbd
- [x] Seerr
- [x] Sonnar
- [ ] Tdarr
- [ ] Unpackerr

### Databases

- [ ] Authentik
- [ ] Bazarr
- [ ] Immich
- [ ] Kestra
- [ ] Mealie
- [ ] n8n
- [ ] Nextcloud
- [ ] Paperless-ngx
- [ ] Prowlarr
- [ ] Radarr
- [ ] Readarr
- [ ] Romm
- [ ] Sabnzbd
- [ ] Sonarr
- [ ] Overseerr

## Applications to add

- [ ] RSS feed
