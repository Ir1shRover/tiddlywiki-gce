# MIT License
# Copyright (c) 2018 Nicola Worthington <nicolaw@tfb.net>

# Well-known GCP environment variables.
GOOGLE_PROJECT ?=
GOOGLE_REGION ?= europe-west1
GOOGLE_ZONE ?= $(GOOGLE_REGION)-d

# Defaults provided by Terraform.
INSTANCE_NAME :=
MACHINE_TYPE := g1-small
TRUSTED_CIDR := 0.0.0.0/0

# Apache & Let's Encrypt certificate generation.
DOMAIN :=
EMAIL :=

# Password protection for TiddlyWiki write access.
TW_USERNAME := anonymous
TW_PASSWORD :=
TW_PRIVATE :=

# Upstream repliaction of TiddlyWiki data.
GIT_REPOSITORY :=
GIT_USERNAME :=
GIT_PASSWORD :=
GIT_SSH_KEY := id_rsa

# Local bind-mount location to store Let's Encrypt certificates.
LETSENCRYPT_DATA := /home/tiddlywiki/letsencrypt

# Output additional debug logging inside docker containers.
DEBUG ?=

# Explicit version required as no latest tag exists.
DOCKER_COMPOSE_VER := 1.19.0

# Google container registry host.
GOOGLE_CONTAINER_REGISTRY := gcr.io

# Should Terraform attempt to manage DNS records?
MANAGE_DNS := 1

# Terraform targets and providers.
TF_AUTO_APPROVE :=
TF_TARGETS := apply destroy plan refresh
TF_PROVIDERS := template google random
TF_PLUGINS := $(addsuffix _v*, $(addprefix .terraform/plugins/*/terraform-provider-, $(TF_PROVIERS)))

AUTOMATION_SSH_KEY := $(if $(GIT_SSH_KEY),automation/id_rsa,)
CP := cp
SPACE := " "
COMMA := ,

.PHONY: $(TF_TARGETS) $(AUTOMATION_SSH_KEY) test clean check_clean help tf_workspace containers

.DEFAULT_GOAL := help

-include secret.mk

help:
	@echo "Available targets:"
	@echo "  make help"
	@echo "  make test"
	@echo "  make apply"
	@echo "  make destroy"
	@echo "  make plan"
	@echo "  make refresh"
	@echo "  make clean"

check_clean:
	@echo "Terraform plugins and workspace state will be permanently destroyed!"
	@echo -n "Are you sure? [y/N] " && read ans && [ "$$ans" = "y" ]

clean:
	$(RM) $(AUTOMATION_SSH_KEY)

veryclean: check_clean clean
	$(RM) -R .terraform terraform.tfstate terraform.tfstate.backup terraform.tfstate.d

$(AUTOMATION_SSH_KEY): $(GIT_SSH_KEY)
	$(CP) $< $@

$(TF_PLUGINS):
	terraform init

terraform.tfstate.d/%:
	terraform workspace new "$(DOMAIN)"

tf_workspace: | terraform.tfstate.d/$(DOMAIN)
	terraform workspace select "$(DOMAIN)"

# TODO: Move this into a local-exec block inside Terraform?
containers:
	@:$(call check_defined, GOOGLE_PROJECT, Google Cloud project ID)
	@:$(call check_defined, GOOGLE_CONTAINER_REGISTRY, Google Cloud container registry host)
	for c in apache automation letsencrypt tiddlywiki ; do \
		gcloud container builds submit \
			--project "$(GOOGLE_PROJECT)" \
			--tag "$(GOOGLE_CONTAINER_REGISTRY)/$(GOOGLE_PROJECT)/tw5_$$c" \
			$$c ; done

# TODO: Remove this hard pre-requisite on id_rsa in cases where we use a Git
#       password instead of SSH key.
$(TF_TARGETS): $(AUTOMATION_SSH_KEY) $(TF_PLUGINS) tf_workspace
	@:$(call check_defined, GOOGLE_PROJECT, Google Cloud project ID)
	terraform $@ $(if $(TF_AUTO_APPROVE),-auto-approve,) \
		-var project="$(GOOGLE_PROJECT)" \
		-var region="$(GOOGLE_REGION)" \
		-var zone="$(GOOGLE_ZONE)" \
		-var 'trusted_cidr=["$(subst $(COMMA),"$(COMMA)",$(TRUSTED_CIDR))"]' \
		-var name="$(INSTANCE_NAME)" \
		-var machine_type="$(MACHINE_TYPE)" \
		-var domain="$(DOMAIN)" \
		-var email="$(EMAIL)" \
		-var tw_username="$(TW_USERNAME)" \
		-var tw_password="$(TW_PASSWORD)" \
		-var tw_private="$(TW_PRIVATE)" \
		-var git_repository="$(GIT_REPOSITORY)" \
		-var git_username="$(GIT_USERNAME)" \
		-var git_password="$(GIT_PASSWORD)" \
		-var letsencrypt_data="$(LETSENCRYPT_DATA)" \
		-var manage_dns="$(MANAGE_DNS)" \
		-var debug="$(DEBUG)"

# TODO: Remove this hard pre-requisite on id_rsa in cases where we use a Git
#       password instead of SSH key.
test: automation/id_rsa
	docker run \
		--rm \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v "$$PWD:/rootfs/$$PWD" \
		-w "/rootfs/$$PWD" \
		--env-file env-file \
	  docker/compose:$(DOCKER_COMPOSE_VER) up --build --force-recreate

check_defined = \
  $(strip $(foreach 1,$1, \
    $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
  $(if $(value $1),, \
    $(error Undefined $1$(if $2, ($2))$(if $(value @), \
      required by target `$@')))
