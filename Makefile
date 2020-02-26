.PHONY: deploy
deploy:
	scp deployer.pl salty.chilts.org:~/bin
	scp deployer.pl zool.webdev.sh:~/bin
	scp deployer.pl lemmings.webdev.sh:~/bin
	scp deployer.pl orion.nebulous.design:~/bin

#old:
  # Don't need this stuff below, since we're not using this script for EasyBC!!!
	# scp deployer.pl makamaka.easybc.nz:~/bin # deleted!
	# scp deployer.pl makamaka.appsattic.com:~/bin # staging, xenial, Digital Ocean, NY1
	# scp deployer.pl miro.easybc.co.nz:~/bin # production, xenial
