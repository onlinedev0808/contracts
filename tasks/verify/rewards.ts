import hre from "hardhat";
import { chainlinkVars } from "../../utils/chainlink";
import addresses from "../../utils/address.json";

const networkName: string = hre.network.name;

// Get network dependent vars.
const { pack, rewards } = addresses[networkName];

async function Rewards() {
  await hre.run("verify:verify", {
    address: rewards,
    constructorArguments: [pack],
  });
}

async function verify() {
  await Rewards();
}

verify()
  .then(() => process.exit(0))
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
