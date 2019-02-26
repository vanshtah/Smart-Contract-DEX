pragma solidity ^0.4.18;

import "./owned.sol";
import "./FixedSupplyToken.sol";

contract Exchange is owned {

    /**
     * @title Offer
     * @dev General structure
     */
    struct Offer {
        uint amountTokens;
        address who;
    }

    struct OrderBook {
        uint higherPrice;
        uint lowerPrice;
        mapping (uint => Offer) offers;
        uint offers_key;
        uint offers_length;
    }

    struct Token {
        address tokenContract;
        string symbolName;
        mapping (uint => OrderBook) buyBook;

        uint curBuyPrice;
        uint lowestBuyPrice;
        uint amountBuyPrices;

        mapping (uint => OrderBook) sellBook;

        uint curSellPrice;
        uint highestSellPrice;
        uint amountSellPrices;
    }

    mapping (uint8 => Token) tokens;
    uint8 symbolNameIndex;

    mapping (address => mapping (uint8 => uint)) tokenBalanceForAddress;

    mapping (address => uint) balanceEthForAddress;

    event TokenAddedToSystem(uint _symbolIndex, string _token, uint _timestamp);
    event DepositForTokenReceived(address indexed _from, uint indexed _symbolIndex, uint _amountTokens, uint _timestamp);
    event WithdrawalToken(address indexed _to, uint indexed _symbolIndex, uint _amountTokens, uint _timestamp);
    event DepositForEthReceived(address indexed _from, uint _amount, uint _timestamp);
    event WithdrawalEth(address indexed _to, uint _amount, uint _timestamp);
    event LimitBuyOrderCreated(uint indexed _symbolIndex, address indexed _who, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event LimitSellOrderCreated(uint indexed _symbolIndex, address indexed _who, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event BuyOrderFulfilled(uint indexed _symbolIndex, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event SellOrderFulfilled(uint indexed _symbolIndex, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event BuyOrderCanceled(uint indexed _symbolIndex, uint _priceInWei, uint _orderKey);
    event SellOrderCanceled(uint indexed _symbolIndex, uint _priceInWei, uint _orderKey);
    event Debug(uint _test1, uint _test2, uint _test3, uint _test4);

    function depositEther() public payable {
        require(balanceEthForAddress[msg.sender] + msg.value >= balanceEthForAddress[msg.sender]);
        balanceEthForAddress[msg.sender] += msg.value;
        DepositForEthReceived(msg.sender, msg.value, now);
    }

    function withdrawEther(uint amountInWei) public {
        require(balanceEthForAddress[msg.sender] - amountInWei >= 0);
        require(balanceEthForAddress[msg.sender] - amountInWei <= balanceEthForAddress[msg.sender]);
        balanceEthForAddress[msg.sender] -= amountInWei;
        msg.sender.transfer(amountInWei);
        WithdrawalEth(msg.sender, amountInWei, now);
    }

    function getEthBalanceInWei() public constant returns (uint) {
        return balanceEthForAddress[msg.sender];
    }

    function addToken(string symbolName, address erc20TokenAddress) public onlyowner {

        require(!hasToken(symbolName));

        symbolNameIndex++;
        tokens[symbolNameIndex].symbolName = symbolName;
        tokens[symbolNameIndex].tokenContract = erc20TokenAddress;
        TokenAddedToSystem(symbolNameIndex, symbolName, now);
    }

    function hasToken(string symbolName) public constant returns (bool) {
        uint8 index = getSymbolIndex(symbolName);
        if (index == 0) {
            return false;
        }
        return true;
    }

    function getSymbolIndex(string symbolName) internal returns (uint8) {
        for (uint8 i = 1; i <= symbolNameIndex; i++) {
            if (stringsEqual(tokens[i].symbolName, symbolName)) {
                return i;
            }
        }
        return 0;
    }

    function getSymbolIndexOrThrow(string symbolName) returns (uint8) {
        uint8 index = getSymbolIndex(symbolName);
        require(index > 0);
        return index;
    }

    function stringsEqual(string storage _a, string memory _b) internal returns (bool) {
        bytes storage a = bytes(_a);
        bytes memory b = bytes(_b);
        if (sha3(a) != sha3(b)) { return false; }
        return true;
    }

    function depositToken(string symbolName, uint amountTokens) public {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        require(tokens[symbolNameIndex].tokenContract != address(0));

        ERC20Interface token = ERC20Interface(tokens[symbolNameIndex].tokenContract);

        require(token.transferFrom(msg.sender, address(this), amountTokens) == true);
        require(tokenBalanceForAddress[msg.sender][symbolNameIndex] + amountTokens >= tokenBalanceForAddress[msg.sender][symbolNameIndex]);
        tokenBalanceForAddress[msg.sender][symbolNameIndex] += amountTokens;
        DepositForTokenReceived(msg.sender, symbolNameIndex, amountTokens, now);
    }

    function withdrawToken(string symbolName, uint amountTokens) public {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        require(tokens[symbolNameIndex].tokenContract != address(0));

        ERC20Interface token = ERC20Interface(tokens[symbolNameIndex].tokenContract);

        require(tokenBalanceForAddress[msg.sender][symbolNameIndex] - amountTokens >= 0);
        require(tokenBalanceForAddress[msg.sender][symbolNameIndex] - amountTokens <= tokenBalanceForAddress[msg.sender][symbolNameIndex]);
        tokenBalanceForAddress[msg.sender][symbolNameIndex] -= amountTokens;
        require(token.transfer(msg.sender, amountTokens) == true);
        WithdrawalToken(msg.sender, symbolNameIndex, amountTokens, now);
    }

    function getBalance(string symbolName) public constant returns (uint) {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        return tokenBalanceForAddress[msg.sender][symbolNameIndex];
    }

    function getBuyOrderBook(string symbolName) public constant returns (uint[], uint[]) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint[] memory arrPricesBuy = new uint[](tokens[tokenNameIndex].amountBuyPrices);
        uint[] memory arrVolumesBuy = new uint[](tokens[tokenNameIndex].amountBuyPrices);

        uint whilePrice = tokens[tokenNameIndex].lowestBuyPrice;
        uint counter = 0;
        if (tokens[tokenNameIndex].curBuyPrice > 0) {
            while (whilePrice <= tokens[tokenNameIndex].curBuyPrice) {
                arrPricesBuy[counter] = whilePrice;
                uint buyVolumeAtPrice = 0;
                uint buyOffersKey = 0;

                buyOffersKey = tokens[tokenNameIndex].buyBook[whilePrice].offers_key;
                while (buyOffersKey <= tokens[tokenNameIndex].buyBook[whilePrice].offers_length) {
                    buyVolumeAtPrice += tokens[tokenNameIndex].buyBook[whilePrice].offers[buyOffersKey].amountTokens;
                    buyOffersKey++;
                }
                arrVolumesBuy[counter] = buyVolumeAtPrice;
                if (whilePrice == tokens[tokenNameIndex].buyBook[whilePrice].higherPrice) {
                    break;
                }
                else {
                    whilePrice = tokens[tokenNameIndex].buyBook[whilePrice].higherPrice;
                }
                counter++;
            }
        }
        return (arrPricesBuy, arrVolumesBuy);
    }

    function getSellOrderBook(string symbolName) public constant returns (uint[], uint[]) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint[] memory arrPricesSell = new uint[](tokens[tokenNameIndex].amountSellPrices);
        uint[] memory arrVolumesSell = new uint[](tokens[tokenNameIndex].amountSellPrices);
        uint sellWhilePrice = tokens[tokenNameIndex].curSellPrice;
        uint sellCounter = 0;
        if (tokens[tokenNameIndex].curSellPrice > 0) {
            while (sellWhilePrice <= tokens[tokenNameIndex].highestSellPrice) {
                arrPricesSell[sellCounter] = sellWhilePrice;
                uint sellVolumeAtPrice = 0;
                uint sellOffersKey = 0;
                sellOffersKey = tokens[tokenNameIndex].sellBook[sellWhilePrice].offers_key;
                while (sellOffersKey <= tokens[tokenNameIndex].sellBook[sellWhilePrice].offers_length) {
                    sellVolumeAtPrice += tokens[tokenNameIndex].sellBook[sellWhilePrice].offers[sellOffersKey].amountTokens;
                    sellOffersKey++;
                }
                arrVolumesSell[sellCounter] = sellVolumeAtPrice;
                if (tokens[tokenNameIndex].sellBook[sellWhilePrice].higherPrice == 0) {
                    break;
                }
                else {
                    sellWhilePrice = tokens[tokenNameIndex].sellBook[sellWhilePrice].higherPrice;
                }
                sellCounter++;
            }
        }
        return (arrPricesSell, arrVolumesSell);
    }

    function buyToken(string symbolName, uint priceInWei, uint amount) public {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint totalAmountOfEtherNecessary = 0;
        uint amountOfTokensNecessary = amount;

        if (tokens[tokenNameIndex].amountSellPrices == 0 || tokens[tokenNameIndex].curSellPrice > priceInWei) {
            createBuyLimitOrderForTokensUnableToMatchWithSellOrderForBuyer(symbolName, tokenNameIndex, priceInWei, amountOfTokensNecessary, totalAmountOfEtherNecessary);
        } else {
            uint totalAmountOfEtherAvailable = 0;
            uint whilePrice = tokens[tokenNameIndex].curSellPrice;
            uint offers_key;

            while (whilePrice <= priceInWei && amountOfTokensNecessary > 0) {
                offers_key = tokens[tokenNameIndex].sellBook[whilePrice].offers_key;
                while (offers_key <= tokens[tokenNameIndex].sellBook[whilePrice].offers_length && amountOfTokensNecessary > 0) {
                    uint volumeAtPriceFromAddress = tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amountTokens;

                    if (volumeAtPriceFromAddress <= amountOfTokensNecessary) {
                        totalAmountOfEtherAvailable = volumeAtPriceFromAddress * whilePrice;

                        require(balanceEthForAddress[msg.sender] >= totalAmountOfEtherAvailable);
                        require(balanceEthForAddress[msg.sender] - totalAmountOfEtherAvailable <= balanceEthForAddress[msg.sender]);

                        balanceEthForAddress[msg.sender] -= totalAmountOfEtherAvailable;
                        require(balanceEthForAddress[msg.sender] >= totalAmountOfEtherAvailable);
                        require(uint(1) > uint(0));
                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] + volumeAtPriceFromAddress >= tokenBalanceForAddress[msg.sender][tokenNameIndex]);
                        require(balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] + totalAmountOfEtherAvailable >= balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who]);

                        tokenBalanceForAddress[msg.sender][tokenNameIndex] += volumeAtPriceFromAddress;
                        tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amountTokens = 0;
                        balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] += totalAmountOfEtherAvailable;
                        tokens[tokenNameIndex].sellBook[whilePrice].offers_key++;

                        BuyOrderFulfilled(tokenNameIndex, volumeAtPriceFromAddress, whilePrice, offers_key);

                        amountOfTokensNecessary -= volumeAtPriceFromAddress;
                    } else {
                        require(tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amountTokens > amountOfTokensNecessary);

                        totalAmountOfEtherNecessary = amountOfTokensNecessary * whilePrice;
                        require(balanceEthForAddress[msg.sender] - totalAmountOfEtherNecessary <= balanceEthForAddress[msg.sender]);
                        balanceEthForAddress[msg.sender] -= totalAmountOfEtherNecessary;
                        require(balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] + totalAmountOfEtherNecessary >= balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who]);

                        tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amountTokens -= amountOfTokensNecessary;
                        balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] += totalAmountOfEtherNecessary;
                        tokenBalanceForAddress[msg.sender][tokenNameIndex] += amountOfTokensNecessary;
                        amountOfTokensNecessary = 0;

                        BuyOrderFulfilled(tokenNameIndex, amountOfTokensNecessary, whilePrice, offers_key);
                    }

                    if (
                        offers_key == tokens[tokenNameIndex].sellBook[whilePrice].offers_length &&
                        tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amountTokens == 0
                    ) {
                        tokens[tokenNameIndex].amountSellPrices--;
                        if (whilePrice == tokens[tokenNameIndex].sellBook[whilePrice].higherPrice || tokens[tokenNameIndex].sellBook[whilePrice].higherPrice == 0) {
                            tokens[tokenNameIndex].curSellPrice = 0;
                        } else {
                            tokens[tokenNameIndex].curSellPrice = tokens[tokenNameIndex].sellBook[whilePrice].higherPrice;
                            tokens[tokenNameIndex].sellBook[tokens[tokenNameIndex].sellBook[whilePrice].higherPrice].lowerPrice = 0;
                        }
                    }
                    offers_key++;
                }
                whilePrice = tokens[tokenNameIndex].curSellPrice;
            }

            if (amountOfTokensNecessary > 0) {
                createBuyLimitOrderForTokensUnableToMatchWithSellOrderForBuyer(symbolName, tokenNameIndex, priceInWei, amountOfTokensNecessary, totalAmountOfEtherNecessary);
            }
        }
    }

    function createBuyLimitOrderForTokensUnableToMatchWithSellOrderForBuyer(
        string symbolName, uint8 tokenNameIndex, uint priceInWei, uint amountOfTokensNecessary, uint totalAmountOfEtherNecessary
    ) internal {
        totalAmountOfEtherNecessary = amountOfTokensNecessary * priceInWei;

        require(totalAmountOfEtherNecessary >= amountOfTokensNecessary);
        require(totalAmountOfEtherNecessary >= priceInWei);
        require(balanceEthForAddress[msg.sender] >= totalAmountOfEtherNecessary);
        require(balanceEthForAddress[msg.sender] - totalAmountOfEtherNecessary >= 0);
        require(balanceEthForAddress[msg.sender] - totalAmountOfEtherNecessary <= balanceEthForAddress[msg.sender]);

        balanceEthForAddress[msg.sender] -= totalAmountOfEtherNecessary;

        addBuyOffer(tokenNameIndex, priceInWei, amountOfTokensNecessary, msg.sender);
 
        LimitBuyOrderCreated(tokenNameIndex, msg.sender, amountOfTokensNecessary, priceInWei, tokens[tokenNameIndex].buyBook[priceInWei].offers_length);
    }

    function addBuyOffer(uint8 tokenIndex, uint priceInWei, uint amount, address who) internal {
        tokens[tokenIndex].buyBook[priceInWei].offers_length++;

        tokens[tokenIndex].buyBook[priceInWei].offers[tokens[tokenIndex].buyBook[priceInWei].offers_length] = Offer(amount, who);

        if (tokens[tokenIndex].buyBook[priceInWei].offers_length == 1) {
            tokens[tokenIndex].buyBook[priceInWei].offers_key = 1;
            tokens[tokenIndex].amountBuyPrices++;

            uint curBuyPrice = tokens[tokenIndex].curBuyPrice;
            uint lowestBuyPrice = tokens[tokenIndex].lowestBuyPrice;

            if (lowestBuyPrice == 0 || lowestBuyPrice > priceInWei) {
                if (curBuyPrice == 0) {
                    tokens[tokenIndex].curBuyPrice = priceInWei;
                    tokens[tokenIndex].buyBook[priceInWei].higherPrice = priceInWei;
                    tokens[tokenIndex].buyBook[priceInWei].lowerPrice = 0;
                } else {
                    tokens[tokenIndex].buyBook[lowestBuyPrice].lowerPrice = priceInWei;
                    tokens[tokenIndex].buyBook[priceInWei].higherPrice = lowestBuyPrice;
                    tokens[tokenIndex].buyBook[priceInWei].lowerPrice = 0;
                }
                tokens[tokenIndex].lowestBuyPrice = priceInWei;
            }
            else if (curBuyPrice < priceInWei) {
                tokens[tokenIndex].buyBook[curBuyPrice].higherPrice = priceInWei;
                tokens[tokenIndex].buyBook[priceInWei].higherPrice = priceInWei;
                tokens[tokenIndex].buyBook[priceInWei].lowerPrice = curBuyPrice;
                tokens[tokenIndex].curBuyPrice = priceInWei;
            }
            else {
                uint buyPrice = tokens[tokenIndex].curBuyPrice;
                bool weFoundLocation = false;
                while (buyPrice > 0 && !weFoundLocation) {
                    if (
                        buyPrice < priceInWei &&
                        tokens[tokenIndex].buyBook[buyPrice].higherPrice > priceInWei
                    ) {
                        tokens[tokenIndex].buyBook[priceInWei].lowerPrice = buyPrice;
                        tokens[tokenIndex].buyBook[priceInWei].higherPrice = tokens[tokenIndex].buyBook[buyPrice].higherPrice;
                        tokens[tokenIndex].buyBook[tokens[tokenIndex].buyBook[buyPrice].higherPrice].lowerPrice = priceInWei;
                        tokens[tokenIndex].buyBook[buyPrice].higherPrice = priceInWei;
                        weFoundLocation = true;
                    }
                    buyPrice = tokens[tokenIndex].buyBook[buyPrice].lowerPrice;
                }
            }
        }
    }

    function sellToken(string symbolName, uint priceInWei, uint amount) public payable {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint totalAmountOfEtherNecessary = 0;
        uint totalAmountOfEtherAvailable = 0;
        uint amountOfTokensNecessary = amount;

        if (tokens[tokenNameIndex].amountBuyPrices == 0 || tokens[tokenNameIndex].curBuyPrice < priceInWei) {
            createSellLimitOrderForTokensUnableToMatchWithBuyOrderForSeller(symbolName, tokenNameIndex, priceInWei, amountOfTokensNecessary, totalAmountOfEtherNecessary);
        } else {
            uint whilePrice = tokens[tokenNameIndex].curBuyPrice;
            uint offers_key;
            while (whilePrice >= priceInWei && amountOfTokensNecessary > 0) {
                offers_key = tokens[tokenNameIndex].buyBook[whilePrice].offers_key;
                while (offers_key <= tokens[tokenNameIndex].buyBook[whilePrice].offers_length && amountOfTokensNecessary > 0) {
                    uint volumeAtPriceFromAddress = tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amountTokens;
                    if (volumeAtPriceFromAddress <= amountOfTokensNecessary) {
                        totalAmountOfEtherAvailable = volumeAtPriceFromAddress * whilePrice;

                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] >= volumeAtPriceFromAddress);
                        
                        tokenBalanceForAddress[msg.sender][tokenNameIndex] -= volumeAtPriceFromAddress;

                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] - volumeAtPriceFromAddress >= 0);
                        require(tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] + volumeAtPriceFromAddress >= tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex]);
                        require(balanceEthForAddress[msg.sender] + totalAmountOfEtherAvailable >= balanceEthForAddress[msg.sender]);

                        tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] += volumeAtPriceFromAddress;
                        tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amountTokens = 0;
                        balanceEthForAddress[msg.sender] += totalAmountOfEtherAvailable;
                        tokens[tokenNameIndex].buyBook[whilePrice].offers_key++;
                        SellOrderFulfilled(tokenNameIndex, volumeAtPriceFromAddress, whilePrice, offers_key);
                        amountOfTokensNecessary -= volumeAtPriceFromAddress;

                    } else {
                        require(volumeAtPriceFromAddress - amountOfTokensNecessary > 0);
                        totalAmountOfEtherNecessary = amountOfTokensNecessary * whilePrice;
                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] >= amountOfTokensNecessary);

                        tokenBalanceForAddress[msg.sender][tokenNameIndex] -= amountOfTokensNecessary;
                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] >= amountOfTokensNecessary);
                        require(balanceEthForAddress[msg.sender] + totalAmountOfEtherNecessary >= balanceEthForAddress[msg.sender]);
                        require(tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] + amountOfTokensNecessary >= tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex]);
                        tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amountTokens -= amountOfTokensNecessary;
                        balanceEthForAddress[msg.sender] += totalAmountOfEtherNecessary;
                        tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] += amountOfTokensNecessary;
                        SellOrderFulfilled(tokenNameIndex, amountOfTokensNecessary, whilePrice, offers_key);
                        amountOfTokensNecessary = 0;
                    }

                    if (
                        offers_key == tokens[tokenNameIndex].buyBook[whilePrice].offers_length &&
                        tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amountTokens == 0
                    ) {
                        tokens[tokenNameIndex].amountBuyPrices--;
                        if (whilePrice == tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice || tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice == 0) {
                            tokens[tokenNameIndex].curBuyPrice = 0;
                        } else {
                            tokens[tokenNameIndex].curBuyPrice = tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice;
                            tokens[tokenNameIndex].buyBook[tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice].higherPrice = tokens[tokenNameIndex].curBuyPrice;
                        }
                    }
                    offers_key++;
                }
                whilePrice = tokens[tokenNameIndex].curBuyPrice;
            }

            if (amountOfTokensNecessary > 0) {

                createSellLimitOrderForTokensUnableToMatchWithBuyOrderForSeller(symbolName, tokenNameIndex, priceInWei, amountOfTokensNecessary, totalAmountOfEtherNecessary);
            }
        }
    }

    function createSellLimitOrderForTokensUnableToMatchWithBuyOrderForSeller(
        string symbolName, uint8 tokenNameIndex, uint priceInWei, uint amountOfTokensNecessary, uint totalAmountOfEtherNecessary
    ) internal {
        totalAmountOfEtherNecessary = amountOfTokensNecessary * priceInWei;

        require(totalAmountOfEtherNecessary >= amountOfTokensNecessary);
        require(totalAmountOfEtherNecessary >= priceInWei);
        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] >= amountOfTokensNecessary);
        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] - amountOfTokensNecessary >= 0);
        require(balanceEthForAddress[msg.sender] + totalAmountOfEtherNecessary >= balanceEthForAddress[msg.sender]);
        tokenBalanceForAddress[msg.sender][tokenNameIndex] -= amountOfTokensNecessary;
        addSellOffer(tokenNameIndex, priceInWei, amountOfTokensNecessary, msg.sender);
        LimitSellOrderCreated(tokenNameIndex, msg.sender, amountOfTokensNecessary, priceInWei, tokens[tokenNameIndex].sellBook[priceInWei].offers_length);
    }

    function addSellOffer(uint8 tokenIndex, uint priceInWei, uint amount, address who) internal {
        tokens[tokenIndex].sellBook[priceInWei].offers_length++;

        tokens[tokenIndex].sellBook[priceInWei].offers[tokens[tokenIndex].sellBook[priceInWei].offers_length] = Offer(amount, who);

        if (tokens[tokenIndex].sellBook[priceInWei].offers_length == 1) {
            tokens[tokenIndex].sellBook[priceInWei].offers_key = 1;
            tokens[tokenIndex].amountSellPrices++;
        
            uint curSellPrice = tokens[tokenIndex].curSellPrice;
            uint highestSellPrice = tokens[tokenIndex].highestSellPrice;

            if (highestSellPrice == 0 || highestSellPrice < priceInWei) {
                if (curSellPrice == 0) {
                    tokens[tokenIndex].curSellPrice = priceInWei;
                    tokens[tokenIndex].sellBook[priceInWei].higherPrice = 0;
                    tokens[tokenIndex].sellBook[priceInWei].lowerPrice = 0;
                } else {
                    tokens[tokenIndex].sellBook[highestSellPrice].higherPrice = priceInWei;
                    tokens[tokenIndex].sellBook[priceInWei].lowerPrice = highestSellPrice;
                    tokens[tokenIndex].sellBook[priceInWei].higherPrice = 0;
                }
                tokens[tokenIndex].highestSellPrice = priceInWei;
            }
            else if (curSellPrice > priceInWei) {
                tokens[tokenIndex].sellBook[curSellPrice].lowerPrice = priceInWei;
                tokens[tokenIndex].sellBook[priceInWei].higherPrice = curSellPrice;
                tokens[tokenIndex].sellBook[priceInWei].lowerPrice = 0;
                tokens[tokenIndex].curSellPrice = priceInWei;
            }
            else {
                uint sellPrice = tokens[tokenIndex].curSellPrice;
                bool weFoundLocation = false;
                while (sellPrice > 0 && !weFoundLocation) {
                    if (
                        sellPrice < priceInWei &&
                        tokens[tokenIndex].sellBook[sellPrice].higherPrice > priceInWei
                    ) {
                        tokens[tokenIndex].sellBook[priceInWei].lowerPrice = sellPrice;
                        tokens[tokenIndex].sellBook[priceInWei].higherPrice = tokens[tokenIndex].sellBook[sellPrice].higherPrice;
                        tokens[tokenIndex].sellBook[tokens[tokenIndex].sellBook[sellPrice].higherPrice].lowerPrice = priceInWei;
                        tokens[tokenIndex].sellBook[sellPrice].higherPrice = priceInWei;
                        weFoundLocation = true;
                    }
                    sellPrice = tokens[tokenIndex].sellBook[sellPrice].higherPrice;
                }
            }
        }
    }

    function cancelOrder(string symbolName, bool isSellOrder, uint priceInWei, uint offerKey) public {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        if (isSellOrder) {
            require(tokens[symbolNameIndex].sellBook[priceInWei].offers[offerKey].who == msg.sender);
            uint tokensAmount = tokens[symbolNameIndex].sellBook[priceInWei].offers[offerKey].amountTokens;
            require(tokenBalanceForAddress[msg.sender][symbolNameIndex] + tokensAmount >= tokenBalanceForAddress[msg.sender][symbolNameIndex]);
            tokenBalanceForAddress[msg.sender][symbolNameIndex] += tokensAmount;
            tokens[symbolNameIndex].sellBook[priceInWei].offers[offerKey].amountTokens = 0;
            SellOrderCanceled(symbolNameIndex, priceInWei, offerKey);

        }
        else {
            require(tokens[symbolNameIndex].buyBook[priceInWei].offers[offerKey].who == msg.sender);
            uint etherToRefund = tokens[symbolNameIndex].buyBook[priceInWei].offers[offerKey].amountTokens * priceInWei;
            require(balanceEthForAddress[msg.sender] + etherToRefund >= balanceEthForAddress[msg.sender]);
            balanceEthForAddress[msg.sender] += etherToRefund;
            tokens[symbolNameIndex].buyBook[priceInWei].offers[offerKey].amountTokens = 0;
            BuyOrderCanceled(symbolNameIndex, priceInWei, offerKey);
        }
    }
}