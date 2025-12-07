# About

Alpine linux xrdp server with xfce4 rdp server with vlc and chromium.
The xrdp audio is working and everything runs unprivileged.
Sessions run in firejail for security. Chromium sandbox is disabled.

# Start the server

```bash
docker run -d --name rdp --shm-size 1g -p 3389:3389 danielguerra/alpine-xfce4-xrdp
```

# Connect with your favorite rdp client

User: alpine
Pass: alpine

# Change the alpine user password

```bash
docker exec -ti rdp passwd alpine
```

# Add users

```bash
docker exec -ti rdp adduser myuser
```

# Run shell inside for management
```bash
docker exec -ti rdp /bin/sh
```

# Building
cd to this directory.
```
docker build --tag 'alpine-xfce4-xrdp' .
```
Run the built container:
```
docker run -d --name rdp --shm-size=1g -p 3389:3389 'alpine-xfce4-xrdp'
```
Run the built in container with RAMdisks to boost performance on spinning disk systems:
```
docker run -d --tmpfs /tmp:rw,size=1G --tmpfs /run:rw,size=64m --tmpfs /home/alpine/.cache:rw,size=1G --name rdp --shm-size=1g -p 33389:3389 'alpine-xfce4-xrdp'
```

