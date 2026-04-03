#!/usr/bin/env bash
# Part 9: compliance, orchestrator, index, audit, server, cmd, bench, schemas, frontend, deploy, docs
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/compliance/ ─────────────────────────────────────────────────────
cat > internal/compliance/sanctions.go << 'ENDOFFILE'
package compliance

import (
	"context"
	"math"
	"strings"
	"unicode/utf8"

	"github.com/youorg/zanzipay/internal/storage"
)

// SanctionsScreener screens entities against sanctions lists.
type SanctionsScreener struct {
	store storage.ComplianceStore
}

// NewSanctionsScreener creates a new screener.
func NewSanctionsScreener(store storage.ComplianceStore) *SanctionsScreener {
	return &SanctionsScreener{store: store}
}

// SanctionsResult holds the result of a sanctions check.
type SanctionsResult struct {
	Matched   bool
	Matches   []SanctionsMatch
	RiskScore float64
}

// SanctionsMatch is a single positive result from a sanctions check.
type SanctionsMatch struct {
	ListType   string
	MatchedName string
	QueryName  string
	Score      float64 // 0.0 to 1.0
}

// Screen checks entity names against all sanctions lists.
func (ss *SanctionsScreener) Screen(ctx context.Context, names []string) (*SanctionsResult, error) {
	result := &SanctionsResult{}
	for _, listType := range []string{"OFAC", "EU", "UN"} {
		entries, err := ss.store.ReadSanctionsList(ctx, listType)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			for _, name := range names {
				score := jaroWinkler(strings.ToLower(name), strings.ToLower(entry.Name))
				if score >= 0.85 {
					result.Matches = append(result.Matches, SanctionsMatch{
						ListType:    listType,
						MatchedName: entry.Name,
						QueryName:   name,
						Score:       score,
					})
					result.Matched = true
					if score > result.RiskScore {
						result.RiskScore = score
					}
				}
			}
		}
	}
	return result, nil
}

// jaroWinkler computes the Jaro-Winkler similarity between two strings.
// Returns a value from 0.0 (no similarity) to 1.0 (identical).
func jaroWinkler(s, t string) float64 {
	jaro := jaroSim(s, t)
	// Jaro-Winkler prefix boost
	prefix := 0
	for i := 0; i < min3(4, min3(len(s), len(t))); i++ {
		if s[i] == t[i] {
			prefix++
		} else {
			break
		}
	}
	return jaro + float64(prefix)*0.1*(1-jaro)
}

func jaroSim(s, t string) float64 {
	if s == t {
		return 1.0
	}
	ls, lt := utf8.RuneCountInString(s), utf8.RuneCountInString(t)
	if ls == 0 || lt == 0 {
		return 0.0
	}
	matchDist := int(math.Max(float64(ls), float64(lt)))/2 - 1
	if matchDist < 0 {
		matchDist = 0
	}
	sMatched := make([]bool, ls)
	tMatched := make([]bool, lt)
	matches := 0
	transpositions := 0

	sRunes := []rune(s)
	tRunes := []rune(t)

	for i, sr := range sRunes {
		start := int(math.Max(0, float64(i-matchDist)))
		end := int(math.Min(float64(lt-1), float64(i+matchDist)))
		for j := start; j <= end; j++ {
			if tMatched[j] || sr != tRunes[j] {
				continue
			}
			sMatched[i] = true
			tMatched[j] = true
			matches++
			break
		}
	}
	if matches == 0 {
		return 0.0
	}
	k := 0
	for i, sr := range sRunes {
		if !sMatched[i] {
			continue
		}
		for k < lt && !tMatched[k] {
			k++
		}
		if k < lt && sr != tRunes[k] {
			transpositions++
		}
		k++
	}
	return (float64(matches)/float64(ls) +
		float64(matches)/float64(lt) +
		float64(matches-transpositions/2)/float64(matches)) / 3.0
}

func min3(a, b, c int) int {
	if a < b {
		if a < c {
			return a
		}
		return c
	}
	if b < c {
		return b
	}
	return c
}
ENDOFFILE
echo "  [OK] internal/compliance/sanctions.go"

