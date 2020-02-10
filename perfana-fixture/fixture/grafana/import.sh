KEY=eyJrIjoiR1NObENxUktDb3FJdHJLb0EzRDQ2elp0SWpyOE5XQnIiLCJuIjoicGVyZmFuYSIsImlkIjoxfQ==


HOST="http://localhost:3000"
for ds in datasources/* ; do

     STATUSCODE=$(curl -i -XPOST -H "Authorization: Bearer ${KEY}" "${HOST}/api/datasources" \
              --write-out "%{http_code}" --output /dev/stderr \
              --header 'Content-Type: application/json' \
              --data-binary @$ds)

     if [ $STATUSCODE -ne 200 ]; then
       echo "Unable to create datasource $ds"
     fi

done

for f in folders/* ; do

     STATUSCODE=$(curl -i -XPOST -H "Authorization: Bearer ${KEY}" "${HOST}/api/folders" \
              --write-out "%{http_code}" --output /dev/stderr \
              --header 'Content-Type: application/json' \
              --data-binary @$f)

     if [ $STATUSCODE -ne 200 ]; then
       echo "Unable to create folder $f"
     fi

done


for jsonfile in dashboards/*.json ; do

     cat $jsonfile | jq 'del(.dashboard.id)' | jq 'del(.dashboard.uid)' > /tmp/datafile
     STATUSCODE=$(curl -i -XPOST -H "Authorization: Bearer ${KEY}" "${HOST}/api/dashboards/db" \
              --write-out "%{http_code}" --output /dev/stderr \
              --header 'Content-Type: application/json' \
              --data-binary @/tmp/datafile)

     if [ $STATUSCODE -ne 200 ]; then
       echo "Unable to create $jsonfile"

     fi

done
