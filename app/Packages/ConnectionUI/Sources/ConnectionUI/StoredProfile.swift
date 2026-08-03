import ProfileStore
// Unambiguous alias — this file imports only ProfileStore so ConnectionProfile
// resolves to ProfileStore's type, not ConnectionManager's.
public typealias StoredProfile = ConnectionProfile
