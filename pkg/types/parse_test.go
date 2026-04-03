package types_test

import (
	"testing"

	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

func TestParseTupleString(t *testing.T) {
	tests := []struct {
		input   string
		wantRT  string
		wantRID string
		wantRel string
		wantST  string
		wantSID string
		wantSRel string
		wantErr bool
	}{
		{
			input:   "account:acme#owner@user:alice",
			wantRT: "account", wantRID: "acme", wantRel: "owner",
			wantST: "user", wantSID: "alice",
		},
		{
			input:   "document:doc1#viewer@team:eng#member",
			wantRT: "document", wantRID: "doc1", wantRel: "viewer",
			wantST: "team", wantSID: "eng", wantSRel: "member",
		},
		{input: "bad-tuple", wantErr: true},
		{input: "account:acme#owner", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got, err := types.ParseTupleString(tt.input)
			if (err != nil) != tt.wantErr {
				t.Fatalf("ParseTupleString(%q) error=%v wantErr=%v", tt.input, err, tt.wantErr)
			}
			if tt.wantErr {
				return
			}
			if got.ResourceType != tt.wantRT {
				t.Errorf("ResourceType=%q want %q", got.ResourceType, tt.wantRT)
			}
			if got.ResourceID != tt.wantRID {
				t.Errorf("ResourceID=%q want %q", got.ResourceID, tt.wantRID)
			}
			if got.Relation != tt.wantRel {
				t.Errorf("Relation=%q want %q", got.Relation, tt.wantRel)
			}
			if got.SubjectType != tt.wantST {
				t.Errorf("SubjectType=%q want %q", got.SubjectType, tt.wantST)
			}
			if got.SubjectID != tt.wantSID {
				t.Errorf("SubjectID=%q want %q", got.SubjectID, tt.wantSID)
			}
			if got.SubjectRelation != tt.wantSRel {
				t.Errorf("SubjectRelation=%q want %q", got.SubjectRelation, tt.wantSRel)
			}
		})
	}
}
