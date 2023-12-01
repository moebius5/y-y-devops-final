FROM debian:bullseye-slim

WORKDIR /

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl \
    && rm -rf /var/lib/apt/lists/*

COPY ./bingo . 

USER nobody:nogroup

EXPOSE 7849

CMD [ "/bingo", "run_server" ]
