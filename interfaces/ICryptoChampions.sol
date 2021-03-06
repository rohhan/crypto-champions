// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

struct ElderSpirit {
    bool valid;
    uint256 raceId;
    uint256 classId;
    string affinity;
    int256 affinityPrice;
}

struct Hero {
    bool valid;
    string name;
    string affinity;
    int256 affinityPrice;
    uint256 roundMinted;
    uint256 elderId;
    uint256 raceId;
    uint256 classId;
    uint256 appearance;
    uint256 trait1;
    uint256 trait2;
    uint256 skill1;
    uint256 skill2;
    uint256 alignment;
    uint256 background;
    uint256 hometown;
    uint256 weather;
    uint256 level;
    uint256 hp;
    uint256 mana;
    uint256 stamina;
    uint256 strength;
    uint256 dexterity;
    uint256 constitution;
    uint256 intelligence;
    uint256 wisdom;
    uint256 charisma;
}

interface ICryptoChampions {
    function createAffinity(string calldata tokenTicker, address feedAddress) external;

    function setElderMintPrice(uint256 price) external;

    function mintElderSpirit(
        uint256 raceId,
        uint256 classId,
        string calldata affinity
    ) external payable returns (uint256);

    function getElderOwner(uint256 elderId) external view returns (address);

    function mintHero(uint256 elderId, string memory heroName) external payable returns (uint256);

    function trainHero(uint256 heroId) external;

    function getHeroOwner(uint256 heroId) external view returns (address);

    function disburseRewards(string calldata winningAffinity) external;

    function burnElders() external;

    function burnHero(uint256 heroId) external;

    function getElderSpirit(uint256 elderId)
        external
        view
        returns (
            bool,
            uint256,
            uint256,
            string memory,
            int256
        );

    function getHeroGameData(uint256 heroId)
        external
        view
        returns (
            bool, // valid
            string memory, // affinity
            int256, // affinity price
            uint256, // round minted
            uint256 // elder id
        );

    function getHeroVisuals(uint256 heroId)
        external
        view
        returns (
            string memory, // name
            uint256, // race id
            uint256, // class id
            uint256 // appearance
        );

    function getHeroTraitsSkills(uint256 heroId)
        external
        view
        returns (
            uint256, // trait 1
            uint256, // trait 2
            uint256, // skill 1
            uint256 // skill 2
        );

    function getHeroLore(uint256 heroId)
        external
        view
        returns (
            uint256, // alignment
            uint256, // background
            uint256, // hometown
            uint256 // weather
        );

    function getHeroVitals(uint256 heroId)
        external
        view
        returns (
            uint256, // level
            uint256, // hp
            uint256, // mana
            uint256 // stamina
        );

    function getHeroStats(uint256 heroId)
        external
        view
        returns (
            uint256, // strength
            uint256, // dexterity
            uint256, // constitution
            uint256, // intelligence
            uint256, // wisdom
            uint256 // charisma
        );

    function getHeroMintPrice(uint256 round, uint256 elderId) external view returns (uint256);

    function getElderSpawnsAmount(uint256 round, uint256 elderId) external view returns (uint256);

    function getAffinityFeedAddress(string calldata affinity) external view returns (address);

    function declareRoundWinner(string calldata winningAffinity) external;

    function getNumEldersInGame() external view returns (uint256);

    function startNewPriceGame() external;
}
