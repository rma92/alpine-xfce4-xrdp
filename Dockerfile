FROM alpine:3.23 as builder
#FROM alpine as builder
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
    pkgconf \
    openssl \
    pulseaudio \
    pulseaudio-utils \
    pulseaudio-dev \
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

COPY --from=builder /tmp/pulseaudio-module-xrdp-0.6/src/.libs/module-xrdp-sink.so   /tmp/module-xrdp-sink.so
COPY --from=builder /tmp/pulseaudio-module-xrdp-0.6/src/.libs/module-xrdp-source.so /tmp/module-xrdp-source.so

# Install them into whatever dir this pulseaudio expects
RUN PULSE_MODDIR="$(pkg-config --variable=modlibexecdir libpulse)" \
 && mkdir -p "$PULSE_MODDIR" \
 && install -m 755 /tmp/module-xrdp-sink.so   "$PULSE_MODDIR/module-xrdp-sink.so" \
 && install -m 755 /tmp/module-xrdp-source.so "$PULSE_MODDIR/module-xrdp-source.so" \
 && rm /tmp/module-xrdp-sink.so /tmp/module-xrdp-source.so

RUN mkdir -p /var/log/supervisor

# add scripts/config
ADD etc /etc
ADD bin /bin

# Disable XFCE compositing (improved RDP performance)
# This should just be appended into xdg
RUN mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml \
 && cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF

# Replace startwm.sh with a script that starts dbus + pulseaudio, then XFCE
RUN cat > /etc/xrdp/startwm.sh << 'EOF' \
 && chmod 755 /etc/xrdp/startwm.sh
#!/bin/sh

# Make sure we have an XDG runtime dir (needed by pulseaudio and friends)
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$UID
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

# Start a per-user dbus session (if not already running)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax --exit-with-session)" || echo "dbus-launch failed" >&2
fi

# Start PulseAudio for this RDP session
pulseaudio --start --exit-idle-time=-1 || echo "pulseaudio failed to start" >&2

# Finally start XFCE
exec startxfce4
EOF

# prepare user alpine
RUN addgroup alpine \
&& adduser  -G alpine -s /bin/sh -D alpine \
&& echo "alpine:alpine" | /usr/sbin/chpasswd \
&& echo "alpine    ALL=(ALL) ALL" >> /etc/sudoers

# prepare xrdp key
RUN xrdp-keygen xrdp auto

# Make startwm.sh executable by alpine user.
RUN chmod 755 /etc/xrdp

EXPOSE 3389 22
VOLUME ["/etc/ssh"]
ENTRYPOINT ["/bin/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisor/supervisord.conf"]
