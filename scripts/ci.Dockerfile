# CI's environment on the PC (scripts/in-docker.sh): Ubuntu 22.04 with the packages from ci-deps.sh.
FROM ubuntu:22.04
COPY ci-deps.sh /tmp/ci-deps.sh
RUN sh /tmp/ci-deps.sh && rm -rf /var/lib/apt/lists/* /tmp/ci-deps.sh
