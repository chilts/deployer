.PHONY: deploy
deploy:
	scp deployer.pl zool.webdev.sh:~/bin
	scp deployer.pl salty.chilts.org:~/bin