cat > internal/compliance/sanctions_test.go << 'ENDOFFILE'
package compliance_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/storage"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestSanctionsScreen(t *testing.T) {
	store := memory.New()
	ctx := context.Background()
	store.WriteSanctionsList(ctx, "OFAC", []storage.SanctionsEntry{
		{Name: "Vladimir Putin", ListType: "OFAC"},
	})
	ss := compliance.NewSanctionsScreener(store)
	result, err := ss.Screen(ctx, []string{"Vladimir Putin"})
	if err != nil {
		t.Fatalf("Screen() error = %v", err)
	}
	if !result.Matched {
		t.Error("expected match for exact name")
	}
	result2, _ := ss.Screen(ctx, []string{"Alice Smith"})
	if result2.Matched {
		t.Error("expected no match for Alice Smith")
	}
}
ENDOFFILE
echo "  [OK] internal/compliance/sanctions_test.go"

cat > internal/compliance/kyc.go << 'ENDOFFILE'
package compliance

import (
	"context"
	"fmt"
)

// KYCTier is the minimum KYC verification level required for an action.
type KYCTier int

const (
	KYCTier1 KYCTier = 1 // Basic: view account, read balance
	KYCTier2 KYCTier = 2 // Enhanced: initiate transfers, process refunds
	KYCTier3 KYCTier = 3 // Full: large transfers, regulatory reporting
)

// KYCResult holds the result of a KYC gate check.
type KYCResult struct {
	Passed      bool
	SubjectTier KYCTier
	RequiredTier KYCTier
	Reason      string
}

// ActionKYCRequirements maps action names to their required KYC tier.
var ActionKYCRequirements = map[string]KYCTier{
	"view":              KYCTier1,
	"read_balance":      KYCTier1,
	"transfer":          KYCTier2,
	"refund":            KYCTier2,
	"initiate_payout":   KYCTier2,
	"large_transfer":    KYCTier3,
	"regulatory_report": KYCTier3,
}

// KYCGate enforces KYC verification requirements.
type KYCGate struct {
	// kycResolver fetches a subject's KYC tier from an external source.
	kycResolver func(ctx context.Context, subjectID string) (KYCTier, error)
}

// NewKYCGate creates a new KYC gate with the given resolver function.
func NewKYCGate(resolver func(ctx context.Context, subjectID string) (KYCTier, error)) *KYCGate {
	if resolver == nil {
		// Default: assume all subjects are Tier 1
		resolver = func(_ context.Context, _ string) (KYCTier, error) {
			return KYCTier1, nil
		}
	}
	return &KYCGate{kycResolver: resolver}
}

// Check verifies that the subject has the required KYC tier for the action.
func (g *KYCGate) Check(ctx context.Context, subjectID, action string) (*KYCResult, error) {
	required, ok := ActionKYCRequirements[action]
	if !ok {
		// Unknown action → require Tier 1 by default
		required = KYCTier1
	}

	subjectTier, err := g.kycResolver(ctx, subjectID)
	if err != nil {
		return nil, fmt.Errorf("resolving KYC tier for %s: %w", subjectID, err)
	}

	result := &KYCResult{
		SubjectTier:  subjectTier,
		RequiredTier: required,
	}
	if subjectTier >= required {
		result.Passed = true
		result.Reason = fmt.Sprintf("KYC tier %d >= required %d", subjectTier, required)
	} else {
		result.Passed = false
		result.Reason = fmt.Sprintf("KYC tier %d < required %d for action %q", subjectTier, required, action)
	}
	return result, nil
}
ENDOFFILE
echo "  [OK] internal/compliance/kyc.go"

cat > internal/compliance/kyc_test.go << 'ENDOFFILE'
package compliance_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/compliance"
)

func TestKYCGate(t *testing.T) {
	// Tier 2 subject
	gate := compliance.NewKYCGate(func(_ context.Context, id string) (compliance.KYCTier, error) {
		if id == "alice" {
			return compliance.KYCTier2, nil
		}
		return compliance.KYCTier1, nil
	})
	ctx := context.Background()

	// alice can refund (requires Tier 2)
	result, _ := gate.Check(ctx, "alice", "refund")
	if !result.Passed {
		t.Errorf("alice should pass Tier2 check: %s", result.Reason)
	}

	// bob (Tier 1) cannot refund (requires Tier 2)
	result2, _ := gate.Check(ctx, "bob", "refund")
	if result2.Passed {
		t.Error("bob (Tier1) should not pass Tier2 refund check")
	}

	// both can view (requires Tier 1)
	result3, _ := gate.Check(ctx, "bob", "view")
	if !result3.Passed {
		t.Error("bob (Tier1) should pass Tier1 view check")
	}
}
ENDOFFILE
echo "  [OK] internal/compliance/kyc_test.go"

