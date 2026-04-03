#!/usr/bin/env bash
# Part 3: internal/config/, internal/storage/
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/config/config.go ───────────────────────────────────────────────
cat > internal/config/config.go << 'ENDOFFILE'
// Package config handles loading and validating ZanziPay configuration.
package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Config is the root configuration struct.
type Config struct {
	Server     ServerConfig     `yaml:"server"`
	Storage    StorageConfig    `yaml:"storage"`
	ReBAC      ReBACConfig      `yaml:"rebac"`
	Policy     PolicyConfig     `yaml:"policy"`
	Compliance ComplianceConfig `yaml:"compliance"`
	Index      IndexConfig      `yaml:"index"`
	Audit      AuditConfig      `yaml:"audit"`
	Metrics    MetricsConfig    `yaml:"metrics"`
}

type ServerConfig struct {
	GRPCPort       int           `yaml:"grpc_port"`
	RESTPort       int           `yaml:"rest_port"`
	MaxConnections int           `yaml:"max_connections"`
	RequestTimeout time.Duration `yaml:"request_timeout"`
}

type StorageConfig struct {
	Engine   string         `yaml:"engine"`
	Postgres PostgresConfig `yaml:"postgres"`
}

type PostgresConfig struct {
	DSN            string        `yaml:"dsn"`
	MaxConnections int           `yaml:"max_connections"`
	QueryTimeout   time.Duration `yaml:"query_timeout"`
}

type ReBACConfig struct {
	CacheSize          int           `yaml:"cache_size"`
	CaveatTimeout      time.Duration `yaml:"caveat_timeout"`
	DefaultConsistency string        `yaml:"default_consistency"`
	ZookieQuantization time.Duration `yaml:"zookie_quantization"`
	ZookieHMACKey      string        `yaml:"zookie_hmac_key"`
}

type PolicyConfig struct {
	AutoAnalyze          bool          `yaml:"auto_analyze"`
	EvaluationTimeout    time.Duration `yaml:"evaluation_timeout"`
	CacheCompiledPolicies bool         `yaml:"cache_compiled_policies"`
}

type ComplianceConfig struct {
	SanctionsUpdateInterval time.Duration `yaml:"sanctions_update_interval"`
	KYCCacheTTL             time.Duration `yaml:"kyc_cache_ttl"`
	FreezeCheckEnabled      bool          `yaml:"freeze_check_enabled"`
}

type IndexConfig struct {
	Enabled             bool          `yaml:"enabled"`
	FullRebuildInterval time.Duration `yaml:"full_rebuild_interval"`
	BitmapShardCount    int           `yaml:"bitmap_shard_count"`
}

type AuditConfig struct {
	BufferSize    int           `yaml:"buffer_size"`
	FlushInterval time.Duration `yaml:"flush_interval"`
	RetentionDays int           `yaml:"retention_days"`
	Immutable     bool          `yaml:"immutable"`
}

type MetricsConfig struct {
	PrometheusPort int  `yaml:"prometheus_port"`
	Enabled        bool `yaml:"enabled"`
}

// Load reads configuration from a YAML file, then overrides with environment variables.
func Load(path string) (*Config, error) {
	cfg := defaults()

	if path != "" {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("reading config file: %w", err)
		}
		// Expand environment variables in YAML values like "${VAR}"
		expanded := os.ExpandEnv(string(data))
		if err := yaml.Unmarshal([]byte(expanded), cfg); err != nil {
			return nil, fmt.Errorf("parsing config file: %w", err)
		}
	}

	applyEnvOverrides(cfg)
	if err := validate(cfg); err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}
	return cfg, nil
}

// defaults returns a Config with sensible defaults.
func defaults() *Config {
	return &Config{
		Server: ServerConfig{
			GRPCPort:       50053,
			RESTPort:       8090,
			MaxConnections: 1000,
			RequestTimeout: 100 * time.Millisecond,
		},
		Storage: StorageConfig{
			Engine: "memory",
			Postgres: PostgresConfig{
				MaxConnections: 20,
				QueryTimeout:   30 * time.Millisecond,
			},
		},
		ReBAC: ReBACConfig{
			CacheSize:          10000,
			CaveatTimeout:      10 * time.Millisecond,
			DefaultConsistency: "minimize_latency",
			ZookieQuantization: 5 * time.Second,
		},
		Policy: PolicyConfig{
			AutoAnalyze:           false,
			EvaluationTimeout:     20 * time.Millisecond,
			CacheCompiledPolicies: true,
		},
		Compliance: ComplianceConfig{
			SanctionsUpdateInterval: 24 * time.Hour,
			KYCCacheTTL:             5 * time.Minute,
			FreezeCheckEnabled:      true,
		},
		Index: IndexConfig{
			Enabled:             true,
			FullRebuildInterval: 6 * time.Hour,
			BitmapShardCount:    16,
		},
		Audit: AuditConfig{
			BufferSize:    10000,
			FlushInterval: time.Second,
			RetentionDays: 2555,
			Immutable:     true,
		},
		Metrics: MetricsConfig{
			PrometheusPort: 9090,
			Enabled:        true,
		},
	}
}

