FROM swift:5.2	

RUN apt-get update && apt-get install -y \
	build-essential \
	libserd-dev \
	libsqlite3-dev \
	libssl-dev \
	zlib1g-dev \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir /work
WORKDIR /work

RUN mkdir -p /data/default
RUN mkdir -p /data/named

COPY Package.swift .
RUN swift package update
COPY Sources Sources
RUN swift build -c release
COPY entrypoint.sh entrypoint.sh

RUN mkdir /endpoint

EXPOSE 8080
VOLUME ["/data"]
ENV PATH="/work:/work/.build/release:${PATH}"

ENTRYPOINT ["kineo-endpoint"]
CMD ["-D", "/data"]
