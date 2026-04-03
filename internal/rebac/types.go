// Package rebac implements the Zanzibar-style ReBAC engine for ZanziPay.
package rebac

// CheckResult is the outcome of a permission check.
type CheckResult int

const (
	CheckDenied      CheckResult = iota
	CheckAllowed     CheckResult = iota
	CheckConditional CheckResult = iota
)

// CheckRequest is the input to a permission check.
type CheckRequest struct {
	Resource      ObjectRef
	Permission    string
	Subject       SubjectRef
	CaveatContext map[string]interface{}
	Zookie        string
}

// CheckResponse is the output of a permission check.
type CheckResponse struct {
	Result        CheckResult
	Verdict       string
	DecisionToken string
	Reasoning     string
}

// ObjectRef is a typed object reference (type + ID).
type ObjectRef struct {
	Type string
	ID   string
}

// SubjectRef is a typed subject (type + ID + optional relation).
type SubjectRef struct {
	Type     string
	ID       string
	Relation string
}

// ExpandRequest requests a userset expansion.
type ExpandRequest struct {
	Resource   ObjectRef
	Permission string
	Zookie     string
}

// ExpandResponse is the result of a userset expansion.
type ExpandResponse struct {
	Tree          *UsersetTree
	DecisionToken string
}

// UsersetTree is the expansion result tree.
type UsersetTree struct {
	Type     string         // "leaf" | "union" | "intersection" | "exclusion"
	Subjects []SubjectRef   // populated for leaf nodes
	Children []*UsersetTree // populated for set-operation nodes
}

// EngineOptions holds optional engine configuration.
type EngineOptions struct {
	CacheSize     int
	HMACKey       []byte
}
