Perfana2 test environment
=========================


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