// applyEnvOverrides reads ZANZIPAY_* environment variables and applies them.
func applyEnvOverrides(cfg *Config) {
	if v := os.Getenv("ZANZIPAY_STORAGE_ENGINE"); v != "" {
		cfg.Storage.Engine = v
	}
	if v := os.Getenv("ZANZIPAY_POSTGRES_DSN"); v != "" {
		cfg.Storage.Postgres.DSN = v
	}
	if v := os.Getenv("ZANZIPAY_HMAC_KEY"); v != "" {
		cfg.ReBAC.ZookieHMACKey = v
	}
	if v := os.Getenv("ZANZIPAY_GRPC_PORT"); v != "" {
		fmt.Sscanf(v, "%d", &cfg.Server.GRPCPort)
	}
	if v := os.Getenv("ZANZIPAY_REST_PORT"); v != "" {
		fmt.Sscanf(v, "%d", &cfg.Server.RESTPort)
	}
}

// validate checks that the config is consistent and complete.
func validate(cfg *Config) error {
	engine := strings.ToLower(cfg.Storage.Engine)
	if engine != "memory" && engine != "postgres" && engine != "cockroach" {
		return fmt.Errorf("storage.engine must be memory|postgres|cockroach, got %q", cfg.Storage.Engine)
	}
	if engine == "postgres" || engine == "cockroach" {
		if cfg.Storage.Postgres.DSN == "" {
			return fmt.Errorf("storage.postgres.dsn is required when engine=%s", engine)
		}
	}
	if cfg.ReBAC.ZookieHMACKey != "" && len(cfg.ReBAC.ZookieHMACKey) < 16 {
		return fmt.Errorf("rebac.zookie_hmac_key must be at least 16 characters")
	}
	if cfg.Server.GRPCPort <= 0 || cfg.Server.GRPCPort > 65535 {
		return fmt.Errorf("server.grpc_port out of range: %d", cfg.Server.GRPCPort)
	}
	return nil
}
ENDOFFILE
echo "  [OK] internal/config/config.go"

cat > internal/config/config_test.go << 'ENDOFFILE'
package config_test

import (
	"os"
	"testing"

	"github.com/youorg/zanzipay/internal/config"
)

func TestLoadDefaults(t *testing.T) {
	cfg, err := config.Load("")
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Server.GRPCPort != 50053 {
		t.Errorf("GRPCPort = %d, want 50053", cfg.Server.GRPCPort)
	}
	if cfg.Storage.Engine != "memory" {
		t.Errorf("Storage.Engine = %s, want memory", cfg.Storage.Engine)
	}
}

func TestEnvOverride(t *testing.T) {
	os.Setenv("ZANZIPAY_STORAGE_ENGINE", "postgres")
	os.Setenv("ZANZIPAY_POSTGRES_DSN", "postgres://user:pass@localhost/db")
	os.Setenv("ZANZIPAY_HMAC_KEY", "test-hmac-key-at-least-16-chars!")
	defer func() {
		os.Unsetenv("ZANZIPAY_STORAGE_ENGINE")
		os.Unsetenv("ZANZIPAY_POSTGRES_DSN")
		os.Unsetenv("ZANZIPAY_HMAC_KEY")
	}()

	cfg, err := config.Load("")
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Storage.Engine != "postgres" {
		t.Errorf("Storage.Engine = %s, want postgres", cfg.Storage.Engine)
	}
}

func TestInvalidEngine(t *testing.T) {
	os.Setenv("ZANZIPAY_STORAGE_ENGINE", "invalid")
	defer os.Unsetenv("ZANZIPAY_STORAGE_ENGINE")
	_, err := config.Load("")
	if err == nil {
		t.Error("expected error for invalid storage engine")
	}
}
ENDOFFILE
echo "  [OK] internal/config/config_test.go"

echo "=== internal/config/ done ==="
ENDOFFILE
echo "Part 3 script written"
