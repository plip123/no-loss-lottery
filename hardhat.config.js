/**
 * @type import('hardhat/config').HardhatUserConfig
 */

 require("dotenv").config();
 require("@nomiclabs/hardhat-truffle5");
 require("@nomiclabs/hardhat-etherscan");
 require("@nomiclabs/hardhat-web3");
 require("@nomiclabs/hardhat-waffle");
 require("hardhat-deploy");
 require('@openzeppelin/hardhat-upgrades');
 require("hardhat-gas-reporter");

module.exports = {
  networks: {
    hardhat: {
      // Uncomment these lines to use mainnet fork
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
        blockNumber: 11589707,
      },
    },
    // rinkeby: {
    //   url: `https://eth-rinkeby.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
    //   accounts: [process.env.RINKEBY_PRIVATE_KEY],
    // },
    // live: {
    //   url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
    //   accounts: [process.env.MAINNET_PRIVKEY],
    // },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API,
  },
  namedAccounts: {
    deployer: 0,
    feeRecipient: 1,
    user: 2,
  },
  solidity: {
    version: "0.6.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 240000,
  },
};
