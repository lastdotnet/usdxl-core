import { DeployFunction } from 'hardhat-deploy/types';
import { StakedTokenV2Rev3__factory, STAKE_AAVE_PROXY, waitForTx } from '@aave/deploy-v3';

const func: DeployFunction = async function ({ getNamedAccounts, deployments, ...hre }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const [deployerSigner] = await hre.ethers.getSigners();

  const stkAaveProxy = await deployments.get(STAKE_AAVE_PROXY);
  const instance = StakedTokenV2Rev3__factory.connect(stkAaveProxy.address, deployerSigner);
};

func.id = 'StkAaveUpgrade';
func.tags = ['StkAaveUpgrade', 'full_gho_deploy'];

export default func;
