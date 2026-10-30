#!/bin/bash
cd /home/ods/imagem-base-v1
echo "Início: $(date)"
tar --one-file-system -cpf - \
  --exclude=/home \
  --exclude='/tmp/*' \
  --exclude='/var/tmp/*' \
  --exclude='/var/cache/apt/archives/*.deb' \
  / | zstd -T0 -3 -f -o imagem-base-v1.tar.zst
echo "tar saiu com código: ${PIPESTATUS[0]}"
sha256sum imagem-base-v1.tar.zst > imagem-base-v1.sha256
echo "Fim: $(date)"
