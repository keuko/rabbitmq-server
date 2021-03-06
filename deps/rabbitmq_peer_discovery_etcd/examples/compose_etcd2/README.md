Dynamic RabbitMQ cluster using:

1. [Docker compose](https://docs.docker.com/compose/)

2. [Etcd](https://coreos.com/etcd/) 

3. [HA proxy](https://github.com/docker/dockercloud-haproxy)

4. [rabbitmq-peer-discovery-etcd plugin](https://github.com/rabbitmq/rabbitmq-peer-discovery-etcd)

---

How to run:

```
docker-compose up
```

How to scale:

```
docker-compose up --scale rabbit=2 -d
```


---

Check running status:

- RabbitMQ Management: http://localhost:15672/#/