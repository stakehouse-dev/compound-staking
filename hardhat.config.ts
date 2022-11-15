require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        runs: 1000000,
        enabled: true
      }
    }
  },
  typechain: {
    outDir: "types",
    target: "ethers-v5",
  },
};

