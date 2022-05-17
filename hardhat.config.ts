import { HardhatUserConfig } from 'hardhat/types/config'

import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-etherscan'
import '@nomiclabs/hardhat-solhint'
import 'hardhat-abi-exporter'
import 'hardhat-contract-sizer'
import 'hardhat-deploy'
import 'hardhat-docgen'
import 'hardhat-gas-reporter'
import 'hardhat-typechain'
import 'hardhat-watcher'
import 'solidity-coverage'
import '@openzeppelin/hardhat-upgrades'

const INFURA_API_KEY = ''
const PRIVATE_KEY: string = process.env.PRIVATE_KEY || ''
const ETHERSCAN_API_KEY = ''

const config: HardhatUserConfig = {
  paths: {
    sources: './contracts',
  },
  defaultNetwork: 'hardhat',
  solidity: {
    version: '0.7.6',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: 'istanbul',
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      gas: 10000000,
      gasPrice: 10000000000
    },
    heco: {
      chainId: 128,
      url : "https://http-mainnet.hecochain.com/",
      accounts: [PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
}

export default config
