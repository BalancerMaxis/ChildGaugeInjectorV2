require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: "0.8.24",
    networks:
        {
            hardhat: {
                forking: {
                    url: `https://lb.drpc.org/ogrpc?network=polygon&dkey=${process.env.DRPC_KEY}`,
                }
            },
            base: {
                url: `https://lb.drpc.org/ogrpc?network=base&dkey=${process.env.DRPC_KEY}`,
                accounts: [process.env.PRIVATE_KEY],
                gasPrice: 1000000000,
            },
            polygon: {
                url: `https://lb.drpc.org/ogrpc?network=polygon&dkey=${process.env.DRPC_KEY}`,
                accounts: [process.env.PRIVATE_KEY],
            },
            ethereum: {
                url: `https://lb.drpc.org/ogrpc?network=ethereum&dkey=${process.env.DRPC_KEY}`,
                accounts: [process.env.PRIVATE_KEY],
            }
        },
    etherscan: {
        apiKey: {
            polygon: process.env.ETHERSCAN_POLYGON_API_KEY,
            ethereum: process.env.ETHERSCAN_API_KEY,
        }
    },
};
