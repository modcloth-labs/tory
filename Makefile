PACKAGE := github.com/modcloth/tory
SUBPACKAGES := $(PACKAGE)/tory

COVERPROFILES := \
  main.coverprofile \
  tory.coverprofile

VERSION_VAR := $(PACKAGE)/tory.VersionString
VERSION_VALUE := $(shell git describe --always --dirty --tags)

REV_VAR := $(PACKAGE)/tory.RevisionString
REV_VALUE := $(shell git rev-parse --sq HEAD)

BRANCH_VAR := $(PACKAGE)/tory.BranchString
BRANCH_VALUE := $(shell git rev-parse --abbrev-ref HEAD)

GENERATED_VAR := $(PACKAGE)/tory.GeneratedString
GENERATED_VALUE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

DOCKER_TAG ?= quay.io/modcloth/tory:latest

DATABASE_URL ?= postgres://$(shell whoami)@localhost/tory?sslmode=disable
PORT ?= 9462

DOCKER ?= docker
GO ?= go
GOX ?= gox
GODERP ?= goderp
GO_BINDATA ?= go-bindata
GOPATH := $(shell echo "$${GOPATH%%:*}")
ifeq ($(shell uname),Darwin)
SHA256SUM ?= gsha256sum
else
SHA256SUM ?= sha256sum
endif
GOBUILD_LDFLAGS := -ldflags "\
  -X $(VERSION_VAR) $(VERSION_VALUE) \
  -X $(REV_VAR) $(REV_VALUE) \
  -X $(BRANCH_VAR) $(BRANCH_VALUE) \
  -X $(GENERATED_VAR) $(GENERATED_VALUE) \
  -w -s"
GOBUILD_FLAGS ?= -tags 'netgo'
GOTEST_FLAGS ?=

GOX_OSARCH ?= linux/amd64 darwin/amd64 windows/amd64
GOX_FLAGS ?= \
	-output="tory-{{.OS}}-{{.Arch}}/bin/{{.Dir}}" \
	-osarch="$(GOX_OSARCH)"

CROSS_TARBALLS := \
	tory-linux-amd64.tar.bz2 \
	tory-darwin-amd64.tar.bz2 \
	tory-windows-amd64.tar.bz2
ALLFILES := $(shell git ls-files)

CGO_ENABLED ?= 0
QUIET ?=
VERBOSE ?=

export CGO_ENABLED
export QUIET
export VERBOSE
export GOPATH
export DATABASE_URL

.PHONY: all
all: clean build migrate test save

.PHONY: build
build: deps .build

.PHONY: .build
.build:
	$(GODERP) $(GO) install -a $(GOBUILD_FLAGS) $(GOBUILD_LDFLAGS) $(PACKAGE) $(SUBPACKAGES)

.PHONY: deps
deps: tory/bindata.go

tory/bindata.go: .go-bindata-bootstrap $(wildcard public/*)
	$(GO_BINDATA) -prefix=public -o=$@ -pkg=tory ./public

.go-bindata-bootstrap:
	$(GO) get -x $(GOBUILD_FLAGS) github.com/jteeuwen/go-bindata/go-bindata > $@

.PHONY: crossbuild
crossbuild: deps .gox-bootstrap
	$(GOX) $(GOX_FLAGS) $(GOBUILD_LDFLAGS) $(PACKAGE) $(SUBPACKAGES)

.PHONY: crosstars
crosstars: $(CROSS_TARBALLS) SHA256SUMS

SHA256SUMS: $(CROSS_TARBALLS)
	$(SHA256SUM) $(CROSS_TARBALLS) > $@

tory-linux-amd64.tar.bz2: crossbuild
	tar -cjvf $@ tory-linux-amd64

tory-darwin-amd64.tar.bz2: crossbuild
	tar -cjvf $@ tory-darwin-amd64

tory-windows-amd64.tar.bz2: crossbuild
	tar -cjvf $@ tory-windows-amd64

.gox-bootstrap:
	$(GOX) -build-toolchain -osarch="$(GOX_OSARCH)" -verbose 2>&1 | tee $@

.PHONY: test
test: build test-deps .test

.PHONY: .test
.test: coverage.html

coverage.html: all.coverprofile
	$(GODERP) $(GO) tool cover -func=$<
	$(GODERP) $(GO) tool cover -html=$< -o $@

all.coverprofile: $(COVERPROFILES)
	echo 'mode: count' > $@
	grep -h -v 'mode: count' $^ >> $@

main.coverprofile:
	$(GODERP) $(GO) test $(GOTEST_FLAGS) $(GOBUILD_LDFLAGS) \
	  -coverprofile=$@ -covermode=count $(PACKAGE)

tory.coverprofile:
	$(GODERP) $(GO) test $(GOTEST_FLAGS) $(GOBUILD_LDFLAGS) \
	  -coverprofile=$@ -covermode=count github.com/modcloth/tory/tory

.PHONY: migrate
migrate: build
	$(GOPATH)/bin/tory migrate -d $(DATABASE_URL)

.PHONY: test-deps
test-deps:
	$(GODERP) $(GO) test -i $(GOTEST_FLAGS) $(GOBUILD_LDFLAGS) $(PACKAGE) $(SUBPACKAGES)

.PHONY: clean
clean:
	$(RM) -r .coverage .*-bootstrap .cache/ $(shell find . -name '*.pyc')
	$(RM) $(GOPATH)/bin/tory *.coverprofile coverage.html
	$(RM) -r tory-*-amd64*
	$(GODERP) $(GO) clean -x $(PACKAGE) $(SUBPACKAGES)

.PHONY: distclean
distclean: clean
	$(RM) .gox-bootstrap .go-bindata-bootstrap

.PHONY: save
save:
	$(GODERP) save $(PACKAGE) $(SUBPACKAGES)

.PHONY: build-container
build-container:
	$(DOCKER) build -t $(DOCKER_TAG) .

.PHONY: run-container
run-container:
	$(DOCKER) run -p $(PORT):$(PORT) -e DATABASE_URL=$(DATABASE_URL) $(DOCKER_TAG)
