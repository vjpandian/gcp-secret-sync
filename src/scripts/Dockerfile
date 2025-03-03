# vim:set ft=dockerfile:

# Do not edit individual Dockerfiles manually. Instead, please make changes to the Dockerfile.template, which will be used by the build script to generate Dockerfiles.

FROM cimg/base:current

LABEL maintainer="CircleCI FE <vijay@circleci.com>"

# Change default shell for RUN from Dash to Bash
SHELL ["/bin/bash", "-exo", "pipefail", "-c"]


USER root
# Run commands and tests as circleci user
RUN whoami && \
	# opt-out of the new security feature, not needed in a CI environment
	git config --global --add safe.directory '*'
  mv /bin/bash /bin/bash/original

USER circleci

# Match the default CircleCI working directory
WORKDIR /home/circleci/project