cat > internal/compliance/regulatory.go << 'ENDOFFILE'
package compliance

import (
	"context"
	"fmt"
	"time"

	"github.com/youorg/zanzipay/internal/storage"
)

// RegulatoryResult holds the result of a regulatory override check.
type RegulatoryResult struct {
	Blocked  bool
	Reason   string
	Authority string
}

// RegulatoryChecker checks court orders and regulatory holds.
type RegulatoryChecker struct {
	store storage.ComplianceStore
}

// NewRegulatoryChecker creates a new regulatory checker.
func NewRegulatoryChecker(store storage.ComplianceStore) *RegulatoryChecker {
	return &RegulatoryChecker{store: store}
}

// Check verifies there are no active regulatory holds on the resource.
func (rc *RegulatoryChecker) Check(ctx context.Context, resourceType, resourceID string) (*RegulatoryResult, error) {
	overrides, err := rc.store.ReadRegulatoryOverrides(ctx, resourceID)
	if err != nil {
		return nil, fmt.Errorf("reading regulatory overrides: %w", err)
	}
	now := time.Now()
	for _, o := range overrides {
		if !o.Active {
			continue
		}
		if o.ExpiresAt != nil && now.After(*o.ExpiresAt) {
			continue
		}
		return &RegulatoryResult{
			Blocked:   true,
			Reason:    o.Reason,
			Authority: o.Authority,
		}, nil
	}
	return &RegulatoryResult{Blocked: false}, nil
}
ENDOFFILE
echo "  [OK] internal/compliance/regulatory.go"

cat > internal/compliance/regulatory_test.go << 'ENDOFFILE'
package compliance_test

import (
	"context"
	"testing"
	"time"

	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/storage"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestRegulatoryChecker(t *testing.T) {
	store := memory.New()
	ctx := context.Background()
	store.WriteRegulatoryOverride(ctx, storage.RegulatoryOverride{
		ResourceID:   "acme",
		ResourceType: "account",
		Reason:       "AML investigation",
		Authority:    "FinCEN",
		IssuedAt:     time.Now().Add(-1 * time.Hour),
		Active:       true,
	})
	rc := compliance.NewRegulatoryChecker(store)
	result, err := rc.Check(ctx, "account", "acme")
	if err != nil {
		t.Fatalf("Check() error = %v", err)
	}
	if !result.Blocked {
		t.Error("expected blocked due to regulatory hold")
	}
}
ENDOFFILE
echo "  [OK] internal/compliance/regulatory_test.go"

cat > internal/compliance/freeze.go << 'ENDOFFILE'
package compliance

import (
	"context"
	"fmt"
	"time"

	"github.com/youorg/zanzipay/internal/storage"
)

// FreezeResult holds the result of a freeze check.
type FreezeResult struct {
	Frozen bool
	Reason string
}

// FreezeEnforcer checks whether an account is frozen.
type FreezeEnforcer struct {
	store storage.ComplianceStore
}

// NewFreezeEnforcer creates a new freeze enforcer.
func NewFreezeEnforcer(store storage.ComplianceStore) *FreezeEnforcer {
	return &FreezeEnforcer{store: store}
}

// Check returns whether an account is currently frozen.
func (fe *FreezeEnforcer) Check(ctx context.Context, accountID string) (*FreezeResult, error) {
	freezes, err := fe.store.ReadFreezes(ctx, accountID)
	if err != nil {
		return nil, fmt.Errorf("reading freezes: %w", err)
	}
	for _, f := range freezes {
		if f.LiftedAt == nil {
			return &FreezeResult{Frozen: true, Reason: f.Reason}, nil
		}
	}
	return &FreezeResult{Frozen: false}, nil
}

// Freeze places an account freeze.
func (fe *FreezeEnforcer) Freeze(ctx context.Context, accountID, reason, authority string) error {
	return fe.store.WriteFreeze(ctx, storage.AccountFreeze{
		AccountID: accountID,
		Reason:    reason,
		Authority: authority,
		FrozenAt:  time.Now(),
	})
}

// Unfreeze lifts an account freeze.
func (fe *FreezeEnforcer) Unfreeze(ctx context.Context, accountID string) error {
	freezes, err := fe.store.ReadFreezes(ctx, accountID)
	if err != nil {
		return err
	}
	now := time.Now()
	for _, f := range freezes {
		if f.LiftedAt == nil {
			f.LiftedAt = &now
			// Re-write with lifted timestamp — in a real DB this would be an UPDATE
			return fe.store.WriteFreeze(ctx, f)
		}
	}
	return nil
}
ENDOFFILE
echo "  [OK] internal/compliance/freeze.go"

