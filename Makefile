GHCR_USERNAME=noetl
VERSION="0.1.0"
K8S_DIR=k8s

# define get_nats_port
# $(shell kubectl get svc nats -n nats -o=jsonpath='{.spec.ports[0].nodePort}')
# endef
# NATS_URL=nats://localhost:$(call get_nats_port)

NATS_URL=nats://localhost:32222

PLUGIN_BASE_VERSION=latest
PLUGIN_DOCKERFILE_BASE=docker/plugins/Dockerfile-base
PLUGIN_BASE_TAG=local/noetl-plugin-base:$(PLUGIN_BASE_VERSION)

DISPATCHER_PLUGIN_NAME=noetl-dispatcher
DISPATCHER_DOCKERFILE=docker/plugins/dispatcher/Dockerfile
DISPATCHER_VERSION=latest
DISPATCHER_PLUGIN_TAG=local/$(DISPATCHER_PLUGIN_NAME):$(DISPATCHER_VERSION)

REGISTRAR_PLUGIN_NAME=noetl-registrar
REGISTRAR_DOCKERFILE=docker/plugins/registrar/Dockerfile
REGISTRAR_VERSION=latest
REGISTRAR_PLUGIN_TAG=local/$(REGISTRAR_PLUGIN_NAME):$(REGISTRAR_VERSION)

HTTP_HANDLER_PLUGIN_NAME=noetl-http-handler
HTTP_HANDLER_DOCKERFILE=docker/plugins/http-handler/Dockerfile
HTTP_HANDLER_VERSION=latest
HTTP_HANDLER_PLUGIN_TAG=local/$(HTTP_HANDLER_PLUGIN_NAME):$(HTTP_HANDLER_VERSION)


PYTHON := python3.11
VENV_NAME := .venv
REQUIREMENTS := requirements.txt


.PHONY: venv requirements activate

venv:
	@echo "Creating Python virtual environment..."
	$(PYTHON) -m venv $(VENV_NAME)
	@. $(VENV_NAME)/bin/activate; \
	pip3 install --upgrade pip; \
	deactivate
	@echo "Virtual environment created."

requirements:
	@echo "Installing python requirements..."
	@. $(VENV_NAME)/bin/activate; \
	pip3 install -r $(REQUIREMENTS); \
	$(PYTHON) -m spacy download en_core_web_sm; \
	echo "Requirements installed."

activate-venv:
	@. $(VENV_NAME)/bin/activate;

activate-help:
	@echo "To activate the virtual environment:"
	@echo "source $(VENV_NAME)/bin/activate"

install-helm:
	@echo "Installing Helm..."
	@brew install helm
	@echo "Helm installation complete."


install-nats-tools:
	@echo "Tapping nats-io/nats-tools..."
	@brew tap nats-io/nats-tools
	@echo "Installing nats from nats-io/nats-tools..."
	@brew install nats-io/nats-tools/nats
	@echo "NATS installation complete."

#all: build-all push-all delete-all deploy-all

.PHONY: venv requirements activate-venv activate-help install-helm install-nats-tools



#[BUILD]#######################################################################
.PHONY: build-plugin-base build-dispatcher remove-dispatcher-image rebuild-dispatcher
.PHONY: build-registrar remove-registrar-image rebuild-registrar
.PHONY: build-all build-base-images rebuild-all remove-base-images clean



build-plugin-base:
	@echo "Building Plugins Base image..."
	docker build --no-cache --build-arg PRJ_PATH=../.. -f $(PLUGIN_DOCKERFILE_BASE) -t $(PLUGIN_BASE_TAG) .

remove-base-images:
	@echo "Removing base Docker images..."
	docker rmi $(API_SERVICE_BASE_TAG)
	docker rmi $(PLUGIN_BASE_TAG)

build-base-images:  build-api-base build-plugin-base


build-all: build-plugin-base build-plugin-images


build-dispatcher:
	@echo "Building Dispatcher image..."
	docker build --build-arg PRJ_PATH=../../ -f $(DISPATCHER_DOCKERFILE) -t $(DISPATCHER_PLUGIN_TAG) .

remove-dispatcher-image:
	@echo "Removing Dispatcher image..."
	docker rmi $(DISPATCHER_PLUGIN_TAG)

rebuild-dispatcher: remove-dispatcher-image build-dispatcher


build-registrar:
	@echo "Building Registrar image..."
	docker build --build-arg PRJ_PATH=../../ -f $(REGISTRAR_DOCKERFILE) -t $(REGISTRAR_PLUGIN_TAG) .

remove-registrar-image:
	@echo "Removing Registrar image..."
	docker rmi $(REGISTRAR_PLUGIN_TAG)

