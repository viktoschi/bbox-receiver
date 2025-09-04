#!/bin/bash

[ ! -f $PWD/config/config.json ] && echo "/config/config.json missing! (see config.json.example)" && exit 1
[ ! -f $PWD/config/.env ] && echo "/config/.env missing! (see env.example)" && exit 1


docker build . -t belabox-receiver
docker run -itd --restart unless-stopped --name belabox-receiver \
 -p 5000:5000/udp \
 -p 8181:8181/tcp \
 -p 8282:8282/udp \
 -v $(pwd)/config:/app belabox-receiver

 docker buildx prune -a -f   

# SLS stats page:
# http://localhost:8181/stats
#
# Belabox
# host: <ip>
# port: 5000
# stream-id: live/stream/belabox
#
# OBS MediaSource:
# srt://<ip>:8282/?streamid=play/stream/belabox
#