cat > internal/compliance/freeze_test.go << 'ENDOFFILE'
package compliance_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestFreezeEnforcer(t *testing.T) {
	store := memory.New()
	fe := compliance.NewFreezeEnforcer(store)
	ctx := context.Background()

	result, _ := fe.Check(ctx, "acme")
	if result.Frozen {
		t.Error("account should not be frozen initially")
	}

	fe.Freeze(ctx, "acme", "fraud investigation", "compliance-team")

	result2, _ := fe.Check(ctx, "acme")
	if !result2.Frozen {
		t.Error("account should be frozen after Freeze()")
	}
}
ENDOFFILE
echo "  [OK] internal/compliance/freeze_test.go"

cat > internal/compliance/engine.go << 'ENDOFFILE'
package compliance

import (
	"context"
	"sync"

	"github.com/youorg/zanzipay/internal/storage"
)

// ComplianceRequest is the input to the compliance engine.
type ComplianceRequest struct {
	SubjectType  string
	SubjectID    string
	SubjectNames []string // Names to screen against sanctions
	ResourceType string
	ResourceID   string
	Action       string
	Context      map[string]interface{}
}

// ComplianceDecision is the output of the compliance engine.
type ComplianceDecision struct {
	Allowed     bool
	Violations  []string
	RiskScore   float64
	Sanctions   *SanctionsResult
	KYC         *KYCResult
	Regulatory  *RegulatoryResult
	Freeze      *FreezeResult
}

// Violation represents a single compliance violation.
type Violation struct {
	Type   string
	Reason string
}

// Engine is the compliance engine — all checks run in parallel.
type Engine struct {
	sanctions  *SanctionsScreener
	kyc        *KYCGate
	regulatory *RegulatoryChecker
	freeze     *FreezeEnforcer
}

// NewEngine creates a new compliance engine.
func NewEngine(store storage.ComplianceStore, kycResolver func(context.Context, string) (KYCTier, error)) *Engine {
	return &Engine{
		sanctions:  NewSanctionsScreener(store),
		kyc:        NewKYCGate(kycResolver),
		regulatory: NewRegulatoryChecker(store),
		freeze:     NewFreezeEnforcer(store),
	}
}

// Evaluate runs all compliance checks in parallel and merges results.
func (e *Engine) Evaluate(ctx context.Context, req *ComplianceRequest) (*ComplianceDecision, error) {
	decision := &ComplianceDecision{Allowed: true}
	var mu sync.Mutex
	var wg sync.WaitGroup
	var firstErr error

	addViolation := func(v string) {
		mu.Lock()
		decision.Violations = append(decision.Violations, v)
		decision.Allowed = false
		mu.Unlock()
	}

	// Sanctions screening
	wg.Add(1)
	go func() {
		defer wg.Done()
		names := req.SubjectNames
		if len(names) == 0 {
			names = []string{req.SubjectID}
		}
		result, err := e.sanctions.Screen(ctx, names)
		if err != nil {
			mu.Lock()
			firstErr = err
			mu.Unlock()
			return
		}
		mu.Lock()
		decision.Sanctions = result
		mu.Unlock()
		if result.Matched {
			addViolation("SANCTIONS: entity matched sanctions list")
			mu.Lock()
			if result.RiskScore > decision.RiskScore {
				decision.RiskScore = result.RiskScore
			}
			mu.Unlock()
		}
	}()

	// KYC check
	wg.Add(1)
	go func() {
		defer wg.Done()
		result, err := e.kyc.Check(ctx, req.SubjectID, req.Action)
		if err != nil {
			return
		}
		mu.Lock()
		decision.KYC = result
		mu.Unlock()
		if !result.Passed {
			addViolation("KYC: " + result.Reason)
		}
	}()

	// Regulatory override check
	wg.Add(1)
	go func() {
		defer wg.Done()
		result, err := e.regulatory.Check(ctx, req.ResourceType, req.ResourceID)
		if err != nil {
			return
		}
		mu.Lock()
		decision.Regulatory = result
		mu.Unlock()
		if result.Blocked {
			addViolation("REGULATORY: " + result.Reason)
		}
	}()

	// Account freeze check
	wg.Add(1)
	go func() {
		defer wg.Done()
		result, err := e.freeze.Check(ctx, req.ResourceID)
		if err != nil {
			return
		}
		mu.Lock()
		decision.Freeze = result
		mu.Unlock()
		if result.Frozen {
			addViolation("FREEZE: account is frozen: " + result.Reason)
		}
	}()

	wg.Wait()
	return decision, firstErr
}
ENDOFFILE
echo "  [OK] internal/compliance/engine.go"

