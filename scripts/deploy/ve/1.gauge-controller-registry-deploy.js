const { formatEther } = require('ethers/lib/utils')
const { ethers, network } = require('hardhat')
const factory = require('../../../specs/util/factory')
const deployments = require('../../util/deployments')

const getDependencies = async (chainId) => {
  if (chainId !== 31337) {
    return deployments.get(chainId)
  }

  const npm = await factory.deployUpgradeable('FakeToken', 'Fake NPM', 'NPM')

  return { npm: npm.address }
}

const deploy = async () => {
  const [deployer] = await ethers.getSigners()
  const previousBalance = await deployer.getBalance()

  console.log('Deployer: %s Balance: %d ETH', deployer.address, formatEther(previousBalance))

  const { chainId } = network.config
  const { npm, gaugeControllerRegistry } = await getDependencies(chainId)

  if (!gaugeControllerRegistry) {
    await factory.deployUpgradeable('GaugeControllerRegistry', 0, deployer.address, deployer.address, [deployer.address], npm)
    return
  }

  await factory.upgrade(gaugeControllerRegistry, 'GaugeControllerRegistry', 0, deployer.address, deployer.address, [deployer.address], npm)
}

deploy().catch(console.error)
