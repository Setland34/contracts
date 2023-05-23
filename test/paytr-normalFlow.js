
var assert = require('assert');
const truffleAssert = require('truffle-assertions');

const Paytr = artifacts.require("Paytr");
const CometAbi = [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"address","name":"admin_","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"admin_","type":"address"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newAdmin","type":"address"}],"name":"changeAdmin","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"implementation","outputs":[{"internalType":"address","name":"implementation_","type":"address"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newImplementation","type":"address"}],"name":"upgradeTo","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newImplementation","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"upgradeToAndCall","outputs":[],"stateMutability":"payable","type":"function"},{"stateMutability":"payable","type":"receive"}]
const Erc20Abi = [{ "constant": true, "inputs": [], "name": "name", "outputs": [ { "name": "", "type": "string" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": false, "inputs": [ { "name": "_spender", "type": "address" }, { "name": "_value", "type": "uint256" } ], "name": "approve", "outputs": [ { "name": "", "type": "bool" } ], "payable": false, "stateMutability": "nonpayable", "type": "function" }, { "constant": true, "inputs": [], "name": "totalSupply", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": false, "inputs": [ { "name": "_from", "type": "address" }, { "name": "_to", "type": "address" }, { "name": "_value", "type": "uint256" } ], "name": "transferFrom", "outputs": [ { "name": "", "type": "bool" } ], "payable": false, "stateMutability": "nonpayable", "type": "function" }, { "constant": true, "inputs": [], "name": "decimals", "outputs": [ { "name": "", "type": "uint8" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "_owner", "type": "address" } ], "name": "balanceOf", "outputs": [ { "name": "balance", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [], "name": "symbol", "outputs": [ { "name": "", "type": "string" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": false, "inputs": [ { "name": "_to", "type": "address" }, { "name": "_value", "type": "uint256" } ], "name": "transfer", "outputs": [ { "name": "", "type": "bool" } ], "payable": false, "stateMutability": "nonpayable", "type": "function" }, { "constant": true, "inputs": [ { "name": "_owner", "type": "address" }, { "name": "_spender", "type": "address" } ], "name": "allowance", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "payable": true, "stateMutability": "payable", "type": "fallback" }, { "anonymous": false, "inputs": [ { "indexed": true, "name": "owner", "type": "address" }, { "indexed": true, "name": "spender", "type": "address" }, { "indexed": false, "name": "value", "type": "uint256" } ], "name": "Approval", "type": "event" }, { "anonymous": false, "inputs": [ { "indexed": true, "name": "from", "type": "address" }, { "indexed": true, "name": "to", "type": "address" }, { "indexed": false, "name": "value", "type": "uint256" } ], "name": "Transfer", "type": "event" }]

const CometContract = new web3.eth.Contract(CometAbi, "0xc3d688B66703497DAA19211EEdff47f25384cdc3");
const USDCContract = new web3.eth.Contract(Erc20Abi, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
const cTokenContract = new web3.eth.Contract(Erc20Abi, "0xc3d688B66703497DAA19211EEdff47f25384cdc3");
const whaleAccount = "0x7713974908Be4BEd47172370115e8b1219F4A5f0";

let amountToPay = 1500000000;
let feeAmount = 200000;
let protocolFee = 100000;
let totalPaid = null;
let totalPayments = null;
let totalFees = null;
let totalPaymentsWithFee = null;

contract("Paytr", (accounts) => {  

  let instance;
  beforeEach('should setup the contract instances', async () => {
    instance = await Paytr.deployed();
  });


describe("Normal payment flow of 2 invoices + payout of due invoices", () => {
    const provider = config.provider;
      
    it("the contract needs to pay out all due invoices", async () => {
  
      //send ETH to whaleaccount
      await web3.eth.sendTransaction({ from: accounts[0], to: whaleAccount, value: 100});
  
      //check total supply:
      let totalSupplyCToken = await cTokenContract.methods.totalSupply().call();
      console.log("test supply: ",totalSupplyCToken)

      //Approval
      await USDCContract.methods.approve(instance.address, 99990000000000).send({from: whaleAccount});

      let contractBalanceBeforeTx1 = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log("Contract balance before tx1: ",contractBalanceBeforeTx1);
      let whaleAccountBalanceBeforeTx1 = await USDCContract.methods.balanceOf(whaleAccount).call();
      console.log("WhaleAccount balance before tx1: ",whaleAccountBalanceBeforeTx1);
  
      //USDC payment
  
      let payment = await instance.payInvoiceERC20(
        USDCContract._address,
        accounts[6],
        30,
        amountToPay,
        "0x194e56332d32347777",
        CometContract._address,
        {from: whaleAccount}
      );
      
      let contractBalanceAfterTx1 = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log("Contract balance after tx1: ",contractBalanceAfterTx1);
      let whaleAccountBalanceAfterTx1 = await USDCContract.methods.balanceOf(whaleAccount).call();
      console.log("WhaleAccount balance after tx1: ",whaleAccountBalanceAfterTx1);
      //sub 2 is needed because the number of cTokens is sometimes lower than the amount supplied
      let expectedContractBalanceAfterTx1 = web3.utils.toBN(contractBalanceBeforeTx1).add(web3.utils.toBN(amountToPay)).sub(web3.utils.toBN(2)).toString();
      let expectedWhaleAccountBalanceAfterTx1 = web3.utils.toBN(whaleAccountBalanceBeforeTx1).sub(web3.utils.toBN(amountToPay)).toString();
    
      assert(contractBalanceAfterTx1 >= expectedContractBalanceAfterTx1,"Contract balance doesn't match expected contract balance tx1");
      assert.equal(whaleAccountBalanceAfterTx1,expectedWhaleAccountBalanceAfterTx1,"Whale account balance doens't match expected balance tx1")
      truffleAssert.eventEmitted(payment,"PaymentERC20Event");
      truffleAssert.eventNotEmitted(payment,"PaymentERC20EventWithFee");   

      totalPaid += amountToPay;
      totalPayments += 1;
      console.log("Total paid: ",totalPaid);
      console.log("Total payments: ",totalPayments);
      //end of USDC payment
  
      //USDC payment with fee
      let contractBalanceBeforeTx2 = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log(contractBalanceBeforeTx2);
      let whaleAccountBalanceBeforeTx2 = await USDCContract.methods.balanceOf(whaleAccount).call();
      console.log("WhaleAccount balance before tx2: ",whaleAccountBalanceBeforeTx2);
  
      let paymentWithFee = await instance.payInvoiceERC20WithFee(
        USDCContract._address,
        accounts[6],
        accounts[3],
        30,
        amountToPay,
        feeAmount,
        "0x194e56332d32347778",
        CometContract._address,
        {from: whaleAccount}
      );
      
      let contractBalanceAfterTx2 = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log("Contract balance after tx2: ",contractBalanceAfterTx2);
      let whaleAccountBalanceAfterTx2 = await USDCContract.methods.balanceOf(whaleAccount).call();
      console.log("WhaleAccount balance after tx2: ",whaleAccountBalanceAfterTx2);
      let expectedContractBalanceAfterTx2 = web3.utils.toBN(contractBalanceBeforeTx2).add(web3.utils.toBN(amountToPay)).add(web3.utils.toBN(feeAmount)).toString();
      let expectedWhaleAccountBalanceAfterTx2 = web3.utils.toBN(whaleAccountBalanceBeforeTx2).sub(web3.utils.toBN(amountToPay)).sub(web3.utils.toBN(feeAmount)).toString();


      assert(contractBalanceAfterTx2 >= expectedContractBalanceAfterTx2,"Contract balance doesn't match expected contract balance tx2");
      assert.equal(whaleAccountBalanceAfterTx2,expectedWhaleAccountBalanceAfterTx2,"Whale account balance doens't match expected balance tx2")

      truffleAssert.eventEmitted(paymentWithFee,"PaymentERC20EventWithFee");
      truffleAssert.eventNotEmitted(paymentWithFee,"PaymentERC20Event");

      totalPaid += amountToPay;
      totalPayments += 1;
      totalFees += feeAmount;
      totalPaymentsWithFee += 1;
      console.log("Total paid: ",totalPaid);
      console.log("Total payments: ",totalPayments);
      console.log("Total payments with fee: ",totalPaymentsWithFee);
      console.log("Total fees: ",totalFees);
  
      //end of USDC payment with fee
      
      //USDC payment with 0 due date
      let contractBalanceBeforeTx3 = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log(contractBalanceBeforeTx3);
      let whaleAccountBalanceBeforeTx3 = await USDCContract.methods.balanceOf(whaleAccount).call();
      console.log("WhaleAccount balance before tx3: ",whaleAccountBalanceBeforeTx3);
  
      let paymentZeroDueDate = await instance.payInvoiceERC20(
        USDCContract._address,
        accounts[6],
        0,
        amountToPay,
        "0x394e56332d32341111",
        CometContract._address,
        {from: whaleAccount}
      );
      
      let contractBalanceAfterTx3 = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log("Contract balance after tx3: ",contractBalanceAfterTx3);
      let whaleAccountBalanceAfterTx3 = await USDCContract.methods.balanceOf(whaleAccount).call();
      console.log("WhaleAccount balance after tx3: ",whaleAccountBalanceAfterTx3);
      //let expectedContractBalanceAfterTx3 = contractBalanceBeforeTx3 + amountToPay;
      let expectedContractBalanceAfterTx3 = web3.utils.toBN(contractBalanceBeforeTx3).add(web3.utils.toBN(amountToPay)).toString();
      let expectedWhaleAccountBalanceAfterTx3 = web3.utils.toBN(whaleAccountBalanceBeforeTx3).sub(web3.utils.toBN(amountToPay)).toString();

      assert.equal(expectedContractBalanceAfterTx3, expectedContractBalanceAfterTx3,"Contract balance doesn't match expected contract balance tx3");
      assert.equal(whaleAccountBalanceAfterTx3,expectedWhaleAccountBalanceAfterTx3,"Whale account balance doens't match expected balance tx3");
      truffleAssert.eventEmitted(paymentZeroDueDate,"PaymentERC20Event");
      truffleAssert.eventNotEmitted(paymentZeroDueDate, "PaymentERC20EventWithFee");

      totalPaid += amountToPay;
      totalPayments += 1;
      console.log("Total paid: ",totalPaid);
      console.log("Total payments: ",totalPayments);
      //end of USDC payment with 0 due date
  
      //update due date of payment ref. 0x394e56332d32341111
      let currentTime = Math.floor(Date.now() / 1000);
      let newDueDate = currentTime + 604800 //1 week in seconds;
      let updateDueDate = await instance.updateDueDate(
        "0x394e56332d32341111",
        newDueDate,
        {from: whaleAccount}
      );
      truffleAssert.eventEmitted(updateDueDate,'DueDateUpdatedEvent');
      //end of update due date
  
      //Mine blocks to earn interest
      let contractBalanceBeforeMining = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log("Contract cToken balance before mining extra blocks: ",contractBalanceBeforeMining);
      
      //console.log("start", await provider.request({method: 'eth_blockNumber', params: []}));
      await provider.request({method: 'evm_mine', params: [{blocks:5000}]});
      //console.log("end", await provider.request({method: 'eth_blockNumber', params: []}));
      
      let contractBalanceAfterMining = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log("Contract cToken balance after mining extra blocks: ",contractBalanceAfterMining);
      let totalInterest = contractBalanceAfterMining - contractBalanceBeforeMining;
      console.log("Total interest: ",totalInterest);
      let interestPerPayment = totalInterest / totalPayments;
      console.log("Interest per payment reference: ",interestPerPayment);
      let feeAmountPerPayment = totalFees / totalPaymentsWithFee;
      console.log("feeAmount per payment reference: ",feeAmountPerPayment);
  
      //payout     
      let payeeBalanceUsdcBeforePayout = await USDCContract.methods.balanceOf(accounts[6]).call();
      console.log("Payee balance USDC before payout function: ",payeeBalanceUsdcBeforePayout);

      console.log("Total to be redeemed: ",totalPaid+totalFees+totalInterest)
      
      let payout = await instance.payOutERC20Invoice([
        [amountToPay, Math.floor(interestPerPayment),0, whaleAccount, accounts[6], USDCContract._address, CometContract._address, whaleAccount, "0x194e56332d32347777"],
        [amountToPay, Math.floor(interestPerPayment),feeAmountPerPayment, whaleAccount, accounts[6], USDCContract._address, CometContract._address, whaleAccount, "0x194e56332d32347778"],
        [amountToPay, Math.floor(interestPerPayment),0, whaleAccount, accounts[6], USDCContract._address, CometContract._address, whaleAccount, "0x394e56332d32341111"],
      ],
        [[USDCContract._address, CometContract._address, totalPaid+totalFees+totalInterest]]
      );
      let contractBalanceAfterPayout = await cTokenContract.methods.balanceOf(instance.address).call();
      console.log("Contract cToken balance after payout: ",contractBalanceAfterPayout);
  
      let expectedPayeeBalanceAfterPayout = web3.utils.toBN(payeeBalanceUsdcBeforePayout).add(web3.utils.toBN(totalPaid)).toString();
      console.log("Expected new total: ",expectedPayeeBalanceAfterPayout);
      let payeeBalanceUsdcAfterPayout = await USDCContract.methods.balanceOf(accounts[6]).call();
      console.log("Payee balance USDC after payout function: ",payeeBalanceUsdcAfterPayout);
        
      assert(contractBalanceAfterPayout <= 20);
      assert.equal(expectedPayeeBalanceAfterPayout,payeeBalanceUsdcAfterPayout, "Payee balance not correct");
      truffleAssert.eventEmitted(payout,'PayOutERC20Event');
      
      });
    });//end describe
});