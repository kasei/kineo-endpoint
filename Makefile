prefix ?= /usr/local
bindir = $(prefix)/bin
libdir = $(prefix)/lib

build:
	swift build -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.14" -c release --disable-sandbox

install: build
	install ".build/release/kineo-endpoint" "$(bindir)"

uninstall:
	rm -rf "$(bindir)/kineo-endpoint"

clean:
	rm -rf .build

.PHONY: build install uninstall clean
