.PHONY: build app run icon clean

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

clean:
	rm -rf .build build
