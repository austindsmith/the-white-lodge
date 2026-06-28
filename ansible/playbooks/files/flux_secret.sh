kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/home/austin/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -
