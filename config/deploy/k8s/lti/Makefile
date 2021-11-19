KUBE=kubectl
NAMESPACE=app-lti

BROKER_SCRIPTS_CM=mconf-lti-broker-scripts-cm
BROKER_TARGETS=--from-file=broker/scripts/seeds.rb --from-file=broker/scripts/start.sh --from-file=broker/scripts/migrate.sh --from-file=broker/scripts/rollback.sh --from-file=broker/scripts/seed.sh

ROOMS_SCRIPTS_CM=mconf-lti-rooms-scripts-cm
ROOMS_TARGETS=--from-file=rooms/scripts/start.sh --from-file=rooms/scripts/migrate.sh --from-file=rooms/scripts/rollback.sh

CERTS_CM=mconf-lti-certs-cm
CERTS_TARGETS=--from-file=../ingress/secrets/mconf-dev-ca.crt

install: create-broker-config create-rooms-config create-certs-config install-rooms install-broker

create-broker-config:
	${KUBE} -n ${NAMESPACE} create configmap ${BROKER_SCRIPTS_CM} ${BROKER_TARGETS}

reload-broker-config:
	${KUBE} -n ${NAMESPACE} create configmap ${BROKER_SCRIPTS_CM} ${BROKER_TARGETS} --dry-run -o yaml | ${KUBE} -n ${NAMESPACE} replace -f -

create-rooms-config:
	${KUBE} -n ${NAMESPACE} create configmap ${ROOMS_SCRIPTS_CM} ${ROOMS_TARGETS}

reload-rooms-config:
	${KUBE} -n ${NAMESPACE} create configmap ${ROOMS_SCRIPTS_CM} ${ROOMS_TARGETS} --dry-run -o yaml | ${KUBE} -n ${NAMESPACE} replace -f -

create-certs-config:
	${KUBE} -n ${NAMESPACE} create configmap ${CERTS_CM} ${CERTS_TARGETS}

install-broker:
	${KUBE} -n ${NAMESPACE} apply -f broker/configmap.yml
	${KUBE} -n ${NAMESPACE} apply -f broker/secrets.yml
	${KUBE} -n ${NAMESPACE} apply -f broker/deployment.yml
	${KUBE} -n ${NAMESPACE} apply -f broker/service.yml

install-rooms:
	${KUBE} -n ${NAMESPACE} apply -f rooms/configmap.yml
	${KUBE} -n ${NAMESPACE} apply -f rooms/secrets.yml
	${KUBE} -n ${NAMESPACE} apply -f rooms/deployment.yml
	${KUBE} -n ${NAMESPACE} apply -f rooms/service.yml
