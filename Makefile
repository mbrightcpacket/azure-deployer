.DEFAULT_GOAL := build

.PHONY: build
build: format build-bicep

.PHONY: build-bicep
build-bicep:
	./create-cclearv-cloud-init.sh
	az bicep build --file main.bicep

.PHONY: default

.PHONY: tag-latest
tag-latest:
	# create a git lightweight tag for lastest release
	git tag --delete latest
	git push origin --delete latest
	git tag latest
	git push origin latest
	git --no-pager log --pretty=oneline --max-count=3

format:
	az bicep format --file main.bicep
