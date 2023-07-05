.DEFAULT_GOAL := build

.PHONY: build
build: format build-bicep

.PHONY: build-bicep
build-bicep:
	./create-cclearv-cloud-init.sh
	az bicep build --file main.bicep

.PHONY: tag-latest
tag-latest:
	# create a git lightweight tag for lastest release
	git tag --delete latest
	git push origin --delete latest
	git tag latest
	git push origin latest
	git --no-pager log --pretty=oneline --max-count=3

.PHONY: format
format:
	az bicep format --file main.bicep

.PHONY: generate-params
generate-params:
	bicep generate-params main.bicep --output-format json --include-params all
	bicep generate-params main.bicep --output-format bicepparam --include-params all
