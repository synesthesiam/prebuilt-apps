.PHONY: build dist

PLATFORMS = linux/amd64,linux/arm/v7,linux/arm64,linux/arm/v6
TAG = $(DOCKER_REGISTRY)rhasspy/prebuilt-apps

all: build

build:
	docker buildx build . --platform $(PLATFORMS) --tag $(TAG) --push

dist:
	./create-dists.sh $(PLATFORMS) $(TAG)
