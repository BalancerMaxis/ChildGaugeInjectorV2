-include .env

# command: test the whole script without broadcasting the transaction into the chain to spot early errors
deployPolygonDry: 
		forge script foundry_scripts/InjectorInfraDeployment.s.sol \
		--rpc-url polygon \
		--slow \
		-vvvv

deployPolygonBroadcastAndVerify:
		forge script foundry_scripts/InjectorInfraDeployment.s.sol \
		--rpc-url polygon \
		--slow \
		--broadcast \
		--verify \
		-vvvv

deployMultiChainDry:
		forge script foundry_scripts/InjectorInfraMultiChainDeployment.s.sol \
		--rpc-url polygon \
		--slow \
		-- multi \
		-vvvv

deployMultiChainBroadcastAndVerify:
		forge script foundry_scripts/InjectorInfraMultiChainDeployment.s.sol \
		--rpc-url polygon \
		--slow \
		-- multi \
		--broadcast \
		--verify \
		-vvvv

		  