.PHONY: build app run icon clean

build:
	swift build -c release

app:
	./Scripts/build-app.sh release

run: app
	pkill -x NotchUsage || true
	open build/NotchUsage.app

install: app
	rm -rf /Applications/NotchUsage.app
	cp -R build/NotchUsage.app /Applications/
	open /Applications/NotchUsage.app

icon:
	swift Scripts/make-icon.swift

clean:
	rm -rf .build build
