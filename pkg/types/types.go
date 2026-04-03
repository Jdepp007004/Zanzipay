// Package types defines the core data types for ZanziPay.
package types

// Tuple is a single relationship record (namespace, object_id, relation, subject).
type Tuple struct {
	ResourceType    string
	ResourceID      string
	Relation        string
	SubjectType     string
	SubjectID       string
	SubjectRelation string
	CaveatName      string
	CaveatContext   map[string]interface{}
}

// TupleFilter specifies which tuples to read or delete.
type TupleFilter struct {
	ResourceType    string
	ResourceID      string
	Relation        string
	SubjectType     string
	SubjectID       string
	SubjectRelation string
}

// ObjectRef represents a typed object (e.g. account:acme).
type ObjectRef struct {
	ObjectType string
	ObjectID   string
}

// SubjectRef represents a typed subject (optional relation for usersets).
type SubjectRef struct {
	ObjectType string
	ObjectID   string
	Relation   string
}

// WriteOperation is a single write request.
type WriteOperation struct {
	Operation string // "TOUCH" | "DELETE"
	Tuple     Tuple
}

// Consistency specifies the read consistency level.
type Consistency int

const (
	ConsistencyMinimizeLatency  Consistency = iota // use cached/stalest snapshot
	ConsistencyAtLeastAsFresh                      // at least as fresh as client zookie
	ConsistencyFullyConsistent                     // force read-from-leader
)
