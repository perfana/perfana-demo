FROM golang:1.10 as build
WORKDIR /
ENV GOOS=linux
ENV GOARCH=amd64
ENV CGO_ENABLED=0
RUN go get github.com/nathanielc/morgoth/cmd/morgoth

FROM kapacitor
EXPOSE 6767
COPY --from=build /go/bin/morgoth /morgoth
RUN mkdir -p /sockets
CMD ["/morgoth", "-socket", "/sockets/morgoth"]
