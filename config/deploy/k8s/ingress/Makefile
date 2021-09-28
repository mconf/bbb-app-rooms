KUBE=kubectl
MAKE=make
DOMAIN=elos.local
NAMESPACE=app-lti

CA_CM=mconf-ca-cm
CA_TARGETS=--from-file=secrets/mconf-dev-ca.crt

install: create-ca-config install-secrets install-ingress

create-ca-config:
	${KUBE} -n ${NAMESPACE} create configmap ${CA_CM} ${CA_TARGETS}

install-secrets:
	@echo "Creating the secrets"
	$(KUBE) create secret tls secret-tls -n app-lti --cert=secrets/$(DOMAIN).crt --key=secrets/$(DOMAIN).key

install-ingress:
	@echo "Installing ingress"
	$(KUBE) apply -f lti-ingress.yml

