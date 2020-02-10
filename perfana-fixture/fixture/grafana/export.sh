KEY=eyJrIjoiejU2TzR3Tjd6eHA3M1lxVWVPeWlzNDUzZGwxZzExckQiLCJuIjoiUGVyZmFuYSIsImlkIjoxfQ==

HOST="http://localhost:3000"

curl -s "$HOST/api/datasources"  -H "Authorization: Bearer $KEY" |jq -c -M '.[]' | split -l 1 - datasources/

for dash in $(curl -sSL -k -H "Authorization: Bearer $KEY" $HOST/api/search\?query\=\& | jq '.' |grep -i uri|awk -F '"uri": "' '{ print $2 }'|awk -F '"' '{print $1 }'); do
  curl -sSL -k -H "Authorization: Bearer ${KEY}" "${HOST}/api/dashboards/${dash}" > dashboards/$(echo ${dash}|sed 's,db/,,g').json
done
