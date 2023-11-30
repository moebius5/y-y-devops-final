FROM gcr.io/distroless/static-debian12:latest-amd64

WORKDIR /

COPY ./bingo . 

EXPOSE 7849

USER nonroot:nonroot

CMD [ "/bingo", "run_server" ]
