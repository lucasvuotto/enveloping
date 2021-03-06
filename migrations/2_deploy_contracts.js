// Primary contracts
const RelayHub = artifacts.require('RelayHub')
const Penalizer = artifacts.require('Penalizer')
const SmartWallet = artifacts.require('SmartWallet')
const SmartWalletFactory = artifacts.require('SmartWalletFactory')
const DeployVerifier = artifacts.require('DeployVerifier')
const RelayVerifier = artifacts.require('RelayVerifier')

// For testing purposes
const SampleRecipient = artifacts.require('TestRecipient')

// For CustomSmartWallet support
const CustomSmartWallet = artifacts.require('CustomSmartWallet')
const CustomSmartWalletFactory = artifacts.require('CustomSmartWalletFactory')
const CustomSmartWalletDeployVerifier = artifacts.require('CustomSmartWalletDeployVerifier')

module.exports = async function (deployer) {
  await deployer.deploy(Penalizer)
  await deployer.deploy(RelayHub, Penalizer.address, 1, 40000, 1, 1, 1)
  await deployer.deploy(SmartWallet)
  await deployer.deploy(SmartWalletFactory, SmartWallet.address)
  await deployer.deploy(DeployVerifier, SmartWalletFactory.address)
  await deployer.deploy(RelayVerifier, SmartWalletFactory.address)
  await deployer.deploy(CustomSmartWallet)
  await deployer.deploy(CustomSmartWalletFactory, CustomSmartWallet.address)
  await deployer.deploy(CustomSmartWalletDeployVerifier, CustomSmartWalletFactory.address)
  await deployer.deploy(RelayVerifier, CustomSmartWalletFactory.address)
  await deployer.deploy(SampleRecipient)
}
