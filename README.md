Perfana2 test environment
=========================

To spin up the environment:

Get docker host ip:

```
ifconfig

docker0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 172.17.0.1  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:77:13:3a:80  txqueuelen 0  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
## Before you start
Log in into the Docker repository at Gitlab to enable access some of the Perfana images:
```docker
docker login registry.gitlab.com/perfana/perfana 
```

## Starting and Stopping

The necessary steps are outlined below. However, the project includes several scripts that perform the steps for you.
* start.sh
  Will first start Mongo, wait, configure Mongo, wait, start all other containers.
* stop.sh
  Stops all containers. 
* clean.sh
  Stops all containers and removes them.


#### Add DOCKER_HOST_IP to .bashrc
```bash
# .bashrc
DOCKER_HOST_IP=$(ifconfig | grep -A1 docker| grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
export DOCKER_HOST_IP
```

#### start mongo containers first
```bash
docker-compose up -d mongo1 mongo2 mongo3
```

#### log into mongo1 container and start mongo shell
```bash
docker exec -it localmongo1 /bin/bash
mongo 
```
#### initiate replica set
```js
rs.initiate(
  {
    _id : "rs0",
    members: [
      { _id : 0, host : "172.17.0.1:27011" },
      { _id : 1, host : "172.17.0.1:27012" },
      { _id : 2, host : "172.17.0.1:27013" }
    ]
  }
) 
```

#### Spin up the rest of the environment:
```bash


docker-compose up -d
```


#### Stop running containers:
```bash
docker-compose stop
```

#### Remove old containers
```bash
docker-compose rm -f
```


#### Check all is well
```bash
docker ps
```

Start docker compose

```
DOCKER_HOST_IP=172.17.0.1 docker-compose up -d
```bash
... PORTS                                                                                                               NAMES
... 50000/tcp, 0.0.0.0:8090->8080/tcp                                                                                   perfana-test-env_jenkins_1
...                                                                                                                     perfana-test-env_perfana-grafana-sync_1
... 0.0.0.0:4000->3000/tcp                                                                                              perfana-test-env_perfana_1
... 80/tcp, 443/tcp, 5858/tcp, 35729/tcp, 0.0.0.0:3333->3000/tcp                                                        perfana-test-env_mean_1
... 0.0.0.0:3000->3000/tcp                                                                                              perfana-test-env_grafana_1
... 2004/tcp, 2023-2024/tcp, 8126/tcp, 8125/udp, 0.0.0.0:8125->8125/tcp, 0.0.0.0:8070->80/tcp, 0.0.0.0:2004->2003/tcp   perfana-test-env_graphite_1
... 0.0.0.0:27017->27017/tcp                                                                                            perfana-test-env_mongo_1
... 0.0.0.0:8080->8080/tcp                                                                                              perfana-test-env_afterburner_1
... 8092/udp, 8125/udp, 8094/tcp                                                                                        perfana-test-env_telegraf_1
... 0.0.0.0:9100->9100/tcp                                                                                              perfana-test-env_node_1
... 0.0.0.0:9103->9103/tcp                                                                                              perfana-test-env_collectd_1
... 0.0.0.0:2003->2003/tcp, 0.0.0.0:8086->8086/tcp                                                                      perfana-test-env_influxdb_1
```

--------------
## Mac

```docker exec -it perfana-test-env_influxdb_1 bash```
```ping host.docker.internal```
```docker-compose stop && docker-compose rm -f && DOCKER_HOST_IP=192.168.65.2 docker-compose up -d```
```docker-compose stop && DOCKER_HOST_IP=192.168.65.2 docker-compose up -d```
------------
When all containers have started, load the fixture data:
```bash
cd perfana-fixture
npm start
```

When fixture data has been loaded, start the perfana-* components in your local


To reset and start from scratch

```docker-compose stop && docker-compose rm -f && docker-compose up -d```




--------------

```docker exec -it perfana-test-env_influxdb_1 bash```
```ping host.docker.internal```
```docker-compose stop && docker-compose rm -f && DOCKER_HOST_IP= docker-compose up```
