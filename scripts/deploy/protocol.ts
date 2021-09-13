import { run, ethers } from "hardhat";

import { Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { getChainlinkVars, ChainlinkVars } from "../../utils/chainlink";
import { getTxOptions } from "../../utils/txOptions";

async function main() {
  await run("compile");

  console.log("\n");

  // Get signer and chainId.
  const [deployer]: SignerWithAddress[] = await ethers.getSigners();
  const chainId: number = await deployer.getChainId();

  console.log(`Deploying contracts with account: ${await deployer.getAddress()} to chain: ${chainId}`);
  
  // Get chainlink vars + tx options.
  const { vrfCoordinator, linkTokenAddress, keyHash, fees } = (await getChainlinkVars(chainId) as ChainlinkVars);
  const txOption = await getTxOptions(chainId);

  // Deploy ProtocolControl
  const ProtocolControl_Factory: ContractFactory = await ethers.getContractFactory("ProtocolControl");
  const protocolControl: Contract = await ProtocolControl_Factory.deploy(txOption);
  
  console.log("ProtocolControl.sol deployed at: ", protocolControl.address);
  
  await protocolControl.deployTransaction.wait()

  // Deploy Pack
  const Pack_Factory: ContractFactory = await ethers.getContractFactory("Pack");
  const pack: Contract = await Pack_Factory.deploy(
    protocolControl.address,
    "$PACK Protocol",
    vrfCoordinator,
    linkTokenAddress,
    keyHash,
    fees,
    txOption
  );

  console.log("Pack.sol is deployed at: ", pack.address);

  await pack.deployTransaction.wait()

  // Deploy Market
  const Market_Factory: ContractFactory = await ethers.getContractFactory("Market");
  const market: Contract = await Market_Factory.deploy(protocolControl.address, txOption);

  console.log("Market.sol is deployed at: ", market.address);

  await market.deployTransaction.wait()

  // Initialize protocol
  const initTx = await protocolControl.initializeProtocol(pack.address, market.address, txOption);
  
  console.log("Initializing protocol: ", initTx.hash);

  await initTx.wait();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