rebuild-registrar: remove-registrar-image build-registrar


build-http-handler:
	@echo "Building Registrar image..."
	docker build --build-arg PRJ_PATH=../../ -f $(HTTP_HANDLER_DOCKERFILE) -t $(HTTP_HANDLER_PLUGIN_TAG) .

remove-http-handler-image:
	@echo "Removing HTTP Handler plugin image..."
	docker rmi $(HTTP_HANDLER_PLUGIN_TAG)

rebuild-http-handler: remove-http-handler-image build-http-handler

.PHONY:build-http-handler remove-http-handler-image rebuild-http-handler


build-plugin-images: build-dispatcher build-registrar build-http-handler




clean:
	docker rmi $$(docker images -f "dangling=true" -q)


#[TAG]#######################################################################
.PHONY: tag-dispatcher tag-registrar



tag-dispatcher:
	@echo "Tagging Dispatcher image"
	docker tag $(DISPATCHER_PLUGIN_TAG) ghcr.io/$(GHCR_USERNAME)/noetl-dispatcher:$(DISPATCHER_VERSION)

tag-registrar:
	@echo "Tagging Registrar image"
	docker tag $(REGISTRAR_PLUGIN_TAG) ghcr.io/$(GHCR_USERNAME)/noetl-registrar:$(REGISTRAR_VERSION)


#[PUSH]#######################################################################
.PHONY: push-dispatcher push-registrar
.PHONY: docker-login push-all

push-all: push-dispatcher push-registrar

docker-login:
	@echo "Logging in to GitHub Container Registry"
	@echo $$PAT | docker login ghcr.io -u noetl --password-stdin

push-cli: tag-cli docker-login
	@echo "Pushing CLI image to GitHub Container Registry"
	docker push ghcr.io/$(GHCR_USERNAME)/noetl-cli:$(CLI_VERSION)

push-dispatcher: tag-dispatcher docker-login
	@echo "Pushing Dispatcher image to GitHub Container Registry"
	docker push ghcr.io/$(GHCR_USERNAME)/noetl-dispatcher:$(DISPATCHER_VERSION)

push-registrar: tag-registrar docker-login
	@echo "Pushing Registrar image to GitHub Container Registry"
	docker push ghcr.io/$(GHCR_USERNAME)/noetl-registrar:$(REGISTRAR_VERSION)


#[DEPLOY]#######################################################################
.PHONY: create-ns deploy-all deploy-all-local
.PHONY: deploy-dispatcher deploy-registrar

deploy-all: create-ns deploy-plugins
deploy-all-local: create-ns deploy-plugins-local

create-ns:
	@echo "Creating NoETL namespace..."
	kubectl config use-context docker-desktop
	kubectl apply -f $(K8S_DIR)/noetl/namespace.yaml

deploy-plugins:
	@echo "Deploying NoETL plugins from ghcr.io ..."
	kubectl config use-context docker-desktop
	kubectl apply -f $(K8S_DIR)/noetl/plugins/deployment.yaml

deploy-plugins-local:
	@echo "Deploying NoETL plugins from local image..."
	kubectl config use-context docker-desktop
	kubectl apply -f $(K8S_DIR)/noetl/plugins-local/deployment.yaml


.PHONY: delete-ns delete-all-deploy delete-all-local-deploy
.PHONY: delete-dispatcher-deploy delete-registrar-deploy

delete-deploy: delete-plugins-deploy
delete-local-deploy:delete-plugins-local-deploy

delete-ns:
	@echo "Deleting NoETL namespace..."
	kubectl config use-context docker-desktop
	kubectl delete -f $(K8S_DIR)/noetl/namespace.yaml

delete-plugins-deploy:
	@echo "Deleting NoETL Plugins"
	kubectl config use-context docker-desktop
	kubectl delete -f $(K8S_DIR)/noetl/plugins/deployment.yaml -n noetl

delete-plugins-local-deploy:
	@echo "Deleting NoETL Plugins locally"
	kubectl config use-context docker-desktop
	kubectl delete -f $(K8S_DIR)/noetl/plugins-local/deployment.yaml -n noetl

.PHONY: redeploy-plugins-locally
redeploy-plugins-locally: build-plugin-images delete-plugins-local-deploy deploy-plugins-local


#[KUBECTL COMMANDS]######################################################################

.PHONY: logs
logs:
	kubectl logs -f -l 'app in (noetl-dispatcher, noetl-http-handler, noetl-registrar)'


#[PIP UPLOAD]############################################################################
.PHONY: pip-upload

pip-upload:
	rm -rf dist/*
	$(PYTHON) setup.py sdist bdist_wheel
	$(PYTHON) -m twine upload dist/*
