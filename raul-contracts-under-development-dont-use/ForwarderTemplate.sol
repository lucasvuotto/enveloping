// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.16 <0.8.0;
pragma experimental ABIEncoderV2;

import "./IForwarder.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


/**
 * This is the Forwarder contract pointed by the Proxy.
 * It implements the common initialization logic and everything else is delegated to a wallet logic provided by
 * the requestor of the deploy.
 */

contract ForwarderTemplate is IForwarder {
    using ECDSA for bytes32;

    event RequestTypeRegistered(bytes32 indexed typeHash, string typeStr);

    string
        public constant GENERIC_PARAMS = "address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data,address tokenRecipient,address tokenContract,uint256 paybackTokens,uint256 tokenGas";
    
    //slot assignment of mappings are kecckak-256 based (the proxy logic shouldnt impact)
    mapping(bytes32 => bool) public typeHashes; 

    // Nonces of senders, used to prevent replay attacks
    mapping(address => uint256) private nonces;

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function getNonce(address from) external override view returns (uint256) {
        return nonces[from];
    }

    //This Template
    constructor() public {
        string memory requestType = string(
            abi.encodePacked("ForwardRequest(", GENERIC_PARAMS, ")")
        );
        registerRequestTypeInternal(requestType);
    }

    function registerRequestTypeInternal(string memory requestType) internal {
        bytes32 requestTypehash = keccak256(bytes(requestType));
        typeHashes[requestTypehash] = true;
        emit RequestTypeRegistered(requestTypehash, string(requestType));
    }

    function _getEncoded(
        ForwardRequest memory req,
        bytes32 requestTypeHash,
        bytes memory suffixData
    ) public pure returns (bytes memory) {
        return
            abi.encodePacked(
                requestTypeHash,
                abi.encode(
                    req.from,
                    req.to,
                    req.value,
                    req.gas,
                    req.nonce,
                    keccak256(req.data),
                    req.tokenRecipient,
                    req.tokenContract,
                    req.paybackTokens,
                    req.tokenGas
                ),
                suffixData
            );
    }

    function _verifySig(
        ForwardRequest memory req,
        bytes32 domainSeparator,
        bytes32 requestTypeHash,
        bytes memory suffixData,
        bytes memory sig
    ) internal view {
        require(typeHashes[requestTypeHash], "invalid request typehash");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(_getEncoded(req, requestTypeHash, suffixData))
            )
        );
        require(digest.recover(sig) == req.from, "signature mismatch");
    }


  function _verifyOwner(ForwardRequest memory req) internal view {
        address swalletOwner;
        assembly{
            //First of all, verify the req.from is the owner of this smart wallet
           swalletOwner := sload(
                0xa7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a
            )
        }

        require(swalletOwner == req.from, "Requestor is not the owner of the Smart Wallet");
  }

  function _verifyNonce(ForwardRequest memory req) internal view {
        require(nonces[req.from] == req.nonce, "nonce mismatch");
    }

    function verify(
        ForwardRequest memory req,
        bytes32 domainSeparator,
        bytes32 requestTypeHash,
        bytes calldata suffixData,
        bytes calldata sig
    ) external override view {
        _verifyOwner(req);
        _verifyNonce(req);
        _verifySig(req, domainSeparator, requestTypeHash, suffixData, sig);
    }

    /**
     * This Proxy will first charge for the deployment and then it will pass the
     * initialization scope to the wallet logic.
     * This function can only be called once, and it is called by the Factory during deployment
     * @param owner - The EOA that will own the smart wallet
     * @param logic - The address containing the custom logic where to delegate everything that is not payment-related
     * @param tokenAddr - The Token used for payment of the deploy
     * @param transferData - payment function and params to use when calling the Token.
     * sizeof(transferData) = transfer(4) + _to(20) + _value(32) = 56 bytes = 0x38
     * @param initParams - Initialization data to pass to the custom logic's initialize(bytes) function
     */
    function initialize(
        address owner,
        address logic,
        address tokenAddr,
        bytes memory transferData,
        bytes memory initParams
    ) external {
        assembly {
            //This function can be called only if not initialized (i.e., owner not set)
            //The slot used complies with EIP-1967-like, obtained as:
            //slot for owner = bytes32(uint256(keccak256('eip1967.proxy.owner')) - 1) = a7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a
            let swalletOwner := sload(
                0xa7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a
            )

            switch swalletOwner
                case 0 {
                    //If swallet is zero then initialize hasn't successfully been called yet

                    //Transfer the negotiated charge of the deploy
                    let isSuccess := call(
                        gas(),
                        tokenAddr,
                        0x0,
                        transferData,
                        0x38,
                        0x0,
                        0x0
                    )

                    //If the payment for the deployment is not successful, then revert
                    if iszero(isSuccess) {
                        revert(0, 0)
                    }
                }
                default {
                    //If swallet is not zero then initialize has already been successfully called.
                    //This contract execution is stopped (the flow exits, the lines below are not executed)
                    stop() //same as return(0,0)
                }
        }

        //swallet was 0 so we need to initialize the contract
        //Initialize function of wallet library must be initialize(bytes) = 439fab91

        //Initialize the custom logic of the Smart Wallet (if any)

        if (address(0) != logic) {
            bytes memory initP = abi.encodePacked(hex"439fab91", initParams);
            (bool success, ) = logic.delegatecall(initP);

            if (!success) {
                revert("initialize(bytes) call in logic contract failed");
            }
            assembly {
                //The slot used complies with EIP-1967, obtained as:
                //bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
                sstore(
                    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                    logic
                )
            }
        }

        //If it didnt revert it means success was true, we can then set this instance as initialized, by
        //storing the logic address
        //Set the owner of this Smart Wallet
        //slot for owner = bytes32(uint256(keccak256('eip1967.proxy.owner')) - 1) = a7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a
        assembly {
            sstore(
                0xa7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a,
                owner
            )
        }
    }

    function registerRequestType(
        string calldata typeName,
        string calldata typeSuffix
    ) external override {
        for (uint256 i = 0; i < bytes(typeName).length; i++) {
            bytes1 c = bytes(typeName)[i];
            require(c != "(" && c != ")", "invalid typename");
        }

        string memory requestType = string(
            abi.encodePacked(typeName, "(", GENERIC_PARAMS, ",", typeSuffix)
        );
        registerRequestTypeInternal(requestType);
    }

    function execute(
        ForwardRequest memory req,
        bytes32 domainSeparator,
        bytes32 requestTypeHash,
        bytes calldata suffixData,
        bytes calldata sig
    )
        external
        override
        payable
        returns (
            bool success,
            bytes memory ret,
            uint256 lastTxSucc
        )
    {
        
      
      

        _verifyOwner(req);
        _verifyNonce(req);
        _verifySig(req, domainSeparator, requestTypeHash, suffixData, sig);
        _updateNonce(req);

        // Perform the payment for the execution
        // solhint-disable-next-line avoid-low-level-calls
        (success, ret) = req.tokenContract.call{gas: req.tokenGas}(
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                req.tokenRecipient,
                req.paybackTokens
            )
        );

        if (!success) {
            return (success, ret, 0);
        }

        _updateNonce(req);

 

        address logic = address(0);
        assembly {
            logic := sload(
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
            )
        }


        // solhint-disable-next-line avoid-low-level-calls
        // If there's no extra logic, then call the destination contract
        if (logic == address(0)) {
            (success, ret) = req.to.call{gas: req.gas, value: req.value}(
                abi.encodePacked(req.data, req.from)
            );
        } 
        //If there's extra logic, delegate the execution
        else {
            (success, ret) = logic.delegatecall(msg.data);
        }

        //If any balance has been added then trasfer it to the owner EOA
        if (address(this).balance > 0) {
            //can't fail: req.from signed (off-chain) the request, so it must be an EOA...
            payable(req.from).transfer(address(this).balance);
        }

        if (!success) {
            return (success, ret, 1);
        }

        return (success, ret, 2);
    }

    function _updateNonce(ForwardRequest memory req) internal {
        nonces[req.from]++;
    }

    fallback() external {
        assembly {
            let ptr := mload(0x40)
            let walletImpl := sload(
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
            )

            // (1) copy incoming call data
            calldatacopy(ptr, 0, calldatasize())

            // (2) forward call to logic contract
            let result := delegatecall(
                gas(),
                walletImpl,
                ptr,
                calldatasize(),
                0,
                0
            )
            let size := returndatasize()

            // (3) retrieve return data
            returndatacopy(ptr, 0, size)

            // (4) forward return data back to caller
            switch result
                case 0 {
                    revert(ptr, size)
                }
                default {
                    return(ptr, size)
                }
        }
    }
}