.PHONY: help test build app install uninstall demo screenshots zip clean

help:  ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

test:  ## Run the test suite
	scripts/test.sh

build:  ## Debug build of the executable
	swift build

app:  ## Build dist/Review Queue.app (universal)
	scripts/build-app.sh

install:  ## Build, install to ~/Applications and start
	scripts/install.sh

uninstall:  ## Quit, remove the app, its login item and its settings
	-"$(HOME)/Applications/Review Queue.app/Contents/MacOS/ReviewQueue" --unregister-login-item
	-pkill -x ReviewQueue
	rm -rf "$(HOME)/Applications/Review Queue.app"
	-defaults delete io.github.sam-cook.review-queue

demo: build  ## Run with made-up data (no GitHub access)
	.build/debug/ReviewQueue --demo

screenshots: build  ## Regenerate the README screenshots from demo data
	rm -f docs/*.png
	for scene in queue expanded team icons; do \
	  .build/debug/ReviewQueue --snapshot docs/$$scene-light.png --demo --scene $$scene && \
	  .build/debug/ReviewQueue --snapshot docs/$$scene-dark.png --demo --scene $$scene --dark || exit 1; \
	done

zip: app  ## Zip the app for a release
	cd dist && ditto -c -k --keepParent "Review Queue.app" "ReviewQueue-$$(tr -d '[:space:]' < ../VERSION).zip"

clean:  ## Remove build output
	rm -rf .build dist
