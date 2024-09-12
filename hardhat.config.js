require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: "0.8.24",
    networks:
        {
            hardhat: {
                forking: {
                    url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
                }
            },
            base: {
                url: 'https://mainnet.base.org',
                accounts: [process.env.PRIVATE_KEY],
                gasPrice: 1000000000,
            },
            polygon: {
                url: `https://lb.drpc.org/ogrpc?network=polygon&dkey=${process.env.DRPC_KEY}`,
                accounts: [process.env.PRIVATE_KEY],
            },
            zkevm: {
                url: `https://lb.drpc.org/ogrpc?network=polygon-zkevm&dkey=${process.env.DRPC_KEY}`,
                accounts: [process.env.PRIVATE_KEY],
            }
        },
    etherscan: {
        apiKey: {
            polygon: process.env.POLYGONSCAN_TOKEN
        }
    },
};
