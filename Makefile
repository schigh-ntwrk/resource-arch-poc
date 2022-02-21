.DELETE_ON_ERROR:
.DEFAULT_GOAL := help
_YELLOW=\033[0;33m
_NC=\033[0m
SHELL := $(shell which bash) -o pipefail

# --------------------------------------------------------------------------------

BIN_DIR        = $(CURDIR)/bin

# https://github.com/protocolbuffers/protobuf/releases/latest
PROTOC_VERSION="3.19.3"
# https://github.com/protocolbuffers/protobuf-go/releases
PROTOC_GEN_GO_VERSION="1.27.1"
# https://pkg.go.dev/google.golang.org/grpc/cmd/protoc-gen-go-grpc?tab=versions
PROTOC_GEN_GO_GRPC_VERSION="1.2.0"
# https://github.com/bufbuild/buf/releases
BUF_VERSION="1.0.0"

# tool urls
PROTOC_URL=""
ifeq ($(shell uname -s), Darwin)
	PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-osx-x86_64.zip"
else
	PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"
endif

# System requirements checks
CURL_INSTALLED=""
ifneq (, $(shell which curl))
	CURL_INSTALLED="yes"
endif

UNZIP_INSTALLED=""
ifneq (, $(shell which unzip))
	UNZIP_INSTALLED="yes"
endif

GO_INSTALLED=""
ifneq (, $(shell which go))
	GO_INSTALLED="yes"
endif


# Tools to be installed to BIN_DIR
default_tool_version="latest"
goimports_version=${default_tool_version}
TOOLS := "golang.org/x/tools/cmd/goimports@${goimports_version}"
golangci_version="v1.43.0"
TOOLS := $(TOOLS) "github.com/golangci/golangci-lint/cmd/golangci-lint@${golangci_version}"
mockgen_version=${default_tool_version}
TOOLS := $(TOOLS) "github.com/golang/mock/mockgen@${mockgen_version}"
wire_version=${default_tool_version}
TOOLS := $(TOOLS) "github.com/google/wire/cmd/wire@${wire_version}"
fieldalign_version=${default_tool_version}
TOOLS := $(TOOLS) "golang.org/x/tools/go/analysis/passes/fieldalignment/cmd/fieldalignment@${fieldalign_version}"

#	############################################################
#	NON-PATH TARGETS
#	############################################################

.PHONY: help
help: ## prints this help
	@ grep -hE '^[\.a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "${_YELLOW}%-16s${_NC} %s\n", $$1, $$2}'

.PHONY: tools
tools: tools-protoc tools-buf tools-protoc-gen-go tools-protoc-gen-grpc ## install tools
	@ $(MAKE) $(BIN_DIR)

.PHONY: tools-protoc
tools-protoc: $(BIN_DIR) _require-curl _require-unzip ## get schema compiler
	@{\
  		echo "installing protoc compiler" ; \
  		curl -L -s $(PROTOC_URL) --output "${BIN_DIR}/protoc.zip" ; \
  		unzip -u "${BIN_DIR}/protoc.zip" ; \
  		rm -f "${BIN_DIR}/protoc.zip" ; \
  		rm -f "$(CURDIR)/readme.txt" ; \
  	}

.PHONY: tools-protoc-gen-go
tools-protoc-gen-go: $(BIN_DIR) _require-go ## get schema codegen for go
	@{ \
  		echo "installing protoc-gen-go" ; \
  		GO111MODULE=on GOBIN="${BIN_DIR}" go install "google.golang.org/protobuf/cmd/protoc-gen-go@v${PROTOC_GEN_GO_VERSION}" ; \
	}

.PHONY: tools-protoc-gen-grpc
tools-protoc-gen-grpc: $(BIN_DIR) _require-go ## get grpc service gen tools
	@{\
  		echo "installing protoc-gen-go-grpc" ; \
  		GO111MODULE=on GOBIN="${BIN_DIR}" go install "google.golang.org/grpc/cmd/protoc-gen-go-grpc@v${PROTOC_GEN_GO_GRPC_VERSION}" ; \
  	}

.PHONY: tools-reinstall
tools-reinstall: ## delete bin folder and reinstall tools
	@{\
  		echo "removing ${BIN_DIR}" ; \
  		rm -rf "${BIN_DIR}" ; \
  		$(MAKE) tools ; \
  	}

.PHONY: fmt
fmt: $(BIN_DIR) ## runs Go code formatting
	@{\
  		gofmt -s -w $(CURDIR) ;\
  		$(BIN_DIR)/goimports -format-only -w -local "github.com/schigh-ntwrk1/resource-arch-poc" $(CURDIR) ; \
  	}

.PHONY: lint
lint: $(BIN_DIR) ## runs Go linter
	@{ \
  		$(BIN_DIR)/golangci-lint cache clean ; \
  		$(BIN_DIR)/golangci-lint run --verbose --out-format colored-line-number --config ./.golangci.yml ; \
	}

.PHONY: lint-ci
lint-ci: $(BIN_DIR) ## runs linter for CI
	@{ \
		$(BIN_DIR)/golangci-lint cache clean ; \
		$(BIN_DIR)/golangci-lint run --config ./.golangci.yml ; \
	}

.PHONY: align
align: $(BIN_DIR) ## optimize struct field alignment
	@{\
  		$(BIN_DIR)/fieldalignment -fix ./... ; \
  	}

.PHONY: test/unit
test/unit: ## runs unit tests for entire project
	@ go test -v -race -cover ./...

.PHONY: tools-buf
tools-buf: $(BIN_DIR) _require-curl ## install buf tooling
	@{\
		echo "fetching buf" ; \
  		curl -sSL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-$(shell uname -s)-$(shell uname -m)" -o "${BIN_DIR}/buf" ; \
  		chmod +x "$(BIN_DIR)/buf" ; \
  		echo "fetching protoc-gen-buf-breaking" ; \
  		curl -sSL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/protoc-gen-buf-breaking-$(shell uname -s)-$(shell uname -m)" -o "${BIN_DIR}/protoc-gen-buf-breaking" ; \
		chmod +x "$(BIN_DIR)/protoc-gen-buf-breaking" ; \
		echo "fetching protoc-gen-buf-lint" ; \
		curl -sSL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/protoc-gen-buf-lint-$(shell uname -s)-$(shell uname -m)" -o "${BIN_DIR}/protoc-gen-buf-lint" ; \
		chmod +x "$(BIN_DIR)/protoc-gen-buf-lint" ; \
  	}

.PHONY: proto
proto: $(BIN_DIR) ## build proto artifacts
	@{\
  		$(BIN_DIR)/protoc \
			--plugin $(BIN_DIR)/protoc-gen-go \
			--plugin $(BIN_DIR)/protoc-gen-grpc \
			-I="./schema-registry" \
			--go_out=./schema-common \
			ntwrk/partner/v1/partner.proto ; \
  	}

# ---------------------------

.PHONY: _require-curl
_require-curl:
	@{\
  		if [[ "${CURL_INSTALLED}" == "" ]] ; then \
  			echo "curl is required to perform the requested action" ; \
  			exit 1 ; \
  		fi \
  	}

.PHONY: _require-unzip
_require-unzip:
	@{\
  		if [[ "${UNZIP_INSTALLED}" == "" ]] ; then \
  			echo "unzip is required to perform the requested action" ; \
  			exit 1 ; \
  		fi \
  	}

.PHONY: _require-go
_require-go:
	@{\
  		if [[ "${GO_INSTALLED}" == "" ]] ; then \
  			echo "go is required to perform the requested action" ; \
  			exit 1 ; \
  		fi \
  	}

#	############################################################
#	PATH TARGETS
#	############################################################

$(BIN_DIR):
	@{\
  		for tool in $(TOOLS) ; do \
  		  	echo "installing $$tool" ; \
			GOBIN="${BIN_DIR}" go install $$tool ; \
		done \
  	}

$(BUILD_DIR):
	@ mkdir -p $(CURDIR)/build
