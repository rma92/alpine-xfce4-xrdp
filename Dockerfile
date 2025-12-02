FROM alpine as builder
MAINTAINER Daniel Guerra

#meta container, we want fresh builds
RUN apk update; \
    apk add alpine-sdk sudo; \
    addgroup sdk; \
    adduser  -G sdk -s /bin/sh -D sdk; \
    echo "sdk:sdk"| /usr/sbin/chpasswd; \
    echo "sdk    ALL=(ALL) ALL" >> /etc/sudoers; \
    chmod g+w /var/cache/distfiles/; \
    sudo addgroup sdk abuild;
USER sdk
WORKDIR /tmp
RUN git clone --depth 1 https://gitlab.alpinelinux.org/alpine/aports
WORKDIR /home/sdk

RUN abuild-keygen -a -n
#RUN sed -i 's/pkgver=0\.9\.13/pkgver=0\.9\.10/' APKBUILD
#RUN abuild checksum
WORKDIR /tmp/aports
RUN git pull

WORKDIR /tmp/aports/community/xrdp
RUN abuild fetch; \
    abuild unpack; \
    abuild deps; \
    abuild prepare; \
    abuild build; \
    abuild rootpkg;

ARG PULSE_VER="17.0"
ENV PULSE_VER=${PULSE_VER}
WORKDIR /tmp/aports/community/pulseaudio
RUN abuild fetch; \
    abuild unpack; \
    abuild deps; \
    abuild prepare; \
    abuild build; \
    abuild rootpkg;
WORKDIR /tmp/aports/community/pulseaudio/src/pulseaudio-"${PULSE_VER}"
RUN cp ./output/config.h .

WORKDIR /tmp/aports/community/xorgxrdp
RUN abuild fetch; \
    abuild unpack; \
    abuild deps; \
    abuild prepare; \
    abuild build; \
    abuild rootpkg;

ARG XRDPPULSE_VER="0.6"
ENV XRDPPULSE_VER=${XRDPPULSE_VER}

RUN echo sdk | sudo -S ls && echo "echo 'http://dl-cdn.alpinelinux.org/alpine/edge/testing'>>/etc/apk/repositories" | sudo sh
RUN echo sdk | sudo -S apk update
RUN echo sdk | sudo -S apk add pulseaudio-dev xrdp-dev xorgxrdp-dev
WORKDIR /tmp
RUN wget https://github.com/neutrinolabs/pulseaudio-module-xrdp/archive/refs/tags/v"${XRDPPULSE_VER}".tar.gz -O pulseaudio-module-xrdp-"${XRDPPULSE_VER}".tar.gz
RUN tar -zxf pulseaudio-module-xrdp-"${XRDPPULSE_VER}".tar.gz
WORKDIR /tmp/pulseaudio-module-xrdp-"${XRDPPULSE_VER}"
RUN ./bootstrap
RUN ./configure PULSE_DIR=/tmp/aports/community/pulseaudio/src/pulseaudio-"${PULSE_VER}"
RUN make
RUN echo sdk | sudo -S make install

RUN ls -al /tmp/pulseaudio-module-xrdp-"${XRDPPULSE_VER}"/src/.libs/module-xrdp-sink.so
RUN ls -al  /tmp/pulseaudio-module-xrdp-"${XRDPPULSE_VER}"/src/.libs/module-xrdp-source.so

# RUN STOP

FROM alpine:edge
MAINTAINER Daniel Guerra
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing">>/etc/apk/repositories

RUN apk --update --no-cache add \
    alpine-conf \
    bash \
    chromium \
    dbus \
    faenza-icon-theme \
    libpulse \
    openssh \
    paper-gtk-theme \
    paper-icon-theme \
    pavucontrol \
    pulseaudio \
    pulseaudio-utils \
    pulsemixer \
    setxkbmap \
    slim \
    sudo \
    supervisor \
    thunar-volman \
    ttf-freefont \
    util-linux \
    vim \
    xauth \
    xf86-input-synaptics \
    xfce4 \
    xfce4-pulseaudio-plugin \
    xfce4-terminal \
    xinit \
    xorg-server \
    xorgxrdp \
    xterm \
    xrdp \
&& rm -rf /tmp/* /var/cache/apk/*

# RUN rm -rf /usr/lib/pulse-"${PULSE_VER}"/modules
RUN ls /usr/lib/pulseaudio
COPY --from=builder /usr/lib/pulseaudio/modules /usr/lib/pulseaudio/modules
COPY --from=builder  /tmp/pulseaudio-module-xrdp-0.6/src/.libs  /tmp/libs
WORKDIR /tmp/libs
COPY --from=builder  /tmp/pulseaudio-module-xrdp-0.6/build-aux/install-sh /bin
RUN install-sh -c -d '/usr/lib/pulse-"${PULSE_VER}"/modules'

#COPY --from=builder /home/sdk/packages/testing/x86_64/firefox.apk /tmp/firefox.apk
RUN ldconfig -n /usr/lib/pulseaudio/modules
RUN ls $(pkg-config --variable=modlibexecdir libpulse)

RUN mkdir -p /var/log/supervisor
# add scripts/config
ADD etc /etc
ADD bin /bin

# Disable XFCE compositing (improved RDP performance)
RUN mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml \
 && cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF

# prepare user alpine
RUN addgroup alpine \
&& adduser  -G alpine -s /bin/sh -D alpine \
&& echo "alpine:alpine" | /usr/sbin/chpasswd \
&& echo "alpine    ALL=(ALL) ALL" >> /etc/sudoers

# prepare xrdp key
RUN xrdp-keygen xrdp auto

# Make startwm.sh executable by alpine user.
RUN chmod 755 /etc/xrdp \
 && chmod 755 /etc/xrdp/startwm.sh

EXPOSE 3389 22
VOLUME ["/etc/ssh"]
ENTRYPOINT ["/bin/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisor/supervisord.conf"]
