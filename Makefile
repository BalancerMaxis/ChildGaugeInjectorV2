-include .env

# command: test the whole script without broadcasting the transaction into the chain to spot early errors
deployDry: 
		forge script foundry_scripts/InjectorInfraDeployment.s.sol \
		--rpc-url polygon \
		--slow \
		-vvvv
		  