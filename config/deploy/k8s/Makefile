KUBE=kubectl
MAKE=make
DOCKER_CONFIG_JSON=$(HOME)/.docker/config.json
APP_NS=app-lti
APP_NS_EXISTS = $(shell kubectl get ns | grep "\b$(APP_NS)\b" | wc -l)

install: install-ns install-secrets install-lti install-ingress

install-ns:
    ifeq ($(APP_NS_EXISTS), 0)
		@echo "Creating the namespace"
		$(KUBE) create ns $(APP_NS)
    else
		@echo "Namespace already created, skipping."
    endif

install-secrets:
	@echo "Creating the secrets"
    ifneq ($(shell test -f $(DOCKER_CONFIG_JSON) && echo 1 || echo 0), 1)
	    @echo "$(DOCKER_CONFIG_JSON) not found, run 'docker login' first."
	    @exit 1
    endif
    ifneq ($(shell cat $(DOCKER_CONFIG_JSON) | grep "\bauth\b" | wc -l), 1)
	    @echo "Run 'docker login' first."
	    @exit 1
    endif
	$(KUBE) create secret generic regcred --from-file=.dockerconfigjson=$(HOME)/.docker/config.json --type=kubernetes.io/dockerconfigjson --namespace=$(APP_NS) --dry-run=client -o yaml > secrets/docker-hub-secret.yml
	$(KUBE) apply -f secrets/

install-lti:
	@echo "Installing lti"
	cd lti && $(MAKE) install

install-ingress:
	@echo "Installing ingress"
	cd ingress && $(MAKE) install

clean:
	@echo "Cleaning up resources"
	$(KUBE) delete ns $(APP_NS)
	rm secrets/*
