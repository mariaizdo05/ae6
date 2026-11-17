#!/usr/bin/env bash

set -u

IP_DPL_LAB="${IP_DPL_LAB:-172.20.0.2}"
BASE_DN="dc=dpl,dc=local"
USER_DN="uid=alumno,ou=usuarios,${BASE_DN}"
USER_PASSWORD="${USER_PASSWORD:-12345678}"
ZONE_FILE="/etc/bind/db.dpl.local"

FALLOS=0

ok() {
    echo "[OK] $1"
}

fallo() {
    echo "[FALLO] $1"
    FALLOS=$((FALLOS + 1))
}


echo "=============================="
echo " DNS"
echo "=============================="

docker exec dpl-lab named-checkconf \
    && ok "named-checkconf" \
    || fallo "named-checkconf"


docker exec dpl-lab \
    named-checkzone dpl.local "$ZONE_FILE" \
    | grep -q "OK" \
    && ok "named-checkzone" \
    || fallo "named-checkzone"


docker exec dpl-lab pgrep -a named >/dev/null \
    && ok "named activo" \
    || fallo "named no activo"


for nombre in www.dpl.local app.dpl.local
do

    ip=$(docker exec dpl-cliente \
        dig +short @"$IP_DPL_LAB" "$nombre" A)

    if [ -n "$ip" ]; then

        ok "$nombre -> $ip"

    else

        fallo "$nombre no resuelve"

    fi

done


echo
echo "=============================="
echo " DIRECTORIO LDAP"
echo "=============================="

docker exec dpl-lab pgrep -a slapd >/dev/null \
    && ok "slapd activo" \
    || fallo "slapd no activo"


docker exec dpl-lab \
    ldapsearch -x -LLL \
    -b "$BASE_DN" \
    "(uid=alumno)" dn \
    | grep -q "dn:" \
    && ok "usuario alumno encontrado" \
    || fallo "usuario alumno ausente"


docker exec dpl-cliente \
    ldapwhoami -x \
    -H "ldap://$IP_DPL_LAB" \
    -D "$USER_DN" \
    -w "$USER_PASSWORD" \
    | grep -q "dn:" \
    && ok "bind LDAP correcto" \
    || fallo "bind LDAP correcto rechazado"


docker exec dpl-cliente \
    ldapwhoami -x \
    -H "ldap://$IP_DPL_LAB" \
    -D "$USER_DN" \
    -w "incorrecta" >/dev/null 2>&1 \
    && fallo "credenciales incorrectas aceptadas" \
    || ok "credenciales incorrectas rechazadas"


echo
echo "=============================="
echo " INTEGRACIÓN"
echo "=============================="

codigo_web=$(docker exec dpl-cliente \
    curl -s \
    -o /dev/null \
    -w "%{http_code}" \
    http://www.dpl.local)

if [ "$codigo_web" = "200" ]; then

    ok "Web por nombre HTTP 200"

else

    fallo "Web por nombre HTTP $codigo_web"

fi


codigo_login=$(docker exec dpl-cliente \
    curl -s \
    -o /dev/null \
    -w "%{http_code}" \
    -X POST \
    -d "usuario=alumno&password=${USER_PASSWORD}" \
    http://www.dpl.local/api/login)

if [ "$codigo_login" = "200" ]; then

    ok "Login LDAP HTTP 200"

else

    fallo "Login LDAP HTTP $codigo_login"

fi


codigo_login_incorrecto=$(docker exec dpl-cliente \
    curl -s \
    -o /dev/null \
    -w "%{http_code}" \
    -X POST \
    -d "usuario=alumno&password=incorrecta" \
    http://www.dpl.local/api/login)

if [ "$codigo_login_incorrecto" = "401" ]; then

    ok "Login incorrecto HTTP 401"

else

    fallo "Login incorrecto devolvió HTTP $codigo_login_incorrecto"

fi


echo
echo "=============================="

if [ "$FALLOS" -eq 0 ]; then

    echo "Resultado: todas las comprobaciones han pasado."
    exit 0

else

    echo "Resultado: $FALLOS comprobación(es) fallida(s)."
    exit 1

fi
