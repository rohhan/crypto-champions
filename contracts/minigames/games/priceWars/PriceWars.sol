// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import "../../Minigame.sol";
import "alphachainio/chainlink-contracts@1.1.3/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "../../../../interfaces/ICryptoChampions.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SignedSafeMath.sol";

/// @title PriceWars
/// @author cds95
/// @notice This is the contract for the price wars minigame
contract PriceWars is Minigame {
    using SignedSafeMath for int;

    // Initializes a new price war minigame
    constructor(address cryptoChampionsContractAddress) Minigame("price-wars", cryptoChampionsContractAddress) public {}

    /// @notice Executes one round of a price war minigame by determining the affinity with the token that had the greatest gain.
    function play() internal override {
        string memory winningAffinity;
        int greatestPercentageChange;
        for(uint256 elderId = 1; elderId <= cryptoChampions.getNumEldersInGame(); elderId++) {
            string memory affinity;
            int startAffinityPrice;
            (, , , affinity, startAffinityPrice) = cryptoChampions.getElderSpirit(elderId);
            int percentageChange = determinePercentageChange(startAffinityPrice, affinity);
            if(percentageChange > greatestPercentageChange || greatestPercentageChange == 0) {
                greatestPercentageChange = percentageChange;
                winningAffinity = affinity;
            }
        }
        cryptoChampions.declareRoundWinner(winningAffinity);
    }

    /// @notice Determines the percentage change of a token.
    /// @return The token's percentage change.
    function determinePercentageChange(int startAffinityPrice, string memory affinity) internal returns (int) {
        address feedAddress = cryptoChampions.getAffinityFeedAddress(affinity);
        int currentAffinityPrice;
        (, currentAffinityPrice, , , ) = AggregatorV3Interface(feedAddress).latestRoundData();
        int absoluteChange = currentAffinityPrice.sub(startAffinityPrice);
        return absoluteChange.mul(100).div(startAffinityPrice);
    }
}