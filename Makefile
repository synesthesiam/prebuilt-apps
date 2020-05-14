.PHONY: build dist

PLATFORMS ?= linux/amd64,linux/arm/v7,linux/arm64,linux/arm/v6

all: build

build:
	docker buildx build . --platform $(PLATFORMS) --output type=local,dest=dist
