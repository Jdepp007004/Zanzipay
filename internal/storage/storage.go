// Package storage defines the storage interfaces for ZanziPay.
package storage

import (
	"context"
	"time"

	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

// Revision is a monotonically-increasing transaction ID.
type Revision = int64

// TupleStore is the interface for relationship tuple storage.
type TupleStore interface {
	WriteTuples(ctx context.Context, tuples []types.Tuple) (Revision, error)
	DeleteTuples(ctx context.Context, filter types.TupleFilter) (Revision, error)
	ReadTuples(ctx context.Context, filter types.TupleFilter, snapshot Revision) (TupleIterator, error)
	Watch(ctx context.Context, afterRevision Revision) (<-chan WatchEvent, error)
	CurrentRevision(ctx context.Context) (Revision, error)
}

// TupleIterator iterates over tuples returned from a query.
type TupleIterator interface {
	Next() (*types.Tuple, error)
	Close() error
}

// WatchEventType classifies what happened to a tuple.
type WatchEventType string

const (
	WatchEventCreate WatchEventType = "CREATE"
	WatchEventDelete WatchEventType = "DELETE"
	WatchEventTouch  WatchEventType = "TOUCH"
)

// WatchEvent is a single change event from the Watch stream.
type WatchEvent struct {
	Type     WatchEventType
	Tuple    types.Tuple
	Revision Revision
}

// AuditStore is the interface for the immutable audit log.
type AuditStore interface {
	AppendDecisions(ctx context.Context, records []DecisionRecord) error
	QueryDecisions(ctx context.Context, filter AuditFilter) ([]DecisionRecord, error)
}

// DecisionRecord is a single immutable authorization decision.
type DecisionRecord struct {
	ID             string
	Timestamp      time.Time
	SubjectType    string
	SubjectID      string
	ResourceType   string
	ResourceID     string
	Action         string
	Allowed        bool
	Verdict        string
	DecisionToken  string
	Reasoning      string
	EvalDurationNs int64
	ClientID       string
	SourceIP       string
	UserAgent      string
}

// AuditFilter constrains audit log queries.
type AuditFilter struct {
	SubjectID    string
	ResourceID   string
	Action       string
	AllowedOnly  bool
	DeniedOnly   bool
	StartTime    *time.Time
	EndTime      *time.Time
	Limit        int
}

// ComplianceStore is the interface for compliance data.
type ComplianceStore interface {
	WriteSanctionsList(ctx context.Context, listType string, entries []SanctionsEntry) error
	ReadSanctionsList(ctx context.Context, listType string) ([]SanctionsEntry, error)
	WriteFreeze(ctx context.Context, freeze AccountFreeze) error
	ReadFreezes(ctx context.Context, accountID string) ([]AccountFreeze, error)
	WriteRegulatoryOverride(ctx context.Context, override RegulatoryOverride) error
	ReadRegulatoryOverrides(ctx context.Context, resourceID string) ([]RegulatoryOverride, error)
}

// SanctionsEntry is a single record in a sanctions list.
type SanctionsEntry struct {
	ListType string
	Name     string
	Country  string
	Reason   string
}

// AccountFreeze records a freeze placed on an account.
type AccountFreeze struct {
	AccountID string
	Reason    string
	Authority string
	FrozenAt  time.Time
	LiftedAt  *time.Time
}

// RegulatoryOverride is a court order or regulatory hold.
type RegulatoryOverride struct {
	ResourceID   string
	ResourceType string
	Reason       string
	Authority    string
	IssuedAt     time.Time
	ExpiresAt    *time.Time
	Active       bool
}

// PolicyStore stores Cedar policy versions.
type PolicyStore interface {
	WritePolicies(ctx context.Context, policies, version string) error
	ReadPolicies(ctx context.Context) (string, string, error)
}

// PolicyVersion is a historical policy entry.
type PolicyVersion struct {
	Version   string
	Policies  string
	CreatedAt time.Time
}

// ChangeEntry records a single changelog entry.
type ChangeEntry struct {
	Revision  Revision
	EventType string
	Tuple     types.Tuple
}

// ChangelogStore stores tuple change history.
type ChangelogStore interface {
	AppendChange(ctx context.Context, change ChangeEntry) error
	ReadChanges(ctx context.Context, after Revision, limit int) ([]ChangeEntry, error)
}
