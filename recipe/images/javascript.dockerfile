ARG REGISTRY=dvirtd
ARG MIRROR_VERSION=0.0.0
FROM ${REGISTRY}/mirror:${MIRROR_VERSION} AS base

ENV USERNEW=archlinux

USER root

RUN pacman -Syy
RUN pacman -S --noconfirm unzip

USER $USERNEW
WORKDIR /home/"${USERNEW}"

ENV BASH_ENV /home/"${USERNEW}"/.bashrc
ENV VOLTA_HOME /home/"${USERNEW}"/.volta
ENV PATH $VOLTA_HOME/bin:$PATH

RUN curl https://get.volta.sh | bash
RUN volta install node
RUN volta install yarn
RUN volta install pnpm

USER $USERNEW
WORKDIR /home/"${USERNEW}"

ENTRYPOINT ["/bin/bash", "-l", "-c"]
