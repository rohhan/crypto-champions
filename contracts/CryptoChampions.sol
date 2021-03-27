// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import "../interfaces/ICryptoChampions.sol";

import "alphachainio/chainlink-contracts@1.1.3/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "alphachainio/chainlink-contracts@1.1.3/contracts/src/v0.6/VRFConsumerBase.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/access/AccessControl.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC1155/ERC1155.sol";

/// @title Crypto Champions Interface
/// @author Oozyx
/// @notice This is the crypto champions class
contract CryptoChampions is ICryptoChampions, AccessControl, ERC1155, VRFConsumerBase {
    using SafeMath for uint256;

    // Possible phases the contract can be in.  Phase one is when users can mint elder spirits and two is when they can mint heros.
    enum Phase { ONE, TWO }

    // The current phase the contract is in.
    Phase public currentPhase;

    // The owner role is used to globally govern the contract
    bytes32 internal constant ROLE_OWNER = keccak256("ROLE_OWNER");

    // The admin role is used for administrator duties and reports to the owner
    bytes32 internal constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    // Reserved id for the in game currency
    uint256 internal constant IN_GAME_CURRENCY_ID = 0;

    // Constants used to determine fee proportions.
    // Usage: fee.mul(proportion).div(10)
    uint8 internal constant HERO_MINT_ROYALTY_PROPORTION = 8;

    // The max amount of elders that can be minted
    uint256 public constant MAX_NUMBER_OF_ELDERS = 7;

    // The amount of elders minted
    // This amount cannot be greater than MAX_NUMBER_OF_ELDERS
    uint256 public eldersInGame = 0;

    // The mapping of elder id to elder owner, ids can only be in the range of [1, MAX_NUMBER OF ELDERS]
    mapping(uint256 => address) internal _elderOwners;

    // The mapping of elder id to the elder spirit
    mapping(uint256 => ElderSpirit) internal _elderSpirits;

    // The amount of heros minted
    uint256 public heroesMinted = 0;

    // The mapping of hero id to owner, ids can only be in the range of
    // [1 + MAX_NUMBER_OF_ELDERS, ]
    mapping(uint256 => address) internal _heroOwners;

    // The mapping of hero id to the hero
    mapping(uint256 => Hero) internal _heroes;

    // The mapping of the round played to the elder spawns mapping
    mapping(uint256 => mapping(uint256 => uint256)) internal _roundElderSpawns;

    // The mint price for elders and heroes
    uint256 public elderMintPrice;

    // The current round index
    uint256 public currentRound;

    // The mapping of affinities (token ticker) to price feed address
    mapping(string => address) internal _affinities;

    // The key hash used for VRF
    bytes32 internal _keyHash;

    // The fee in LINK for VRF
    uint256 internal _fee;

    // Random result from the VRF
    uint256 internal _randomResult;

    /// @notice Triggered when an elder spirit gets minted
    /// @param elderId The elder id belonging to the minted elder
    /// @param owner The address of the owner
    event ElderSpiritMinted(uint256 elderId, address owner);

    /// @notice Triggered when a hero gets minted
    /// @param heroId The hero id belonging to the hero that was minted
    /// @param owner The address of the owner
    event HeroMinted(uint256 heroId, address owner);

    /// @notice Triggered when the elder spirits have been burned
    event ElderSpiritsBurned();

    /// @notice Triggered when a hero has been burned
    /// @param heroId The hero id of the hero that was burned
    event HeroBurned(uint256 heroId);

    // Initializes a new CryptoChampions contract
    // TODO: need to provide the proper uri
    constructor(
        bytes32 keyhash,
        address vrfCoordinator,
        address linkToken
    ) public ERC1155("uri") VRFConsumerBase(vrfCoordinator, linkToken) {
        // Set up administrative roles
        _setRoleAdmin(ROLE_OWNER, ROLE_OWNER);
        _setRoleAdmin(ROLE_ADMIN, ROLE_OWNER);

        // Set up the deployer as the owner and give admin rights
        _setupRole(ROLE_OWNER, msg.sender);
        grantRole(ROLE_ADMIN, msg.sender);

        // Set initial elder mint price
        elderMintPrice = 0.271 ether;

        // Set the initial round to 0
        currentRound = 0;

        // Set initial phase to phase one
        currentPhase = Phase.ONE;

        // Set VRF fields
        _keyHash = keyhash;
        _fee = 0.1 * 10**18; // 0.1 LINK
    }

    modifier isValidElderSpiritId(uint256 elderId) {
        require(elderId > IN_GAME_CURRENCY_ID && elderId <= MAX_NUMBER_OF_ELDERS); // dev: Given id is not valid.
        _;
    }

    // Restrict to only admins
    modifier onlyAdmin {
        _hasRole(ROLE_ADMIN);
        _;
    }

    /// @notice Makes a request for a random number
    /// @param userProvidedSeed The seed for the random request
    /// @return The request id
    function _getRandomNumber(uint256 userProvidedSeed) internal returns (bytes32) {
        require(LINK.balanceOf(address(this)) >= _fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(_keyHash, _fee, userProvidedSeed);
    }

    /// @notice Callback function used by the VRF coordinator
    /// @param requestId The request id
    /// @param randomness The randomness
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        _randomResult = randomness;
    }

    /// @notice Sets the contract's phase
    /// @param phase The phase the contract should be set to
    function setPhase(Phase phase) external onlyAdmin {
        currentPhase = phase;
    }

    /// @notice Check if msg.sender has the role
    /// @param role The role to verify
    function _hasRole(bytes32 role) internal view {
        require(hasRole(role, msg.sender)); // dev: Access denied.
    }

    /// @notice Creates a new token affinity
    /// @dev This will be called by a priviledged address. It will allow to create new affinities. May need to add a
    /// remove affinity function as well.
    /// @param tokenTicker The token ticker of the affinity
    /// @param feedAddress The price feed address
    function createAffinity(string calldata tokenTicker, address feedAddress) external override onlyAdmin {
        _affinities[tokenTicker] = feedAddress;
    }

    /// @notice Sets the elder mint price
    /// @dev Can only be called by an admin address
    /// @param price The new elder mint price
    function setElderMintPrice(uint256 price) external override onlyAdmin {
        elderMintPrice = price;
    }

    /// @notice Mints an elder spirit
    /// @dev For now only race, class, and token (affinity) are needed. This will change. The race and class ids will
    /// probably be public constants defined in the crypto champions contract, this is subject to change.
    /// @param raceId The race id
    /// @param classId The class id
    /// @param affinity The affinity of the minted hero
    /// @return The elder spirit id
    function mintElderSpirit(
        uint256 raceId,
        uint256 classId,
        string calldata affinity
    ) external payable override returns (uint256) {
        require(eldersInGame < MAX_NUMBER_OF_ELDERS); // dev: Max number of elders already minted.
        require(msg.value >= elderMintPrice); // dev: Insufficient payment.
        require(_affinities[affinity] != address(0)); // dev: Affinity does not exist.

        // Generate the elderId and make sure it doesn't already exists
        uint256 elderId = eldersInGame.add(1);
        assert(_elderOwners[elderId] == address(0)); // dev: Elder with id already has owner.
        assert(_elderSpirits[elderId].valid == false); // dev: Elder spirit with id has already been generated.

        // Get the price data of affinity
        int256 affinityPrice;
        (, affinityPrice, , , ) = AggregatorV3Interface(_affinities[affinity]).latestRoundData();

        // Create the elder spirit
        ElderSpirit memory elder;
        elder.valid = true;
        elder.raceId = raceId;
        elder.classId = classId;
        elder.affinity = affinity;
        elder.affinityPrice = affinityPrice;

        // Mint the NFT
        _mint(_msgSender(), elderId, 1, ""); // TODO: give the URI

        // Assign the elder id with the owner and its spirit
        _elderOwners[elderId] = _msgSender();
        _elderSpirits[elderId] = elder;

        // Increment elders minted
        eldersInGame = eldersInGame.add(1);

        // Refund if user sent too much
        _refundSender(elderMintPrice);

        emit ElderSpiritMinted(elderId, _msgSender());

        return elderId;
    }

    /// @notice Gets the elder owner for the given elder id
    /// @param elderId The elder id
    /// @return The owner of the elder
    function getElderOwner(uint256 elderId) public view override isValidElderSpiritId(elderId) returns (address) {
        require(_elderOwners[elderId] != address(0)); // dev: Given elder id has not been minted.

        return _elderOwners[elderId];
    }

    /// @notice Mints a hero based on an elder spirit
    /// @param elderId The id of the elder spirit this hero is based on
    /// @return The hero id
    function mintHero(uint256 elderId, string calldata heroName)
        external
        payable
        override
        isValidElderSpiritId(elderId)
        returns (uint256)
    {
        require(_elderSpirits[elderId].valid); // dev: Elder with id doesn't exists or not valid.

        require(_canMintHero(elderId)); // dev: Can't mint hero. Too mnay heroes minted for elder.

        uint256 mintPrice = getHeroMintPrice(currentRound, elderId);
        require(msg.value >= mintPrice); // dev: Insufficient payment.

        // Generate the hero id
        uint256 heroId = heroesMinted.add(1) + MAX_NUMBER_OF_ELDERS;
        assert(_heroOwners[heroId] == address(0)); // dev: Hero with id already has an owner.
        assert(_heroes[heroId].valid == false); // dev: Hero with id has already been generated.

        // Create the hero
        Hero memory hero;
        hero.valid = true;
        hero.name = heroName;
        hero.roundMinted = currentRound;
        hero.elderId = elderId;
        hero.raceId = _elderSpirits[elderId].raceId;
        hero.classId = _elderSpirits[elderId].classId;
        hero.affinity = _elderSpirits[elderId].affinity;

        // Mint the NFT
        _mint(_msgSender(), heroId, 1, ""); // TODO: give the URI

        // Assign the hero id with the owner and with the hero
        _heroOwners[heroId] = _msgSender();
        _heroes[heroId] = hero;

        // Increment the heroes minted and the elder spawns
        heroesMinted = heroesMinted.add(1);
        _roundElderSpawns[currentRound][elderId] = _roundElderSpawns[currentRound][elderId].add(1);

        // Disburse royalties
        uint256 royaltyFee = mintPrice.mul(HERO_MINT_ROYALTY_PROPORTION).div(10);
        address seedOwner = _elderOwners[elderId];
        (bool success, ) = seedOwner.call{ value: royaltyFee }("");
        require(success, "Payment failed");
        // Remaining 20% kept for contract/Treum

        // Refund if user sent too much
        _refundSender(mintPrice);

        emit HeroMinted(heroId, _msgSender());

        return heroId;
    }

    /// @notice Checks to see if a hero can be minted for a given elder
    /// @dev (n < 4) || (n <= 2 * m)
    ///     n is number of champions already minted for elder
    ///     m is number of champions already minted for elder with least amount of champions
    /// @param elderId The elder id
    /// @return True if hero can be minted, false otherwise
    function _canMintHero(uint256 elderId) internal view returns (bool) {
        // Verify first condition
        if (_roundElderSpawns[currentRound][elderId] < 4) {
            return true;
        }

        // Find the elder with the least amount of heroes minted
        uint256 smallestElderAmount = _roundElderSpawns[currentRound][elderId];
        for (uint256 i = 1; i <= eldersInGame; ++i) {
            if (_roundElderSpawns[currentRound][i] < smallestElderAmount) {
                smallestElderAmount = _roundElderSpawns[currentRound][i];
            }
        }

        return _roundElderSpawns[currentRound][elderId] <= smallestElderAmount.mul(2);
    }

    /// @notice Get the hero owner for the given hero id
    /// @param heroId The hero id
    /// @return The owner address
    function getHeroOwner(uint256 heroId) public view override returns (address) {
        require(heroId > MAX_NUMBER_OF_ELDERS); // dev: Given hero id is not valid.
        require(_heroOwners[heroId] != address(0)); // dev: Given hero id has not been minted.

        return _heroOwners[heroId];
    }

    /// @notice Disburses the rewards evenly among the heroes of the winning affinity
    /// @dev This will be called from a priviledged address
    /// @param winningAffinity The winning affinity token ticker
    function disburseRewards(string calldata winningAffinity) external override onlyAdmin {}

    /// @notice Burns all the elder spirits in game
    function burnElders() external override onlyAdmin {
        require(eldersInGame > 0); // dev: No elders have been minted.
        for (uint256 i = 1; i <= MAX_NUMBER_OF_ELDERS; ++i) {
            if (_elderSpirits[i].valid) {
                _burnElder(i);
            }
        }

        // Increment the round
        currentRound = currentRound.add(1);

        emit ElderSpiritsBurned();
    }

    /// @notice Burns the elder spirit
    /// @dev This will only be able to be called by the contract
    /// @param elderId The elder id
    function _burnElder(uint256 elderId) internal isValidElderSpiritId(elderId) {
        require(_elderSpirits[elderId].valid); // dev: Cannot burn elder that does not exist.

        // TODO: need to make sure _elderOwners[elderId] can never be address(0).
        //     Check recipient before every token send so that we never send to address(0).
        _burn(_elderOwners[elderId], elderId, 1);

        // Reset elder values for elder id
        eldersInGame = eldersInGame.sub(1);
        _elderOwners[elderId] = address(0);
        _elderSpirits[elderId].valid = false;
        _elderSpirits[elderId].raceId = 0;
        _elderSpirits[elderId].classId = 0;
        _elderSpirits[elderId].affinity = "";
        _elderSpirits[elderId].affinityPrice = 0;
    }

    /// @notice Burns the hero for a refund
    /// @dev This will only be able to be called from the owner of the hero
    /// @param heroId The hero id to burn
    function burnHero(uint256 heroId) external override {
        require(heroId > MAX_NUMBER_OF_ELDERS); // dev: Cannot burn with invalid hero id.
        require(_heroes[heroId].valid); // dev: Cannot burn hero that does not exist.
        require(_heroOwners[heroId] == _msgSender()); // dev: Cannot burn hero that is not yours.

        _burn(_heroOwners[heroId], heroId, 1);

        // Decrement the amount of spawns for the hero's elder
        uint256 elderId = _heroes[heroId].elderId;
        uint256 heroRound = _heroes[heroId].roundMinted;
        _roundElderSpawns[heroRound][elderId] = _roundElderSpawns[heroRound][elderId].sub(1);

        // Reset hero values for hero id
        _heroOwners[heroId] = address(0);
        _heroes[heroId].valid = false;
        _heroes[heroId].roundMinted = 0;
        _heroes[heroId].elderId = 0;
        _heroes[heroId].raceId = 0;
        _heroes[heroId].classId = 0;
        _heroes[heroId].affinity = "";

        emit HeroBurned(heroId);
    }

    /// @notice Gets the minting price of a hero based on specified elder spirit
    /// @param round The round of the hero to be minted
    /// @param elderId The elder id for which the hero will be based on
    /// @return The hero mint price
    function getHeroMintPrice(uint256 round, uint256 elderId) public view override returns (uint256) {
        require(round <= currentRound); // dev: Cannot get price round has not started.
        require(elderId > IN_GAME_CURRENCY_ID && elderId <= MAX_NUMBER_OF_ELDERS); // dev: Elder id is not valid.

        uint256 heroAmount = _roundElderSpawns[round][elderId].add(1);

        return _priceFormula(heroAmount);
    }

    /// @notice The bounding curve function that calculates price for the new supply
    /// @dev price = 0.02*(heroes minted) + 0.1
    /// @param newSupply The new supply after a burn or mint
    /// @return The calculated price
    function _priceFormula(uint256 newSupply) internal pure returns (uint256) {
        uint256 price;
        uint256 base = 1;
        price = newSupply.mul(10**18).mul(2).div(100);
        price = price.add(base.mul(10**18).div(10));

        return price;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; i++) {
            // If token is an elder spirit, update owners so can send them royalties
            if (ids[i] > IN_GAME_CURRENCY_ID && ids[i] <= MAX_NUMBER_OF_ELDERS) {
                _elderOwners[ids[i]] = payable(to);
            }
            if (ids[i] > MAX_NUMBER_OF_ELDERS) {
                _heroOwners[ids[i]] = to;
            }
        }
    }

    /// @notice Gets the amount of heroes spawn from the elder with the specified id during the specified round
    /// @param round The round the elder was created
    /// @param elderId The elder id
    /// @return The amount of heroes spawned from the elder
    function getElderSpawnsAmount(uint256 round, uint256 elderId)
        public
        view
        override
        isValidElderSpiritId(elderId)
        returns (uint256)
    {
        require(round <= currentRound); // dev: Invalid round.
        return _roundElderSpawns[round][elderId];
    }

    /// @notice Refunds the sender if they sent too much
    /// @param cost The cost
    function _refundSender(uint256 cost) internal {
        if (msg.value.sub(cost) > 0) {
            (bool success, ) = msg.sender.call{ value: msg.value.sub(cost) }("");
            require(success); // dev: Refund failed.
        }
    }

    /// @notice Fetches the data of a single elder spirit
    /// @param elderId The id of the elder being searched for
    /// @return The elder's attributes in the following order (valid, raceId, classId, affinity)
    function getElderSpirit(uint256 elderId)
        external
        view
        override
        isValidElderSpiritId(elderId)
        returns (
            bool,
            uint256,
            uint256,
            string memory,
            int256
        )
    {
        ElderSpirit memory elderSpirit = _elderSpirits[elderId];
        return (
            elderSpirit.valid,
            elderSpirit.raceId,
            elderSpirit.classId,
            elderSpirit.affinity,
            elderSpirit.affinityPrice
        );
    }
}
