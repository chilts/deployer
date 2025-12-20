# Dead
# * ilum.chilts.me
# * speedball.chilts.org
# * salty.webdev.sh
# * zool.webdev.sh
# * lemmings.webdev.sh
# * orion.nebulous.design

all:
	echo "Doing nothing here since we might just call 'make' during tests."

deploy:
	# scp deployer.pl deployer-pg-dump.sh rodia.chilts.me:~/bin
	scp deployer.pl deployer-pg-dump.sh kamino.chilts.me:~/bin
	scp deployer.pl deployer-pg-dump.sh xenon.chilts.me:~/bin

.PHONY: deploy
