// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/Utils/SafeERC20.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


interface IComet {
    function supply(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
    function baseToken() external view returns (address);
}

interface ICometRewards {
  function claim(address comet, address src, bool shouldAccrue) external;
}

interface IERC20FeeProxy {
    function transferFromWithReferenceAndFee(
        address _tokenAddress,
        address _to,
        uint256 _amount,
        bytes calldata _paymentReference,
        uint256 _feeAmount,
        address _feeAddress
    ) external;
}

/**
 * @title   Paytr
 * @notice  Paytr allows you to receive yield by making early payments.
 * @dev     All string parameters will change to bytes.
 */

contract Paytr is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    AggregatorV3Interface internal priceFeed;

    address public ERC20FeeProxyAddress;
    address public gelatoAddress;

    constructor(address _gelatoAddress, address _cometAddress, uint8 _decimals, address _ERC20FeeProxyAddress) {
        gelatoAddress = _gelatoAddress; //Polygon + Mumbai msg.sender Gelato address = 0x83C766237dD04EB47F62784218839F892A691E84
        allowedCometInfo[_cometAddress] = CometInfo(true, _decimals); //Comet Mumbai cUSDCv3 address = 0xF09F0369aB0a875254fB565E52226c88f10Bc839, USDC uses 6 decimals
        ERC20FeeProxyAddress = _ERC20FeeProxyAddress; //Mumbai ERC20FeeProxyAddress (Request Network) = 0x131eb294E3803F23dc2882AB795631A12D1d8929
        priceFeed = AggregatorV3Interface(
            0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7
        );
    }

    event PaymentERC20Event(uint256 amount, uint256 dueDate, address payee, address tokenAddress, bytes paymentReference);
    event PaymentERC20EventWithFee(uint256 amount, uint256 dueDate, address payee, address tokenAddress, address feeAddress, bytes paymentReference, uint256 feeAmount);
    event PayOutERC20Event(address tokenAddress, address payee, uint256 amount, bytes paymentReference,  uint256 feeAmount, address feeAddress);
    event DueDateUpdatedEvent(address payer, address payee, bytes paymentReference, uint256 dueDate);    
    
    struct PaymentERC20 {
        uint256 amount;
        uint256 feeAmount;
        uint256 dueDate;
        address payer;
        address payee;
        address asset;
        address cometAddress;
        address feeAddress;       
    }

    struct RedeemDataERC20 {
        uint256 amount;
        uint256 interestAmount;
        uint256 feeAmount;
        address payer;
        address payee;
        address asset;
        address cometAddress;
        address feeAddress;
        bytes paymentReference;   
    }

    struct totalPerAssetToRedeem {        
        address asset;
        address cometAddress;
        uint256 amount;        
    }

    struct CometInfo {
        bool allowed;
        uint8 decimals;
    }

    /**
     * @notice paymentMapping keeps track of the paid invoices. The mapping uses keyType string (the payment reference of the invoice) 
        and valueType struct InvoiceERC20.
     */   
    mapping(bytes => PaymentERC20) public paymentMapping;

    /**
     * @notice allowedCometAddresses keeps track of the allowed Comet addresses for Compound Finance + the number of decimals, to make sure no malicious Comet contracts can be used
        while making a payment.
    */
    mapping(address => CometInfo) public allowedCometInfo;

    /**
     * @notice allowedRequestNetworkFeeAddresses makes sure ERC20 payments originating from the Request Network protocol go through the correct ERC20FeeProxy contract.
        This makes sure Request Network can detect the payment.
        See function payOutERC20Invoice in this contract for more details.
    */
    mapping(address => bool) public allowedRequestNetworkFeeAddresses;

    /**
    * @notice modifier checks if payment is present in contract.
    */
    modifier IsInContract(bytes memory _paymentReference) {       
        require(paymentMapping[_paymentReference].amount != 0, "No prepayment found");
        _;
    }

