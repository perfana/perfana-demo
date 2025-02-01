# Perfana demo

## Demo environment

The Perfana demo environment can be used to try out all the features. It uses Docker compose and has a all components to emulate a live-like environment for Perfana, including an application to run a performance test.

## Prerequisites

* [Docker](https://docs.docker.com/get-started/)
* [Docker compose](https://docs.docker.com/compose/gettingstarted/)
* A minimum 8Gb of RAM allocated to docker daemon, preferably more

## Getting started

* Clone perfana-demo repository 
  ```sh
  git clone https://github.com/perfana/perfana-demo.git
  ```
  or download [here](https://github.com/perfana/perfana-demo/archive/master.zip)

  > If you use the download option, make sure to extract the zip to a directory named `perfana-demo`!

* Add this to your hosts file
  ```sh
  127.0.1.1  perfana
  127.0.1.1  jenkins  
  127.0.1.1  grafana
  ```

* Inside the repository root run
  ```sh
  ./start.sh
  ```

This spins up a number of containers

| Container                | Description                                       | exposed to local port |
|:-------------------------|:--------------------------------------------------|:----------------------|
| perfana-fe               | Perfana front end                                 | 4000                  |
| perfana-grafana          | Perfana - Grafana integration service             | n/a                   |
| perfana-snapshot         | Perfana snapshot service                          | n/a                   |
| perfana-check            | Perfana results check service                     | n/a                   |
| perfana-scheduler        | Perfana schduled jobs                             | n/a                   |
| perfana-ds-api           | Perfana data science api                          | 8080                  |
| perfana-ds-worker        | Perfana data science api                          | n/a                   |
| perfana-ds-metric-worker | Perfana data science api                          | n/a                   |
| mongodb                  | MongoDb replicaset to store Perfana configuration | 27011 / 27012 /27013  |
| grafana                  | Grafana graphing dashboard                        | 3000                  |
| influxdb                 | InfluxDb metrics datastore                        | 8086 / 2003           |
| telegraf                 | Telegraf metrics agent                            | n/a                   |
| prometheus               | Prometheus metrics datastore                      | 9090                  |
| alertmanager             | Alertmanager handles alerts from Prometheus       | 9093                  |
| afterburner-fe           | Springboot test application                       | 8090                  |
| afterburner-be           | Springboot test application                       | n/a                   | 
| mariadb                  | Database used by test application                 | n/a                   | 
| jaeger                   | Distributed tracing                               | 16686                 | 
| tempo                    | Distributed traces backend                        | 3100                  | 
| loki                     | Loki for parsing logs                             | n/a                   | 
| Pyrocope                 | Continuous profiling                              | 4040                  | 
| wiremock                 | Mocking tool                                      | 8060                  | 


To stop all containers, run

```sh
./stop.sh
```

To remove all containers, use

```sh
./clean.sh
``` 

--- 

> When you use the `clean.sh` script, all of the data inside the containers will be lost!

---

To deploy a version of the test application with a performance issue, run

```sh
./deploy-and-test.sh cpu
````
or 
```sh
./deploy-and-test.sh pool
```

> The `perfana-demo` repository is updated frequently, so to get the latest and greatest pull repo and images.


```sh
git pull && docker-compose pull
```

## Exploring the demo environment

### Perfana

To log into Perfana, open [http://localhost:4000](http://localhost:4000) and use `admin@perfana.io` as user with password `perfana`. If you want to log in as a non-admin user, you can try users `daniel@perfana.io` or `dylan@perfana.io`, both with password `perfana`

### Grafana

To log into Grafana, open [http://localhost:3000](http://localhost:3000) and use `perfana` as user with password `perfana` 

## Credits

The database used in this demo setup is created from a subset of data from https://github.com/datacharmer/test_db