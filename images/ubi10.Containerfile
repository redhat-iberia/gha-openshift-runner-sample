# Inspired by https://some-natalie.dev/blog/kubernoodles-pt-5/

# This Dockerfile is used to build a custom image for GitHub Actions runners
# It includes the necessary tools and configurations to run GitHub Actions jobs

FROM registry.access.redhat.com/ubi10:10.0

LABEL org.opencontainers.image.source="https://github.com/redhat-iberia/gha-openshift-runner-sample"
LABEL org.opencontainers.image.path="images/ubi10.Dockerfile"
LABEL org.opencontainers.image.title="ubi10"
LABEL org.opencontainers.image.description="A RedHat UBI 10 based runner image for GitHub Actions"
LABEL org.opencontainers.image.authors="Ramon Gordillo (@rgordill)"
LABEL org.opencontainers.image.licenses="GPLv2"
LABEL org.opencontainers.image.documentation="TBD"

# Arguments
ARG TARGETPLATFORM
ARG RUNNER_VERSION=2.327.1
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0

# The UID env var should be used in child Containerfile.
ENV UID=1000
ENV GID=0
ENV USERNAME="runner"

# Install software
RUN dnf update -y \
  && dnf install dnf-plugins-core -y \
  && dnf install -y \
  git \
  jq \
  krb5-libs \
  libicu \
  libyaml-devel \
  openssl-libs \
  openssl \
  passwd \
  rpm-build \
  vim \
  wget \
  yum-utils \
  zlib \
  && dnf clean all

# Red Hat moved lttng to a separate repo in UBI 10
# However, it is not required for .NET as https://github.com/dotnet/runtime/pull/113876
# But it is required by https://docs.microsoft.com/en-us/dotnet/core/linux-prerequisites?tabs=netcore2x
# So we take it from CentOS Stream 10

# TODO: Make it multi-arch compatible
RUN dnf install -y https://mirror.stream.centos.org/10-stream/AppStream/x86_64/os/Packages/lttng-ust-2.13.7-5.el10.x86_64.rpm \
  && dnf clean all

RUN test -n "$TARGETPLATFORM" || (echo "TARGETPLATFORM must be set" && false)

# Create our user and their home directory
RUN useradd -m $USERNAME -u $UID -N -g 0

WORKDIR /home/runner

# Avoid changing group when doing untar/unzip
USER runner

RUN export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
  && if [ "$ARCH" = "amd64" ]; then export ARCH=x64 ; fi \
  && curl -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz \
  && tar xf ./runner.tar.gz \
  && rm runner.tar.gz

# Install container hooks
RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
  && unzip ./runner-container-hooks.zip -d ./k8s \
  && rm runner-container-hooks.zip

# Restore root for further commands
USER root

# The way to run in OpenShift with dynamic user: change group to root and set g+rw permissions
RUN chmod -R g+rwx /home/runner

# -- Install additional software/tools used for actions by the runner

# --- buildah ---
# Source: https://catalog.redhat.com/software/containers/rhel10/buildah/6704f1db2d6a34af2266c2cd?container-tabs=dockerfile
# Don't include container-selinux and remove
# directories used by yum that are just taking
# up space.
RUN dnf -y install buildah \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/yum.*

# Use vfs storage driver in OpenShift
RUN sed -i -e 's|^driver = "overlay"|driver = "vfs"|g' /usr/share/containers/storage.conf 

# Set up environment variables to note that this is
# not starting with usernamespace and default to
# isolate the filesystem with chroot.
ENV _BUILDAH_STARTED_IN_USERNS="" BUILDAH_ISOLATION=chroot

# --- GitHub CLI ---
RUN dnf -y install 'dnf-command(config-manager)' \
  && dnf -y config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo \
  && dnf -y install gh --repo gh-cli 

# --- kubectl from fedora ---
RUN dnf -y install https://dl.fedoraproject.org/pub/fedora/linux/updates/42/Everything/x86_64/Packages/k/kubernetes1.33-client-1.33.3-1.fc42.x86_64.rpm \
  && dnf clean all

# --- helm from fedora ---
RUN dnf -y install https://dl.fedoraproject.org/pub/fedora/linux/updates/42/Everything/x86_64/Packages/h/helm-3.18.4-1.fc42.x86_64.rpm \
  && dnf clean all

# restore user for further commands
USER runner