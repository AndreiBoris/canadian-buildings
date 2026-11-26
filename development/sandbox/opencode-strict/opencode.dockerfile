# syntax=docker/dockerfile:1@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183

# -- Pinned versions (single source of truth) ----------------------------------
ARG OPENCODE_VERSION=2.4.0

# Config & markup
ARG JQ_VERSION=1.8.2
ARG YQ_VERSION=4.54.3
ARG TAPLO_VERSION=0.10.0
ARG TAPLO_SHA256_AMD64=8fe196b894ccf9072f98d4e1013a180306e17d244830b03986ee5e8eabeb6156
ARG TAPLO_SHA256_ARM64=033681d01eec8376c3fd38fa3703c79316f5e14bb013d859943b60a07bccdcc3
ARG YAMLFMT_VERSION=0.21.0
ARG YAMLLINT_VERSION=1.38.0
ARG CHECK_JSONSCHEMA_VERSION=0.39.0

# Infra & CI
ARG ACTIONLINT_VERSION=1.7.12
ARG HADOLINT_VERSION=v2.15.1
ARG SHELLCHECK_VERSION=v0.11.0

# Security & Python
ARG BETTERLEAKS_VERSION=v1.9.0
ARG UV_VERSION=0.13.10
ARG RUFF_VERSION=0.17.6
ARG PYREFLY_VERSION=1.5.0

# -- Official binary stages (pulled in parallel, multi-arch automatically) -----
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv
FROM ghcr.io/jqlang/jq:${JQ_VERSION} AS jq
FROM mikefarah/yq:${YQ_VERSION} AS yq
FROM rhysd/actionlint:${ACTIONLINT_VERSION} AS actionlint
FROM hadolint/hadolint:${HADOLINT_VERSION} AS hadolint
FROM koalaman/shellcheck:${SHELLCHECK_VERSION} AS shellcheck
FROM ghcr.io/betterleaks/betterleaks:${BETTERLEAKS_VERSION} AS betterleaks
FROM ghcr.io/google/yamlfmt:${YAMLFMT_VERSION} AS yamlfmt

# -- Final sandbox image -------------------------------------------------------
# Pinned by digest; bump deliberately with the command in docs/agent_sandbox.md.
FROM docker/sandbox-templates:opencode@sha256:7feb9784bc882dbe014888becb65c23e7fb1d1b24169a68d33660fe44476a0b4

USER root
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# 1. OpenCode CLI (slowest layer -> goes first)
ARG OPENCODE_VERSION
RUN npm uninstall -g opencode-ai \
    && npm install -g "@opencode/cli@${OPENCODE_VERSION}" --include=optional

# 2. Pin uv/uvx (overwrites base image's unpinned uv)
COPY --link --from=uv /uv /uvx /usr/local/bin/

# 3. Python-ecosystem verifiers (immutable, self-describing for `agent`)
ENV UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON_PREFERENCE=only-system

ARG YAMLLINT_VERSION
ARG CHECK_JSONSCHEMA_VERSION
ARG RUFF_VERSION
ARG PYREFLY_VERSION
RUN --mount=type=cache,target=/root/.cache/uv \
    uv tool install "yamllint==${YAMLLINT_VERSION}" \
    && uv tool install "check-jsonschema==${CHECK_JSONSCHEMA_VERSION}" \
    && uv tool install "ruff==${RUFF_VERSION}" \
    && uv tool install "pyrefly==${PYREFLY_VERSION}" \
    && chmod -R a+rX /opt/uv-tools

# 4. Taplo (verified per-arch prebuilt release binary)
ARG TARGETARCH
ARG TAPLO_VERSION
ARG TAPLO_SHA256_AMD64
ARG TAPLO_SHA256_ARM64
RUN case "${TARGETARCH}" in \
      amd64) TAPLO_ARCH="x86_64";  TAPLO_SHA256="${TAPLO_SHA256_AMD64}" ;; \
      arm64) TAPLO_ARCH="aarch64"; TAPLO_SHA256="${TAPLO_SHA256_ARM64}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 3 --retry-all-errors -o /tmp/taplo.gz \
       "https://github.com/tamasfe/taplo/releases/download/${TAPLO_VERSION}/taplo-linux-${TAPLO_ARCH}.gz" \
    && echo "${TAPLO_SHA256}  /tmp/taplo.gz" | sha256sum -c - \
    && gzip -dc /tmp/taplo.gz > /usr/local/bin/taplo \
    && rm -f /tmp/taplo.gz \
    && chmod 755 /usr/local/bin/taplo

# 5. Static verifier binaries (placed after RUN layers so bumps rebuild in ~1s)
COPY --link --from=jq          /jq                       /usr/local/bin/jq
COPY --link --from=yq          /usr/bin/yq               /usr/local/bin/yq
COPY --link --from=actionlint  /usr/local/bin/actionlint /usr/local/bin/actionlint
COPY --link --from=hadolint    /bin/hadolint             /usr/local/bin/hadolint
COPY --link --from=shellcheck  /bin/shellcheck           /usr/local/bin/shellcheck
COPY --link --from=betterleaks /usr/bin/betterleaks      /usr/local/bin/betterleaks
COPY --link --from=yamlfmt     /bin/yamlfmt              /usr/local/bin/yamlfmt

# Pre-create /etc/opencode as root (0755): traversable by agent,
# read-only to it, avoids COPY --chmod=644 stripping +x (below)
RUN install -d -m 755 /etc/opencode \
    && touch /etc/opencode/sandbox

# 6. Build-time smoke test as the actual runtime user
USER agent
RUN set -x \
    && opencode --version \
    && test "$(command -v jq)" = "/usr/local/bin/jq" \
    && yamllint --version \
    && jq --version \
    && yq --version \
    && check-jsonschema --version \
    && yamlfmt -version \
    && taplo --version \
    && actionlint -version \
    && hadolint --version \
    && shellcheck --version \
    && betterleaks version \
    && ruff --version \
    && uv --version \
    && pyrefly --version \
    && tools="$(uv tool list)" \
    && printf '%s\n' "$tools" \
    && test "$(printf '%s\n' "$tools" | grep -c '^ruff')" -eq 1

# 7. Config last + offline JSON syntax/permission check
COPY --chmod=644 opencode.json /etc/opencode/opencode.json
RUN jq empty /etc/opencode/opencode.json

ENTRYPOINT ["opencode"]
CMD []
