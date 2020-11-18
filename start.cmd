@ECHO OFF

echo Starting Mongo cluster...
docker-compose  --compatibility up -d mongo1 mongo2 mongo3

echo Sleeping for 5 secs to give Mongo a chance to start...
PING localhost -n 6 >NUL

echo Configuring Mongo replica-set...
docker run -ti --rm -v %CD%/init-mongo.js:/init-mongo.js --net perfana-demo_perfana mongo:4.2-bionic /usr/bin/mongo --host mongo1 /init-mongo.js

echo Sleeping for 15 secs to give Mongo a chance to start the replicaset...
PING localhost -n 16 >NUL

echo Bringing up the rest of the Perfana test environment...
docker-compose --compatibility up -d

echo Done!
