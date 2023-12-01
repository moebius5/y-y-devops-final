FROM debian:bullseye-slim

WORKDIR /

COPY ./bingo . 

EXPOSE 7849

USER nobody:nogroup

CMD [ "/bingo", "run_server" ]
