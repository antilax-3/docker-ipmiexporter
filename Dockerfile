FROM golang:alpine AS builder

ENV CGO_ENABLED=0

RUN \
 echo "**** install build dependencies ****" && \
 apk update && apk add --no-cache git make

RUN \
 echo "**** build go application ****" && \
 mkdir -p src/github.com/lovoo/ && cd src/github.com/lovoo/ && \
 git clone https://github.com/lovoo/ipmi_exporter && \
 cd ipmi_exporter && make build

FROM antilax3/alpine

RUN \
echo "**** install runtime packages ****" && \
apk add --no-cache ipmitool

# copy executable and config
COPY --from=builder /go/src/github.com/lovoo/ipmi_exporter/build/ipmi_exporter/ipmi_exporter /app/ipmi_exporter

# set version label
ARG build_date
ARG version
LABEL build_date=$build_date
LABEL version=$version
LABEL maintainer="Nightah"

# set working directory
WORKDIR /app

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 9289