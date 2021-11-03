# Dockerfile to run the staging tests

ARG GOLANG_VERSION=1.15.2
ARG DISTRO_NAME
ARG DISTRO_VERS

FROM ppc64le/$DISTRO_NAME:$DISTRO_VERS

ARG GOLANG_VERSION
ARG DISTRO_NAME
ARG DISTRO_VERS

WORKDIR /workspace
RUN mkdir -p /workspace
ENV WORKSPACE=/workspace \
    TERM=xterm
ENV PATH /usr/local/go/bin:$PATH


RUN if [ -f /bin/rpm  ] ; \
    then\
     echo rpm ; \
     set -eux; yum -y install wget make gcc findutils;\
    else \
        echo deb;\
        apt-get update && apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg2 \
        wget \
        software-properties-common \
        lsb-release\
        make\
        gcc\
        libc-dev\
        procps\
        iptables libdevmapper1.02.1 && \
        rm -rf /var/lib/apt/lists/* ;\
    fi

#Install from Docker-ce staging
RUN set -eux; curl -fsSL https://download-stage.docker.com/linux/${DISTRO_NAME}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg &&\
    echo "deb [arch=ppc64el signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download-stage.docker.com/linux/${DISTRO_NAME} ${DISTRO_VERS} stable"\
    | tee /etc/apt/sources.list.d/docker.list > /dev/null  &&\
    apt-get update && apt-get -y install docker-ce docker-ce-cli containerd.io

##
#Docker in Docker inspired from
#  https://github.com/docker-library/docker/tree/master/20.10/dind
# set up subuid/subgid so that "--userns-remap=default" works out-of-the-box
##
RUN set -eux; \
        addgroup --system dockremap; \
        adduser --system --ingroup dockremap dockremap; \
        echo 'dockremap:165536:65536' >> /etc/subuid; \
        echo 'dockremap:165536:65536' >> /etc/subgid

# https://github.com/docker/docker/tree/master/hack/dind
ENV DIND_COMMIT ed89041433a031cafc0a0f19cfe573c31688d377

RUN set -eux; \
        wget -O /usr/local/bin/dind "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind"; \
        chmod +x /usr/local/bin/dind;

RUN set -eux; \
	url="https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-ppc64le.tar.gz";\
    wget -O go.tgz "$url" --progress=dot:giga; \
    tar -C /usr/local -xzf go.tgz; \
    rm go.tgz; \
    go version;

COPY test_launch.sh /usr/local/bin

VOLUME /var/lib/docker
EXPOSE 2375 2376

ENTRYPOINT ["test_launch.sh"]
CMD []
