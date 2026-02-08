# Dead
# * ilum.chilts.me
# * speedball.chilts.org
# * salty.webdev.sh
# * zool.webdev.sh
# * lemmings.webdev.sh
# * orion.nebulous.design

all:
	echo "Doing nothing here since we might just call 'make' during tests."

SCRIPTS = deployer.pl deployer-pg-dump.sh deployer-origin-cert-setup.sh deployer-origin-cert-check.sh deployer-setup.sh

deploy:
	# scp $(SCRIPTS) rodia.chilts.me:~/bin
	scp $(SCRIPTS) kamino.chilts.me:~/bin
	scp $(SCRIPTS) xenon.chilts.me:~/bin
	scp $(SCRIPTS) superfrog.chilts.me:~/bin

.PHONY: deploy
