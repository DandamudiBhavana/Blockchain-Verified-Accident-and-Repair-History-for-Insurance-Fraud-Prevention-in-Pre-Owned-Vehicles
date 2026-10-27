// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// Educational prototype: Vehicle accident, claim, repair and inspection history.
/// Use fictional demo data only. Not a production permissioned consortium chain.
contract VehicleHistory {
    address public admin;
    enum Role { None, Admin, Insurer, Garage, Inspector }

    struct Vehicle {
        string vin; string make; string model; uint16 year;
        address registeredBy; uint256 registeredAt; bool exists;
    }
    struct Accident {
        string claimId; string vin; uint64 accidentDate;
        string accidentType; string damageLevel; string description;
        address recordedBy; uint256 recordedAt; bool exists;
    }
    struct Repair {
        uint256 id; string vin; string claimId; uint64 repairDate;
        string partsReplaced; uint256 repairCost; string status;
        address recordedBy; uint256 recordedAt; bool inspected;
        address inspectedBy; uint256 inspectedAt;
    }
    struct Inspection {
        uint256 id; string vin; string claimId; bool passed;
        string notes; address inspector; uint256 inspectedAt;
    }

    mapping(address => Role) public roles;
    mapping(string => Vehicle) private vehicles;
    mapping(string => Accident) private accidents;
    mapping(string => bool) public claimIdUsed;
    mapping(string => string[]) private claimsByVin;
    mapping(string => Repair[]) private repairsByVin;
    mapping(string => Inspection[]) private inspectionsByVin;
    mapping(string => bytes32[]) private documentHashesByVin;
    string[] private vins;
    uint256 public nextRepairId = 1;
    uint256 public nextInspectionId = 1;

    event RoleGranted(address indexed account, Role role);
    event VehicleRegistered(string indexed vin, address indexed registeredBy);
    event AccidentRecorded(string indexed vin, string indexed claimId, address indexed insurer);
    event RepairRecorded(string indexed vin, uint256 indexed repairId, address indexed garage);
    event InspectionRecorded(string indexed vin, uint256 indexed inspectionId, bool passed);
    event DocumentHashAdded(string indexed vin, bytes32 documentHash, address indexed addedBy);

    modifier onlyAdmin() { require(msg.sender == admin, "Only admin"); _; }
    modifier onlyRole(Role r) { require(roles[msg.sender] == r, "Unauthorized role"); _; }
    modifier vehicleExists(string memory vin) { require(vehicles[vin].exists, "Vehicle not registered"); _; }

    constructor() {
        admin = msg.sender;
        roles[msg.sender] = Role.Admin;
        emit RoleGranted(msg.sender, Role.Admin);
    }

    function authorizeInsurer(address a) external onlyAdmin { _grant(a, Role.Insurer); }
    function authorizeGarage(address a) external onlyAdmin { _grant(a, Role.Garage); }
    function authorizeInspector(address a) external onlyAdmin { _grant(a, Role.Inspector); }
    function _grant(address a, Role r) private {
        require(a != address(0), "Invalid address");
        roles[a] = r;
        emit RoleGranted(a, r);
    }
    function revokeRole(address a) external onlyAdmin {
        require(a != admin, "Cannot revoke admin");
        roles[a] = Role.None;
        emit RoleGranted(a, Role.None);
    }

    function registerVehicle(string calldata vin, string calldata make, string calldata model, uint16 year)
        external onlyAdmin
    {
        require(bytes(vin).length >= 5, "VIN too short");
        require(bytes(make).length > 0 && bytes(model).length > 0, "Missing vehicle details");
        require(year >= 1886 && year <= 2100, "Invalid year");
        require(!vehicles[vin].exists, "VIN already registered");
        vehicles[vin] = Vehicle(vin, make, model, year, msg.sender, block.timestamp, true);
        vins.push(vin);
        emit VehicleRegistered(vin, msg.sender);
    }

    function recordAccident(
        string calldata vin, string calldata claimId, uint64 accidentDate,
        string calldata accidentType, string calldata damageLevel, string calldata description
    ) external onlyRole(Role.Insurer) vehicleExists(vin) {
        require(bytes(claimId).length > 0, "Claim ID required");
        require(!claimIdUsed[claimId], "Duplicate claim ID");
        require(accidentDate > 0 && accidentDate <= block.timestamp, "Invalid accident date");
        require(bytes(accidentType).length > 0 && bytes(description).length > 0, "Missing accident details");
        accidents[claimId] = Accident(claimId, vin, accidentDate, accidentType, damageLevel,
            description, msg.sender, block.timestamp, true);
        claimIdUsed[claimId] = true;
        claimsByVin[vin].push(claimId);
        emit AccidentRecorded(vin, claimId, msg.sender);
    }

    function recordRepair(
        string calldata vin, string calldata claimId, uint64 repairDate,
        string calldata partsReplaced, uint256 repairCost, string calldata status
    ) external onlyRole(Role.Garage) vehicleExists(vin) {
        require(bytes(claimId).length == 0 || accidents[claimId].exists, "Claim does not exist");
        require(repairDate > 0 && repairDate <= block.timestamp, "Invalid repair date");
        require(bytes(partsReplaced).length > 0 && bytes(status).length > 0, "Missing repair details");
        uint256 id = nextRepairId++;
        repairsByVin[vin].push(Repair(id, vin, claimId, repairDate, partsReplaced, repairCost,
            status, msg.sender, block.timestamp, false, address(0), 0));
        emit RepairRecorded(vin, id, msg.sender);
    }

    function verifyRepair(string calldata vin, uint256 index, bool passed, string calldata notes)
        external onlyRole(Role.Inspector) vehicleExists(vin)
    {
        require(index < repairsByVin[vin].length, "Repair index not found");
        Repair storage r = repairsByVin[vin][index];
        r.inspected = passed; r.inspectedBy = msg.sender; r.inspectedAt = block.timestamp;
        uint256 id = nextInspectionId++;
        inspectionsByVin[vin].push(Inspection(id, vin, r.claimId, passed, notes, msg.sender, block.timestamp));
        emit InspectionRecorded(vin, id, passed);
    }

    function addDocumentHash(string calldata vin, bytes32 h) external vehicleExists(vin) {
        Role r = roles[msg.sender];
        require(r == Role.Admin || r == Role.Insurer || r == Role.Garage || r == Role.Inspector,
            "Not an authorized participant");
        require(h != bytes32(0), "Empty document hash");
        documentHashesByVin[vin].push(h);
        emit DocumentHashAdded(vin, h, msg.sender);
    }

    function getVehicle(string calldata vin) external view returns (Vehicle memory) {
        require(vehicles[vin].exists, "Vehicle not registered"); return vehicles[vin];
    }
    function getAccidentByClaim(string calldata claimId) external view returns (Accident memory) {
        require(accidents[claimId].exists, "Claim not found"); return accidents[claimId];
    }
    function getAccidentCount(string calldata vin) external view vehicleExists(vin) returns (uint256) {
        return claimsByVin[vin].length;
    }
    function getAccidentClaimIdAt(string calldata vin, uint256 i) external view vehicleExists(vin) returns (string memory) {
        require(i < claimsByVin[vin].length, "Index out of range"); return claimsByVin[vin][i];
    }
    function getRepairCount(string calldata vin) external view vehicleExists(vin) returns (uint256) {
        return repairsByVin[vin].length;
    }
    function getRepairAt(string calldata vin, uint256 i) external view vehicleExists(vin) returns (Repair memory) {
        require(i < repairsByVin[vin].length, "Index out of range"); return repairsByVin[vin][i];
    }
    function getInspectionCount(string calldata vin) external view vehicleExists(vin) returns (uint256) {
        return inspectionsByVin[vin].length;
    }
    function getInspectionAt(string calldata vin, uint256 i) external view vehicleExists(vin) returns (Inspection memory) {
        require(i < inspectionsByVin[vin].length, "Index out of range"); return inspectionsByVin[vin][i];
    }
    function getDocumentHashCount(string calldata vin) external view vehicleExists(vin) returns (uint256) {
        return documentHashesByVin[vin].length;
    }
    function getDocumentHashAt(string calldata vin, uint256 i) external view vehicleExists(vin) returns (bytes32) {
        require(i < documentHashesByVin[vin].length, "Index out of range"); return documentHashesByVin[vin][i];
    }
    function getRegisteredVehicleCount() external view returns (uint256) { return vins.length; }
    function getRegisteredVinAt(uint256 i) external view returns (string memory) {
        require(i < vins.length, "Index out of range"); return vins[i];
    }
}