    /**
     * @notice modifier only allows payer to use this function.
     */
    modifier OnlyPayer(bytes memory _paymentReference) {
        require(msg.sender == paymentMapping[_paymentReference].payer, "Not Authorized");
        _;
    }

    /**
     * @notice modifier only allows the Gelato smart contract or the contract owner to use this function. Gelato offers a dedicated msg.sender per account.
     This ensures the integrity of the off-chain computation callData.
     */
    modifier onlyGelatoOrOwner {
        require(msg.sender == gelatoAddress || msg.sender == owner(), "Only Gelato or owner");
        _;
    }

    function getLatestPrice() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return price;
    }

    /**
    * @notice Make a payment using an ERC20 token.
    * @notice This function can't be used while it's paused.
    * @param _asset Make sure the ERC20 token (base currency, USDC for example) is supported by Compound Finance V3. Using unsupported assets will result in an error.
    * @param _payee The receiver of the payment.
    * @param _dueDate The due date of the payment, or invoice, in days.
    * @param _amount The _asset amount in wei (10 USDC = 10**6 for example). Double check the number of decimals for each ERC20 token before paying the invoice.
    * @param _paymentReference Reference of the related payment.  
    * @param _cometAddress The address of the Comet contract you want to call. Check https://docs.compound.finance/#networks to get the correct contract address.
    * @dev Uses modifier IsNotPaid, nonReentrant and whenNotPaused.
    * @dev The parameter _dueDate needs to be inserted in number of days (uint8).
    * @dev The parameter _amount needs be inserted in wei. Double check the decimal input for each token.
    */

    function payInvoiceERC20(
        address _asset, //address base token, like USDC
        address _payee,
        uint8 _dueDate,
        uint256 _amount,
        bytes calldata _paymentReference,
        address _cometAddress
        ) public nonReentrant whenNotPaused {

            require(_amount != 0, "0 Amount");
            require(paymentMapping[_paymentReference].payer != msg.sender,"Payment reference already used");
            require(paymentMapping[_paymentReference].payee != _payee,"Payment reference already used");
            require(allowedCometInfo[_cometAddress].allowed == true, "Invalid Comet address"); //prevents the use of malicious Comet contracts
            require(IComet(_cometAddress).baseToken() == _asset, "Invalid asset"); //requires the use of the correct base asset for the Comet address
            require(_payee != address(0), "Payee is 0 address");

            uint256 dueDate;
            uint256 baseFee;

            _dueDate != 0 ? dueDate = block.timestamp + _dueDate * 1 days : dueDate = _dueDate;
            allowedCometInfo[_cometAddress].decimals == 6 ? baseFee = 10**5 : baseFee = 10**17;

            IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);                
            IERC20(_asset).safeApprove(_cometAddress, _amount);
            IERC20(_asset).safeTransferFrom(msg.sender, owner(), baseFee);

            IComet(_cometAddress).supply(_asset, _amount);

            paymentMapping[_paymentReference] = PaymentERC20(
                _amount,
                0,
                dueDate,
                msg.sender,
                _payee,  
                _asset,
                _cometAddress,
                msg.sender        
            );
            
            emit PaymentERC20Event(_amount, dueDate, _payee, _asset, _paymentReference);            
        }
    /**
    * @notice Make a payment using an ERC20 token.
    * @notice This function can't be used while it's paused.
    * @param _asset Make sure the ERC20 token (base currency, USDC for example) is supported by Compound Finance V3. Using unsupported assets will result in an error.
    * @param _payee The receiver of the payment.
    * @param _feeAddress When using an additional fee, this is the address that will receive the feeAmount. Requires msg.sender address when param _feeAmount == 0.
    * @param _dueDate The due date of the payment, or invoice, in days
    * @param _amount The _asset amount in wei (10 USDC = 10**6 for example). Double check the number of decimals for each ERC20 token before paying the invoice.
    * @param _feeAmount The total _asset fee amount in wei.
    * @param _paymentReference Reference of the related payment.  
    * @param _cometAddress The address of the Comet contract you want to call. Check https://docs.compound.finance/#networks to get the correct contract address.
    * @dev Uses modifier IsNotPaid, nonReentrant and whenNotPaused.
    * @dev The parameter _dueDate needs to be inserted in number of days (uint8).
    * @dev The parameters _amount and _feeAmount need be inserted in wei. Double check the decimal input for each token.
    */

    function payInvoiceERC20WithFee(
        address _asset, //address base token, like USDC
        address _payee,
        address _feeAddress,
        uint8 _dueDate,
        uint256 _amount,
        uint256 _feeAmount,
        bytes calldata _paymentReference,
        address _cometAddress
        ) public nonReentrant whenNotPaused {

            require(_amount != 0, "0 Amount");
            require(paymentMapping[_paymentReference].payer != msg.sender,"Payment reference already used");
            require(paymentMapping[_paymentReference].payee != _payee,"Payment reference already used");
            require(allowedCometInfo[_cometAddress].allowed == true, "Invalid Comet address"); //prevents the use of malicious Comet contracts
            require(IComet(_cometAddress).baseToken() == _asset, "Invalid asset"); //requires the use of the correct base asset for the Comet address
            require(_payee != address(0), "Payee is 0 address");
            require(_feeAddress != address(0), "Fee address is 0 address");
            require(_feeAmount != 0, "0 Fee amount");

            uint256 dueDate;
            uint256 baseFee;

            _dueDate != 0 ? dueDate = block.timestamp + _dueDate * 1 days : dueDate = _dueDate;
            allowedCometInfo[_cometAddress].decimals == 6 ? baseFee = 10**5 : baseFee = 10**17;

            IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount + _feeAmount);          
            IERC20(_asset).safeApprove(_cometAddress, _amount + _feeAmount);
            IERC20(_asset).safeTransferFrom(msg.sender, owner(), baseFee);

            IComet(_cometAddress).supply(_asset, _amount + _feeAmount);

            paymentMapping[_paymentReference] = PaymentERC20(
                _amount,
                _feeAmount,
                dueDate,
                msg.sender,
                _payee,  
                _asset,
                _cometAddress,
                _feeAddress        
            );
            
            emit PaymentERC20EventWithFee(_amount, dueDate, _payee, _asset, _feeAddress, _paymentReference, _feeAmount);            
        }

    /**
    @notice This function allows the payer to update the due date of the payment. This is only possible when the initial payment had a '0' dueDate,
    for example when using the Paytr contract for escrow or crowdfunding. Updating the due date means releasing the funds.
    @param _paymentReference Input the paymentReference in bytes.
    @param _dueDateUpdated Input the due date in Epoch time.    
     */    
    
    function updateDueDate(bytes calldata _paymentReference, uint256 _dueDateUpdated) public IsInContract(_paymentReference) OnlyPayer(_paymentReference) nonReentrant whenNotPaused {
        require(paymentMapping[_paymentReference].dueDate == 0, "Your payment reference already has a due date assigned");
        require(_dueDateUpdated >= block.timestamp + 1 days, "New due date needs to be > block.timestamp + 1 day");
        paymentMapping[_paymentReference].dueDate = _dueDateUpdated;
        address _payee = paymentMapping[_paymentReference].payee;

        emit DueDateUpdatedEvent(msg.sender, _payee, _paymentReference, _dueDateUpdated);
    }

     /**
     *
     @notice Private function 
     @dev Handles the redeeming of the asset from Compound Finance
    */
    function redeemFundsERC20(totalPerAssetToRedeem[] calldata assetsToRedeem) private {
        uint i;
        uint assetsToRedeemLength = assetsToRedeem.length;

        for (;i < assetsToRedeemLength;) {
            IComet(assetsToRedeem[i].cometAddress).withdraw(assetsToRedeem[i].asset, assetsToRedeem[i].amount);
            ++i;
        }
    }

     /**
    * @notice Allows the contract to pay payee (principal amount), payer (interest amount) and fee receiver (fee amount).
    This function cannot be paused.
    * @dev Uses modifiers onlyGelatoOrOwner. 
    **/
    function payOutERC20Invoice(RedeemDataERC20[] calldata redeemData, totalPerAssetToRedeem[] calldata assetsToRedeem ) public onlyGelatoOrOwner nonReentrant {  

        require(redeemData.length > 0 && assetsToRedeem.length > 0, "No payments to redeem");        
        redeemFundsERC20(assetsToRedeem);

        uint256 i;
        uint256 redeemDataLength = redeemData.length;

        for (; i < redeemDataLength;) {
            bytes memory _paymentReference = redeemData[i].paymentReference;
            require(paymentMapping[_paymentReference].amount != 0,"Unknown payment reference"); //check to see if payment reference to be paid out is present in the contract
            address payable _payee = payable(redeemData[i].payee);
            address payable _payer = payable(redeemData[i].payer);
            address payable _feeAddress = payable(redeemData[i].feeAddress);
            address _asset = redeemData[i].asset;            
            uint256 _amount = redeemData[i].amount;
            uint256 _feeAmount = redeemData[i].feeAmount;
            uint256 _interestAmount = redeemData[i].interestAmount * 9000 / 10000;
            
            //Update state before transferring funds
            paymentMapping[_paymentReference].amount = 0;
            
            /*
            Transfer funds to payer, payee and feeAddress. Payments originating from Request Network call the ERC20FeeProxy contract.
            The Request Network payments are detected by checking the _feeAddress parameter.
            */
            if(allowedRequestNetworkFeeAddresses[_feeAddress] == true) {
                IERC20(_asset).safeApprove(ERC20FeeProxyAddress, _amount + _feeAmount);

                IERC20FeeProxy(ERC20FeeProxyAddress).transferFromWithReferenceAndFee(
                    _asset,
                    _payee,
                    _amount,
                    _paymentReference,
                    _feeAmount,
                    _feeAddress
                );
            
            } else {
                IERC20(_asset).safeTransfer(_payee, _amount);
                if(_feeAmount != 0) {
                    IERC20(_asset).safeTransfer(_feeAddress, _feeAmount);
                }
            }
            
            IERC20(_asset).safeTransfer(_payer, _interestAmount);
            ++i; 

            emit PayOutERC20Event(_asset, _payee, _amount, _paymentReference, _feeAmount, _feeAddress);           
        }
        //transfer total fee amount to contract owner
        uint256 j;
        for (;j < assetsToRedeem.length;) {
            uint256 _balanceAfterRedeeming = IERC20(assetsToRedeem[j].asset).balanceOf(address(this));
            IERC20(assetsToRedeem[j].asset).safeTransfer(owner(), _balanceAfterRedeeming);
            ++j;
        }      
    }

    function claimCompRewards(address _cometAddress) public onlyOwner {
        ICometRewards(_cometAddress).claim(_cometAddress, address(this), true);
        IERC20(_cometAddress).safeTransfer(owner(), IERC20(_cometAddress).balanceOf(address(this)));
    }

    function addCometAddress(address _cometAddressToAdd, uint8 _decimals) public onlyOwner {
        allowedCometInfo[_cometAddressToAdd] = CometInfo(
            true,
            _decimals
        );
    }

    function addRequestNetworkFeeAddress(address _requestNetworkFeeAddress) public onlyOwner {
        allowedRequestNetworkFeeAddresses[_requestNetworkFeeAddress] = true;
    }

    function setGelatoAddress(address _gelatoAddress) public onlyOwner {
        gelatoAddress = _gelatoAddress;
    }

    function setERC20FeeProxy(address _ERC20FeeProxyAddress) public onlyOwner {
        ERC20FeeProxyAddress = _ERC20FeeProxyAddress;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

}