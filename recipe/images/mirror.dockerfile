ARG REGISTRY=dvirtd
ARG BUILDER_VERSION=0.0.0
FROM ${REGISTRY}/builder:${BUILDER_VERSION} AS base

ARG GIT_AUTHOR_NAME
ARG GIT_AUTHOR_EMAIL

ENV FLAVOR=mirror
ENV USERNEW=archlinux
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

USER root

RUN pacman -Syy
RUN pacman -S --noconfirm glibc-locales
RUN echo "LANG=en_US.UTF-8" > /etc/locale.conf
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
RUN locale-gen en_US.UTF-8

RUN pacman -S --needed --noconfirm git vim kitty man
RUN pacman -S --noconfirm i3 dmenu
RUN pacman -S --noconfirm xorg-xrandr xorg-setxkbmap
RUN pacman -Syu --noconfirm
RUN pacman -Scc --noconfirm

USER $USERNEW
WORKDIR /home/"${USERNEW}"

RUN git config --global user.name "${GIT_AUTHOR_NAME}"
RUN git config --global user.email "${GIT_AUTHOR_EMAIL}"

RUN mkdir -p ~/.config
COPY mixins/${FLAVOR}/config/ /home/"${USERNEW}"/.config/
COPY mixins/${FLAVOR}/env/ /home/"${USERNEW}"/
RUN mv /home/"${USERNEW}"/{bashrc,.bashrc}

USER root
RUN chown -R ${USERNEW}:users /home/"${USERNEW}"
RUN chmod +x /home/"${USERNEW}"/arch-entry.sh
RUN ln -s /home/"${USERNEW}"/arch-entry.sh /usr/local/bin/arch-entry

USER $USERNEW
WORKDIR /home/"${USERNEW}"

ENTRYPOINT ["/bin/bash", "-l", "-c"]
