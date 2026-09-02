.PHONY: build app run icon shots clean

build:
	swift build -c release

app:
	./Scripts/build-app.sh release

run: app
	pkill -x Islet || true
	open build/Islet.app

install: app
	rm -rf /Applications/Islet.app
	cp -R build/Islet.app /Applications/
	open /Applications/Islet.app

icon:
	swift Scripts/make-icon.swift

shots: build
	ISLET_MOCK=1 ISLET_SNAPSHOT=$(CURDIR)/docs/collapsed.png .build/release/Islet
	ISLET_MOCK=1 ISLET_EXPANDED=1 ISLET_SNAPSHOT=$(CURDIR)/docs/expanded.png .build/release/Islet

clean:
	rm -rf .build build
