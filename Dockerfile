FROM node:22-alpine

# Argumentos de versão e arquitetura
ARG CLOUD_SDK_VERSION=586.0.0
ARG TARGETARCH

# Variáveis de ambiente
ENV PATH=$PATH:/google-cloud-sdk/bin

# 1. Pacotes do sistema (Alpine)
# - Removido daemon completo 'docker' (mantido apenas docker-cli e adicionado plugin docker-cli-buildx)
# - Removido 'ruby' e 'nano' (não utilizados)
# - 's3cmd' e 'py3-yq' instalados nativamente via apk sem compilação nem gcc/musl-dev
RUN apk add --no-cache \
    aws-cli \
    bash \
    ca-certificates \
    curl \
    docker-cli \
    docker-cli-buildx \
    findutils \
    gettext \
    git \
    jq \
    libc6-compat \
    moreutils \
    openssh \
    openssl \
    php \
    php-mbstring \
    php-phar \
    py3-cffi \
    py3-cryptography \
    py3-pip \
    py3-yq \
    python3 \
    s3cmd

# 2. Binários multi-stage (rápidos, imutáveis e multi-arch)
COPY --from=composer:2.6 /usr/bin/composer /usr/local/bin/composer
COPY --from=alpine/helm:3.17.1 /usr/bin/helm /usr/local/bin/helm

# 3. Google Cloud SDK com kubectl
# - Suporte multi-arch nativo (amd64 / arm64)
# - Streaming via curl | tar direto (sem gravar tar.gz temporário de 150MB no disco)
# - Limpeza profunda: remoção de .backup, testes, __pycache__, arquivos .pyc e telemetria
RUN case "${TARGETARCH}" in \
      "arm64") GCLOUD_ARCH="arm" ;; \
      *) GCLOUD_ARCH="x86_64" ;; \
    esac && \
    curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${CLOUD_SDK_VERSION}-linux-${GCLOUD_ARCH}.tar.gz" | tar -xz -C / && \
    /google-cloud-sdk/install.sh --additional-components kubectl --path-update true --usage-reporting false --quiet && \
    /google-cloud-sdk/bin/gcloud config set --installation component_manager/disable_update_check true && \
    /google-cloud-sdk/bin/gcloud config set --installation core/disable_usage_reporting true && \
    rm -rf /google-cloud-sdk/.install/.backup && \
    find /google-cloud-sdk -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true && \
    find /google-cloud-sdk -type d -name "test" -exec rm -rf {} + 2>/dev/null || true && \
    find /google-cloud-sdk -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true && \
    find /google-cloud-sdk -name "*.pyc" -delete && \
    find /google-cloud-sdk -name "*.pyo" -delete

# 4. Pacotes globais Node.js (posicionados após ferramentas de base para melhor cache)
# - Limpeza de testes, documentação e caches de build
RUN npm i -g --no-fund --no-audit \
    ejs-cli \
    firebase-tools \
    ts-node \
    typescript \
    @resendegu/kube-templates \
    @types/node@~24 && \
    npm cache clean --force && \
    rm -rf /root/.npm /root/.cache /tmp/* && \
    find /usr/local/lib/node_modules -type d -name "test" -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/node_modules -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/node_modules -name "*.map" -delete 2>/dev/null || true

WORKDIR /

# 5. Scripts e arquivos de configuração (camadas finais que mudam com mais frequência)
COPY kubectl/* /bin/
COPY docker/* /bin/
COPY sites/deploy /bin/deploy_site
COPY sites/undeploy /bin/undeploy_site
COPY s3/s3cfg_from_env /bin/
COPY helm/upload_chart /bin/
COPY gcs/gsutil_auth_from_env /bin/
COPY scripts/ /bin/
COPY gcs/boto.ini /root/.boto
