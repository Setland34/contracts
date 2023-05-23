const Paytr = artifacts.require("Paytr.sol");

module.exports = function (deployer) {
  deployer.deploy(Paytr, "0x83C766237dD04EB47F62784218839F892A691E84","0xc3d688B66703497DAA19211EEdff47f25384cdc3",6,"0x131eb294E3803F23dc2882AB795631A12D1d8929","0xFC078A6812eb56320f879A153A0bd23C34D9B508");
};