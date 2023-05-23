# Paytr protocol smart contracts

You can find all our smart contracts in this repository.
At the moment there's one main contact, `Paytr.sol`.

Looking to use the Paytr protocol for your project? Check out our documentation [here](https://paytr.gitbook.io/product-docs/).

## Truffle test

All the tests are located in the `test/paytr.test.js`file.
Install the necessary dependencies like Ganache and Truffle.

We recommend to fork Mainnet and unlock an account which holds a lot of USDC, by using this command:
`ganache --fork https://mainnet.infura.io/v3/YOURKEY --wallet.unlockedAccounts="0x7713974908Be4BEd47172370115e8b1219F4A5f0"`

Open a new terminal window and run `truffle test --network develop`.