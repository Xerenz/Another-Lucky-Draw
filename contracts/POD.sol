pragma solidity ^0.5.0;

contract POD {
    
    address payable public seller;
    address payable public buyer;
    address payable public transporter;
    address payable public arbitrator; // Trusted incase of dispute
    address payable public attestaionAuthority; // Party that attested the smart contract

    uint public itemPrice;
    bytes32 itemID;
    
    string public TermsIPFS_Hash; // Terms and conditions agreement IPFS Hash
    
    // Enum wont allow the contract t be in any other state
    enum contractState { waitingForVerificationbySeller, waitingForVerificationbyTransporter, 
                        waitingForVerificationbyBuyer, MoneyWithdrawn, PackageAndTransporterKeyCreated, 
                        ItemOnTheWay,PackageKeyGivenToBuyer, ArrivedToDestination, buyerKeysEntered, 
                        PaymentSettledSuccess, DisputeVerificationFailure, EtherWithArbitrator, 
                        CancellationRefund, Refund, Aborted }
    
    contractState public state;
    
    mapping(address => bytes32) public verificationHash;
    mapping(address => bool) cancellable;
    
    uint deliveryDuration;
    uint startEntryTransporterKeysBlocktime;
    uint buyerVerificationTimeWindow;
    uint startdeliveryBlocktime;
    
    constructor(address payable _seller,
    address payable _buyer,
    address payable _transporter
    address payable _arbitrator,
    address payable _attestationAuthority,
    string memory _itemID) public payable {
        seller = _seller;
        buyer = _buyer;
        transporter = _transporter;
        arbitrator = _arbitrator;
        attestaionAuthority = _attestationAuthority;

        itemPrice = 2 ether;
        itemID = _itemID;
        deliveryDuration = 2 hours; // 2 hours
        buyerVerificationTimeWindow = 15 minutes; // Time for the buyer to verify keys after transporter entered the keys
        TermsIPFS_Hash = "QmWWQSuPMS6aXCbZKpEjPHPUZN2NjB3YrhJTHsV4X3vb2td";

        state = contractState.waitingForVerificationbySeller;
        cancellable[seller] = true;
        cancellable[buyer] = true;
        cancellable[transporter] = true;
    }
    
    modifier costs() {
       require(msg.value == 2*itemPrice);
       _;
    }

    modifier OnlySeller() {
        require(msg.sender == seller);
        _;
    }

    modifier OnlyBuyer() {
        require(msg.sender == buyer);
        _;
    }

    modifier OnlyTransporter() {
        require(msg.sender == transporter);
        _;
    }

    modifier OnlySeller_Buyer_Transporter() {
        require(msg.sender == seller || msg.sender == buyer || msg.sender == transporter);
        _;
    }
    
    event TermsAndConditionsSignedBy(string info, address entityAddress);
    event collateralWithdrawnSuccessfully(string info, address entityAddress);
    event PackageCreatedBySeller(string info, address entityAddress);
    event PackageIsOnTheWay(string info, address entityAddress);
    event PackageKeyGivenToBuyer(string info, address entityAddress);
    event ArrivedToDestination(string info, address entityAddress);
    event BuyerEnteredVerificationKeys(string info, address entityAddress);
    event SuccessfulVerification(string info);
    event VerificationFailure(string info);
    event CancellationReuest(address entityAddress, string info, string reason);
    event RefundDueToCancellation(string info);
    event DeliveryTimeExceeded(string info);
    event EtherTransferredToArbitrator(string info, address entityAddress);
    event BuyerExceededVerificationTime(string info, address entityAddress);
    
    function SignTermsAndConditions() public payable OnlySeller_Buyer_Transporter {
        if(msg.sender == seller) {
            require(state == contractState.waitingForVerificationbySeller);
            emit TermsAndConditionsSignedBy("Terms and Conditiond verified : ", msg.sender);
            emit collateralWithdrawnSuccessfully("Double deposit is withdrawn successfully from: ", msg.sender);
            state = contractState.waitingForVerificationbyTransporter;
        }
        else if(msg.sender == transporter) {
            require(state == contractState.waitingForVerificationbyTransporter);
            emit TermsAndConditionsSignedBy("Terms and Conditiond verified : ", msg.sender);
            emit collateralWithdrawnSuccessfully("Double deposit is withdrawn successfully from: ", msg.sender);
            state = contractState.waitingForVerificationbyBuyer;
        }
        else if(msg.sender == buyer) {
            require(state == contractState.waitingForVerificationbyBuyer);
            emit TermsAndConditionsSignedBy("Terms and Conditiond verified : ", msg.sender);
            emit collateralWithdrawnSuccessfully("Double deposit is withdrawn successfully from: ", msg.sender);
            state = contractState.MoneyWithdrawn;
        }
    }
    
    function createPackageAndKey() public payable OnlySeller returns(bytes32) {
        require(state == contractState.MoneyWithdrawn);
        emit PackageCreatedBySeller("Package created and Key given to transporter by the sender ", msg.sender);
        state = contractState.PackageAndTransporterKeyCreated;
        cancellable[msg.sender] = false;
        cancellable[transporter]=false;
        bytes32 keyT = keccak256(
            abi.encodePacked(itemID, transporter, block.timestamp)
        );
        return keyT;
    }
    
    function deliverPackage() public OnlyTransporter {
        require(state == contractState.PackageAndTransporterKeyCreated);
        startdeliveryBlocktime = block.timestamp;//save the delivery time
        cancellable[buyer] = false;
        emit PackageIsOnTheWay("The package is being delivered and the key is received by the ", msg.sender);
        state = contractState.ItemOnTheWay;
    }
    
    function requestPackageKey() public OnlyBuyer returns (uint) {
        require(state == contractState.ItemOnTheWay);
        emit PackageKeyGivenToBuyer("The package Key is given to the ", msg.sender);
        state = contractState.PackageKeyGivenToBuyer;
        uint keyB = uint(keccak256(
            abi.encodePacked(itemID, buyer, block.timestamp)
        ));
        return keyB; 
    }
    
    function verifyTransporter(string memory keyT, string memory keyR) public OnlyTransporter {
        require(state == contractState.PackageKeyGivenToBuyer);
        emit ArrivedToDestination("Transporter Arrived To Destination and entered keys " , msg.sender);
        verificationHash[transporter] = keccak256(
                abi.encodePacked(keyT, keyR)    
            );
        state = contractState.ArrivedToDestination;
        startEntryTransporterKeysBlocktime = block.timestamp;
    }
    
    function verifyKeyBuyer(string memory keyT, string memory keyR) public OnlyBuyer {
        require(state == contractState.ArrivedToDestination);
        emit BuyerEnteredVerificationKeys("Reciever entered keys, waiting for payment settlement", msg.sender);
        verificationHash[buyer] = keccak256(
                abi.encodePacked(keyT, keyR)
            );
        state = contractState.buyerKeysEntered;
        verification();
    }
    
    function BuyerExceededTime() public OnlyTransporter {
        require(block.timestamp > startEntryTransporterKeysBlocktime + buyerVerificationTimeWindow && 
        state == contractState.ArrivedToDestination);
        emit BuyerExceededVerificationTime("Dispute: Buyer Exceeded Verification Time", msg.sender);
        verification();
    }
    
    function refund() public OnlyBuyer {
        //refund incase delivery took more than deadline
        require(block.timestamp > startdeliveryBlocktime+deliveryDuration &&
        (state == contractState.ItemOnTheWay || state == contractState.PackageKeyGivenToBuyer));
        emit DeliveryTimeExceeded("Item not delivered on time, Refund Request");
        state = contractState.Refund;
        buyer.transfer(2*itemPrice);
        seller.transfer(2*itemPrice);
        arbitrator.transfer(address(this).balance); //rest of ether with the arbitrator
        state = contractState.EtherWithArbitrator;
        emit EtherTransferredToArbitrator("Due to exceeding delivery time and refund request by receiver , all Ether deposits have been transferred to arbitrator ", arbitrator);
        state = contractState.Aborted;
        selfdestruct(msg.sender);
    }
    
    function verification() internal {
        require(state == contractState.buyerKeysEntered);
        if(verificationHash[transporter] == verificationHash[buyer]){
            emit SuccessfulVerification("Payment will shortly be settled , successful verification!");
            buyer.transfer(itemPrice);
            transporter.transfer((2*itemPrice) + ((10*itemPrice)/100));//receiver gets 10% of item price delivered
            seller.transfer((2*itemPrice)+((90*itemPrice)/100));
            state = contractState.PaymentSettledSuccess;
        }
        else {
            //trusted entity the Arbitrator resolves the issue
            emit VerificationFailure("Verification failed , keys do not match. Please solve the dispute off chain. No refunds.");
            state = contractState.DisputeVerificationFailure;
            arbitrator.transfer(address(this).balance);//all ether with the contract
            state = contractState.EtherWithArbitrator;
            emit EtherTransferredToArbitrator("Due to dispute all Ether deposits have been transferred to arbitrator ", arbitrator);
            state = contractState.Aborted;
            selfdestruct(msg.sender);
        }
    }
    
}
