-include makefile.pass

# {{{ -- meta

OPSYS            := jinade
SVCNAME          := bind9
DOCKERSRC        := $(OPSYS)_base

USERNAME         := cretinon
DOCKER_USER      := cretinon
GITHUB_USER      := cretinon
EMAIL            := jacques@cretinon.fr

HOSTARCH         := x86_64# on travis.ci
ARCH             := $(shell uname -m | sed "s_armv7l_armhf_") # armhf/x86_64 auto-detect on build and run

SHCOMMAND        := /bin/bash

IMAGETAG         := $(DOCKER_USER)/$(OPSYS)_$(SVCNAME):$(DISTRIB)_$(ARCH)

CNTNAME          := $(SVCNAME) # name for container name : $(OPSYS)_name, hostname : name

PUID             := $(shell id -u)
PGID             := $(shell id -g) 

# -- }}}

# {{{ -- docker build and run flags

BUILDFLAGS := --rm --force-rm --compress -f $(CURDIR)/$(ARCH)/$(DISTRIB)/Dockerfile -t $(IMAGETAG) \
	--build-arg ARCH=$(ARCH) \
	--build-arg DOCKERSRC=$(DOCKERSRC) \
	--build-arg USERNAME=$(DOCKER_USER) \
        --build-arg DISTRIB=$(DISTRIB) \
	--build-arg PUID=$(PUID) \
	--build-arg PGID=$(PGID) \
	--label org.label-schema.build-date=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ") \
	--label org.label-schema.name=$(OPSYS)_$(SVCNAME) \
	--label org.label-schema.schema-version="1.0" \
	--label org.label-schema.url="https://github.com/$(GITHUB_USER)/$(OPSYS)_$(SVCNAME)" \
	--label org.label-schema.usage="https://github.com/$(GITHUB_USER)/$(OPSYS)_$(SVCNAME)" \
	--label org.label-schema.vcs-ref=$(shell git rev-parse --short HEAD) \
	--label org.label-schema.vcs-url="https://github.com/$(GITHUB_USER)/$(OPSYS)_$(SVCNAME)" \
	--label org.label-schema.vendor=$(DOCKER_USER)

MOUNTFLAGS := -v /mnt/nfs/DebianShare/bind9:/data
OTHERFLAGS := --network bind-net --ip=$(IP) --privileged 
PORTFLAGS  := -p 53:53/udp
CACHEFLAGS := # --no-cache=true --pull
NAMEFLAGS  := --name $(OPSYS)_$(CNTNAME) --hostname $(CNTNAME)
RUNFLAGS   := -e PGID=$(PGID) -e PUID=$(PUID)

# -- }}}


# {{{ -- docker run args
#sample master     -j -v -c -d jinade.me -m --ns1 jinade1 --ipns1 217.182.142.201 -r
ifeq "$(origin CONTARGS)" "undefined"
CONTARGS    := -j -v -r
endif


# -- }}}


# {{{ -- docker targets

all : build start

build : 
	if [ "$(DISTRIB)" = "alpine" ]; then make fetch; fi
	echo "Building $(DISTRIB) for $(ARCH) from $(HOSTARCH)";
	if [ "$(ARCH)" != "$(HOSTARCH)" ]; then make regbinfmt fetchqemu ; fi;
	docker build $(BUILDFLAGS) $(CACHEFLAGS) $(PROXYFLAGS) .

clean :
	docker images | awk '(NR>1) && ($$2!~/none/) {print $$1":"$$2}' | grep "$(DOCKER_USER)/$(OPSYS)_$(SVCNAME)" | xargs -n1 docker rmi

logs :
	docker logs -f $(OPSYS)_$(CNTNAME)

restart :
	docker ps -a | grep $(OPSYS)_$(CNTNAME) -q && docker restart $(OPSYS)_$(CNTNAME) || echo "Service not running.";

rm : stop
	docker rm -f $(OPSYS)_$(CNTNAME)

start :
	if docker network ls | grep bind-net ; then echo "no creation" ; else docker network create -d overlay bind-net --attachable --subnet=10.2.1.0/24; fi
	docker run -d $(NAMEFLAGS) $(RUNFLAGS) $(PORTFLAGS) $(MOUNTFLAGS) $(OTHERFLAGS) $(IMAGETAG) $(CONTARGS)
	docker network connect gluster-net jinade_bind9
	docker network connect bridge jinade_bind9

rshell :
	docker exec -u root -it $(OPSYS)_$(CNTNAME) $(SHCOMMAND)