cat > internal/compliance/engine_test.go << 'ENDOFFILE'
package compliance_test

import (
	"context"
	"testing"

	"github.com/youorg/zanzipay/internal/compliance"
	"github.com/youorg/zanzipay/internal/storage/memory"
)

func TestComplianceEngine(t *testing.T) {
	store := memory.New()
	engine := compliance.NewEngine(store, nil)
	ctx := context.Background()

	decision, err := engine.Evaluate(ctx, &compliance.ComplianceRequest{
		SubjectID:    "alice",
		ResourceType: "account",
		ResourceID:   "acme",
		Action:       "view",
	})
	if err != nil {
		t.Fatalf("Evaluate() error = %v", err)
	}
	if !decision.Allowed {
		t.Errorf("expected ALLOWED, violations: %v", decision.Violations)
	}
}
ENDOFFILE
echo "  [OK] internal/compliance/engine_test.go"

# ─── compliance/lists/ ────────────────────────────────────────────────────────
cat > internal/compliance/lists/loader.go << 'ENDOFFILE'
// Package lists manages sanctions list data loading and updating.
package lists

import (
	"context"
	"encoding/csv"
	"io"
	"strings"

	"github.com/youorg/zanzipay/internal/storage"
)

// Loader loads sanctions lists from raw data sources.
type Loader struct {
	store storage.ComplianceStore
}

// NewLoader creates a new list loader.
func NewLoader(store storage.ComplianceStore) *Loader {
	return &Loader{store: store}
}

// LoadCSV loads a sanctions list from CSV data (Name,Country,Reason format).
func (l *Loader) LoadCSV(ctx context.Context, listType string, r io.Reader) (int, error) {
	reader := csv.NewReader(r)
	var entries []storage.SanctionsEntry
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return 0, err
		}
		if len(record) < 1 {
			continue
		}
		entry := storage.SanctionsEntry{
			ListType: listType,
			Name:     strings.TrimSpace(record[0]),
		}
		if len(record) > 1 {
			entry.Country = strings.TrimSpace(record[1])
		}
		if len(record) > 2 {
			entry.Reason = strings.TrimSpace(record[2])
		}
		entries = append(entries, entry)
	}
	if err := l.store.WriteSanctionsList(ctx, listType, entries); err != nil {
		return 0, err
	}
	return len(entries), nil
}
ENDOFFILE
echo "  [OK] internal/compliance/lists/loader.go"

cat > internal/compliance/lists/matcher.go << 'ENDOFFILE'
package lists

import "strings"

// ExactMatch checks if name exactly matches any entry name (case-insensitive).
func ExactMatch(name string, entries []string) bool {
	lower := strings.ToLower(name)
	for _, e := range entries {
		if strings.ToLower(e) == lower {
			return true
		}
	}
	return false
}

// ContainsMatch checks if any entry name contains the query or vice versa.
func ContainsMatch(name string, entries []string) bool {
	lower := strings.ToLower(name)
	for _, e := range entries {
		el := strings.ToLower(e)
		if strings.Contains(el, lower) || strings.Contains(lower, el) {
			return true
		}
	}
	return false
}
ENDOFFILE
echo "  [OK] internal/compliance/lists/matcher.go"

cat > internal/compliance/lists/updater.go << 'ENDOFFILE'
package lists

import (
	"context"
	"time"
)

// Updater periodically refreshes sanctions lists from external sources.
type Updater struct {
	loader   *Loader
	interval time.Duration
}

// NewUpdater creates a new periodic updater.
func NewUpdater(loader *Loader, interval time.Duration) *Updater {
	return &Updater{loader: loader, interval: interval}
}

// Start begins the periodic update loop. Blocks until ctx is cancelled.
func (u *Updater) Start(ctx context.Context) {
	ticker := time.NewTicker(u.interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// In a real implementation, fetch from OFAC/EU/UN APIs
			// and call u.loader.LoadCSV() with the retrieved data.
		}
	}
}
ENDOFFILE
echo "  [OK] internal/compliance/lists/updater.go"

echo "=== internal/compliance/ done ==="
ENDOFFILE
echo "Part 9 script written"
