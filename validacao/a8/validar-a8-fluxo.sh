#!/usr/bin/env bash
# Fluxo completo do A8: empresa -> login -> usuario -> veiculo convidado -> login do usuario.
# Cria dados de teste e apaga tudo no fim.
API="http://localhost:3000"; SAIDA="$HOME/containers/evidencias/a8-fluxo-$(date +%F).txt"
CNPJ="99000000000001"; EEMP="zz-empresa@teste.invalid"; EUSR="zz-usuario@teste.invalid"
CPF="99999999999"; SENHA="Teste12345"; TMP=$(mktemp); falhas=0
mkdir -p "$(dirname "$SAIDA")"
log() { echo "$*" | tee -a "$SAIDA"; }
sql() { echo "$1" | docker exec -i a8-mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -D a8' 2>/dev/null; }
limpar() { sql "DELETE FROM Usuario WHERE email='$EUSR'; DELETE FROM Empresa WHERE CNPJ='$CNPJ';" >/dev/null; }
req() { # nome esperado metodo caminho json [token]
  local h=(-H "Content-Type: application/json"); [ -n "$6" ] && h+=(-H "Authorization: Bearer $6")
  local code; code=$(curl -s -o "$TMP" -w "%{http_code}" -X "$3" "$API$4" "${h[@]}" ${5:+-d "$5"})
  if [ "$code" = "$2" ]; then log "OK    $1 (http $code)"
  else log "FALHA $1 (esperado $2, veio $code) $(head -c 200 "$TMP")"; falhas=$((falhas+1)); fi
}
tok() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("token",""))' "$TMP" 2>/dev/null; }
log "== A8 fluxo $(date) =="; limpar; trap limpar EXIT
req "cadastra empresa" 201 POST /api/empresas "{\"nome\":\"ZZ EMPRESA TESTE\",\"email\":\"$EEMP\",\"senha\":\"$SENHA\",\"confirmarSenha\":\"$SENHA\",\"cnpj\":\"$CNPJ\",\"tipo\":\"empresa\",\"userCadastra\":false}"
req "empresa faz login" 200 POST /api/login "{\"email\":\"$EEMP\",\"senha\":\"$SENHA\"}"; TE=$(tok)
[ -n "$TE" ] && log "OK    token da empresa recebido" || { log "FALHA sem token da empresa"; falhas=$((falhas+1)); }
req "empresa cadastra usuario" 201 POST /api/usuarios "{\"nome\":\"Usuario Teste\",\"email\":\"$EUSR\",\"cpf\":\"$CPF\",\"senha\":\"$SENHA\"}" "$TE"
req "cadastra veiculo convidado" 201 POST /api/veiculos-convidados "{\"placa\":\"ABC1D23\",\"emailUsuario\":\"$EUSR\",\"dataEntrada\":\"2026-11-05 10:00:00\",\"dataSaida\":\"2026-11-05 18:00:00\"}" "$TE"
n=$(sql "SELECT COUNT(*) FROM Veiculo_Convidado WHERE placa='ABC1D23' AND f_CNPJ='$CNPJ';")
[ "$n" = "1" ] && log "OK    veiculo convidado gravado no banco" || { log "FALHA veiculo nao esta no banco (count=$n)"; falhas=$((falhas+1)); }
req "usuario faz login" 200 POST /api/login "{\"email\":\"$EUSR\",\"senha\":\"$SENHA\"}"; TU=$(tok)
req "usuario lista suas empresas" 200 GET /api/usuarios/empresas "" "$TU"
limpar
r=$(sql "SELECT (SELECT COUNT(*) FROM Empresa WHERE CNPJ='$CNPJ')+(SELECT COUNT(*) FROM Usuario WHERE email='$EUSR')+(SELECT COUNT(*) FROM Veiculo_Convidado WHERE f_CNPJ='$CNPJ');")
[ "$r" = "0" ] && log "OK    dados de teste removidos" || { log "FALHA sobrou lixo no banco ($r linhas)"; falhas=$((falhas+1)); }
[ "$falhas" -eq 0 ] && log "RESULTADO: FUNCIONA (fluxo completo)" || log "RESULTADO: $falhas falha(s)"
rm -f "$TMP"; exit "$falhas"
