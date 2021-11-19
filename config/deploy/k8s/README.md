Starting minikube

* $ `minikube start`
* $ `minikube addons enable ingress`

Run bbb-app-rooms and bbb-lti-broker databases outside kubernetes

* $ `cd path/to/bbb-app-rooms/`
* Add the line `network_mode: host` in the `postgres` service in the docker-compose.yml
* $ `docker-compose up postgres`
* Repeat the same steps for bbb-lti-broker

Change the database URLs in the secrets.yml

* Copy your local IP address
* Run (replacing YOUR_IP with your actual IP) `echo -n "postgresql://postgres:password@YOUR_IP:5432/lti_broker" | base64`
* Copy the base64 string and set it in the field `DATABASE_URL` in `lti/broker/secrets.yml`

Repeat it for bbb-app-rooms (note that the URL is not the same)

* Copy your local IP address
* Run (replacing YOUR_IP with your actual IP) `echo -n "postgresql://postgres:password@YOUR_IP:5433/lti_rooms" | base64`
* Copy the base64 string and set it in the field `DATABASE_URL` in `lti/rooms/secrets.yml`

Login on dockerhub

* $ `docker login`

Add the elos.local to /etc/hosts

* Get the cluster IP with `minikube ip`
* Paste the following line in /etc/hosts
  * `<IP_OBTAINED> elos.local`

Start the cluster

* `cd config/deploy/k8s`
* `make install`

Wait for the pods to change the state to running:

* `k -n app-lti get pods -w`

Then proceed to test the applicatoin normally

---

Troubleshooting

* The command `make install` copies your local dockerhub keys to the
secrets/docker-hub-secret.yml file. For this to work, the file
$HOME/.docker/config.json must exist (it's created when you run docker login)

