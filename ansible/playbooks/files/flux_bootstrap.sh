echo "y" | flux bootstrap git \
  --url=ssh://git@github.com/austindsmith/the-white-lodge \
  --branch=main \
  --path=kubernetes/clusters/production \
  --private-key-file=/home/austin/.ssh/keys/austin@theblacklodge.org
