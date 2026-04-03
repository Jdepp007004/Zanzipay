package policy_test

import (
	"context"
	"testing"

	"github.com/Jdepp007004/Zanzipay/internal/policy"
)

func TestPolicyCedarParseAndEval(t *testing.T) {
	src := `permit(principal, action, resource);`
	policies, err := policy.ParseCedarPolicies(src)
	if err != nil {
		t.Fatalf("ParseCedarPolicies() error = %v", err)
	}
	if len(policies) != 1 {
		t.Fatalf("got %d policies, want 1", len(policies))
	}
	if policies[0].Effect != policy.EffectPermit {
		t.Errorf("effect = %s, want permit", policies[0].Effect)
	}

	eval := policy.NewCedarEvaluator(policies)
	resp, err := eval.IsAuthorized(context.Background(), policy.CedarRequest{Action: "view"})
	if err != nil {
		t.Fatalf("IsAuthorized() error = %v", err)
	}
	if !resp.Allowed {
		t.Error("expected ALLOWED with blanket permit")
	}
}

func TestPolicyForbidWins(t *testing.T) {
	policies, _ := policy.ParseCedarPolicies(`
permit(principal, action, resource);
forbid(principal, action, resource) when { frozen == true };
`)
	eval := policy.NewCedarEvaluator(policies)
	resp, _ := eval.IsAuthorized(context.Background(), policy.CedarRequest{
		Context: map[string]interface{}{"frozen": true},
	})
	if resp.Allowed {
		t.Error("forbid should win over permit")
	}
}

func TestPolicyStoreAndEngine(t *testing.T) {
	store := policy.NewPolicyStore()
	engine := policy.NewEngine(store)
	ctx := context.Background()

	dec, _ := engine.Evaluate(ctx, &policy.PolicyEvalRequest{Action: "view"})
	if dec.Allowed {
		t.Error("no policies => DENY")
	}

	_, _, err := engine.DeployPolicies(ctx, `permit(principal, action, resource);`)
	if err != nil {
		t.Fatalf("DeployPolicies() error = %v", err)
	}

	dec2, _ := engine.Evaluate(ctx, &policy.PolicyEvalRequest{Action: "view"})
	if !dec2.Allowed {
		t.Error("permit-all should ALLOW")
	}
}
