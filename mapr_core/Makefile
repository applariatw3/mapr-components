include make_env

CORE_VERSION ?= 6.0.0
MEP_VERSION ?=$ 4.0.0
BASE_OS ?= ubuntu14
ACCOUNT ?= maprtech
IMAGE_NAME ?= mapr-core
IMAGE_TAG ?= ${CORE_VERSION}_${MEP_VERSION}_${BASE_OS}}
PUSH_TO_HUB=${7:-0}

NS ?= jmkhael
VERSION ?= latest

IMAGE_NAME ?= mx-fs
CONTAINER_NAME ?= mx-fs
CONTAINER_INSTANCE ?= default

.PHONY: build build-arm push push-arm shell shell-arm run run-arm start start-arm stop stop-arm rm rm-arm release release-arm

build: Dockerfile
    docker build -t $(NS)/$(IMAGE_NAME):$(VERSION) -f Dockerfile .

build-arm: Dockerfile.arm
    docker build -t $(NS)/rpi-$(IMAGE_NAME):$(VERSION) -f Dockerfile.arm .