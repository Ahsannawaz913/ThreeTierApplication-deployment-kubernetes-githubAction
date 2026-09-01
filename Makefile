# ============================================================
# SkillPulse - Three Tier Application
# Dependencies + Docker + Kind + Kubectl + Deployment
# ============================================================

SHELL := /bin/bash

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

CLUSTER       ?= skillpulse
NAMESPACE     ?= skillpulse

BACKEND_IMAGE  ?= trainwithshubham/skillpulse-backend:latest
FRONTEND_IMAGE ?= trainwithshubham/skillpulse-frontend:latest

.PHONY: install update dependencies docker kubectl kind permissions \
        up down build load apply status logs mysql restart


# ============================================================
# FRESH EC2 SETUP
# ============================================================

install: update dependencies docker permissions kubectl kind
	@echo
	@echo "=============================================="
	@echo " All dependencies installed successfully!"
	@echo "=============================================="
	@echo
	@echo "Docker:"
	@docker --version
	@echo
	@echo "Kubectl:"
	@kubectl version --client
	@echo
	@echo "Kind:"
	@kind version
	@echo
	@echo "IMPORTANT:"
	@echo "Run: newgrp docker"
	@echo "Then run: make up"
	@echo


# ------------------------------------------------------------
# Update Ubuntu
# ------------------------------------------------------------

update:
	@echo "=============================================="
	@echo " Updating Ubuntu"
	@echo "=============================================="

	sudo apt-get update -y
	sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y


# ------------------------------------------------------------
# Install basic dependencies
# ------------------------------------------------------------

dependencies:
	@echo "=============================================="
	@echo " Installing basic dependencies"
	@echo "=============================================="

	sudo apt-get install -y \
		curl \
		wget \
		git \
		make \
		unzip \
		ca-certificates \
		apt-transport-https \
		gnupg \
		lsb-release


# ============================================================
# DOCKER
# ============================================================

docker:
	@echo "=============================================="
	@echo " Installing Docker"
	@echo "=============================================="

	@if command -v docker >/dev/null 2>&1; then \
		echo "Docker is already installed."; \
	else \
		curl -fsSL https://get.docker.com | sudo sh; \
	fi

	sudo systemctl enable docker
	sudo systemctl start docker

	@echo
	@docker --version


# ------------------------------------------------------------
# Docker permissions
# ------------------------------------------------------------

permissions:
	@echo "=============================================="
	@echo " Configuring Docker permissions"
	@echo "=============================================="

	sudo usermod -aG docker $$USER

	@echo
	@echo "User $$USER added to docker group."
	@echo "Run 'newgrp docker' before using Docker."
	@echo


# ============================================================
# KUBECTL
# ============================================================

