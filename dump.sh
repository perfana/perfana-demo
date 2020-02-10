#!/bin/bash
export DOCKER_HOST_IP=$(ifconfig | grep -A1 docker| grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)

DEST=dump-$(docker ps | grep perfana-fe | tr -s ' ' | sed "s/^.*perfana-fe:\(.*\)\ \".*$/perfana-fe_\1/")

[ ! -d $DEST ] && mkdir $DEST

MONGO_URI=mongodb://mongo1:27017,mongo2:27017,mongo3:27017/perfana?replicaSet=rs0

echo Dumping selected data from $DEST

docker run --rm -u $UID -ti --net perfana-test-env_perfana --volume $(pwd)/$DEST:/dump mongo:4.2-bionic /bin/bash -c \
  "for i in benchmarks CheckResults compareResults testRuns snapshots; do mongoexport --uri=mongodb://mongo1:27017,mongo2:27017,mongo3:27017/perfana?replicaSet=rs0 -c \$i -o /dump/\$i.json --pretty; done"
