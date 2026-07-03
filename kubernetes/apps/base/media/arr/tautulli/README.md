# Tautulli

GitOps deployment:

To import a file directly:

```yaml
configMapGenerator:
  - name: tautulli-config
    files:
      - config.ini=files/tautulli-config.ini
```

Create a `CronJob` to rclone all the `config.ini` files etc
