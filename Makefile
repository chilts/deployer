all:
	echo "Doing nothing here since we might just call 'make' during tests."

deploy:
	scp deployer.pl speedball.chilts.org:~/bin
#	scp deployer.pl salty.webdev.sh:~/bin       # dead
#	scp deployer.pl zool.webdev.sh:~/bin        # dead
#	scp deployer.pl lemmings.webdev.sh:~/bin    # dead
#	scp deployer.pl orion.nebulous.design:~/bin # dead

.PHONY: deploy
