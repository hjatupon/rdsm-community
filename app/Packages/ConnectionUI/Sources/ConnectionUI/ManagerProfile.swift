import ConnectionManager
// Unambiguous alias — this file imports only ConnectionManager so ConnectionProfile
// resolves to ConnectionManager's type, not ProfileStore's.
public typealias ManagerProfile = ConnectionProfile
