#!/usr/bin/env bash
# Verifica PADRAO-NOMES.md contra as imagens ods/* existentes. Saida 0 = tudo conforme.
cd "$(dirname "$0")"
falha=0
chk() { if [ "$2" = ok ]; then echo "OK    $1"; else echo "FALHA $1"; falha=1; fi; }
RE='^ods/[a-z0-9-]+:[0-9]+\.[0-9]+\.[0-9]+-jp6\.2\.1-b[0-9]{3}$'
n=$(grep -cE '^[0-9]+\. \*\*' PADRAO-NOMES.md)
if [ "$n" -ge 7 ]; then chk "PADRAO-NOMES.md com $n regras" ok; else chk "PADRAO-NOMES.md com $n regras" x; fi
for img in $(sudo docker images 'ods/*' --format '{{.Repository}}:{{.Tag}}'); do
  if [[ "$img" =~ $RE ]]; then chk "$img (formato da tag)" ok; else chk "$img (formato da tag)" x; continue; fi
  for l in ods.servico ods.versao ods.build ods.jetpack ods.l4t ods.commit ods.fonte ods.data ods.base; do
    v=$(sudo docker image inspect "$img" --format "{{index .Config.Labels \"$l\"}}")
    if [ -n "$v" ]; then :; else chk "$img (label $l ausente)" x; fi
  done
done
exit $falha