#make ARCH=x86_64 DISTRIB=debian EXECCOMMAND="/bin/bash -c '/usr/local/entrypoint.sh _test'"  eshell
eshell :
	docker exec -u root -it $(OPSYS)_$(CNTNAME) $(EXECCOMMAND)

shell :
	docker run --rm -it $(NAMEFLAGS) $(RUNFLAGS) $(PORTFLAGS) $(MOUNTFLAGS) $(OTHERFLAGS) $(IMAGETAG) $(SHCOMMAND)

stop :
	docker stop -t 2 $(OPSYS)_$(CNTNAME)

# -- }}}

# {{{ -- other targets

pull :
	docker pull $(IMAGETAG)

push :
	docker push $(IMAGETAG); \
	if [ "$(ARCH)" = "$(HOSTARCH)" ]; \
		then \
		LATESTTAG=$$(echo $(IMAGETAG) | sed 's/:$(ARCH)/:latest/'); \
		docker tag $(IMAGETAG) $${LATESTTAG}; \
		docker push $${LATESTTAG}; \
	fi; 
	curl -X POST $$(echo $$(curl https://api.microbadger.com/v1/images/$(DOCKER_USER)/$(OPSYS)_$(SVCNAME) 2>/dev/null | grep WebhookURL | cut -d, -f2 | cut -d \" -f4))

test :
	docker run --rm -it $(NAMEFLAGS) $(RUNFLAGS) $(PORTFLAGS) $(MOUNTFLAGS) $(OTHERFLAGS) $(IMAGETAG) sh -ec 'echo "do what you want here"'

regbinfmt :
	docker run --rm --privileged multiarch/qemu-user-static:register --reset

ALPINE_VERSION   := 3.7.0

fetch:
	mkdir -p data && cd data \
	&& curl \
		-o ./rootfs.tar.gz -SL https://nl.alpinelinux.org/alpine/latest-stable/releases/$(ARCH)/alpine-minirootfs-$(ALPINE_VERSION)-$(ARCH).tar.gz \
		&& gunzip -f ./rootfs.tar.gz;

fetchqemu :
	mkdir -p data \
	&& QEMUARCH="$$(echo $(ARCH) | sed 's_armhf_arm_')" \
	&& QEMUVERS="$$(curl -SL https://api.github.com/repos/multiarch/qemu-user-static/releases/latest | awk '/tag_name/{print $$4;exit}' FS='[""]')" \
	&& echo "Using qemu-user-static version: "$${QEMUVERS} \
	&& curl \
		-o ./data/$(HOSTARCH)_qemu-$${QEMUARCH}-static.tar.gz -SL https://github.com/multiarch/qemu-user-static/releases/download/$${QEMUVERS}/$(HOSTARCH)_qemu-$${QEMUARCH}-static.tar.gz \
		&& tar xv -C data/ -f ./data/$(HOSTARCH)_qemu-$${QEMUARCH}-static.tar.gz;

# -- }}}

# {{{ -- New SCV / OPSYS

CUR_DIR := $(shell pwd)
BASE_DIR := $(shell cd .. ; pwd)

ifeq "$(origin NEW_OPSYS)" "undefined"
NEW_OPSYS := $(OPSYS)
endif

ifeq "$(origin NEW_SVC)" "undefined"
NEW_SVC := $(SVCNAME)
endif

NEW_SVC_DIR := $(NEW_OPSYS)_$(NEW_SVC)

new_svc_pass :
	if [ "a$(NEW_SVC)" != "a" ]; then \
		mkdir -p $(BASE_DIR)/$(NEW_SVC_DIR)  ;\
		read -r -p "Enter DOCKER_PASS : "  ANSWER ; echo "DOCKER_PASS := $$ANSWER"  >  $(BASE_DIR)/$(NEW_SVC_DIR)/makefile.pass ;\
		read -r -p "Enter GITHUB_PASS : "  ANSWER ; echo "GITHUB_PASS := $$ANSWER"  >> $(BASE_DIR)/$(NEW_SVC_DIR)/makefile.pass ;\
		read -r -p "Enter TRAVIS_TOKEN : " ANSWER ; echo "TRAVIS_TOKEN := $$ANSWER" >> $(BASE_DIR)/$(NEW_SVC_DIR)/makefile.pass ;\
	fi

new_svc_create :
	if [ "a$(NEW_SVC)" != "a" ]; then \
		mkdir -p             $(BASE_DIR)/$(NEW_SVC_DIR)  ;\
		cp -Rp armhf         $(BASE_DIR)/$(NEW_SVC_DIR)/ ;\
		cp -Rp x86_64        $(BASE_DIR)/$(NEW_SVC_DIR)/ ;\
		rm -rf $(BASE_DIR)/$(NEW_SVC_DIR)/*/*/Dockerfile ;\
		if [ "$(NEW_SVC)" = "base" ]; then \
			cp $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/alpine/Dockerfile_template.base  $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/alpine/Dockerfile ;\
			cp $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/debian/Dockerfile_template.base  $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/debian/Dockerfile ;\
			cp $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/alpine/Dockerfile_template.base $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/alpine/Dockerfile ;\
			cp $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/debian/Dockerfile_template.base $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/debian/Dockerfile ;\
		else 	cp $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/alpine/Dockerfile_template.src  $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/alpine/Dockerfile ;\
			cp $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/debian/Dockerfile_template.src  $(BASE_DIR)/$(NEW_SVC_DIR)/armhf/debian/Dockerfile ;\
			cp $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/alpine/Dockerfile_template.src $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/alpine/Dockerfile ;\
			cp $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/debian/Dockerfile_template.src $(BASE_DIR)/$(NEW_SVC_DIR)/x86_64/debian/Dockerfile ;\
		fi ;\
		cp     README.md     $(BASE_DIR)/$(NEW_SVC_DIR)/ ;\
		cp     makefile      $(BASE_DIR)/$(NEW_SVC_DIR)/ ;\
		cp     .dockerignore $(BASE_DIR)/$(NEW_SVC_DIR)/ ;\
		cp     .travis.yml   $(BASE_DIR)/$(NEW_SVC_DIR)/ ;\
		cp     .gitignore    $(BASE_DIR)/$(NEW_SVC_DIR)/ ;\
		sed -i 's/= '$(OPSYS)'/= '$(NEW_OPSYS)'/g' $(BASE_DIR)/$(NEW_SVC_DIR)/makefile ;\
		sed -i 's/= '$(SVCNAME)'/= '$(NEW_SVC)'/g' $(BASE_DIR)/$(NEW_SVC_DIR)/makefile ;\
		sed -i 's/'$(OPSYS)'/'$(NEW_OPSYS)'/g' $(BASE_DIR)/$(NEW_SVC_DIR)/README.md ;\
		sed -i 's/'$(SVCNAME)'/'$(NEW_SVC)'/g' $(BASE_DIR)/$(NEW_SVC_DIR)/README.md ;\
	fi

svc_first_push :
		curl -u '$(GITHUB_USER):$(GITHUB_PASS)' https://api.github.com/user/repos -d '{"name":"'$(OPSYS)_$(SVCNAME)'"}' ;\
		git init ;\
		git add makefile README.md .dockerignore .gitignore armhf/debian/Dockerfile* armhf/alpine/Dockerfile* x86_64/debian/Dockerfile* x86_64/alpine/Dockerfile*  ;\
		git commit -m "first commit" ;\
		git remote add origin https://$(GITHUB_USER):$(GITHUB_PASS)@github.com/$(GITHUB_USER)/$(OPSYS)_$(SVCNAME).git ;\
		git push origin master ;\
		head -12 .travis.yml > .travis.yml.NEW   ;\
		docker run -it --rm $(DOCKER_USER)/jinade_travis:debian_x86_64 sh -ec "cd /tmp ; rm -rf .travis.yml ; touch .travis.yml ; echo "y" | travis version ; travis sync -t $(TRAVIS_TOKEN) ; sleep 5 ; travis enable -r $(DOCKER_USER)/$(OPSYS)_$(SVCNAME) ; sleep 5 ; travis encrypt -r $(DOCKER_USER)/$(OPSYS)_$(SVCNAME) DOCKER_EMAIL=$(EMAIL) --add ; travis encrypt -r $(DOCKER_USER)/$(OPSYS)_$(SVCNAME) DOCKER_USER=$(DOCKER_USER) --add ; travis encrypt -r $(DOCKER_USER)/$(OPSYS)_$(SVCNAME) DOCKER_PASS=$(DOCKER_PASS) --add ; cat .travis.yml" | grep -v "env" | grep -v "repository" | grep -v "completion" | grep -v "enable" | grep -v "sync" >> .travis.yml.NEW ;\
		tail -12 .travis.yml >> .travis.yml.NEW   ;\
		rm -rf .travis.yml ;\
		mv .travis.yml.NEW .travis.yml ;\
		git add .travis.yml ;\
		git commit -m "first commit" ;\
		git push https://$(GITHUB_USER):$(GITHUB_PASS)@github.com/$(GITHUB_USER)/$(OPSYS)_$(SVCNAME).git ;\
		cd - ;\
	fi

# -- }}}
