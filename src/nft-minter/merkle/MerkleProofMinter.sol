// Neptune Mutual Protocol (https://neptunemutual.com)
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../util/interfaces/IAccessControlUtil.sol";
import "../../util/interfaces/IThrowable.sol";
import "../../util/TokenRecovery.sol";
import "./MerkleProofMinterState.sol";

contract MerkleProofMinter is IAccessControlUtil, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, TokenRecovery, MerkleProofMinterState {
  using MerkleProofUpgradeable for bytes32[];

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    super._disableInitializers();
  }

  function initialize(INeptuneLegends nft, address admin, address prover) external initializer {
    super.__AccessControl_init();
    super.__Pausable_init();

    _nft = nft;

    _setRoleAdmin(NS_ROLES_PROOF_AGENT, DEFAULT_ADMIN_ROLE);

    _setupRole(DEFAULT_ADMIN_ROLE, admin);
    _setupRole(NS_ROLES_RECOVERY_AGENT, admin);
    _setupRole(NS_ROLES_PROOF_AGENT, prover);
  }

  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  //                             Danger!!! External & Public Functions
  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  function setMyPersona(uint8[3] calldata personas) external nonReentrant whenNotPaused {
    if (_personas[_msgSender()][1] > 0) {
      revert PersonaAlreadySetError();
    }

    uint8[3] memory levels = [1, 3, 5];

    for (uint8 i = 0; i < personas.length; i++) {
      uint8 persona = personas[i];

      if (persona != 1 && persona != 2) {
        revert InvalidPersonaError();
      }

      _personas[_msgSender()][levels[i]] = persona;
      _personas[_msgSender()][levels[i] + 1] = persona;

      emit PersonaSet(_msgSender(), levels[i], persona);
      emit PersonaSet(_msgSender(), levels[i] + 1, persona);
    }
  }

  function mint(bytes32[] calldata proof, uint256 boundTokenId, uint8 level, bytes32 family, uint8 persona, uint256 tokenId) external nonReentrant whenNotPaused {
    validate(boundTokenId, level, family, persona, tokenId);
    validateProof(proof, level, family, persona);

    _mintStatus[_msgSender()][level] = true;
    _nft.mint(_getMintInfo(tokenId, _msgSender()));

    emit MintedWithProof(_msgSender(), proof, level, tokenId);
  }

  function validate(uint256 boundTokenId, uint8 level, bytes32 family, uint8 persona, uint256 tokenId) public view {
    if (tokenId == 0 || boundTokenId == 0) {
      revert InvalidTokenIdError(tokenId);
    }

    if (IERC721Upgradeable(address(_nft)).ownerOf(boundTokenId) != _msgSender()) {
      revert InvalidBindingError(_msgSender(), boundTokenId);
    }

    if (_nft._minted(tokenId)) {
      revert TokenAlreadyMintedError(tokenId);
    }

    if (_nft._soulbound(tokenId)) {
      revert TokenAlreadySoulbound(tokenId);
    }

    if (_mintStatus[_msgSender()][level]) {
      revert TokenAlreadyClaimedError(level);
    }

    if (level == 7 && persona != 1) {
      revert PersonaMismatchError(persona, _personas[_msgSender()][level]);
    }

    if (level != 7 && _personas[_msgSender()][level] != persona) {
      revert PersonaMismatchError(persona, _personas[_msgSender()][level]);
    }

    // @todo: not during withdrawal period

    Boundary storage boundary = _boundaries[level][family];

    if (tokenId < boundary.min || tokenId > boundary.max) {
      revert TokenIdOutOfBoundsError(boundary.min, boundary.max);
    }

    if (level > 1) {
      if (_mintStatus[_msgSender()][level - 1] == false) {
        revert PreviousLevelMissingError();
      }
    }
  }

  function validateProof(bytes32[] calldata proof, uint8 level, bytes32 family, uint8 persona) public view {
    bytes32 leaf = keccak256(abi.encodePacked(_msgSender(), level, family, persona));

    if (proof.verify(_merkleRoot, leaf) == false) {
      revert InvalidProofError();
    }
  }

  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  //                                          Merkle Tree
  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  function setMerkleRoot(bytes32 newRoot) external whenNotPaused onlyRole(NS_ROLES_PROOF_AGENT) {
    if (newRoot == _merkleRoot) {
      revert DuplicateRootError();
    }

    emit MerkleRootSet(_msgSender(), _merkleRoot, newRoot);
    _merkleRoot = newRoot;
  }

  function setBoundaries(uint256[] calldata levels, bytes32[] calldata families, Boundary[] calldata candidates) external whenNotPaused onlyRole(NS_ROLES_PROOF_AGENT) {
    if (levels.length != candidates.length || levels.length != families.length) {
      revert RelatedArrayItemCountMismatchError();
    }

    for (uint256 i = 0; i < levels.length; i++) {
      _boundaries[levels[i]][families[i]] = candidates[i];
    }

    emit BoundariesSet(_msgSender(), levels, candidates);
  }

  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  //                                         Access Control
  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  function grantRoles(AccountWithRoles[] calldata detail) external override nonReentrant whenNotPaused {
    if (detail.length == 0) {
      revert InvalidArgumentError("detail");
    }

    for (uint256 i = 0; i < detail.length; i++) {
      for (uint256 j = 0; j < detail[i].roles.length; j++) {
        super.grantRole(detail[i].roles[j], detail[i].account);
      }
    }
  }

  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  //                                          Recoverable
  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  function recoverEther(address sendTo) external onlyRole(NS_ROLES_RECOVERY_AGENT) {
    super._recoverEther(sendTo);
  }

  function recoverToken(IERC20Upgradeable malicious, address sendTo) external onlyRole(NS_ROLES_RECOVERY_AGENT) {
    super._recoverToken(malicious, sendTo);
  }

  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  //                                            Pausable
  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  function pause() external onlyRole(NS_ROLES_PAUSER) {
    super._pause();
  }

  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    super._unpause();
  }

  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  //                                       Private Functions
  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  function _getMintInfo(uint256 tokenId, address account) private pure returns (INeptuneLegends.MintInfo memory) {
    INeptuneLegends.MintInfo memory info;

    info.sendTo = account;
    info.id = tokenId;
    info.soulbound = false;

    return info;
  }
}
