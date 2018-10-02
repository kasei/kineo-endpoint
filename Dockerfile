FROM swift:4.2

RUN apt-get update && apt-get install -y \
	build-essential \
	libserd-dev \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir /work
WORKDIR /work

COPY Package.swift .
COPY Sources Sources
RUN swift build

RUN mkdir /endpoint

EXPOSE 8080
VOLUME ["/data"]
ENV PATH="/work/.build/debug:${PATH}"
CMD ["kineo-endpoint"]
