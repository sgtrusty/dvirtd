FROM archlinux/archlinux:base-devel-20260503.0.523481

ARG BUILD_DATE
ARG UUID=1000
ARG GUID=$UUID

LABEL maintainer="dvirtd"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.build-date=$BUILD_DATE
LABEL org.label-schema.name="dvirtd/builder"
LABEL org.label-schema.description="Base containerized development environment"

ENV FLAVOR=builder
ENV TZ="UTC"
ENV USERNEW=archlinux

RUN sed -e '/NoProgressBar/ s/^#*/#/' -i /etc/pacman.conf ;\
    sed -e '/Color/ s/^#//' -i /etc/pacman.conf

RUN pacman -Syy
RUN pacman -S --needed --noconfirm openssl
COPY mixins/$FLAVOR/mirrorlist /etc/pacman.d/mirrorlist
RUN pacman -Syyu --noconfirm --needed

RUN groupadd -g "${GUID}" "${USERNEW}" ;\
    useradd -ms /bin/bash "${USERNEW}" -u "${UUID}" -g "${USERNEW}" -g wheel

USER $USERNEW
WORKDIR /home/"${USERNEW}"

ENTRYPOINT ["/bin/bash", "-l", "-c"]