kubectl:
	@echo "=============================================="
	@echo " Installing kubectl"
	@echo "=============================================="

	@if command -v kubectl >/dev/null 2>&1; then \
		echo "kubectl is already installed."; \
	else \
		KUBECTL_VERSION=$$(curl -L -s https://dl.k8s.io/release/stable.txt); \
		curl -LO https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl; \
		sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; \
		rm -f kubectl; \
	fi

	@echo
	@kubectl version --client


# ============================================================
# KIND
# ============================================================

kind:
	@echo "=============================================="
	@echo " Installing kind"
	@echo "=============================================="

	@if command -v kind >/dev/null 2>&1; then \
		echo "kind is already installed."; \
	else \
		curl -Lo kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64; \
		chmod +x kind; \
		sudo mv kind /usr/local/bin/kind; \
	fi

	@echo
	@kind version


# ============================================================
# APPLICATION
# ============================================================

up: ## One-shot: build images, create cluster, load images, apply manifests
	@echo "=============================================="
	@echo " Starting SkillPulse deployment"
	@echo "=============================================="

	$(MAKE) build

	@if kind get clusters 2>/dev/null | grep -qx "$(CLUSTER)"; then \
		echo "Kind cluster '$(CLUSTER)' already exists."; \
	else \
		kind create cluster \
			--config k8s/kind-config.yaml \
			--name $(CLUSTER); \
	fi

	$(MAKE) load
	$(MAKE) apply

	@echo
	@echo "=============================================="
	@echo " SkillPulse is deployed!"
	@echo "=============================================="
	@echo
	@echo "Cluster:  $(CLUSTER)"
	@echo "Namespace: $(NAMESPACE)"
	@echo
	@echo "Access:"
	@echo "http://localhost:8888"
	@echo


# ============================================================
# BUILD DOCKER IMAGES
# ============================================================

build: ## Build backend + frontend images
	@echo "=============================================="
	@echo " Building Docker images"
	@echo "=============================================="

	docker build -t $(BACKEND_IMAGE) ./backend
	docker build -t $(FRONTEND_IMAGE) ./frontend

	@echo
	@echo "Images built:"
	@docker images | grep -E "skillpulse|REPOSITORY"


# ============================================================
# LOAD IMAGES INTO KIND
# ============================================================

load: ## Push built images into the kind node
	@echo "=============================================="
	@echo " Loading images into kind"
	@echo "=============================================="

	kind load docker-image $(BACKEND_IMAGE) --name $(CLUSTER)
	kind load docker-image $(FRONTEND_IMAGE) --name $(CLUSTER)


# ============================================================
# KUBERNETES DEPLOYMENT
# ============================================================

apply: ## Apply manifests and wait for rollouts
	@echo "=============================================="
	@echo " Applying Kubernetes manifests"
	@echo "=============================================="

	kubectl apply -f k8s/00-namespace.yaml \
	              -f k8s/10-mysql.yaml \
	              -f k8s/20-backend.yaml \
	              -f k8s/30-frontend.yaml

	@echo
	@echo "Waiting for MySQL..."
	kubectl rollout status \
		statefulset/mysql \
		-n $(NAMESPACE) \
		--timeout=180s

	@echo
	@echo "Waiting for backend..."
	kubectl rollout status \
		deployment/backend \
		-n $(NAMESPACE) \
		--timeout=120s

	@echo
	@echo "Waiting for frontend..."
	kubectl rollout status \
		deployment/frontend \
		-n $(NAMESPACE) \
		--timeout=60s

	@echo
	@echo "Deployment completed."


# ============================================================
# DELETE KIND CLUSTER
# ============================================================

down: ## Delete the kind cluster
	@echo "Deleting cluster $(CLUSTER)..."
	kind delete cluster --name $(CLUSTER)


# ============================================================
# STATUS
# ============================================================

status: ## Quick health snapshot
	@echo "=============================================="
	@echo " SkillPulse Status"
	@echo "=============================================="

	@echo
	@echo "Pods:"
	@kubectl get pods -n $(NAMESPACE)

	@echo
	@echo "Services:"
	@kubectl get svc -n $(NAMESPACE)

	@echo
	@echo "Endpoints:"
	@kubectl get endpoints -n $(NAMESPACE)


# ============================================================
# LOGS
# ============================================================

logs: ## Tail all three workloads
	@echo "Showing SkillPulse logs..."
	kubectl logs \
		-n $(NAMESPACE) \
		-l 'app in (mysql,backend,frontend)' \
		--all-containers \
		--tail=50 \
		-f \
		--max-log-requests=10


# ============================================================
# MYSQL
# ============================================================

mysql: ## Open MySQL shell
	kubectl exec \
		-it \
		-n $(NAMESPACE) \
		mysql-0 \
		-- mysql \
		-uskillpulse \
		-pskillpulse123 \
		skillpulse


# ============================================================
# RESTART APPLICATION
# ============================================================

restart: ## Rebuild + reload images + restart backend/frontend
	@echo "=============================================="
	@echo " Rebuilding application"
	@echo "=============================================="

	$(MAKE) build
	$(MAKE) load

	@echo
	@echo "Restarting backend and frontend..."

	kubectl rollout restart \
		deployment/backend \
		deployment/frontend \
		-n $(NAMESPACE)

	@echo
	@echo "Waiting for backend..."
	kubectl rollout status \
		deployment/backend \
		-n $(NAMESPACE) \
		--timeout=120s

	@echo
	@echo "Waiting for frontend..."
	kubectl rollout status \
		deployment/frontend \
		-n $(NAMESPACE) \
		--timeout=60s

	@echo
	@echo "Restart completed."


# ============================================================
# HELP
# ============================================================

help:
	@echo
	@echo "SkillPulse Makefile"
	@echo
	@echo "Fresh EC2 setup:"
	@echo "  make install       Install all dependencies"
	@echo "  newgrp docker      Activate Docker permissions"
	@echo
	@echo "Deployment:"
	@echo "  make up            Build + create cluster + deploy"
	@echo "  make build         Build Docker images"
	@echo "  make load          Load images into kind"
	@echo "  make apply         Apply Kubernetes manifests"
	@echo
	@echo "Management:"
	@echo "  make status        Show application status"
	@echo "  make logs          Show application logs"
	@echo "  make mysql         Open MySQL shell"
	@echo "  make restart       Rebuild and restart application"
	@echo "  make down          Delete kind cluster"
	@echo
