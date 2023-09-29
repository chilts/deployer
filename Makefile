all:
	echo "Doing nothing here since we might just call 'make' during tests."

deploy:
	# Servers
	scp deployer.pl speedball.chilts.me:~/bin
	scp deployer.pl xenon.chilts.me:~/bin
	# shed
	scp deployer.pl ilum.chilts.me:~/bin
	scp deployer.pl kamino.chilts.me:~/bin
	scp deployer.pl rodia.chilts.me:~/bin
	# RPi Zero 2
	scp deployer.pl mahler.chilts.me:~/bin

.PHONY: deploy
