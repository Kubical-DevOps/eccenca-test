.PHONY: help backup cleanup initrestore restore start stop

SHELL := /bin/bash
K8S_VERSION := 1.21.7

BACKEND_CONTAINER := fyl_backend
DATABASE_CONTAINER := fyl_database
FRONTEND_CONTAINER := fyl_frontend

MK_STATUS = $(shell minikube status 1> /dev/null; echo $$?)
MK_CREATE = $(shell minikube start \
	--kubernetes-version=$(K8S_VERSION) 1> /dev/null)
MK_DELETE = $(shell minikube delete 1> /dev/null)
MK_ADDON_INGRESS =$(shell minikube addons enable ingress > /dev/null)

DOCKER_CREATE_DUMP = $(shell docker exec -it \
	$(DATABASE_CONTAINER) sh -c 'mysqldump \
	-uroot -p"$$MARIADB_ROOT_PASSWORD" application \
	> /root/dump.sql')
DOCKER_DOWNLOAD_DUMP = $(shell docker cp \
	$(DATABASE_CONTAINER):/root/dump.sql .)
DOCKER_UPLOAD_DUMP = $(shell docker cp dump.sql \
	$(DATABASE_CONTAINER):/root/dump.sql)
DOCKER_RESTORE_DUMP = $(shell docker exec -it \
	$(DATABASE_CONTAINER) sh -c 'mysqldump \
	-uroot -p"$$MARIADB_ROOT_PASSWORD" application \
	< /root/dump.sql' 1>/dev/null)
#The sleep 20 is in order to wait for ingress-nginx-controller-admission. The other sleep 20 is in order to wait for secret creation
ARGOCD_BOOTSTRAP = $(shell (kubectl get ns argocd || kubectl create ns argocd) && \
					(kubectl delete secret helm-secrets-private-keys -n argocd || \
					kubectl create secret generic helm-secrets-private-keys --from-file=key.asc -n argocd) && sleep 20 &&\
					helm upgrade --install argocd ./helm-charts/argocd/ --namespace=argocd --create-namespace -f helm-charts/argocd/values-development.yaml -f secrets+gpg-import://key.asc?helm-charts/argocd/secrets.yaml 1> /dev/null )

ARGOCD_CLEANUP = $(shell kubectl delete app --all -n argocd && \
			       kubectl delete appproj --all -n argocd && kubectl delete ns frontend backend && \
				   helm delete argocd -n argocd && kubectl delete ns argocd )

ARGOCD_ADMIN_PASSWORD = $(shell sleep 20 && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d )

K8S_DATABASE_POD = $(shell kubectl get pod -n backend | grep postgresql-0 | awk '{print $1}')

K8S_CREATE_DUMP = $(shell kubectl -n backend exec -it \
	$(K8S_DATABASE_POD) -- /bin/sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_dump -U  $$POSTGRES_USER $$POSTGRES_DB > /tmp/dump.sql')

K8S_DOWNLOAD_DUMP = $(shell kubectl -n backend exec -it \
	$(K8S_DATABASE_POD) -- /bin/sh -c 'cat /tmp/dump.sql' > dump.sql)


###NOT TESTED, I need to enjoy my weekend :)
K8S_UPLOAD_DUMP = $(shell kubectl cp dump.sql /tmp/dump.sql')

K8S_RESTORE_DUMP = $(shell kubectl -n backend exec -it \
	$(K8S_DATABASE_POD) -- /bin/sh -c 'psql -u$$POSTGRES_USER -p$$POSTGRES_PASSWORD $$POSTGRES_DB < /tmp/dump.sql')
#####

help:
	@echo "Usage: make COMMAND [VARIABLE=value ...]"
	@echo ""
	@echo "Commands"
	@echo "  backup                Create a database backup"
	@echo "  cleanup               Cleanup the development environment"
	@echo "  init                  Setup the development environment"
	@echo "  restore               Restore the database from a backup file"
# @echo "  start               ?"
# @echo "  stop                ?"
	@echo ""
	@echo "Variables"
	@echo "  BACKEND_CONTAINER     Name of the backend container (default: $(BACKEND_CONTAINER))"
	@echo "  DATABASE_CONTAINER    Name of the database container (default: $(DATABASE_CONTAINER))"
	@echo "  FRONTEND_CONTAINER    Name of the frontend container (default: $(FRONTEND_CONTAINER))"

backup:
	$(info Creating database backup.)
	@echo $(DOCKER_CREATE_DUMP)
	@echo $(DOCKER_DOWNLOAD_DUMP)
	$(info Database backup finished.)

k8s-backup:
	$(info Creating database backup.)
	@echo $(K8S_CREATE_DUMP)
	@echo $(K8S_DOWNLOAD_DUMP)
	$(info Database backup finished.)

cleanup:
ifeq ($(MK_STATUS), 0)
	$(info Deleting minikube cluster.)
	@echo $(MK_DELETE)
	$(info Minikube cluster deleted.)
else
	@echo "No minikube cluster found."
endif

k8s-cleanup: 
	$(info Cleaning up resources created by argocd.)
	@echo $(ARGOCD_CLEANUP)


init:
ifneq ($(MK_STATUS), 0)
	$(info No minikube cluster found. Creating one now. \
		This will take a few minutes.)
	@echo $(MK_CREATE)
	$(info Minikube cluster created.)
	$(info Adding ingress addon.)
	@echo $(MK_ADDON_INGRESS)
	$(info Minikube cluster is now ready.)
else
	$(info Minikube is already running.)
	@sleep 10
endif
	$(info Bootstaping cluster.)
	@echo $(ARGOCD_BOOTSTRAP)
	@echo "Cluster Bootstrapped"
	@echo "ArgoCD admin password:" $(ARGOCD_ADMIN_PASSWORD)

restore:
	$(info Restoring database backup.)
	@echo $(DOCKER_UPLOAD_DUMP)
	@echo $(DOCKER_RESTORE_DUMP)
	$(info Database backup restored.)

k8s-restore:
	$(info Restoring database backup.)
	@echo $(K8S_UPLOAD_DUMP)
	@echo $(K8S_RESTORE_DUMP)
	$(info Database backup restored.)

